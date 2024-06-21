---
layout: post
author: 'Bin Meng'
title: 'RISC-V Semihosting 技术'
draft: false
plugin: 'mermaid'
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-semihosting/
description: 'RISC-V Semihosting 技术'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - Semihosting
  - 调试
  - 半主机
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces codeinline images urls]
> Author:    Bin Meng <bmeng@tinylab.org>
> Date:      2023/05/20
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

作为一名嵌入式开发工程师，在调试问题时最常用到的调试手段是什么？可能大多数人都会回答：串口打印 :-) 嵌入式系统通常会通过一个串口与主机的终端连接，在早期调试启动引导程序的时候，如果没有调试器的帮助，可见的调试手段就只有通过串口打印了。

但是，通过串口打印来调试的方法，先决条件是串口驱动程序必须能正常工作，这对于如今越来越复杂的片上系统芯片来说，工作量可能会比较大。比如使能一个串口，可能需要先初始化好时钟模块、电源模块、管脚复用等。

串口打印输出可能还只是众多调试场景中的一种比较简单的情况。有些复杂一点的场景，比如开发相机固件特别是图像处理算法时，我们可能经常需要将图像传输至主机端进行分析，这种场景下工作量就会相当可观，一般来说可行的办法有：

* 把图像以文件的形式保存到目标设备的可拔插的存储介质上，那就要求我们要有可用的存储介质的驱动（如 SD 卡）以及一个简单的文件系统（如 FAT）
* 把图像通过网络协议（如 FTP）传输到主机侧，那就要求我们要有可用的网络接口驱动以及一个简单的 TCP/IP 协议栈

有没有一种办法，能借助更强大的主机来简化我们的开发工作，方便我们的调试呢？

## Semihosting

### 技术概览

Semihosting（以下译作 “半主机”）是一种机制，它使在目标机处理器（如 Arm、RISC-V 等）上运行的代码能够与正在运行调试器的主机进行通信并使用其 I/O 设施。这些设施包括键盘输入、屏幕输出和磁盘 I/O。比如我们可以通过该机制使 C 库中的函数（如 printf() 和 scanf()）能够使用主机的屏幕和键盘，而无需在目标系统上具备屏幕和键盘。

半主机通过在目标系统上运行的代码和调试器的巧妙组合来执行诸如文件输入/输出和在控制台打印等任务。半主机最早由 Arm 公司在 1995 年定义，并以 Arm [半主机规范][001] 的形式提供。它被许多调试器实现，并在许多库中得到支持。半主机通过一组定义的软件指令（例如 Arm 的 SVC 指令，RISC-V 的 ebreak 指令）序列来实现，这些指令会从程序控制中产生异常。应用程序调用适当的半主机调用，然后调试代理（debug agent）处理异常。调试代理提供与主机的所需通信。

RISC-V 版本的 [半主机规范][002] 基于 Arm 的规范，调整了 Arm 规范中半主机调用请求的软件指令序列和寄存器调用约定使之适应 RISC-V 架构，其他则跟 Arm 版本完全一致。

Semihosting 这个词包含了拉丁词 semi（一半）的含义，因为该操作的一半在目标设备上执行，另一半在主机上执行。半主机操作在调试开发平台上调试应用程序时，程序调用路径如下图所示（以 RISC-V 为例）：

![RISC-V Semihosting](/wp-content/uploads/2022/03/riscv-linux/images/riscv_semihosting/semihosting_overview.png)

目标板上的程序调用 printf() 函数，直接在主机端的屏幕上显示出来了 “hello”，神奇吧？

### 实现原理

下面我们以上面打印的例子来说明半主机的实现原理。

目标设备上的应用程序调用类似 printf() 的标准库函数，在库的底层，它不会将其重定向到串口，而是准备好要发送的数据后，使用特殊的一组预定义的软件指令通知调试器。调试器收到通知后，检测到这是一个接收数据的特殊异常，然后执行对应这个特殊异常的 “异常处理程序”，即读取要发送的数据，然后将其显示在主机侧的终端上。

以 RISC-V 为例，下面这组特殊的指令序列向调试器表明，这是目标板发起了一个半主机操作请求：

```
    slli x0, x0, 0x1f       # 0x01f01013    NOP 指令，表明半主机调用请求开始
    ebreak                  # 0x00100073    断点异常陷入到调试器
    srai x0, x0, 7          # 0x40705013    NOP 指令，表明半主机调用请求结束
```

RISC-V 规范使用了一个巧妙的技巧，即在 ebreak 指令周围添加额外的指令来帮助调试器区分 “半主机 ebreak” 和 “常规 ebreak”。这种方式可以使调试器识别出特定的半主机操作。注意，这三个指令必须是 32 位宽的指令，不能是压缩的 16 位 RVC 指令，因为 32 位宽的指令序列确保能在所有的 RISC-V 处理器中使用。如果处理器当前模式下正在使用 MMU 分页机制，这个序列不能跨越页面边界，这要求半主机系统必须能够检查半主机序列，从而无需从可能缺失的页面获取指令数据。下面这个半主机请求函数演示了如何通过将序列放置在单独的函数中并对其进行对齐来实现这一点，以防止跨越页面边界。

```
    .option norvc
    .text
    .balign 16
    .global sys_semihost
    .type sys_semihost @function
sys_semihost:
    slli zero, zero, 0x1f
    ebreak
    srai zero, zero, 0x7
    ret
```

### 参数和返回值

每个半主机调用都由一个编号来标识，在执行半主机 ebreak 指令序列之前，该编号被放置在 a0 寄存器中。如果操作需要参数，它们将被放置在内存中，并将内存地址记录在 a1 寄存器里。主机/调试器执行完半主机调用的操作后，调试器将在 a0 寄存器中放置该操作的返回值。

下面的图示显示了 RISC-V 架构上的半主机调用过程的状态图，左侧是目标机，右侧是主机和调试器：

<pre><div class="mermaid">
stateDiagram-v2
direction LR
state RISC-V semihosting {
state 目标机 {
prepare: 准备半主机调用号（a0）及其参数（a1）
ebreak: 执行半主机 ebreak 指令序列
return: 读取返回值（a0）并处理

prepare --> ebreak
ebreak --> detect
unhalt --> return
}
--
state 主机/调试器 {
poll: 轮询 CPU HALT 状态
detect: 检测半主机 ebreak 指令序列
read: 读取半主机调用号（a0）及其参数（a1）
exec: 执行半主机调用请求
done: 返回请求结果到 a0 寄存器
unhalt: 目标机处理器继续执行

poll --> detect
detect --> read
detect --> detect
read --> exec
exec --> done
done --> unhalt
unhalt --> poll
}
}
</div></pre>

（[下载由 Mermaid 生成的 PNG 图片][007]）

### 功能简介

规范一共定义了 24 种半主机调用，调用名称及功能号分别是：

| Name              | No.  |
|-------------------|------|
| SYS_OPEN          | 0x01 |
| SYS_CLOSE         | 0x02 |
| SYS_WRITEC        | 0x03 |
| SYS_WRITE0        | 0x04 |
| SYS_WRITE         | 0x05 |
| SYS_READ          | 0x06 |
| SYS_READC         | 0x07 |
| SYS_ISERROR       | 0x08 |
| SYS_ISTTY         | 0x09 |
| SYS_SEEK          | 0x0a |
| SYS_FLEN          | 0x0c |
| SYS_TMPNAM        | 0x0d |
| SYS_REMOVE        | 0x0e |
| SYS_RENAME        | 0x0f |
| SYS_CLOCK         | 0x10 |
| SYS_TIME          | 0x11 |
| SYS_SYSTEM        | 0x12 |
| SYS_ERRNO         | 0x13 |
| SYS_GET_CMDLINE   | 0x15 |
| SYS_HEAPINFO      | 0x16 |
| SYS_EXIT          | 0x18 |
| SYS_EXIT_EXTENDED | 0x20 |
| SYS_ELAPSED       | 0x30 |
| SYS_TICKFREQ      | 0x31 |

从上表可以看出，功能大致可以分为以下几类：

- 文件 I/O，如 SYS_OPEN，SYS_READ，SYS_WRITE 等
- 终端 I/O，如 SYS_READC，SYS_WRITEC 等
- 获取半主机上下文信息，如 SYS_ERRNO 等
- 改变目标机执行流程，如 SYS_EXIT 等
- 在主机侧执行 system 命令，SYS_SYSTEM
- 获取当前时钟/时间信息，如 SYS_CLOCK，SYS_TIME 等

## QEMU 实现

前文描述的半主机实现是在主机上的调试器中完成的，除了调试器支持半主机操作外，QEMU 的系统模拟模式和用户态模拟模式也支持客户机代码的半主机操作。运行在真实目标板上的代码在调试器看来就如同从 QEMU 视角看到的客户机代码，都是 “上帝” 模式，QEMU 和其运行的主机协同工作支持客户机代码的半主机调用也是顺理成章的事。

QEMU 源码树（版本号 8.0）下的 `semihosting` 目录包含了与 Arm 规范兼容的半主机支持的与体系架构无关的代码，其中的 `do_common_semihosting()` 是处理所有半主机调用的函数入口：

```C
// semihosting/arm-compat-semi.c
void do_common_semihosting(CPUState *cs)
{
    CPUArchState *env = cs->env_ptr;
    target_ulong args;
    target_ulong arg0, arg1, arg2, arg3;
    target_ulong ul_ret;
    char * s;
    int nr;
    uint32_t ret;
    int64_t elapsed;

    nr = common_semi_arg(cs, 0) & 0xffffffffU;  // 这里取出半主机调用号
    args = common_semi_arg(cs, 1);              // 这里取出半主机调用的参数

    switch (nr) {
    case TARGET_SYS_OPEN:  // 针对不同的半主机调用进行处理
    ...
    }
}
```

以 RISC-V 为例，RISC-V 体系架构对半主机的支持代码在 `trans_privileged.c.inc` 和 `cpu_helper.c`（系统模式）/ `cpu_loop.c`（用户态模式） 里，完成了检测半主机调用的特定指令序列、抛出异常并执行异常处理。

### ebreak 指令翻译

```C
// target/riscv/insn_trans/trans_privileged.c.inc
static bool trans_ebreak(DisasContext *ctx, arg_ebreak *a)
{
    target_ulong    ebreak_addr = ctx->base.pc_next;
    target_ulong    pre_addr = ebreak_addr - 4;     // ebreak 前一条指令地址，注意 -4 表明这是 32 位指令
    target_ulong    post_addr = ebreak_addr + 4;    // ebreak 后一条指令地址
    uint32_t pre    = 0;
    uint32_t ebreak = 0;
    uint32_t post   = 0;

    /*
     * The RISC-V semihosting spec specifies the following
     * three-instruction sequence to flag a semihosting call:
     *
     *      slli zero, zero, 0x1f       0x01f01013
     *      ebreak                      0x00100073
     *      srai zero, zero, 0x7        0x40705013
     *
     * The two shift operations on the zero register are no-ops, used
     * here to signify a semihosting exception, rather than a breakpoint.
     *
     * Uncompressed instructions are required so that the sequence is easy
     * to validate.
     *
     * The three instructions are required to lie in the same page so
     * that no exception will be raised when fetching them.
     */

    if (semihosting_enabled(ctx->mem_idx < PRV_S) &&
        (pre_addr & TARGET_PAGE_MASK) == (post_addr & TARGET_PAGE_MASK)) {  // 检查是否跨越页边界
        pre    = opcode_at(&ctx->base, pre_addr);       // 取出 ebreak 前一条指令
        ebreak = opcode_at(&ctx->base, ebreak_addr);    // 取出 ebreak 当前指令
        post   = opcode_at(&ctx->base, post_addr);      // 取出 ebreak 后一条指令
    }

    if (pre == 0x01f01013 && ebreak == 0x00100073 && post == 0x40705013) {  // 检查是否是半主机调用指令序列
        generate_exception(ctx, RISCV_EXCP_SEMIHOST);   // 是，抛出半主机调用异常
    } else {
        generate_exception(ctx, RISCV_EXCP_BREAKPOINT); // 不是，抛出普通的断点异常
    }
    return true;
}
```

### 系统模式

```C
// target/riscv/cpu_helper.c
void riscv_cpu_do_interrupt(CPUState *cs)
{
#if !defined(CONFIG_USER_ONLY)

    RISCVCPU *cpu = RISCV_CPU(cs);
    CPURISCVState *env = &cpu->env;
    target_ulong cause = cs->exception_index & RISCV_EXCP_INT_MASK;

    if  (cause == RISCV_EXCP_SEMIHOST) {    // 异常原因是半主机调用
        do_common_semihosting(cs);          // 调用半主机调用通用处理函数
        env->pc += 4;
        return;
    }

    ...
}
```

### 用户态模式

```C
// linux-user/riscv/cpu_loop.c
void cpu_loop(CPURISCVState *env)
{
    CPUState *cs = env_cpu(env);
    int trapnr;
    target_ulong ret;

    for (;;) {
        cpu_exec_start(cs);
        trapnr = cpu_exec(cs);
        cpu_exec_end(cs);
        process_queued_cpu_work(cs);

        switch (trapnr) {               // 检查 CPU 抛出的异常原因
        ...
        case RISCV_EXCP_SEMIHOST:       // 半主机调用异常
            do_common_semihosting(cs);  // 调用半主机调用通用处理函数
            env->pc += 4;
            break;
        ...
        }
    }
    ...
}
```

## 实战演练

### 支持半主机的 C 库

本文前面提到了，通过半主机的方式我们可以使 C 库中的函数（如 printf() 和 scanf()）能够使用主机的屏幕和键盘进行输入输出。那么问题来了，我的应用程序使用的 C 库有半主机的支持吗？传统的 glibc 并不支持半主机，但专门面向嵌入式领域的 C 库则大多实现了半主机支持。

以下是一些实现了半主机支持的 C 库：

- Newlib：Newlib 是一个广泛使用的 C 库，在其配置选项中提供了对半主机的支持。通过设置适当的编译标志和链接选项，可以启用 Newlib 的半主机支持。
- Picolibc：Picolibc 是 Newlib 的一个分支（fork），它也支持半主机。可以使用 Picolibc 的配置选项来启用半主机功能。
- Arm CMSIS（Cortex Microcontroller Software Interface Standard）：Arm 公司提供的 CMSIS 库中包含了对半主机的支持。CMSIS 是一套用于 Arm Cortex-M 处理器系列的软件接口标准，其中包括 C 库、设备驱动接口和其他实用工具。

Newlib 是一个开源的 C 库，旨在为嵌入式系统提供标准的 C 库函数支持。Newlib 与许多传统的 C 库（如 glibc）不同，它被设计为占用更少的资源，是为了在资源受限的环境中运行而设计的，并支持在不同的目标平台上进行定制。它的设计目标是可移植性和灵活性，可以根据特定的需求进行配置和优化。Newlib 支持 RISC-V 架构的半主机改动详见 [这里][003]。

Picolibc 是 Newlib 的一个分支（fork），旨在提供更小、更精简的 C 库函数集。与 Newlib 相比，Picolibc 更加精简，它只包含了核心的 C 库函数，如字符串处理、数学函数、输入输出和内存管理等。Picolibc 的设计目标是最小化代码大小和资源消耗，以便在非常有限的存储器和处理器能力的嵌入式系统上运行。

下面我们以 [Picolibc][004] 为例进行半主机代码的开发调试说明。

下面的命令首先安装了编译 Picolibc 所需要的 RISC-V GCC 工具链（注意：官方支持的是 `riscv64-unknown-elf-gcc`，`riscv64-linux-gnu-gcc` 不确定能否正常编译），然后用自带的 `do-riscv-configure` 配置 Picolibc，最后用 `ninja` 进行编译。

```shell
$ sudo apt install gcc-riscv64-unknown-elf
$ git clone https://github.com/picolibc/picolibc.git
$ cd picolibc
$ mkdir build
$ cd build
$ ../scripts/do-riscv-configure
$ ninja
$ sudo ninja install
```

编译好的 Picolibc 库可以配合 GCC 使用，利用 Picolibc 附带的 GCC .specs 文件通过 `--specs` 命令行参数告诉 `riscv64-unknown-elf-gcc` 即可。这将设置 GCC 系统头文件路径和链接库路径，使其指向 Picolibc。当我们通过 `ninja install` 将 Picolibc 安装到系统中，picolibc.specs 文件会被放置到 GCC 目录中，这样只需使用文件的基本名称即可找到它。

```shell
$ riscv64-unknown-elf-gcc --specs=picolibc.specs -c foo.c
```

如果在 config 阶段显式地配置了安装目录，如：

```shell
$ ../scripts/do-riscv-configure -Dprefix=/path/to/install/dir -Dspecsdir=/path/to/install/dir
```

Picolibc 会被安装到我们提供的目录，编译的时候则需要提供 picolibc.specs 文件的绝对路径名：

```shell
$ riscv64-unknown-elf-gcc --specs=/path/to/install/dir/picolibc.specs -c foo.c
```

Picolibc 将半主机支持的实现作为一个独立的库（libsemihost.a）进行分发。由于它提供了被 libc 自身使用的接口，因此必须在链接器命令行中将其包含在 libc 之后。可以使用由 picolibc.specs 定义的 GCC --oslib=semihost 命令行标志来实现这一点。

```shell
$ riscv64-unknown-elf-gcc --specs=/path/to/install/dir/picolibc.specs --oslib=semihost -o bar.elf bar.c
```

我们先来写一个简单的 C 程序 `main.c`：

```C
#include <stdio.h>

int main(void)
{
    printf("Hello semihosting\n");
    return 0;
}
```

编译：

```shell
$ riscv64-unknown-elf-gcc --specs=/path/to/install/dir/picolibc.specs --oslib=semihost -march=rv64imac -mabi=lp64 -mcmodel=medany -static main.c -o main
```

注意这里的 `-mcmodel=medany` 参数，没有这个参数 GCC 会用默认的 medlow 的 code model，使用 medlow 会报错：

```
/tmp/ccvn4FCp.o: in function `main':
main.c:(.text+0x8): relocation truncated to fit: R_RISCV_HI20 against `.LC0'
collect2: error: ld returned 1 exit status
```

因为我们用的是 `riscv64-unknown-elf-gcc` 工具链，需要查看下默认的链接脚本把代码段放置到什么位置了，祭出 `readelf`：

```shell
$ readelf -h main
ELF Header:
  Magic:   7f 45 4c 46 02 01 01 00 00 00 00 00 00 00 00 00
  Class:                             ELF64
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              EXEC (Executable file)
  Machine:                           RISC-V
  Version:                           0x1
  Entry point address:               0x80000000
  Start of program headers:          64 (bytes into file)
  Start of section headers:          23016 (bytes into file)
  Flags:                             0x1, RVC, soft-float ABI
  Size of this header:               64 (bytes)
  Size of program headers:           56 (bytes)
  Number of program headers:         4
  Size of section headers:           64 (bytes)
  Number of section headers:         20
  Section header string table index: 19
```

注意到 `Entry point address` 正好是 0x80000000，这是大部分 RISC-V 机器内存的起始位置。我们可以很方便地用 QEMU（版本号 8.0） `virt` 机器来验证这个可执行程序。

首先我们以如下的 QEMU 命令行运行这个程序，`-serial stdio` 实例化 `virt` 机器定义的串口并连接到主机终端窗口的标准输入：

```shell
$ qemu-system-riscv64 -M virt -bios main -display none -serial stdio
```

我们的程序并没有输出任何字符，如我们的预期那样，因为 printf 函数在 Picolibc 底层会被转化到半主机调用。

再次以新的 QEMU 命令行运行这个程序，这次我们不实例化串口（`-serial null`），但是加入 `-semihosting` 打开半主机支持：

```shell
$ qemu-system-riscv64 -M virt -bios main -display none -serial null -semihosting
Hello semihosting
```

终端窗口中出现了 `Hello semihosting` 的字符串！这里的 `-serial null` 其实不加也行，因为我们的代码没有任何操作串口寄存器的东西，显式地加入这个参数能让大家清晰地看到输出的字符串是从半主机调用到主机而非串口输出的 :-)

### 手搓裸金属程序

依赖 C 库来实现半主机操作比较方便，下面我们尝试不使用任何 C 库，而是直接按照 RISC-V 半主机规范用手搓出一个可用的裸金属程序来实现半主机操作。

首先我们改编一下之前的 main.c 文件，不包含任何 C 库头文件，直接手搓 RISC-V GCC 内联汇编：

```C
static inline void smh_puts(char *s)
{
    asm volatile("addi    a1, %0, 0\n"
                 "addi    a0, zero, 4\n"
                 ".balign 16\n"
                 ".option push\n"
                 ".option norvc\n"
                 "slli    zero, zero, 0x1f\n"
                 "ebreak\n"
                 "srai    zero, zero, 0x7\n"
                 ".option pop\n"
                 : : "r" (s) : "a0", "a1", "memory");
}

int main(void)
{
    smh_puts("Hello semihosting\n");
    return 0;
}
```

`smh_puts()` 函数改编自 Linux 内核 RISC-V 架构支持半主机的 [semihost.h][005] 文件中的 `smh_putc()` 函数，该文件来自之前笔者向 Linux 内核提交 RISC-V 架构使用半主机调用来作为早期串口输出驱动的一笔 [提交][006]。注意这里的 a0 寄存器值由 Linux 版本的 3 改为了 4，4 号半主机调用对应规范中的 SYS_WRITE0 功能，该调用将目标机上一个以 NULL 结尾的字符串在主机侧的终端上输出。

因为我们不再依赖 Picolibc 库，我们需要手动创建一个 crt0.S 汇编文件，作为启动裸金属程序的起始文件。crt0 是 C 运行时启动（C runtime startup）的简称。

```asm
    .text
    .globl _start
_start:
    li   sp, 0x80100000
    tail main
```

crt0.S 负责执行一些初始化操作，设置必要的运行时环境，然后将控制权转移到 C 语言代码的入口函数（例如 main 函数）。对于我们的 main.c 来说，由于我们没有使用任何未初始化的全局变量，crt0.S 只需要初始化好堆栈指针（stack pointer）将其设置到正确的位置即可。这里我们设置 sp 指向内存起始地址 1 MiB（0x80100000）的位置。

最后，我们还需要写一个简单的链接脚本 semihosting.ld，用来控制链接过程。

```ld
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
    . = 0x80000000;
    .text : {
        crt0.o  (.text)
        main.o  (.text)
    }

    .rodata : {
        *(.rodata*)
    }

    .data : {
        *(.data*)
    }

    .bss : {
        *(.bss*)
    }
}
```

这个链接脚本确保 crt0.o 在代码段的最开始，程序的入口地址 `_start` 被设置为内存的起始地址 0x80000000。

三个文件都已准备就绪，下面开始编译和链接：

```shell
$ riscv64-unknown-elf-gcc -nostdlib -march=rv64imac -mabi=lp64 -mcmodel=medany -static -c main.c -o main.o
$ riscv64-unknown-elf-gcc -nostdlib -march=rv64imac -mabi=lp64 -mcmodel=medany -static -c crt0.S -o crt0.o
$ riscv64-unknown-elf-ld -Tsemihosting.ld -static crt0.o main.o -o main
```

同样用 QEMU 运行这个程序：

```shell
$ qemu-system-riscv64 -M virt -bios main -display none -serial null -semihosting
Hello semihosting
```

大功告成！

## 总结

通过实践 RISC-V 体系架构上的半主机技术，我们可以看到半主机技术具有以下优点：

- 方便的调试和开发：半主机允许嵌入式应用程序与主机系统进行通信，通过主机系统的文件系统、终端和其他设备进行输入输出操作。这使得调试和开发变得更加方便，开发人员可以轻松地在嵌入式系统中输出调试信息、读取文件等。
- 节省资源：相比于在嵌入式系统中实现完整的文件系统和设备驱动程序，使用半主机可以节省宝贵的资源。半主机可以通过与主机系统的交互来代替在嵌入式系统中实现类似功能的代码，从而减少了嵌入式系统上的存储器占用和处理器负载。
- 快速开发和原型验证：半主机可以帮助快速开发和验证嵌入式应用程序的原型。通过使用半主机，开发人员可以更快地实现关键功能，并进行快速迭代和调试，而无需为完整的硬件和驱动程序开发耗费大量时间和精力。
- 灵活性和可移植性：半主机的接口是独立于特定的硬件平台和操作系统的，因此具有良好的可移植性。开发人员可以在不同的嵌入式系统和操作系统上使用相同的半主机接口来实现输入输出功能，从而提高代码的可重用性和移植性。

总的来说，半主机技术提供了方便的调试和开发环境，节省了资源，加快了开发速度，并提供了灵活性和可移植性，使嵌入式系统的开发更加高效和便捷。

## 参考资料

- [Arm Semihosting 规范][001]
- [RISC-V Semihosting 规范][002]
- [Newlib 支持 RISC-V 半主机的改动][003]
- [Picolibc 主页][004]
- [Linux 内核 RISC-V 架构 semihost.h 文件][005]
- [Linux 内核 RISC-V 架构使用半主机调用来作为早期串口输出驱动的改动][006]

[001]: https://github.com/ARM-software/abi-aa/blob/main/semihosting/semihosting.rst
[002]: https://github.com/riscv-software-src/riscv-semihosting/blob/main/riscv-semihosting-spec.adoc
[003]: https://sourceware.org/git/gitweb.cgi?p=newlib-cygwin.git;h=865cd30dcc2f00c81c8b3624a9f3464138cd24a5
[004]: https://keithp.com/picolibc/
[005]: https://github.com/torvalds/linux/blob/master/arch/riscv/include/asm/semihost.h
[006]: https://github.com/torvalds/linux/commit/db5489f4be000cbb7e7ce9cc1a264c5d3d25b56f
[007]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/riscv_semihosting/mermaid-riscv-semihosting-1.png
