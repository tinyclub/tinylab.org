---
layout: post
author: 'Bin Meng'
title: '设备树 overlay 机制深入拆解'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /20230804_devicetree-overlay-internals/
description: '设备树 overlay 机制深入拆解'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [spaces tables]
> Author:    Bin Meng <bmeng@tinylab.org>
> Date:      2023/08/04
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

设备树 overlay（以下译作 “叠加”）是一种动态配置硬件设备的机制。在非 x86 架构的嵌入式系统里，硬件设备的配置信息通常以设备树的形式提供给软件，比如 bootloader、操作系统内核等。设备树是一种描述硬件设备结构和属性的数据结构，它将设备的硬件特性以及操作系统所需的配置信息以一种统一的方式表示出来。然而某些情况下，需要在运行时对设备树进行修改或者添加新的设备树信息，而不必重新编译整个设备树，这就是设备树叠加的作用所在。设备树叠加允许在设备树中覆盖、修改或扩展已有设备的属性，或者添加新的设备节点，从而实现对硬件配置的动态修改。

设备树叠加的工作原理是，通过在文件系统中提供一个或多个叠加设备树文件（也称为设备树片段），这些文件包含了要修改或添加的设备树信息。在系统启动过程中，设备树管理器（通常是 U-Boot 或 Linux 内核）会加载这些叠加文件，并将其应用到原始的设备树上，生成一个新的、包含叠加信息的设备树。操作系统内核会使用这个新的设备树来初始化和配置硬件设备。

设备树叠加的好处是可以在不重新编译设备树的情况下，实现对硬件配置的灵活修改。它特别适用于嵌入式系统中需要动态添加或修改硬件设备的场景，例如在运行时连接或断开外部设备，根据当前主板的信息动态加载新的硬件模块、扩展板卡等。

目前网上对设备树叠加的介绍，大多提到了要使设备树叠加机制正常工作，需要 `dtc` 带上 `-@` 选项编译基础设备树和叠加设备树源文件。但也有文章提到了 `-@` 选项不是必须的，写叠加设备树源文件的时候需要用到另一种写法。初学者对此往往非常迷惑。本文我们就来实际动手详细拆解一下，`dtc` 的这个 `-@` 选项到底干了什么，以及它对于设备树叠加机制到底是不是强制需要的。

## 初体验

下面我们实践一下具体的设备树叠加的全过程，在这过程中，我们会编写一个基础设备树源文件，一个叠加设备树源文件，用 `dtc` 对其进行编译，并由 U-Boot 来完成最终的设备树叠加。

### 工具软件

本文用到的工具软件及其版本如下：

- dtc v1.5.0
- U-Boot v2023.04
- QEMU v8.0.0

### 基础设备树

我们先写一个基础设备树文件：

```shell
$ cat base.dts
/dts-v1/;

/ {
    L_foo: foo {
        foo-property;
    };
};
```

分别以 `-@` 选项和不加 `-@` 选项用 `dtc` 对其进行编译成 dtb 格式，再以 `dtc` 对其进行反编译成 dts 格式。

（注意 `-@` 选项是从 `dtc` 版本 1.4.4 开始支持的）

加 `-@` 的情况：

```shell
$ dtc -@ -I dts -O dtb -o base.dtb base.dts
$ dtc -I dtb -O dts base.dtb
/dts-v1/;

/ {

        foo {
                foo-property;
                phandle = <0x01>;
        };

        __symbols__ {
                L_foo = "/foo";
        };
};
```

不加 `-@` 的情况：

```shell
$ dtc -I dts -O dtb -o base.dtb base.dts
$ dtc -I dtb -O dts base.dtb
/dts-v1/;

/ {

        foo {
                foo-property;
        };
};
```

可以看到用 `-@` 选项编译后，节点 foo 下会生成一个新的 phandle 属性，并且根节点下加入了一个 `__symbols__` 的节点，节点内容包含所有带标签的节点的列表，如 `label = "node_full_path"`。

可以这么认为，`__symbols__` 节点就是用来记录基础设备树（或后续加载的叠加层）中所有带有标签的节点，以便后续做设备树叠加的时候可以将它们与在设备树对象中对它们的引用进行匹配。该节点不会影响板子的正常启动，bootloader 和操作系统内核都会安全的忽略它，唯一的损失可能是浪费了一点内存和磁盘空间 :)

### 叠加设备树

再来写一个叠加设备树文件：

```shell
$ cat overlay.dts
/dts-v1/;
/plugin/;

/ {
    fragment@0 {
        target = <&L_foo>;
        __overlay__ {
            overlay-1-property;
            L_bar: bar {
                bar-property;
            };
        };
    };
};
```

叠加设备树文件要求在源文件开头的 /dts-v1/ 后加入一行代表这是一个设备树片段的标签 /plugin/，该标签告诉 `dtc` 需要记录对编译时不存在的节点的未定义引用，以便运行时利用设备树叠加机制来修复它们。其他地方的写法和基础设备树文件并无很大的不同，所有叠加的信息统一放在根节点下面的 fragment@n 节点，其节点内容包含一个 target 属性和 `__overlay__` 的子节点。

同样我们用 `dtc` 加 `-@` 选项编译后：

```shell
$ dtc -@ -I dts -O dtb -o overlay.dtbo overlay.dts
$ dtc -I dtb -O dts overlay.dtbo
/dts-v1/;

/ {

        fragment@0 {
                target = <0xffffffff>;

                __overlay__ {
                        overlay-1-property;

                        bar {
                                bar-property;
                                phandle = <0x01>;
                        };
                };
        };

        __symbols__ {
                L_bar = "/fragment@0/__overlay__/bar";
        };

        __fixups__ {
                L_foo = "/fragment@0:target:0";
        };
};
```

这里我们看到，叠加设备树源文件中对 L_foo 标签的引用是外部引用，在本文件中是未定义，因此这个引用的 phandle 值被填充为非法值 0xffffffff，同时 dtc 生成了一个名为 `__fixups__` 的节点，该节点标记了所有未定义的外部引用。

`__fixups__` 节点的格式如下：

```
    <label> = "<local-full-path>:<property-name>:<offset>"[, "<local-full-path>:<property-name>:<offset>"...];
```

* `<label>`：所引用的标签
* `<local-full-path>`：引用所在节点的完整路径
* `<property-name>`：包含引用的属性名称
* `<offset>`：属性的 phandle 值所在的偏移量（以字节为单位）

## 上手实验

### 测试环境

U-Boot 命令行下有个非常实用的 `fdt` 命令，可以方便的测试设备树叠加的功能。下面我们以 qemu-riscv64_smode_defconfig 配置为例，在 QEMU 上进行测试。

注意默认的 qemu-riscv64_smode_defconfig 配置没有打开设备树叠加支持，需要手动使能 CONFIG_OF_LIBFDT_OVERLAY 配置选项，可通过 `make menuconfig => Library routines => Enable the FDT library overlay support` 打开。

用下面的 QEMU 命令行启动 U-Boot，该命令行把 base.dtb 和 overlay.dtbo 分别加载到系统内存偏移地址 16 MiB / 32 MiB 的地方：

```shell
$ qemu-system-riscv64 -nographic -M virt -kernel u-boot -device loader,file=base.dtb,addr=0x81000000 -device loader,file=overlay.dtbo,addr=0x82000000
```

启动 U-Boot 后，设置 `fdt` 命令的工作地址，我们需要将基础设备树的地址告诉它。

```shell
=> fdt addr 81000000
Working FDT set to 81000000
=> fdt print
/ {
        foo {
                foo-property;
                phandle = <0x00000001>;
        };
        __symbols__ {
                L_foo = "/foo";
        };
};
```

打印一下这个基础设备树，可以看到跟前面 `dtc` 命令反编译的输出结果是一样的。

接下来我们把基础设备树的大小增加到 1024 字节，以便容纳可能的设备树叠加，然后执行设备树叠加操作。

```shell
=> fdt resize 1024
=> fdt apply 82000000
=> fdt print
/ {
        foo {
                overlay-1-property;
                foo-property;
                phandle = <0x00000001>;
                bar {
                        phandle = <0x00000002>;
                        bar-property;
                };
        };
        __symbols__ {
                L_bar = "/foo/bar";
                L_foo = "/foo";
        };
};
```

可以看到在执行完设备树叠加后，打印基础设备树所在地址的设备树，叠加层中的设备树片段已经合并到基础设备树中了。

上述例子是基础设备树和叠加设备树源文件都用 `-@` 选项编译的测试结果，我们接下来分别测试了其他三种情况，看看设备树叠加功能是否正常。

### 其它几种组合

下面测试了叠加设备树不加 `-@` 编译的情况：

```shell
=> fdt print
/ {
        foo {
                overlay-1-property;
                foo-property;
                phandle = <0x00000001>;
                bar {
                        bar-property;
                };
        };
        __symbols__ {
                L_foo = "/foo";
        };
};
```

这是基础设备树不加 `-@` 编译的情况，执行设备树叠加命令时报错 FDT_ERR_NOTFOUND，找不到 `__symbols__` 节点。

```shell
=> fdt apply 82000000
failed on fdt_overlay_apply(): FDT_ERR_NOTFOUND
base fdt does did not have a /__symbols__ node
make sure you've compiled with -@
```

基础设备树和叠加设备树都不加 `-@` 编译，测试结果跟 “基础设备树不加 -@” 的情况一样。

### 测试结果

下表列出了 `-@` 应用于基础设备树和叠加设备树的 4 种可能情况对应的测试结果：

| 基础设备树 -@ | 叠加设备树 -@ | 功能正常 |
|---------------|---------------|----------|
| Y             | Y             | Y        |
| Y             | N             | Y        |
| N             | Y             | N        |
| N             | N             | N        |

测试结果表明，在基础设备树不加 `-@` 编译的情况下，设备树叠加不能正确工作。那么这就是最后的结论了吗？答案是否定的。

## 另一种写法

### target-path 节点

现在我们稍微修改一下 overlay.dts 文件：

```shell
$ cat overlay.dts
/dts-v1/;
/plugin/;

/ {
    fragment@0 {
        target-path = "/foo";
        __overlay__ {
            overlay-1-property;
            L_bar: bar {
                bar-property;
            };
        };
    };
};
```

修改的地方只有一行，从原来的 target = <&L_foo> 修改为 target-path = "/foo"。这里将属性名称从 target 改成 target-path，属性值为原 label 所在节点的全路径的字符串。

不带 `-@` 编译一下看看：

```shell
$ dtc -I dts -O dtb -o overlay.dtbo overlay.dts
$ dtc -I dtb -O dts overlay.dtbo
/dts-v1/;

/ {

        fragment@0 {
                target-path = "/foo";

                __overlay__ {
                        overlay-1-property;

                        bar {
                                bar-property;
                        };
                };
        };
};
```

这次目标文件中并没有出现 `__fixups__` 节点

再次在 U-Boot 命令行下进行测试，测试结果表明无论基础设备树还是叠加设备树加不加 `-@` 编译，设备树叠加的功能都正常。

### 实验结论

回顾一下上面的测试结果，我们发现 `-@` 选项控制生成 `__symbols__` 节点，而源文件中的 /plugin/ 标签控制生成 `__fixups__` 节点。值得注意的是，这两个节点不是一定会生成的，需要满足一定的条件。

- 设备树源文件中如果出现带标签的节点，`-@` 选项就会在目标文件中生成 `__symbols__` 节点
- 设备树源文件中如果出现标签 /plugin/，并且文件中存在对外部 label 的引用，就会在目标文件中生成 `__fixups__` 节点

相应地，我们得到如下的实验结论：

- 如果基础设备树目标文件中不存在 `__symbols__` 节点，则要求与之配套的叠加设备树源文件不能出现 label 的引用
- 如果叠加设备树目标文件中存在 `__fixups__` 节点，则要求与之配套的基础设备树源文件**一定**要用 `-@` 来编译

## dtc 软件包

发行版提供的 dtc 软件包不只包含我们最常用的 `dtc` 工具，还包括一些很实用的小工具，如 `fdtdump`、`fdtoverlay` 等。

### fdtdump

前文中用 `dtc` 工具把 dtb 格式转换成 dts 格式，也可以直接用 `fdtdump` 工具，更加简便。

```shell
$ dtc -@ -I dts -O dtb -o base.dtb base.dts
$ fdtdump base.dtb

**** fdtdump is a low-level debugging tool, not meant for general use.
**** If you want to decompile a dtb, you probably want
****     dtc -I dtb -O dts <filename>

/dts-v1/;
// magic:               0xd00dfeed
// totalsize:           0xb3 (179)
// off_dt_struct:       0x38
// off_dt_strings:      0x98
// off_mem_rsvmap:      0x28
// version:             17
// last_comp_version:   16
// boot_cpuid_phys:     0x0
// size_dt_strings:     0x1b
// size_dt_struct:      0x60

/ {
    foo {
        foo-property;
        phandle = <0x00000001>;
    };
    __symbols__ {
        L_foo = "/foo";
    };
};
```

### fdtoverlay

测试设备树叠加能否正常工作，也不用非得到 U-Boot 命令行下测试，使用 dtc 软件包中的 `fdtoverlay` 这个主机侧的工具可以非常方便地进行测试。

```shell
$ dtc -I dts -O dtb -o base.dtb base.dts
$ dtc -I dts -O dtb -o overlay.dtbo overlay.dts
$ fdtoverlay -i base.dtb -o merged.dtb overlay.dtbo
$ fdtdump merged.dtb

**** fdtdump is a low-level debugging tool, not meant for general use.
**** If you want to decompile a dtb, you probably want
****     dtc -I dtb -O dts <filename>

/dts-v1/;
// magic:               0xd00dfeed
// totalsize:           0xb1 (177)
// off_dt_struct:       0x38
// off_dt_strings:      0x84
// off_mem_rsvmap:      0x28
// version:             17
// last_comp_version:   16
// boot_cpuid_phys:     0x0
// size_dt_strings:     0x2d
// size_dt_struct:      0x4c

/ {
    foo {
        overlay-1-property;
        foo-property;
        bar {
            bar-property;
        };
    };
};
```

## 语法糖

传统的叠加层是通过在根节点中创建片段节点来创建的。每个片段节点必须具有一个 target 属性，其值是一个标签引用，或者一个 target-path 字符串属性，其值为一个节点的绝对路径。然后，片段节点必须有一个名为 `__overlay__` 的子节点，当应用叠加层时，该子节点的属性和子节点将与基础设备树进行合并。

这种写法在需要叠加的片段节点非常多的情况下非常繁琐，每个片段节点需要手工编号，从 0 一直写到 n：

```
/dts-v1/;
/plugin/;

/ {
    fragment@0 {
        target = <&xxx>;
        __overlay__ {
            ...
        };
    };

    fragment@1 {
        target = <&yyy>;
        __overlay__ {
            ...
        };
    };

    fragment@2 {
        target = <&zzz>;
        __overlay__ {
            ...
        };
    };

    ...

    fragment@n {
        target = <&nnn>;
        __overlay__ {
            ...
        };
    };
};
```

为了简化生成叠加层的过程，从 `dtc` 1.5.0 版本开始引入了更简单的语法糖。不需要手动创建显式的片段，而是通过使用传统 dts 源文件中支持的 `&label` 语法来指定目标标签。这将指示应生成一个片段，其中给定的标签将作为 target 属性，属性和子节点将用作 `__overlay__` 子节点的内容。

此外，该语法糖也支持基于路径的版本，使用形式为 `&{/path}` 的名称来指定基础设备树中的路径作为目标。与 `&label` 情况下一样，将为节点生成一个片段，片段节点内的生成 target-path 属性并将其设置为 /path，而不会生成 target 属性。这种形式实际上是用到了 label 的替换写法，即对原 label 的引用修改为包含在大括号中的原 label 所在节点的全路径，注意大括号两端不能有空格。

### label 形式

利用这个语法糖我们改造一下之前 overlay.dts 例子：

```shell
$ cat overlay.dts
/dts-v1/;
/plugin/;

&L_foo {
    overlay-1-property;
    L_bar: bar {
        bar-property;
    };
};
$ dtc -I dts -O dtb -o overlay.dtbo overlay.dts
$ fdtdump overlay.dtbo

**** fdtdump is a low-level debugging tool, not meant for general use.
**** If you want to decompile a dtb, you probably want
****     dtc -I dtb -O dts <filename>

/dts-v1/;
// magic:               0xd00dfeed
// totalsize:           0x109 (265)
// off_dt_struct:       0x38
// off_dt_strings:      0xdc
// off_mem_rsvmap:      0x28
// version:             17
// last_comp_version:   16
// boot_cpuid_phys:     0x0
// size_dt_strings:     0x2d
// size_dt_struct:      0xa4

/ {
    fragment@0 {
        target = <0xffffffff>;
        __overlay__ {
            overlay-1-property;
            bar {
                bar-property;
            };
        };
    };
    __fixups__ {
        L_foo = "/fragment@0:target:0";
    };
};
```

可以看到，最后生成的设备树目标文件的内容跟传统的叠加层写法是完全一样的，这里我们引用了带标签的外部节点，叠加层片段节点里正确生成了 target 属性，并在根节点下生成了 `__fixups__` 子节点。

### 全路径形式

我们也可以直接用全路径来引用要叠加的节点：

```shell
$ cat overlay.dts
/dts-v1/;
/plugin/;

&{/foo} {
    overlay-1-property;
    L_bar: bar {
        bar-property;
    };
};
$ dtc -I dts -O dtb -o overlay.dtbo overlay.dts
$ fdtdump overlay.dtbo

**** fdtdump is a low-level debugging tool, not meant for general use.
**** If you want to decompile a dtb, you probably want
****     dtc -I dtb -O dts <filename>

/dts-v1/;
// magic:               0xd00dfeed
// totalsize:           0xd4 (212)
// off_dt_struct:       0x38
// off_dt_strings:      0xa8
// off_mem_rsvmap:      0x28
// version:             17
// last_comp_version:   16
// boot_cpuid_phys:     0x0
// size_dt_strings:     0x2c
// size_dt_struct:      0x70

/ {
    fragment@0 {
        target-path = "/foo";
        __overlay__ {
            overlay-1-property;
            bar {
                bar-property;
            };
        };
    };
};
```

这种情况我们没有引用带标签的外部节点，而是用的全路径的语法糖写法，生成的叠加层片段节点里正确生成了 target-path 属性，注意目标文件里没有生成 `__fixups__` 子节点，这与我们预料的一致。

## 疑问

有同学可能会有疑问，这种设备树叠加的做法，跟我们在内核代码树中见到的下面这种写法，有什么不同吗？

比如 SiFive HiFive Unmatched 板子的 dts 文件中，我们用 #include 语法把 SoC 的 dtsi 文件包含到板子 dts 文件中，fu740-c000.dtsi 里 uart0 节点的 status 属性是 "disabled" 的：

```
    uart0: serial@10010000 {
        ...
        status = "disabled";
    };
```

然后在 hifive-unmatched-a00.dts 开头，`#include "fu740-c000.dtsi"`，并在后面修改 uart0 节点的 status 属性。

```
&uart0 {
    status = "okay";
};
```

乍一看这种写法跟前面介绍的语法糖写法非常像，但要注意，这种写法并不是设备树叠加，这里最终由 `dtc` 编译生成的只有一个 hifive-unmatched-a00.dtb 文件。

打个不恰当的比方，这种方式就像我们编程中的静态链接，设备树叠加机制则是动态链接。动态链接的优点之一就是代码段只保留一份拷贝，节省内存空间。对应地，设备树叠加在存储介质里只保留一份基础设备树，这个基础设备树对同一板卡的不同变种、版本、子卡都适用，另外只需要在存储介质里保存变种板卡等的叠加设备树文件，这样会极大的减小对存储空间的要求。

那可能有同学又会问了，这种设备树叠加来动态修改设备树的方法，我在代码里利用 libfdt 的 API 也一样可以实现啊，比如：

```C
#include <libfdt.h>

void fixup_dtb(void *dtb)
{
    int offset, err;

    offset = fdt_path_offset(dtb, "/serial@10010000");
    if (offset < 0) {
        return;
    }

    err = fdt_setprop_string(dtb, offset, "status", "okay");
    if (err != 0) {
        return;
    }

    ...
}
```

但是这种写法应对简单的设备树修改还算方便，对于需要大量修改原设备树的节点就会显得力不从心了，会有巨量的处理修改节点属性、增加删除节点等逻辑充斥在代码中。而且笔者认为最重要的一点是，这种做法不够 “优雅”，它没有贯彻设备树发明的初衷，即设备树应被视为一种数据，数据应当与代码解耦，而不是紧耦合在一起。设备树叠加机制则把这些修改逻辑通过 “叠加” 这个操作隐藏起来，让本应该是数据的东西（叠加设备树片段）回归数据，让代码专注与数据无关的通用操作。

## 总结

综上所述，设备树叠加机制提供了一种灵活、高效和可维护的方式来配置和修改设备树，使系统能够适应不同的硬件配置和应用需求，并简化了设备树的更新和维护过程。

## 参考资料

* https://git.kernel.org/pub/scm/utils/dtc/dtc.git/tree/Documentation/dts-format.txt
* https://git.kernel.org/pub/scm/utils/dtc/dtc.git/tree/Documentation/dt-object-internal.txt
