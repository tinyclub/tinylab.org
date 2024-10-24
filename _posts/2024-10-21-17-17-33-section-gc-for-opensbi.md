---
layout: post
author: 'Kele Zhang'
title: '为 OpenSBI 增加 Section GC 功能'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /section-gc-for-opensbi/
description: '为 OpenSBI 增加 Section GC 功能'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - OpenSBI
  - Section Gc
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [pangu]
> Author:    Kele Zhang <zhangcola2003@gmail.com>
> Date:      20230730
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [为 OpenSBI 增加 Section GC 功能][004]
> Sponsor:   PLCT Lab, ISCAS


## 概述

OpenSBI 目前并不支持 Section GC，Section GC 是指 Section Garbage Collection，即段（Section）的垃圾收集。在编译程序时，GCC 会将代码和数据组织成不同的段（Sections），例如 .text 段存储可执行代码，.data 段存储已初始化的全局变量等等。而 Section GC 则是指在链接阶段对这些节进行清理，去除未使用的代码和数据，以减小最终生成的可执行文件的大小。

实现这个功能时，我们需要分析其链接脚本，并且完备的测试这个改动是否会影响其正常功能。

## 理解编译器提供的 Section GC 功能

我们需要理解 Section GC 的功能和实现原理才能为 OpenSBI 增加这个功能，否则将无从下手。

参考以下三篇文章，我们能够了解 Section GC 的原理和实现细节。

- [Section GC 分析 - Part 1 原理简介][001]
- [Section GC 分析 - Part 2 gold 源码解析][002]
- [Section GC 分析 - Part 3 引用建立过程][003]

链接器提供的的 `--gc-sections` 选项可以在链接时对未使用到的函数和变量进行裁剪。

对 section 执行 GC 操作的前提，链接前每个函数和数据都有自己的 section。但默认情况下，GCC 把函数统一放在了 `.text` section 中。我们可以使用 `-ffunction-sections` 参数来让每个函数都有自己的 section。

默认情况下，编译器按照以下规则将数据放入各个段中：

| 段        | 数据类型           | 说明                                                          |
|-----------|----------------|-------------------------------------------------------------|
| `.text`   | 可执行代码         | 存放程序的机器指令                                            |
| `.rodata` | 只读数据           | 存放不可修改的常量数据，例如字符串常量、全局常量等              |
| `.data`   | 初始化的可读写数据 | 存放已初始化的全局变量和静态变量，可以在程序运行时进行读写操作 |
| `.bss`    | 未初始化数据       | 存放未初始化的全局和静态变量                                  |

像这样所有代码都放在了代码段中，链接器不知道哪些函数和变量被使用了，无法进行裁剪。要想进行垃圾回收，需要让每个函数都有自己的节。

GCC 的 `-ffunction-sections` 和 `-fdata-sections` 选项会让每个函数或者变量拥有自己的节。我们在这里只详细介绍 `-ffunction-sections`，`-fdata-sections` 同理。

以下是示例代码，包括了使用到的函数 `fun()` 和未使用到的函数 `unused()`

```C
void fun(){
    return;
}

void unused(){
    return;
}

int main(){
    fun();
}
```

启用 `-ffunction-sections` 选项，编译该文件，但不进行链接。

```
gcc -c test.c
```

查看目标文件符号表。

```bash
$ readelf -s test.o

Symbol table '.symtab' contains 8 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
     1: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS test.c
     2: 0000000000000000     0 SECTION LOCAL  DEFAULT    1 .text
     5: 0000000000000000    11 FUNC    GLOBAL DEFAULT    1 fun
     6: 0000000000000000    11 FUNC    GLOBAL DEFAULT    1 unused
     7: 0000000000000000    25 FUNC    GLOBAL DEFAULT    1 main
```

可以看到 `fun()` 和 `unused()` 函数没有单独的 section。

启用 `-ffunction-sections` 选项，编译该文件，但不进行链接。

```
gcc -c --function-sections test.c
```

查看目标文件符号表：

```bash
$ readelf -s test.o

Symbol table '.symtab' contains 8 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT  UND
     1: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS test.c
     2: 0000000000000000     0 SECTION LOCAL  DEFAULT    4 .text.fun
     3: 0000000000000000     0 SECTION LOCAL  DEFAULT    5 .text.unused
     4: 0000000000000000     0 SECTION LOCAL  DEFAULT    6 .text.main
     5: 0000000000000000    11 FUNC    GLOBAL DEFAULT    4 fun
     6: 0000000000000000    11 FUNC    GLOBAL DEFAULT    5 unused
     7: 0000000000000000    25 FUNC    GLOBAL DEFAULT    6 main
```

可以看到 `fun()` 和 `unused())` 函数都有了各自的 section。

启用 `--gc-sections` 后，链接器将会删除没有别引用到的 section。

## 寻找被错误 GC 掉的节

在弄明白了 Section GC 的原理后，我们就可以尝试着修改 OpenSBI 代码了。

```diff
-CFLAGS		=	-g -Wall -Werror -ffreestanding -nostdlib -fno-stack-protector -fno-strict-aliasing
+CFLAGS		=	-g -Wall -Werror -ffreestanding -nostdlib -fno-stack-protector -fno-strict-aliasing -ffunction-sections -fdata-sections
```

```diff
 ELFFLAGS	+=	$(USE_LD_FLAG)
+ELFFLAGS	+=	-Wl,--gc-sections
```

以上修改启动编译器和链接器的 Section GC 相关选项。

需要注意的是，由于代码需要合并入主线，我们修改的方式需要和原来的代码相适应，包括代码的顺序和位置。

然后我们编译 OpenSBI，并在 QEMU 中启动提前编译好的 Linux 内核和 OpenSBI。

```bash
CROSS_COMPILE=riscv64-linux-gnu- make PLATFORM=generic FW_PAYLOAD_PATH=./Image -j16
qemu-system-riscv64 -M virt -kernel ./Image -append 'rootwait root=/dev/vda ro' -nographic --bios ./build/platform/generic/firmware/fw_dynamic.bin
```

然而运行的时候没有任何输出。这个难题很棘手，没有输出不知道卡在了哪里。

开启 `--print-gc-sections` 后发现，有特别多的 `.text.*` 节被删除了。

根据上文对 Section GC 功能的解析，我们需要在链接脚本中，手动保留 `.text.*` 这样节。

```diff
diff --git a/firmware/fw_base.ldS b/firmware/fw_base.ldS
index fb47984..a33746a 100644
--- a/firmware/fw_base.ldS
+++ b/firmware/fw_base.ldS
@@ -20,6 +20,7 @@
 		PROVIDE(_text_start = .);
 		*(.entry)
 		*(.text)
+		*(.text.*)
 		. = ALIGN(8);
 		PROVIDE(_text_end = .);
 	}
```

再次编译，成功运行。

一些汇编语法会导致无法建立 section 之间的引用，此时就需要使用在链接脚本中使用 KEEP()。在 OpenSBI 项目中，没有观察到这样的情况。

## 测试增加的 Section GC 功能是否会影响 OpenSBI 的正常功能

我们需要确保 Section GC 的引入不会破坏其功能。

### 测试三种引导方式

OpenSBI 有三种引导内核的方式：

- FW_PAYLOAD：下一引导阶段被作为 payload 打包进来，通常是 U-Boot 或 Linux。这是兼容 Linux 的 RISC-V 硬件所使用的默认 firmware。

- FW_JUMP：跳转到一个固定地址，该地址上需存有下一个加载器。QEMU 的早期版本曾经使用过它。

- FW_DYNAMIC：根据前一个阶段传入的信息加载下一个阶段。通常是 U-Boot SPL 使用它。现在 QEMU 默认使用 FW_DYNAMIC。

我们需要确保这三种方式都能正常工作，编写以下 Bash 脚本：

```bash
CROSS_COMPILE=riscv64-linux-gnu- make PLATFORM=generic FW_PAYLOAD_PATH=$Image_PATH -j16

qemu-system-riscv64 -M virt -kernel ./Image -append 'rootwait root=/dev/vda ro' -nographic --bios ./build/platform/generic/firmware/fw_dynamic.bin
qemu-system-riscv64 -M virt -kernel ./Image -append 'rootwait root=/dev/vda ro' -nographic --bios ./build/platform/generic/firmware/fw_jump.bin
qemu-system-riscv64 -M virt -nographic --bios ./build/platform/generic/firmware/fw_payload.bin
```

都能够正常运行。

### Payload 是否被正常引用

FW_PAYLOAD 打包了下一阶段的程序，例如内核。如果没有引用 payload，payload 将会被链接器删除。

分析这部分代码：

```assembly
fw_next_addr:
	lla	a0, payload_bin
	ret

	.section .entry, "ax", %progbits
	.align 3
	.global fw_next_mode
	/*
	 * We can only use a0, a1, and a2 registers here.
	 * The next address should be returned in 'a0'.
	 */
```

`fw_next_addr` 会使用到 `payload_bin` 这个符号。

```assembly
	.section .payload, "ax", %progbits
	.align 4
	.globl payload_bin
payload_bin:
#ifndef FW_PAYLOAD_PATH
	wfi
	j	payload_bin
#else
	.incbin	FW_PAYLOAD_PATH
#endif
```

`payload_bin` · 位于 `.payload` section 中。

可以得出结论：`fw_next_addr` 引用到了 `payload_bin`，导致 `.payload` section 被保留。所以 `.payload` 不需要额外的 KEEP()。

### 单元测试

此外 OpenSBI 还有 SBIUNIT tests 功能。开启后，每次运行 OpenSBI 时都会进行单元测试。

![image-20240927212453431](/wp-content/uploads/2022/03/riscv-linux/images/20240920-section-gc-for-opensbi/image-20240927212453431.png)

经过测试，也能正常运行。

### 完整 Linux 内核与用户态环境

```
qemu-system-riscv64 -M virt -kernel ../linux/arch/riscv/boot/Image \
					-nographic \
					--bios ./build/platform/generic/firmware/fw_dynamic.bin \
                    -append "root=/dev/vda rw console=ttyS0"             \
                    -drive file=./rootfs.ext2,format=raw,id=hd0\
                    -device virtio-blk-device,drive=hd0
```

正常运行：

![image-20240929192301894](/wp-content/uploads/2022/03/riscv-linux/images/20240920-section-gc-for-opensbi/image-20240929192301894.png)

除此之外，我们还测试了 LLVM 对该功能的兼容性。

### OpenSBI 的 PIE 支持

使用 riscv64-unknown-elf-gcc 工具链编译 OpenSBI v1.5.1 会报错 `Your linker does not support creating PIEs, opensbi requires this.`。然而，README 中明确的写到使用不支持 PIE 的工具链会生成一个 static linked firmware images。这里存在一些问题。

经过调查，总结了 OpenSBI 中关于 PIE 的改动。

| 日期      | Commit SHA | Title                                            | 备注                                               |
|---------|------------|--------------------------------------------------|--------------------------------------------------|
| 2021 年 3 月 | 0f20e8     | firmware: Support position independent execution | 加入了 PIE 支持                                    |
| 2021 年 4 月 | bf3ef5     | firmware: Enable FW_PIC by default               | 默认启用 PIE                                       |
| 2024 年 3 月 | 76d7e9     | firmware: remove copy-base relocation            | 强制要求 PIE，删除了宏 BOOT_STATUS_RELOCATE_DONE 等 |

目前看来是最新一次改动强制要求 PIE 后，没有修改文档。但是强制要求 PIE 的必要性仍然有待商榷。

暂时先修改文档，使其与代码行为一致。

### 增加 Kconfig 配置项

使用户可以在 menuconfig 中选择编译选项。

```
menu "Compiler Options"

	choice
		prompt "Compiler optimization level"
		default CC_OPTIMIZE_FOR_PERFORMANCE

	config CC_OPTIMIZE_FOR_PERFORMANCE
		bool "Optimize for performance (-O2)"
        help
          Enable this option to compile with the -Os flag, which optimizes
          the code for size.

	config CC_OPTIMIZE_FOR_SIZE
		bool "Optimize for size (-Os)"
        help
          Enable this option to compile with the -O2 flag, which optimizes
          the code for speed.

	endchoice

endmenu
```

同时需要修改 Makefile 文件：

```
ifdef CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
CFLAGS += -O2
else ifdef CONFIG_CC_OPTIMIZE_FOR_SIZE
CFLAGS += -Os
endif
```

## 总结

经过以上完善的测试，我们可以把 Section GC 功能的 Patch 整理发送到上游了。

## 参考资料

- [Section GC 分析 - Part 1 原理简介][001]
- [Section GC 分析 - Part 2 gold 源码解析][002]
- [Section GC 分析 - Part 3 引用建立过程][003]

[001]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230526-section-gc-part1.md
[002]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230526-section-gc-part2.md
[003]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230615-section-gc-part3.md
