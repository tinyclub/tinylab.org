---
layout: post
author: 'yjmstr'
title: 'GCC RISC-V ISA 扩展支持'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-isa-extensions-discovery-2-gcc/
description: 'GCC RISC-V ISA 扩展支持'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [codeinline urls refs]
> Author:    YJMSTR [jay1273062855@outlook.com](https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:jay1273062855@outlook.com)
> Date:      2023/08/02
> Revisor:   Bin Meng, Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   ISCAS


## 前言

本文是 RISC-V 扩展软硬件支持系列的第 2 篇文章，将介绍 GCC 对 RISC-V 扩展的检测与支持方式。在本系列第 1 篇文章中已经介绍过 RISC-V 扩展的命名、分类与硬件支持现状。

## GCC 简介

GCC 是指 GNU Compiler Collection，其提供了多种语言的编译器，支持多种处理器架构。使用 `gcc` 命令编译程序时，我们使用的其实是 GCC 工具包中提供的编译器（GNU C Compiler，注意区分 GCC 与 `gcc` 命令），而使用 `g++` 命令编译时，我们使用的是 GCC 提供的 GNU C++ Compiler。

要在我们日常使用的 x86-64 架构或 ARM 架构设备上使用 GCC 编译出能在 RISC-V 架构运行的程序（交叉编译），就需要配置交叉编译工具链（或者可以选择直接使用 [RISC-V Lab][001]，在 RISC-V 架构下进行开发）。某些 Linux 发行版（如 Ubuntu）会自带交叉编译工具链。

本文将以 GCC-13.2.0 作为分析对象。

## 构建可以编译 RISC-V 的 GCC

我们可以从 [riscv-gnu-toolchain 仓库][004] 克隆工具链（大陆用户可以选择从 [软件所镜像站][005] 进行克隆），其中包含了 GCC。克隆下来的仓库根目录下包含的配置文件会帮我们完成大部分的配置，使我们能够轻松编译出可以进行交叉编译的 GCC。配置工具链的教程可以参考[软件所的文章][006]。

在克隆完 gcc 子模块后进入 gcc 目录下，通过 `git checkout releases/gcc-13.2.0` 命令切换到 13.2.0 版本。然后回到上级目录下继续按照教程进行编译即可。

假设我们将 gcc 安装到了 `$RVGCC`，将 `$RVGCC/bin` 添加到 PATH 环境变量中，在 `$HOME/.profile` 中添加 `PATH="$RVGCC/bin:$PATH"`，随后 `source $HOME/.profile`，即可在终端中使用 `riscv64-unknown-elf-gcc`。`riscv64-unknown-elf-gcc -v` 得到的输出如下：

```bash
Using built-in specs.
COLLECT_GCC=riscv64-unknown-elf-gcc
COLLECT_LTO_WRAPPER=/path/to/riscv-gcc13.2.0-install/libexec/gcc/riscv64-unknown-elf/13.2.0/lto-wrapper
Target: riscv64-unknown-elf
Configured with: /path/to/riscv-gnu-toolchain/gcc13.2.0-build/../gcc/configure --target=riscv64-unknown-elf --prefix=/path/to/riscv-gcc13.2.0-install --disable-shared --disable-threads --enable-languages=c,c++ --with-pkgversion=gc891d8dc23e --with-system-zlib --enable-tls --with-newlib --with-sysroot=/path/to/riscv-gcc13.2.0-install/riscv64-unknown-elf --with-native-system-header-dir=/include --disable-libmudflap --disable-libssp --disable-libquadmath --disable-libgomp --disable-nls --disable-tm-clone-registry --src=../../gcc --disable-multilib --with-abi=lp64d --with-arch=rv64imafdc --with-tune=rocket --with-isa-spec=20191213 'CFLAGS_FOR_TARGET=-Os    -mcmodel=medlow' 'CXXFLAGS_FOR_TARGET=-Os    -mcmodel=medlow'
Thread model: single
Supported LTO compression algorithms: zlib zstd
gcc version 13.2.0 (gc891d8dc23e)
```

如果在编译时使用 `make linux` 命令代替 `make`，可以得到使用 glibc 的 `riscv64-unknown-linux-` 工具链。

## Machine-Dependent Options

GCC 通过用户传入的参数来决定要生成那种处理器架构的代码，在传递的参数中启用/关闭某些扩展可能会导致 GCC 最终生成不同的代码。

GCC 提供了 Machine-Dependent Options，来为不同的设备提供特殊的选项。对于 RISC-V 设备，GCC 有以下特殊选项与 RISC-V ISA 扩展相关：

- -march=*ISA-string*: 给定 RISC-V ISA 字符串，以生成对应 ISA 的代码。*ISA-string* 必须是小写的，如 `rv64i`，`rv32g`。若没有指定 -march，使用 -mcpu 的设定。若 -march 和 -mcpu 都没有指定，就使用系统默认值。
- -mcpu=*processor-string*: *processor-string* 指定处理器架构，例如 `sifive-e20`。
- -mabi=*ABI-string*: 指定 int 和 long 的位数以及浮点类型使用的寄存器。*ABI-string* 目前的可选值包括 `ilp32`，`ilp32f`，`ilp32d`，`lp64`，`lp64f`，`lp64d`。前面的 i，l 分别表示 int 和 long，p 表示指针，后面跟着的数字 32/64 表示这些类型所占的位数，其后 f 表示 float 类型的参数可以通过浮点寄存器进行传递，d 表示 float 和 double 类型的参数都可以通过浮点寄存器进行参数传递，如果 f 和 d 都没有，就用整数寄存器传递浮点数参数。其中 `lp64`，`lp64f`，`lp64d` 隐含了 int 为 32 位这一信息。
- -misa-spec=*ISA-spec-string*：指定 GCC 生成的代码要服从哪个版本的非特权级规范。*ISA-spec-string* 的可选值包括 `2.2`，`20190608`，`20191213`，分别对应这三个版本的非特权级规范。GCC 默认 `-misa-spec=20191213`，可以通过 `--with-isa-spec=` 来更改默认值。

此外，在安装 GCC 时需要进行配置（Configuration，在 RISC-V Lab 中通过 apt 安装 gcc-13 时自动完成了这一步），配置时可以通过 `--with-arch=` 参数指定 `-march` 的默认值，以及 `--with-abi=` 参数指定 `-mabi` 选项的默认值。例如前言一节中我们在 RISC-V Lab 中键入 `gcc-13 -v` 得到的输出中，就有 `--with-arch=rv64gc --with-abi=lp64d`。

GCC 需要对用户输入的参数进行解析，来判断应该生成哪些扩展组合下的程序。

## 向 GCC 中添加 RISC-V ISA 扩展支持

要搞清楚如何向 GCC 中添加对某个 RISC-V 扩展的支持，我们可以找一个向 GCC 添加 RISC-V 扩展的具体 patch 进行分析。总结出的流程如下：

`gcc/common/config/riscv/riscv-common.cc` 包含了 GCC 处理 RISC-V Target 时要用到的大部分定义与处理函数。文件开头首先是各扩展间的依赖信息，如果我们添加的扩展与其它扩展之间存在依赖（例如实现 d 扩展的系统必须实现 f 扩展，则有依赖 `{"d", "f"}`），需要在此处添加相应内容：

```c
// gcc/common/config/riscv/riscv-common.cc:48
/* Implied ISA info, must end with NULL sentinel. */
static const riscv_implied_info_t riscv_implied_info[] =
{
  {"d", "f"},
  {"f", "zicsr"},
  {"d", "zicsr"},
  //此处省略部分代码
  ...
  {"zhinx", "zhinxmin"},
  {"zhinxmin", "zfinx"},

  {NULL, NULL}
};
```

以及各已实现扩展的版本信息，如果要添加的扩展不在 RISC-V ISA spec 中，此处的 ISA spec 列应填 ISA_SPEC_CLASS_NONE，否则填对应版本 spec 的字符串：

```c
// gcc/common/config/riscv/riscv-common.cc:125
static const struct riscv_ext_version riscv_ext_version_table[] =
{
  /* name, ISA spec, major version, minor_version. */
  {"e", ISA_SPEC_CLASS_20191213, 1, 9},
  {"e", ISA_SPEC_CLASS_20190608, 1, 9},
  {"e", ISA_SPEC_CLASS_2P2,      1, 9},
  //此处省略部分代码
  ...
  {"xtheadsync", ISA_SPEC_CLASS_NONE, 1, 0},

  /* Terminate the list. */
  {NULL, ISA_SPEC_CLASS_NONE, 0, 0}
};
```

继续往下翻来到该文件的 1180 行左右，可以看见一个表格，其包含了扩展与 gcc 内部 flag 间的映射关系，我们要在这里添加对应内容：

```c
// gcc/common/config/riscv/riscv-common.cc:1178
/* Type for pointer to member of gcc_options. */
typedef int (gcc_options::*opt_var_ref_t);

/* Types for recording extension to internal flag. */
struct riscv_ext_flag_table_t {
  const char *ext;
  opt_var_ref_t var_ref;
  int mask;
};

/* Mapping table between extension to internal flag. */
static const riscv_ext_flag_table_t riscv_ext_flag_table[] =
{
  {"e", &gcc_options::x_target_flags, MASK_RVE},
  {"m", &gcc_options::x_target_flags, MASK_MUL},
  // 此处省略部分代码
  ...
}
```

再往下的几个函数是对传入的 ISA 相关参数的解析，这段代码会将传入的 ISA-string 解析为上一段代码中定义的选项掩码。本文的上一小节介绍了 ISA 相关的选项，添加扩展时不用修改这里。

然后把目光转移到 `gcc/config/riscv` 目录下，这个目录包含了与 RISC-V 相关的配置文件。在 riscv-opts.h 这个头文件中可以看见 RISC-V 相关选项的枚举类定义，如支持的 abi 种类、ISA 版本等。此外还有一部分与扩展有关的宏定义，如各类扩展对应的位掩码等。riscv.opt 这个文件中将 RISC-V ISA 划分为了多个子集，每个子集有一个对应的 TargetVariable 变量。riscv-opts.h 文件中会将 TargetVariable 与该子集中扩展对应的掩码进行按位与，来判断某一扩展是否启用，例如：

```c
// gcc/config/riscv/riscv-opts.h:79
#define MASK_ZICSR    (1 << 0)
#define MASK_ZIFENCEI (1 << 1)

#define TARGET_ZICSR    ((riscv_zi_subext & MASK_ZICSR) != 0)
#define TARGET_ZIFENCEI ((riscv_zi_subext & MASK_ZIFENCEI) != 0)
```

如果我们要添加的扩展不属于任何一个现有子集，就需要同时修改 riscv-opts.h 与 riscv.opt 这两个文件。

随后来到关键的一步：向 GCC 中添加该扩展的指令！在添加指令之前，建议先学习[软件所的 RISC-V GCC 课程][007]，了解一些基本概念，这个课程的最后一节也介绍了向 GCC 中添加指令的方法，本文不再展开。此外，在网上可以找到 2018 年的一篇[会话][008]，其中提到了几种添加 RISC-V 指令支持的方式，总结如下：

1. 在 Binutils 中实现指令。Binutils 是 GNU 提供的一系列二进制工具的集合，包含链接器等。Binutils 提供了 .insn 文件的模板，直接改模板就行。如果要添加的扩展已经在 Binutils 中实现了对扩展包含的指令的支持，就只需要按上文提到的步骤在 GCC 中添加相关定义即可，实现较为简单。
2. 改 `gcc/config/riscv/riscv.md` 文件。这个文件是 GCC 中 RISC-V 的机器描述文件，GCC 会根据该文件中的指令模板来生成指令对应的函数，指令模板使用 RTL 编写。

## 总结

本文简要介绍了 GCC 对 RISC-V ISA 扩展的支持方式，包括交叉编译工具链的配置、ISA 相关的参数、对参数的解析、向 GCC 添加对某一 RISC-V 扩展支持的步骤等。如果想要进一步学习 GCC 与 RISC-V，可以参考[软件所的课程][007]。后续文章将介绍 QEMU、Linux 等软件对 RISC-V 扩展的检测、支持方式。

## 参考资料

- [RISC-V lab 仓库地址][001]
- [gcc-13.2.0 在线文档][002]
- [gcc-13 changelog][003]
- [riscv-gnu-toolchain 仓库][004]
- [软件所 riscv 工具链镜像][005]
- [制作交叉工具链 riscv-gnu-toolchain 汪辰][006]
- [零基础入门 RISC-V GCC 编译器开发 暨 编译技术入门与实战第四季][007]
- [How to add a custom instruction to the RISC-V GCC tools?][008]

[001]: https://gitee.com/tinylab/riscv-lab
[002]: https://gcc.gnu.org/onlinedocs/gcc-13.2.0/gcc/
[003]: https://gcc.gnu.org/gcc-13/changes.html
[004]: https://github.com/riscv-collab/riscv-gnu-toolchain
[005]: https://help.mirrors.cernet.edu.cn/riscv-toolchains/
[006]: https://gitee.com/aosp-riscv/working-group/blob/master/articles/20220721-riscv-gcc.md
[007]: https://www.bilibili.com/video/BV1kU4y137Ba
[008]: https://groups.google.com/a/groups.riscv.org/g/sw-dev/c/sL_OHXYj3LY/m/Gsm6sBc9BQAJ?pli=1
