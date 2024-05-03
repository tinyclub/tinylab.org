---
layout: post
author: 'SHT'
title: 'RISC-V 异常处理流程介绍'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-irq-pipeline-introduction/
description: 'RISC-V 异常处理流程介绍'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - 异常处理
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [spaces tables pangu]
> Author:  天外天 1056572776@qq.com
> Date:    2022/08/19
> Revisor: Chen Chen <chen1233216@hotmail.com>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor: PLCT Lab, ISCAS


## 前言

在学习 RISC-V 的异常处理流程之前，我们需要对「异常」有一个明确的理解。

中断与异常，站在处理器处理的过程来说，其实并没有区别。当中断与异常发生时，处理器的表现形式都是暂停当前执行的程序，转而执行处理中断或异常的处理程序，处理完后**视情况**恢复执行之前被暂停的程序。通常我们所理解的中断与异常都可以被统称为**广义上的异常**。

广义上的异常分为两种：

1. 同步异常：执行某个程序流，能稳定复现的异常，能比较精确的确定是哪条指令引发的异常。（例如程序流中执行一条非法指令，属于内因）
2. 异步异常（中断）：异常产生的原因与当前的程序流无关，与外部的中断事件有关。（由外部事件引起的，属于外因）

下文中的异常均指广义上的异常，狭义的异常我会用同步异常表达。

对于 RISC-V 的特权架构来说，异常处理是其重要的组成部分。学习 RISC-V 的异常处理流程，主要也就是学习 RISC-V 特权模式下进行异常处理的 CSRs（Control and Status Registers，控制状态寄存器组）的用法。

## RISC-V 的权限模式

在任何时候，一个 RISC-V 的 hart（hardware thread，硬件线程）都会运行在一个权限模式当中，这个权限模式作为一个模式编码在 CSRs 当中。当前一共有三种 RISC-V 的权限模式：

| 编码 | 名称                 | 缩写 |
| ---- | -------------------- | ---- |
| 00   | User（用户）         | U    |
| 01   | Supervisor（监管者） | S    |
| 11   | Machine（机器）      | M    |

M 模式是 RISC-V 中 hart 可以执行的最高权限模式，也是唯一所有标准 RISC-V 处理器都必须实现的权限模式。所以本文以机器模式下的异常处理为例，介绍 RISC-V 异常处理的大致流程。S 模式是为操作系统提供支持的模式，其异常处理的流程和 M 模式类似，只是用其自己的一套 CSRs，名称和 M 模式类似，以 s 开头。

## 机器模式 CSRs

RISC-V 处理异常主要依靠 CSRs，主要关注以下八个控制状态寄存器：

### mcause（Machine Exception Cause）

![mcause](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-pipeline-introduction/mcause.png)

机器模式异常原因寄存器，记录发生异常的原因，首位 Interrupt 置 1 时是中断，0 时为异常。Exception Code 域记录异常发生的原因编码。下表列出了可能出现的异常编码。

![exception_code](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-pipeline-introduction/exception_code.png)

### mtvec（Machine Trap Vector Base-Address Register）

![mtvec](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-pipeline-introduction/mtvec.png)

机器模式异常入口基地址寄存器，保存发生异常时处理器需要跳转到的地址，实际上就是异常处理程序的入口地址。该寄存器包含基地址 BASE 以及模式 MODE 两个域，其中 MODE 域表示异常处理程序入口地址的寻址方式。注意基地址 BASE 域必须 4 字节对齐，所以在计算异常处理程序的入口地址时，需要把末两位即 MODE 域中的两位恒置 0。

| MODE | 名字 | 说明                                    |
| ---- | ---- | --------------------------------------- |
| 0    | 直接 | 所有的异常都将 PC 设为 BASE             |
| 1    | 向量 | 异步的中断会将 PC 设为 BASE + 4 * cause |
| >=2  |      | 保留                                    |

例如，如果一个机器模式的时钟中断产生了，那么 PC 会被设置为 `BASE + 7 * 4 = BASE + 0x1c`，7 是机器模式时钟中断在 mcause 寄存器中 Exception Code 域的值。

### mepc（Machine Exception PC）

机器模式异常程序计数器，它指向发生异常的指令。对于同步异常，mepc 指向导致异常的指令；对于中断，它指向中断处理后应该恢复执行的位置。

### mie（Machine Interrupt Enable）

![mie](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-pipeline-introduction/mie.png)

机器模式中断使能寄存器，记录处理器目前能处理和必须忽略的中断，即相应的中断使能位。值得注意的是，异常在 mcause 寄存器中的异常编码值即 Exception Code 域的值，正好对应 mie 寄存器中相应位置的中断使能位。例如，机器模式时钟中断的异常编码是 7，mie[7] 就表示机器模式时钟中断的使能，MTIE 即 Machine Time Interrupt Enable。

### mip（Machine Interrupt Pending）

![mip](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-pipeline-introduction/mip.png)

机器模式中断等待寄存器，表示目前正准备处理的中断。它和 mie 有相同的布局。

### mstatus（Machine Status）

![mstatus](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-pipeline-introduction/mstatus.png)

机器模式状态寄存器，它保存全局中断使能，以及许多其他的状态。xIE 保存对应模式的全局中断使能，比如，MIE 保存机器模式的全局中断使能。xPIE 保存对应模式异常发生前的全局中断使能，xPP 保存对应模式异常发生前的权限模式。MPP 有 2 位，SPP 只有 1 位，因为异常进入 S 模式只能是 U 模式或 S 模式，而异常进入 M 模式可以是所有的模式。

处理器在 M 模式下运行时，只有在全局中断使能位 mstatus.MIE 置 1 时才会允许中断。此外，每个中断在 mie 和 mip 中都有自己的对应位。将上述三个控制状态寄存器合在一起考虑，如果 mstatus.MIE = 1，mie[7] = 1，且 mip[7] = 1，则表示开始处理机器模式的时钟中断。

### mtval（Machine Trap Value）

机器模式异常值寄存器，保存了异常的附加信息。比如，地址异常中出错的地址、发生非法指令异常的指令本身。对于其他异常，它的值为 0。

### mscratch（Machine Scratch）

这个寄存器会在实现线程时起到作用，目前仅了解即可。

它暂时存放一个字大小的数据。在 U 模式下，mscratch 保存 M 模式下栈的地址；在 M 模式下，mscratch 的值为 0。可以在发生异常时通过 mscratch 中的值判断异常前程序是否处于 M 模式。为了能够执行 M 模式的中断处理流程，很可能需要使用栈，而程序当前的用户栈是不安全的。因此，我们还需要一个预设的安全的栈空间，存放在这里。

大致用处可以在源码中明晰，如下源码是以 S 模式即内核态为例：

```assembly
// linux/v5.10/source/arch/riscv/kernel/entry.S:20
ENTRY(handle_exception)
	/*
	 * If coming from userspace, preserve the user thread pointer and load
	 * the kernel thread pointer.  If we came from the kernel, the scratch
	 * register will contain 0, and we should continue on the current TP.
	 */
	csrrw tp, CSR_SCRATCH, tp
	bnez tp, _save_context

_restore_kernel_tpsp:
	csrr tp, CSR_SCRATCH
	REG_S sp, TASK_TI_KERNEL_SP(tp)
_save_context:
	...
```

Linux 内核使用 `CSR_SCRATCH` 寄存器保存发生异常前权限模式的 `tp` 寄存器的值，且如果 `CSR_SCRATCH` 为 0 则表示异常是在内核态触发的。源码先将当前 `tp` 的值与 `CSR_SCRATCH` 的值进行交换，如果发现 `CSR_SCRATCH` 的值为 0，则明显是由内核态进入异常处理的，此时需要将 `tp` 寄存器的值还原，并将此时的内核栈指针保存在 `struct thread_info` 的 `kernel_sp` 字段中。否则，通过交换后 `tp` 寄存器中指向的栈空间保存异常前权限模式的上下文，即通用寄存器组。

## 异常处理流程

当一个 hart 发生异常时，硬件自动经历如下的状态转换：

- 将异常发生前所处的权限模式保存到 mstatus.MPP 中，再把权限模式更改为 M 模式。将异常发生前的 mstatus.MIE 保存到 mstatus.MPIE 当中，再把 mstatus.MIE 置零以禁用中断。这意味着在硬件上，RISC-V 是不支持嵌套中断的。若要实现嵌套中断，则只能通过软件的方式来实现。
- 根据异常来源设置 mcause，并将异常的附加信息写入 mtval。
- 异常指令的 PC 被保存在 mepc 中，将 PC 设置为 mtvec 中所定义的异常处理入口地址。对于同步异常，mepc 指向导致异常的指令；对于中断，mepc 指向中断处理后应该恢复执行的位置，一般是中断指令的下一条指令地址，即 mepc + 4。同之前所提到的，mtvec 有两种模式。一种是直接模式，直接跳转到 mtvec 中的基地址执行；另一种是向量模式，根据 mcause 中的中断类型跳转到对应的中断处理程序首地址中执行。

然后执行异常处理程序，注意在程序中实现上下文环境的保存和切换。

当异常处理程序执行完毕后，在程序最后会调用 MRET 指令来退出异常处理程序，S 模式中调用的是 SRET 指令。执行 MRET 指令后处理器硬件的行为如下：

- 更新 mstatus。将异常发生前的 mstatus 的状态恢复，将 mstatus.MPIE 复制到 mstatus.MIE 来恢复之前的中断使能设置，并将权限模式设置为 mstatus.MPP 域中的值。
- 从 mepc 中保存的地址执行，即恢复到异常发生前的程序流执行。

整体的大致流程如下图所示：

![irq_pipeline](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-pipeline-introduction/irq_pipeline.png)

## 异常委托

默认情况下，发生所有异常（不论在什么权限模式下）的时候，控制权都会被移交到 M 模式的异常处理程序。但是 Unix 系统中的大多数异常都会进行 S 模式下的系统调用。M 模式的异常处理程序可以将异常重新导向 S 模式，但这些额外的操作会减慢大多数异常的处理速度。因此，RISC-V 提供了一种异常委托机制。通过该机制可以选择性地将异常交给 S 模式处理，而完全绕过 M 模式。

RISC-V 通过两个寄存器 medeleg（Machine Exception Delegation，机器同步异常委托）和 mideleg（Machine Interrupt Delegation，机器中断委托）分别控制将哪些同步异常和中断委托给 S 模式。与 mip 和 mie 的布局一样，medeleg 和 mideleg 中的位置对应于 mcause 中的异常编码值。例如，mideleg[5] 对应于 S 模式的时钟中断，如果把它置 1，S 模式的时钟中断将会移交 S 模式的异常处理程序，而不是 M 模式的异常处理程序。

委托给 S 模式的任何异常都可以被 S 模式屏蔽。sie（Supervisor Interrupt Enable，监管者中断使能）和 sip（Supervisor Interrupt Pending，监管者中断待处理）是 S 模式的控制状态寄存器，它们是 mie 和 mip 的子集。它们有着和 M 模式下相同的布局，但在 sie 和 sip 中只有由 mideleg 委托的中断对应的位才能读写，那些没有被委派的中断对应的位始终为 0。

**注意**：无论委派设置是怎样的，发生异常时控制权都不会移交给权限更低的模式。在 M 模式下发生的异常总是在 M 模式下处理。在 S 模式下发生的异常，根据具体的委派设置，可能由 M 模式或 S 模式处理，但永远不会由 U 模式处理。

## 小结

本文对 RISC-V 架构的异常处理流程进行了简单的介绍，主要分析了相关控制状态寄存器的用途，后续会结合 Linux 内核的源码进一步分析其代码的实现流程。

## 参考资料

- [RISC-V 中文手册 v2.1][005]
- [RISC-V 特权架构手册][004]
- [RISC-V 异常与中断机制概述][006]
- [RISC- V 特权架构介绍][003]
- [RISC-V 与中断相关的寄存器和指令][001]
- [Linux 内核在 RISC-V 架构下的 setup_arch 与异常处理][002]

[001]: https://rcore-os.cn/rCore-Tutorial-deploy/docs/lab-1/guide/part-2.html
[002]: https://crab2313.github.io/post/riscv-setup-arch-exception/
[003]: https://dingfen.github.io/risc-v/2020/08/05/riscv-privileged.html
[004]: https://github.com/riscv/riscv-isa-manual/releases/download/draft-20220825-1237e31/riscv-privileged.pdf
[005]: https://ica123.com/wp-content/uploads/2021/03/RISC-V-%E6%8C%87%E4%BB%A4%E9%9B%86%E6%89%8B%E5%86%8C-v2.1%E4%B8%AD%E6%96%87%E7%89%88.pdf
[006]: http://www.sunnychen.top/2019/07/06/RISC-V%E5%BC%82%E5%B8%B8%E4%B8%8E%E4%B8%AD%E6%96%AD%E6%9C%BA%E5%88%B6%E6%A6%82%E8%BF%B0/
