---
layout: post
author: 'Bin Meng'
title: 'gdb 和 QEMU gdbstub 调试技巧'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /gdb-and-qemu-gdbstub-debug/
description: 'gdb 和 QEMU gdbstub 调试技巧'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - QEMU
  - gdb
  - gdbstub
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces]
> Author:    Bin Meng <bmeng@tinylab.org>
> Date:      2023/04/28
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

我们在调试与 QEMU 自带的 gdbstub 相关的问题时，单独调试 QEMU 的 gdbstub 可能看不到问题的全貌。俗话说“一个巴掌拍不响”，QEMU 的 gdbstub 是要跟 gdb 客户端配合使用的，如果出现 bug 也有可能是 gdb 客户端的问题。本文用一个实际例子说明 gdb 和 QEMU gdbstub 的调试技巧。

## QEMU gdbstub

调试与 QEMU 自带的 gdbstub 相关的问题时，需要熟练掌握 gdb 的远程串行调试协议。协议内容详见 [GDB Remote Serial Protocol][001]。

QEMU 里与 gdbstub 相关的代码分布在如下目录：

- gdbstub/
- gdb-xml/
- target/*/gdbstub.c

其中 gdbstub/ 目录里的 gdbstub.c 包含处理 gdb 远程串行调试协议的与体系架构无关的核心逻辑。与体系架构相关的处理逻辑都放到了各个体系架构支持的子目录里（target/*/gdbstub.c）。

gdbstub/trace-events 包含了 QEMU 自带的 trace 功能记录下来的 gdbstub 相关的事件，可供调试需要，通过 QEMU 命令行 `-d trace:gdbstub*` 打开，如下面的命令行：

```shell
$ qemu-system-riscv64 -nographic -M sifive_u,msel=11 -smp 5 -m 8G -bios u-boot-spl.bin -drive file=sdcard.img,if=sd -s -S -D gdbstub.txt -d trace:gdbstub*
```

按照给定的命令行参数启动模拟的 sifive_u 机器，将所有与 gdbstub 相关的 trace 事件日志（-d trace:gdbstub*）都写入当前目录下的 gdbstub.txt（-D gdbstub.txt） 里，查看 gdbstub.txt 可以得到 QEMU 记录的其与 gdb 客户端非常详细的交互信息。下面是日志里的一段信息，可以看到 QEMU 收到了客户端的读取 target.xml 的请求并返回了文件内容。

```
gdbstub_io_command Received: qXfer:features:read:target.xml:0,ffb
gdbstub_io_binaryreply 0x0000: 6c 3c 3f 78  6d 6c 20 76  65 72 73 69  6f 6e 3d 22  l<?xml version="
gdbstub_io_binaryreply 0x0010: 31 2e 30 22  3f 3e 3c 21  44 4f 43 54  59 50 45 20  1.0"?><!DOCTYPE
gdbstub_io_binaryreply 0x0020: 74 61 72 67  65 74 20 53  59 53 54 45  4d 20 22 67  target SYSTEM "g
gdbstub_io_binaryreply 0x0030: 64 62 2d 74  61 72 67 65  74 2e 64 74  64 22 3e 3c  db-target.dtd"><
gdbstub_io_binaryreply 0x0040: 74 61 72 67  65 74 3e 3c  61 72 63 68  69 74 65 63  target><architec
gdbstub_io_binaryreply 0x0050: 74 75 72 65  3e 72 69 73  63 76 3a 72  76 36 34 3c  ture>riscv:rv64<
gdbstub_io_binaryreply 0x0060: 2f 61 72 63  68 69 74 65  63 74 75 72  65 3e 3c 78  /architecture><x
gdbstub_io_binaryreply 0x0070: 69 3a 69 6e  63 6c 75 64  65 20 68 72  65 66 3d 22  i:include href="
gdbstub_io_binaryreply 0x0080: 72 69 73 63  76 2d 36 34  62 69 74 2d  63 70 75 2e  riscv-64bit-cpu.
gdbstub_io_binaryreply 0x0090: 78 6d 6c 22  2f 3e 3c 78  69 3a 69 6e  63 6c 75 64  xml"/><xi:includ
gdbstub_io_binaryreply 0x00a0: 65 20 68 72  65 66 3d 22  72 69 73 63  76 2d 36 34  e href="riscv-64
gdbstub_io_binaryreply 0x00b0: 62 69 74 2d  66 70 75 2e  78 6d 6c 22  2f 3e 3c 78  bit-fpu.xml"/><x
gdbstub_io_binaryreply 0x00c0: 69 3a 69 6e  63 6c 75 64  65 20 68 72  65 66 3d 22  i:include href="
gdbstub_io_binaryreply 0x00d0: 72 69 73 63  76 2d 36 34  62 69 74 2d  76 69 72 74  riscv-64bit-virt
gdbstub_io_binaryreply 0x00e0: 75 61 6c 2e  78 6d 6c 22  2f 3e 3c 78  69 3a 69 6e  ual.xml"/><xi:in
gdbstub_io_binaryreply 0x00f0: 63 6c 75 64  65 20 68 72  65 66 3d 22  72 69 73 63  clude href="risc
gdbstub_io_binaryreply 0x0100: 76 2d 63 73  72 2e 78 6d  6c 22 2f 3e  3c 2f 74 61  v-csr.xml"/></ta
gdbstub_io_binaryreply 0x0110: 72 67 65 74  3e                                     rget>
gdbstub_io_got_ack Got ACK
```

gdb-xml/ 目录下包含 QEMU 支持的所有体系架构的静态的 XML 文件，这里主要包括 CPU 通用寄存器、浮点寄存器等。如 gdb-xml/riscv-64bit-cpu.xml 文件描述了 gdb 访问 64 位 RISC-V 处理器的所有通用寄存器的信息。对于 CSR 这种与某个特定处理器实现相关的寄存器描述文件，通过 target/*/gdbstub.c 在代码里动态生成，如 RISC-V 的代码 target/riscv/gdbstub.c::riscv_gen_dynamic_csr_xml() 通过遍历检查 CSR 表里的每个 CSR 是否存在来决定是否向 gdb 客户端报告这个寄存器。

## gdb 调试

上一节简单介绍了 QEMU gdbstub 是什么，在 QEMU 里实现的代码在何处，以及 gdb 客户端连上 QEMU gdbstub 后 QEMU 侧收到的 target.xml 的读取请求。

如果 gdb 客户端连不上 QEMU gdbstub，这种情况应该怎么调试呢？下面以一个实际例子为例进行说明。

### 复现环境

实验用到的软件版本和主机系统如下：

- QEMU (v7.2.0)
- gdb-multiarch (v9.2)
- Host: Ubuntu 20.04 LTS

QEMU 命令行：

```shell
$ qemu-system-riscv64 -nographic -M virt -s -S
```

### 问题描述

gdb 连上 QEMU 调试：

```shell
$ gdb-multiarch
>>> set architecture riscv:rv64
>>> target extended-remote :1234
Remote debugging using :1234
warning: Architecture rejected target-supplied description
warning: No executable has been specified and target does not support
determining executable automatically.  Try using the "file" command.
```

注意：在 `gdb-multiarch` 连到 QEMU 侧的 gdbstub 之前，如果命令行或者 gdb shell 下没有指定被调试文件，连接到 QEMU 的 gdbstub 的时候可能会出现一个错误信息 “Truncated register 37 in remote 'g' packet”，这是因为主机端的 `gdb-multiarch` 默认配置的被调试代码的体系架构为 x86_64，而当我们没有指定被调试文件的情况下，gdb 无法根据被调试文件的类型（如 ELF 文件）来正确设置 gdb 被调试代码的体系架构，当 QEMU 这侧模拟的 CPU 体系架构不是 x86_64 就会抛出上述错误信息。在我们的例子中，使用 `set architecture` 的命令来设置 `gdb-multiarch` 被调试的目标体系架构为 riscv:rv64。

这里出现了两条 warning。第二条 warning 是正常的，因为我在启动 gdb 的时候没有给它被调试的文件，所以这条可以忽略。

### 初步分析

对于这个问题笔者的第一反应这应该是一个 QEMU regression。笔者工作的主机环境是 Ubuntu 20.04，平时多次用 gdb-multiarch 调试跑在 QEMU 上的软件，在 7.2 版本之前并没有发现这个 warning，那么一定是 QEMU 之后的某个修改引入了这个 bug。查阅 QEMU 历史，以下两个 commit 跟 gdbstub 相关：

- [target/riscv: remove fflags, frm, and fcsr from riscv-*-fpu.xml][002]
- [target/riscv: remove fixed numbering from GDB xml feature files][003]

简单测试发现只要 revert [commit][002]，这个问题便不再复现。但是仔细阅读这个 commit 的 commit message 和修改，发现改动是合理的，那么问题来了，有没有可能是原作者使用的 gdb 版本跟笔者的不一样，而新版本 gdb 的行为发生了改变？

### 编译新版本 gdb

好，我们来编译一下最新的 gdb v12.1 试试看：

```shell
$ wget https://ftp.gnu.org/gnu/gdb/gdb-12.1.tar.xz
$ tar xf gdb-12.1.tar.xz
$ cd gdb-12.1
$ mkdir build
$ cd build
$ ../configure --target=riscv64-linux --with-python=/usr/bin/python3
$ make -j$(nproc)
```

注意：如果不 `make install` 而直接从 build 目录里执行 gdb 程序，gdb python 模块不会正确的加载。gdb 的 python 模块在 <build_dir>/gdb/data-directory，需要显式的给 gdb 传入这个目录：

```shell
$ ./gdb --data-directory=./data-directory
```

果然，新版本的 gdb 不会出现这个问题。我们可以分析一下 gdb 的行为发生了什么改变，这里我们需要一些调试 gdb 程序本身的技巧。

### 深入分析

由 warning 信息我们自然地想到这个问题可能跟 gdb 的 target description 有关，在本文开始的 QEMU gdbstub 章节中笔者提到了 QEMU 会发送 target description（cpu、fpu、csr 等寄存器描述）给 gdb 客户端，那么我们在 gdb 这边可以查看一下，gdb 到底用了 QEMU 的 target description 没有。这里要用到 gdb 的命令 maintenance 中的 `print c-tdesc` 子命令，以 C 代码的形式打印出 gdb 当前所用的 target description。

用 Ubuntu 20.04 自带的 gdb-multiarch v9.2：

```
>>> maintenance print c-tdesc
The current target description did not come from an XML file.
```

可以看到 9.2 版本根本没有用到 QEMU 发送过来的 target description XML 文件？！

换刚编好的 gdb v12.1 试试：

```
>>> maintenance print c-tdesc
/* THIS FILE IS GENERATED.  -*- buffer-read-only: t -*- vi:set ro:
  Original:  */

#include "defs.h"
#include "osabi.h"
#include "target-descriptions.h"

struct target_desc *tdesc_;
static void
initialize_tdesc_ (void)
{
...
}
```

可以看到 12.1 版本的 gdb 用到了 target description，且内容跟 QEMU 发送过来的 XML 文件内容完全能对上。

注意：从 gdb v10.0 版本开始 gdb 引入了一条新命令 `maintenance print xml-tdesc`，直接打印出 XML 文件，更加直观和人性化。

```
>>> maintenance print xml-tdesc
<?xml version="1.0"?>
<!DOCTYPE target SYSTEM "gdb-target.dtd">
<target>
  <architecture>riscv:rv64</architecture>
  <feature name="org.gnu.gdb.riscv.cpu">
    <reg name="zero" bitsize="64" type="int" regnum="0"/>
    <reg name="ra" bitsize="64" type="code_ptr" regnum="1"/>
...
```

至此，我们可以非常确信这个问题跟 gdb 不同版本处理 RISC-V 的 target description 有关了。在 gdb 源码里搜索 warning 的文本 “Architecture rejected target-supplied description”，看到 `./gdb/target-descriptions.c::target_find_description()` 函数打印出的 warning：

```c
  if (tdesc_info->tdesc != nullptr)
    {
      struct gdbarch_info info;

      info.target_desc = tdesc_info->tdesc;
      if (!gdbarch_update_p (info))
        warning (_("Architecture rejected target-supplied description"));
      else
```

这个 warning 在检查调用 gdbarch_update_p() 函数的返回值后打印，进一步查看 gdbarch_update_p() 函数发现它里面有很多调试信息打印：

```c
int
gdbarch_update_p (struct gdbarch_info info)
{
  struct gdbarch *new_gdbarch;

...

  /* If there no architecture by that name, reject the request.  */
  if (new_gdbarch == NULL)
    {
      if (gdbarch_debug)
        gdb_printf (gdb_stdlog, "gdbarch_update_p: "
          "Architecture not found\n");
      return 0;
    }

  /* If it is the same old architecture, accept the request (but don't
     swap anything).  */
  if (new_gdbarch == target_gdbarch ())
    {
      if (gdbarch_debug)
        gdb_printf (gdb_stdlog, "gdbarch_update_p: "
          "Architecture %s (%s) unchanged\n",
          host_address_to_string (new_gdbarch),
          gdbarch_bfd_arch_info (new_gdbarch)->printable_name);
      return 1;
    }

  /* It's a new architecture, swap it in.  */
  if (gdbarch_debug)
    gdb_printf (gdb_stdlog, "gdbarch_update_p: "
      "New architecture %s (%s) selected\n",
      host_address_to_string (new_gdbarch),
      gdbarch_bfd_arch_info (new_gdbarch)->printable_name);
  set_target_gdbarch (new_gdbarch);

  return 1;
}
```

调试信息的打印都受一个名叫 `gdbarch_debug` 的全局变量控制，该变量定义在这里且默认值为 0：

```c
#ifndef GDBARCH_DEBUG
#define GDBARCH_DEBUG 0
#endif
unsigned int gdbarch_debug = GDBARCH_DEBUG;
```

这不很简单嘛，修改源码将此默认值改成 1，然后再次测试即可看到调试信息输出了。

### gdb 进阶调试技巧

gdb 本身作为一个调试器，对于自己输出的调试信息还需要修改源码来控制这么 “老土” 么？答案当然是否定的，详见 [gdb 文档][004]。

这里我们需要关心这个 gdbarch。不多说，直接修改看看效果：

```
>>> show debug arch
Architecture debugging is 0.
>>> set debug arch 1
>>> show debug arch
Architecture debugging is 1.
>>> target remote :1234
Remote debugging using :1234
gdbarch_find_by_info: info.bfd_arch_info riscv:rv64
gdbarch_find_by_info: info.byte_order 1 (little)
gdbarch_find_by_info: info.osabi 5 (GNU/Linux)
gdbarch_find_by_info: info.abfd 0x0
gdbarch_find_by_info: info.tdep_info 0x0
gdbarch_find_by_info: Target rejected architecture
gdbarch_update_p: Architecture not found
warning: Architecture rejected target-supplied description
```

对比一下 12.1 版本的输出：

```
>>> target remote :1234
Remote debugging using :1234
gdbarch_find_by_info: info.bfd_arch_info riscv:rv64
gdbarch_find_by_info: info.byte_order 1 (little)
gdbarch_find_by_info: info.osabi 5 (GNU/Linux)
gdbarch_find_by_info: info.abfd 0x0
gdbarch_find_by_info: info.tdep_info 0x0
gdbarch_find_by_info: New architecture 0x55c97f9defc0 (riscv:rv64) selected
```

这里问题非常清楚了，v9.2 版本的 gdb 的 `./gdb/arch-utils.c::gdbarch_find_by_info()` 返回值检查报错：

```c
  if (new_gdbarch == NULL)
    {
      if (gdbarch_debug)
        fprintf_unfiltered (gdb_stdlog, "gdbarch_update_p: "
          "Architecture not found\n");
      return 0;
    }
```

“Target rejected architecture” 的报错信息来自 new_gdbarch 指针为空，由函数 gdbarch_find_by_info() 抛出：

```c
  /* Ask the tdep code for an architecture that matches "info".  */
  new_gdbarch = rego->init (info, rego->arches);

  /* Did the tdep code like it?  No.  Reject the change and revert to
     the old architecture.  */
  if (new_gdbarch == NULL)
    {
      if (gdbarch_debug)
        fprintf_unfiltered (gdb_stdlog, "gdbarch_find_by_info: "
          "Target rejected architecture\n");
      return NULL;
    }
```

### 问题根因和解决办法

回顾整个问题，笔者一如既往用 Ubuntu 20.04 自带的 9.2 版本的 gdb-multiarch 来调试 QEMU 7.2.0，发现了 “Architecture rejected target-supplied description” 的告警信息，换用新版本的 gdb 这个问题不再复现。虽然 revert QEMU v7.2.0 的这个 [commit][002] 可以使问题消失，但仔细分析 QEMU 这个 commit 并没有问题。真正的问题在于 gdb 侧做了修改，QEMU v7.2.0 也跟着做了相应的修改，所以这意味着 QEMU v7.2.0 其实是要配合新版本的 gdb 来使用的，严格意义上来讲 gdb 这里存在着一个向后兼容性的问题，但从 [commit][002] 的描述来看，这是对 RISC-V 体系架构早期支持过程中在 gdb/QEMU 中引入的一些 hack 的清理，选择正本清源长期来看对 RISC-V 体系架构支持肯定是具有积极意义的。

## 总结

本文介绍了一个与 QEMU gdbstub 相关的问题调试实例，其中牵涉了一些 QEMU gdbstub 本身的调试思路和 gdb 客户端的高级调试技巧，希望在读者遇到类似问题时能够有所启发。

## 参考资料

- [GDB Remote Serial Protocol][001]
- [QEMU commit: target/riscv: remove fflags, frm, and fcsr from riscv-*-fpu.xml][002]
- [QEMU commit: target/riscv: remove fixed numbering from GDB xml feature files][003]
- [GDB Debugging Output][004]

[001]: https://sourceware.org/gdb/onlinedocs/gdb/Remote-Protocol.html
[002]: https://gitlab.com/qemu-project/qemu/-/commit/94452ac4cf263e8996613db8d981e4ea85bd019a
[003]: https://gitlab.com/qemu-project/qemu/-/commit/4c0f0b6619126637e802f07c9fe8e9fffbc1c4bb
[004]: https://sourceware.org/gdb/onlinedocs/gdb/Debugging-Output.html
