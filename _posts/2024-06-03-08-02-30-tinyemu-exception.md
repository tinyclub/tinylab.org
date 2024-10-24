---
layout: post
author: 'yjmstr'
title: '从零开始，徒手写一个 RISC-V 模拟器（4）——RISC-V 异常处理'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /tinyemu-exception/
description: '从零开始，徒手写一个 RISC-V 模拟器（4）——RISC-V 异常处理'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - 异常
  - 中断
  - 陷入
---

> Author:    YJMSTR <pyjmstr@gmail.com><br\>
> Date:      2023/04/27
> Revisor:   Bin Meng, Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

在上一篇文章中我们介绍了 RISC-V 中的控制与状态寄存器 CSR 和特权级 ISA，本文中我们将进一步介绍 RISC-V 中的异常、中断与陷入等概念，重点关注其中异常（Exception）处理的相关定义，并为 TinyEMU 添加 trap 相关定义和部分处理函数。在之后的文章中我们将进一步完善异常以及中断处理的实现。

## RISC-V 中的异常、中断与陷入

不同的架构中对于中断、陷入和异常的定义可能有所差别。在 RISC-V 中：

- 异常（Exception）指执行指令时出现的与指令有关联的特殊情况
- 中断（Interrupt）指可能导致 hart 发生意料之外的控制流转移的外部异步事件。
- 陷入（Trap）指异常或中断导致的控制流转移，这时控制流会转移至 trap handler。

异常（Exception）和中断（Interrupt）都属于陷入（Trap），异常是同步的，中断是异步的。

同步异常：在指令执行期间发生，比如访问了无效的存储器地址或执行了具有无效操作码的指令时。

异步中断：与指令流异步的外部事件，例如鼠标点击。

根据 RISC-V Spec，RISC-V 中的 trap 被分为这几类：

- Contained Trap：这类 trap 对程序执行环境内的软件可见，并且由这些软件进行处理。例如：
  - 在 U 模式下执行 ECALL 指令主动触发 trap，会使当前 hart 切换到 S 模式下的 trap 处理程序。
  - 运行在 U 模式下的 hart 发生中断时，该 hart 会切换到 S 模式的 trap 处理程序进行处理。
- Request Trap：这类 trap 是由对执行环境的显示调用引起的同步异常，例如系统调用。
- Invisible Trap：这类 trap 由执行环境进行处理。运行在执行环境内的软件察觉不到这类 trap 的发生和处理。比如 page fault 的处理。
- Fatal Trap：这类 trap 表示发生了导致执行环境终止的致命错误。

除 Contained Trap 外，其它类型的 trap 都需要由执行环境进行处理。我们的模拟器首先要提供对 Fatal Trap 的支持：当发生 Fatal Trap 时，终止模拟器的执行；其它类型的 trap 可能由其它执行环境进行处理。

## CSR

在上一篇文章中我们简要介绍了 trap 相关的一些 CSR 寄存器，现在让我们深入了解一下它们，并介绍之前没提到的 CSR：mideleg 与 medeleg。

### [m/s]status

mstatus 保存当前 hart 的状态。sstatus 是 mstatus 的子集。[m/s]status 寄存器中有很多字段，用于存储与当前运行状态有关的信息。

![mstatus.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/mstatus.png)

在上一篇文章中我们提到过，[m/s]status 中的 MIE 与 SIE 字段为全局中断使能位，若当前 hart 在特权模式 $x$ 下执行，则 $x$IE=1 表示全局中断启用，$x$IE=0 表示全局中断禁用。更低特权等级 $w$ ($w<x$) 的中断总是全局禁用，无论 $w$IE 的值是多少；更高特权等级 $h$ ($h>x$) 的中断总是全局启用，无论 $h$IE 的值是多少。

此外，为了支持 trap 嵌套，[m/s]status 寄存器还提供了这些字段：xPIE 字段记录 trap 进特权模式 x 之前的中断使能位，xPP 字段记录 trap 进 x 模式之前的特权模式。xPP 字段只能保存特权等级不高于 x 的特权模式。

当从特权模式 y trap 进特权模式 x 时，xPIE 被设为 xIE，xIE 随后被设为 0，xPP 被设为 y。

### [m/s]tvec

[m/s]tvec 用于保存 trap vector configuration。发生 trap 时，需要根据当前的特权等级来读取 [m/s]tvec 中的值，并根据 [m/s]tvec 中的值修改 pc，以跳转至 trap 处理程序。

mtvec 用于保存 M 模式下发生 trap 时处理器需要跳转到的地址。S 模式下也有对应的 stvec 寄存器。

mtvec 的低 2 位为 MODE 字段，剩下的位组成 BASE 字段。

- BASE 字段中的值总是 4 字节对齐。
- MODE 字段为 0 表示当前 trap 为异常，应该将 pc 设为 BASE。
- MODE 字段为 1 表示当前 trap 为异步中断，应该将 pc 设为 BASE+4*cause.
- MODE 字段大于等于 2 的情况被保留，目前不进行处理。

stvec 同样由 BASE 和 MODE 字段组成，与 mtvec 类似。当 trap 到 M 模式时，根据 mtvec 进行跳转；当 trap 到 S 模式时，根据 stvec 进行跳转。

### [m/s]epc

[m/s]epc 用于存储引发 trap 的指令对应的 pc 值。发生中断时，它会存储被中断的指令对应的 PC 值；而发生异常时，它会存储导致异常的指令对应的 PC 值。

### [m/s]cause

[m/s]cause 用于标识导致当前 trap 的原因。最高位为 1 代表当前 trap 为中断引起的，否则为异常，剩下的位用于标识不同的 trap 原因。

mcause 内的值和 trap 原因的对应关系如下表所示：

![mcause.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/mcause.png)

一条指令可能触发多个同步异常，此时异常的优先级如下所示：

![mcause_exception_priority.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/mcause_exception_priority.png)

scause 内的值与 trap 原因的关系如下图所示，与 mcause 有所不同：

![scause.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/scause.png)

可以看出 scause 中能够存储的值其实是 mcause 中能够存储的值的子集。

### [m/s]tval

[m/s]tval 用于在发生异常时存储一些额外的信息，来帮助异常处理程序处理异常。例如当发生非法指令异常时，[m/s]tval 可以存储该非法指令的值。

### [m/s]ie 和 [m/s]ip

[m/s]ip 用于存储待处理的中断的信息，而 [m/s]ie 用于存放中断使能位。有关这两个寄存器我们在后续讲解 RISC-V 中断时在详细讲解。

### [m/s]scratch

用于临时保存一些数据，我们暂时用不上它。

### mideleg 和 medeleg

默认情况下任何特权模式的 trap 都是在 M 模式下处理的，M 模式也可以通过 mret 指令将 trap 交给其它特权模式处理。为了增加性能，RISC-V 实现可以通过设置 mideleg 和 medeleg 寄存器来标识某些 trap 应该直接交由其它特权等级进行处理。

medeleg 的每一位对应了一种异常，这些位号通过 [m/s]cause 中的值指定，mideleg 也类似，每一位对应了一种中断情况。

## 异常处理流程

发生异常时，首先需要执行 trap 流程：

- 切换到对应的特权模式以处理该 trap。检查 medeleg 寄存器中的相应位，以判断是直接 trap 进 S 模式还是 M 模式。
- 设置 [m/s]status 中的 xPP，xPIE，xIE 等字段。

并设置相关 CSR 的值：

- 将 [m/s]epc 设为导致异常的指令对应的 PC 值。
- 在 [m/s]tval 中存储有关的信息。
- 设置 [m/s]cause 寄存器的值。

随后读出 [m/s]tvec 中的值，并根据这个值跳转到 trap 处理程序。

## 代码实现

添加有关 trap 类型的定义：

```c
enum TRAP {
    Contained,
    Requested,
    Invisible,
    Fatal
};
```

添加 [m/s]cause 中各种异常代码的定义：

```c
enum EXCEPTION {
    Instruction_address_misaligned = 0,
    Instruction_access_fault,
    Illegal_instruction,
    Breakpoint,
    Load_address_misaligned,
    Load_access_fault,
    Store_AMO_address_misaligned,
    Store_AMO_access_fault,
    Environment_call_from_U_mode,
    Environment_call_from_S_mode,
    Environment_call_from_M_mode = 11,
    Instruction_page_fault,
    Load_page_fault,
    Store_AMO_page_fault = 15
};
```

其中 Illegal_instruction，Instruction_page_fault，Load_page_fault 和 Store_AMO_page_fault 还有附带的异常值，这个异常值会被写入 [m/s]tval 中。

下面实现 trap 处理函数，其中也包含了一部分中断处理相关的代码：

```c
void trap_handler(DECODER *decoder, enum TRAP traptype, bool isException, uint64_t cause, uint64_t tval) {
    if (traptype == Fatal) {
        cpu.state = CPU_STOP;
        return;
    }
    enum CPU_PRI_LEVEL nxt_level = M;
    if (cpu.pri_level <= S) {
        if ((isException && (get_csr(medeleg) & (1 << cause)))
            || (!isException && (get_csr(mideleg) & (1 << cause)))) {
            nxt_level = S;
        }
    }
    if (nxt_level == S) {
        set_xpp(S, cpu.pri_level);
        set_xpie(S, get_xie(S));
        set_xie(S, 0);
        set_csr(sepc, cpu.pc);
        set_csr(stval, tval);
        set_csr(scause, ((isException?0ull:1ull) << 63) | cause);
        uint64_t tvec = get_csr(stvec);
        decoder->dnpc = (BITS(tvec, 63, 2) << 2) + (BITS(tvec, 1, 0) == 1 ? cause * 4 : 0);
    } else {
        set_xpp(M, cpu.pri_level);
        set_xpie(M, get_xie(M));
        set_xie(M, 0);
        set_csr(mepc, cpu.pc);
        set_csr(mtval, tval);
        set_csr(mcause, ((isException?0ull:1ull) << 63) | cause);
        uint64_t tvec = get_csr(mtvec);
        decoder->dnpc = (BITS(tvec, 63, 2) << 2) + (BITS(tvec, 1, 0) == 1 ? cause * 4 : 0);
    }
    cpu.pri_level = nxt_level;
}
```

## 总结

本文介绍了 RISC-V 中 trap，exception 与 interrupt 的概念，以及相关的 CSR，并给出了模拟器中 exception 处理有关的代码实现。之后的文章中我们将继续为模拟器添加中断处理的支持，并完善相关指令的实现。

## 参考资料

- [RISC-V spec][001]
- [RVEMU][002]

[001]: https://riscv.org/technical/specifications
[002]: https://github.com/d0iasm/rvemu
