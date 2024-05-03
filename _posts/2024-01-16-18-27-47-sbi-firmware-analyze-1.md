---
layout: post
author: 'Groot'
title: 'OpenSBI 固件代码分析（一）：启动流程'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /sbi-firmware-analyze-1/
description: 'OpenSBI 固件代码分析（一）：启动流程'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - OpenSBI
  - 固件分析
  - 启动流程
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [tables urls refs autocorrect epw]
> Author:    groot <gr00t@foxmail.com>
> Date:      2023/07/28
> Revisor:   Falcon [falcon@tinylab.org](https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:falcon@tinylab.org)
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V Linux 内核 SBI 调用技术分析](https://gitee.com/tinylab/riscv-linux/issues/I64YC4)
> Sponsor:   PLCT Lab, ISCAS


## 前言

之前的文章给大家介绍了一下 SBI 和 OpenSBI，不过并没有特别深入地分析 OpenSBI 的整个流程。接下来我将带领读者从源码开始剖析，分析 OpenSBI 的启动流程，逐渐深入地学习 OpenSBI。

因为 OpenSBI 的启动过程从 `firmware/fw_base.S` 这个文件开始，所以我将从这个文件开始带领读者阅读 OpenSBI 的固件源码部分，探索 OpenSBI 的世界。

## 三种固件类型

该内容链接到 [《QEMU 启动方式分析（4）: OpenSBI 固件分析与 SBI 规范的 HSM 扩展》][003] 的第四部分，这里不做过多的赘述。

如果读者对这方面并不感兴趣，这里给出相关内容的简略概述：

* FW_PAYLOAD 类型固件打包了二进制文件和固件，适用于无法同时加载 OpenSBI 和 Runtime 的下一引导阶段。
* FW_JUMP 类型固件能够跳转到下一引导阶段的入口，需要在编译时指定下一引导阶段要加载的地址。
* FW_DYNAMIC 类型固件可以从上一引导阶段获得 Runtime 的下一个入口地址，无需在编译时指定。使用 struct fw_dynamic_info 结构体提供信息。

如果想指定某个启动方式，可以在编译的时候使用 `PLATFORM` 参数进行指定。

```bash
make PLATFORM=<platform_subdir>
```

如果使用 `FW_PAYLOAD` 方式，可以在编译的时候使用 `FW_PAYLOAD_PATH` 进行指定。

```shell
make PLATFORM=<platform_subdir> FW_PAYLOAD_PATH=<payload path>
```

同时，选择 `FW_OPTIONS` 来控制 `OpenSBI` 在运行时是否输出，具体的 `options` 支持可以在文件 `include/sbi/sbi_scratch.h` 代码 `enum sbi_scratch_options` 中查看。

```bash
make PLATFORM=<platform_subdir> FW_OPTIONS=<options>
```

## RISC-V 汇编预知识

### 通用寄存器

risc-v 有 32 个通用寄存器（简写 reg），标号为 `x0` - `x31`

| 寄存器 | 编程接口名称（ABI） | 描述                            | 使用                               |
|--------|-------------------|---------------------------------|------------------------------------|
| x0     | zero              | Hard-wired zero                 | 硬件零                             |
| x1     | ra                | Return address                  | 常用于保存（函数的）返回地址         |
| x2     | sp                | Stack pointer                   | 栈顶指针                           |
| x3     | gp                | Global pointer                  | —                                  |
| x4     | tp                | Thread pointer                  | —                                  |
| x5-7   | t0-2              | Temporary                       | 临时寄存器                         |
| x8     | s0/fp             | Saved Register/ Frame pointer   | （函数调用时）保存的寄存器和栈顶指针 |
| x9     | s1                | Saved register                  | （函数调用时）保存的寄存器           |
| x10-11 | a0-1              | Function argument/ return value | （函数调用时）的参数/函数的返回值    |
| x12-17 | a2-7              | Function argument               | （函数调用时）的参数                 |
| x18-27 | s2-11             | Saved register                  | （函数调用时）保存的寄存器           |
| x28-31 | t3-6              | Temporary                       | 临时寄存器                         |

### 指令格式

RISC-V 基本整数指令集（"I"）有六种指令格式：

* R 类型指令：用于寄存器 - 寄存器操作；
* I 类型指令：用于短立即数和访存 load 操作；
* S 类型指令：用于访存 store 操作；
* B 类型指令：用于条件跳转操作；
* U 类型指令：用于长立即数操作；
* J 类型指令：用于无条件操作；
  ![RISC-V 指令格式](/wp-content/uploads/2022/03/riscv-linux/images/sbi-firmware/instruction-spec.png)

### 常见指令

这里不再花费篇幅给大家介绍常见指令，大家可以通过互联网学习相关内容。

对于初学者，我推荐可以先从 [《rvbook》][001] 和 [《RISC-V Assembly Programmer&#39;s Manual》][004] 开始学起。

### 汇编指示符

RISC-V 的汇编指示符和作用如下

| 指示符          | 作用                                                                                |
|:----------------|:----------------------------------------------------------------------------------|
| .text           | 代码段，之后跟的符号都在 .text 内                                                    |
| .data           | 数据段，之后跟的符号都在 .data 内                                                    |
| .bss            | 未初始化数据段，之后跟的符号都在 .bss 中                                             |
| .section .foo   | 自定义段，之后跟的符号都在.foo 段中，.foo 段名可以做修改                              |
| .align n        | 按 2 的 n 次幂字节对齐                                                              |
| .balign n       | 按 n 字节对齐                                                                       |
| .globl sym      | 声明 sym 为全局符号，其它文件可以访问                                                |
| .string “str”   | 将字符串 str 放入内存                                                               |
| .byte b1,…,bn   | 在内存中连续存储 n 个单字节                                                         |
| .half w1,…,wn   | 在内存中连续存储 n 个半字（2 字节）                                                   |
| .word w1,…,wn   | 在内存中连续存储 n 个字（4 字节）                                                     |
| .dword w1,…,wn  | 在内存中连续存储 n 个双字（8 字节）                                                   |
| .float f1,…,fn  | 在内存中连续存储 n 个单精度浮点数                                                   |
| .double d1,…,dn | 在内存中连续存储 n 个双精度浮点数                                                   |
| .option rvc     | 使用压缩指令 (risc-v c)                                                             |
| .option norvc   | 不压缩指令                                                                          |
| .option relax   | 允许链接器松弛（linker relaxation，链接时多次扫描代码，尽可能将跳转两条指令替换为一条） |
| .option norelax | 不允许链接松弛                                                                      |
| .option pic     | 与位置无关代码段                                                                    |
| .option nopic   | 与位置有关代码段                                                                    |
| .option push    | 将所有 .option 设置存入栈                                                           |
| .option pop     | 从栈中弹出上次存入的 .option 设置                                                   |

## fw_base

`firmware/fw_base.S` 文件中的代码是整个 OpenSBI 的起点，我们理解 OpenSBI 的代码就从这里开始吧！

### 代码分析

该段代码首先执行启动函数，在这个过程中通过之前规定的启动方式（fw_payload, fw_jump, fw_dynamic）找到一个启动核。如果规定了 `FW_PIC = y`，意味着将生成位置无关的固件映像，代码将进行一些重定位工作。这一部分读者暂且先不用关心。

该文件是 RISC-V 处理器的引导程序，用于启动操作系统或其他固件。

代码以汇编语言和宏定义为主，用于初始化处理器，设置运行时环境，并将控制权转移到操作系统或其他固件。下面将解释代码的主要部分：

- 起始部分：该部分定义了代码的许可证、版权信息和作者。
- 宏定义：在这部分，定义了一些宏指令，用于简化代码中的重复操作，例如 MOV_3R 和 MOV_5R 宏用于将寄存器中的值复制到另一个寄存器。
- _start：这是代码的主要入口点。它开始执行时会查找首选的启动核心（preferred boot HART id）。然后，它调用 fw_boot_hart 函数，该函数会尝试选择要启动的核心，如果未指定，它将选择一个核心来执行。启动核心将进行一系列初始化操作，然后根据指定的启动参数跳转到适当的代码段。
- _try_lottery：这段代码在多核情况下使用。在多个核同时启动时，只有最先执行原子加指令的核心会获得 "lottery"，其他核心将等待启动核心完成初始化。
- _relocate：如果启动核心的加载地址和链接地址不同，将进行重定位。它将把代码从加载地址复制到链接地址，以便在链接地址上运行。这部分代码是用于位置无关执行（FW_PIC=y）的情况，使 OpenSBI 能够在不同的地址上正确运行。
- _relocate_done：在重定位完成后，将在这里标记重定位完成。这对于其他核心等待重定位完成非常重要。
- _scratch_init：在这里设置了每个 HART（核心）的 scratch 空间，该空间用于保存处理器的运行时信息。
- _start_warm：在这里进行非启动核心的初始化，等待启动核心完成初始化。非启动核心会等待启动核心在主要初始化工作完成后，再进行自己的初始化。
- _hartid_to_scratch：用于将 HART ID 映射到 scratch 空间的函数。
- 其他一些功能：还包括处理中断、初始化 FDT（Flattened Device Tree）等功能。

firmware 部分是一个用于 RISC-V 平台的引导程序，用于初始化处理器和运行时环境，并最终将控制权转移到操作系统或其他固件。它支持多核处理器，并确保每个核心都能正确初始化和运行。

### 代码流程分析

1. 初始化：

   - 代码以宏和包含必要的头文件开始。
   - 定义了在不同寄存器之间移动寄存器值的宏。
   - 定义了基于范围进行条件分支的宏。
2. 开始和引导 HART 识别：

   - 定义了 _start 标签，引导过程从此开始。
   - 代码使用一个函数（fw_boot_hart）来确定首选引导 HART（硬件线程）ID。
   - 结果存储在寄存器 a6 中。
   - 如果结果为 -1，则表示使用 _try_lottery 机制随机选择引导 HART。
3. 重定位和初始化：

   - 如果定义了 `FW_PIC` 并且编译器启用了位置无关可执行文件（英文：position-independent executable，缩写为 PIE），代码执行重定位。
   - 设置了 BSS 段，初始化临时陷阱处理程序、堆栈和其他临时空间。
   - 为不同的 HART 初始化了各种临是空间的值。
4. 设备树重定位：

   - 如果提供了设备树，代码将对其进行重定位。
5. 引导状态和等待：

   - 标记引导 HART 为完成状态，并等待所有 HART 完成重定位和初始化。
6. 非引导 HART 的热启动：

   - 非引导 HART 进行热启动初始化，包括设置它们的临时空间、堆栈、陷阱处理程序和其他运行时数据。
7. 进入 SBI 运行时：

   - 非引导 HART 初始化 SBI 运行时环境。
8. 非引导 HART 的循环：

   - 非引导 HART 进入循环，不断执行 wfi（等待中断）指令，基本上处于空闲状态。

另外，固件中还实现了一些基础的内存复制函数：

- 内存复制（memcpy）和内存置位（memset）函数。

需要注意的是，这里只涉及了启动代码的一部分，还有其他的功能和细节可能没有在这个代码片段中展示出来。

整个 OpenSBI 启动过程涵盖了从硬件复位到 SBI 初始化和传递控制权给操作系统的完整流程。

将流程整理一下，以字符画的形式绘制出来 OpenSBI 的启动流程大致分为以下几个步骤：

```
                +-------------------+
                |                   |
                |     _start        |
                |                   |
                +-------------------+
                          |
                          v
                +-------------------+
                |                   |
                |   Find preferred  |
                |     boot HART     |
                |                   |
                +-------------------+
                          |
                          v
                +-------------------+
                |                   |
                | Call fw_boot_hart |
                |                   |
                +-------------------+
                          |
                          v
                +-------------------+
                |                   |
                |  Handle Boot HART |
                |                   |
                +-------------------+
             /           |           \
            v            |            v
  +-----------------+    |    +-----------------+
  |                 |    |    |                 |
  | Handle lottery  |    |    |  Wait for Boot  |
  | and relocation  |    |    |     HART Done   |
  |                 |    |    |                 |
  +-----------------+    |    +-----------------+
             \           |           /
              v          |          v
  +----------------------+----------------------+
  |                                             |
  |              Boot HART Done                 |
  |                                             |
  +----------------------+----------------------+
                         |
                         v
              +------------------------+
              |                        |
              |      Initialize        |
              |     for Boot HART      |
              |                        |
              +------------------------+
                         |
                         v
           +-------------------------------+
           |                               |
           |   Mark relocate copy done     |
           |                               |
           +-------------------------------+
                          |
                          v
           +-------------------------------+
           |                               |
           |   Clear BSS, Set Stack, etc.  |
           |                               |
           +-------------------------------+
                          |
                          v
           +---------------------------------+
           |                                 |
           |   Store Information in Scratch  |
           |                                 |
           +---------------------------------+
                          |
                          v
           +---------------------------------+
           |                                 |
           |  Relocate Flattened Device Tree |
           |                                 |
           +---------------------------------+
                          |
                          v
           +-------------------------------+
           |                               |
           |     Mark boot hart done       |
           |                               |
           +-------------------------------+
                            |
                            v
           +-------------------------------+
           |                               |
           |      Warm Boot Start          |
           |                               |
           +-------------------------------+
                            |
                            v
           +----------------------------------+
           |                                  |
           |      Initialize for Non-Boot     |
           |            HART                  |
           |                                  |
           +----------------------------------+
                          |
                          v
           +-------------------------------+
           |                               |
           |          sbi_init             |
           |                               |
           +-------------------------------+

```

## 小结

通过分析 `fw_base.S` 中的源码，我们已经知道了 OpenSBI 的启动流程的最前面一段的逻辑内容。之后我们会对其中的代码进行具体的解析，将上面的内容与具体的代码对应起来，加深读者对 OpenSBI 固件代码的理解。

## 参考资料

- OpenSBI 源代码
- RISC-V 手册
- [Lingrui98/RISC-V-book/blob/master/rvbook.pdf][001]
- [OpenSBI 官方仓库固件部分文档][002]
- [opensbi-firmware-and-sbi-hsm][003]
- [riscv-non-isa/riscv-asm-manual/blob/master/riscv-asm.md][004]

[001]: https://github.com/Lingrui98/RISC-V-book/blob/master/rvbook.pdf
[002]: https://github.com/riscv-software-src/opensbi/tree/master/docs/firmware
[003]: https://tinylab.org/opensbi-firmware-and-sbi-hsm/
[004]: https://github.com/riscv-non-isa/riscv-asm-manual/blob/master/riscv-asm.md
