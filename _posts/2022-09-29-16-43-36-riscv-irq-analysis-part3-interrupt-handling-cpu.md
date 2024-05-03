---
layout: post
author: 'Wu Zhangjin'
title: 'RISC-V 中断子系统分析——CPU 中断处理'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-irq-analysis-part3-interrupt-handling-cpu/
description: 'RISC-V 中断子系统分析——CPU 中断处理'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - 中断
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc1 - [spaces newline urls]
> Author:  通天塔 <985400330@qq.com>
> Date:    2022/07/12
> Revisor: Falcon <falcon@tinylab.org>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor: PLCT Lab, ISCAS


## 前言

之前两篇文章对中断的硬件实现以及硬件初始化，中断的申请、产生、处理进行了分析，并对 IRQ 的 domain 实现进行了深入分析，但之前的两篇文章都没对 CPU 寄存器、汇编的层面进行分析。

* [RISC-V 中断子系统分析——硬件及其初始化][001]
* [RISC-V 中断子系统分析——PLIC 中断处理][002]

本篇文章将对 CPU 的中断处理流程进行深入分析。

对于中断的处理一直没想好从哪里下手，最后决定从 51 单片机下手，再扩展到 RISC-V 架构的 CPU。

本文代码分析基于 Linux-5.17。

## 51 单片机中断处理

51 单片机是我大学中学的一款单片机，也是我入门编程的一款单片机，今天一起回顾一下，单片机对于中断的处理流程。

[STC89C51RC-RD.pdf (stcmcudata.com)][007] 手册中讲了 51 单片机的中断处理流程：

> 当某中断产生而且被 CPU 响应，主程序被中断，接下来将执行如下操作：
>
> 1. 当前正被执行的指令全部执行完毕；
>
> 2. PC 值被压入栈；
>
> 3. 现场保护；
>
> 4. 阻止同级别其他中断；
>
> 5. 将中断向量地址装载到程序计数器 PC；
>
> 6. 执行相应的中断服务程序。
>
> 中断服务程序 ISR 完成和该中断相应的一些操作。ISR 以 RETI（中断返回）指令结束，将 PC 值从栈中取回，并恢复原来的中断设置，之后从主程序的断点处继续执行。
> 当某中断被响应时，被装载到程序计数器 PC 中的数值称为中断向量，是同该中断源相对应的中断服务程序的起始地址。

通过下一节的表，可以看到中断向量的地址，当物理上的中断产生之后，中断会对中断请求标志位进行置位，MCU 会对中断请求标志位进行响应，从而触发中断的处理流程。

### 单片机中断寄存器

下表表示了中断产生时的中断标志位，以及中断产生后，MCU 将要跳到的中断向量地址。下表参考 STC89C51 芯片手册给出。

| 中断源  | 中断向量地址 | 中断请求标志位 |
| :-----: | :----------: | :------------: |
|  INT0   |    0003H     |      IE0       |
| Timer 0 |    000BH     |      TF0       |
|  INT1   |    0013H     |      IE1       |
| Timer 1 |    001BH     |      TF1       |
|  UART   |    0023H     |     RI+TI      |
| Timer2  |    002BH     |    TF2+EXF2    |
|  INT2   |    0033H     |      IE2       |
|  INT3   |    003BH     |      IE3       |

### 汇编代码

汇编代码在第一部分对中断向量表进行了设置，在规定的中断地址设置了跳转代码，使程序发生中断时跳转到对应的中断处理函数，当中断处理完成后，执行恢复指令 RETI。

```assembly
;-----------------------------------------
;interrupt vector table
ORG 0000H
LJMP MAIN
ORG 0003H ;INT0, interrupt 0 (location at 0003H)
LJMP EXINT0
;-----------------------------------------
ORG 0100H
MAIN:
MOV SP, #7FH ;initial SP
SETB IT0 ;set INT0 interrupt type (1:Falling 0:Low level)
SETB EX0 ;enable INT0 interrupt
SETB EA ;open global interrupt switch
SJMP$
;-----------------------------------------
;External interrupt0 service routine
EXINT0:
CPL P0.0
RETI
;-----------------------------------------
END
```

以上是一个 51 单片机中断响应后的处理流程。

## RISC-V CPU 中断处理

### CPU 中断寄存器

[RISC-V-Reader-Chinese-v2p1][005] 第十章讲了机器模式下的特权处理，可以拦截和处理异常，当产生异常时，寄存器就会被置位，通过寄存器的值，就可以进一步定位异常原因，并作出响应。文章中也给出了寄存器对应关系。

[第 2 卷，特权规范与 20211203][003]  这篇手册中就是被以上译文引用内容。

下表就是产生异常时寄存器的对应关系。

![image-20220710155415029](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220710155415029.png)

通过上表可知，陷阱（trap）分为中断和异常两种，当产生中断时，Interrupt 寄存器置 1，异常时置 0。

中断共 6 种分别是：

* 监管模式软中断
* 机器模式软中断
* 监管模式定时器中断
* 机器模式定时器中断
* 监管模式外部中断
* 机器模式外部中断

### 特权模式下的中断处理

1. 机器模式，权限最高，可以访问任意内存、寄存器

2. 用户模式，无法处理中断，有内存隔离

3. 监管者模式，既能处理中断，又有内存隔离，并且使用内存映射的方式实现了虚拟内存，可供现代操作系统使用。

#### 机器模式（M）下中断处理

先分析机器模式下的中断处理流程。[RISC-V-Reader-Chinese-v2p1][005] 10.3 小节，对机器模式下的异常处理所需要的寄存器，以及异常处理流程进行了详细介绍，文章写得非常详细，通俗易懂，这里不再赘述。

以下引自 [RISC-V-Reader-Chinese-v2p1][005]：

> * 异常指令的 PC 被保存在 mepc 中，PC 被设置为 mtvec。（对于同步异常，mepc 指向导致异常的指令；对于中断，它指向中断处理后应该恢复执行的位置。）
>
> * 根据异常来源设置 mcause（如图 10.3 所示），并将 mtval 设置为出错的地址或者其它适用于特定异常的信息字。
> * 把控制状态寄存器 mstatus 中的 MIE 位置零以禁用中断，并把先前的 MIE 值保留到 MPIE 中。
> * 发生异常之前的权限模式保留在 mstatus 的 MPP 域中，再把权限模式更改为 M。图 10.5 显示了 MPP 域的编码（如果处理器仅实现 M 模式，则有效地跳过这个步骤）。

这里针对文章中给出的一段时钟中断处理代码再分析。

```assembly
# save registers
# 交换 a0 与 mscratch 的值，使 a0 保存临时内存空间地址指针
csrrw a0, mscratch, a0 # save a0; set a0 = &temp storage
# 保存其他整数寄存器的值到临时内存中
sw a1,0(a0) # save a1
sw a2，4(a0) # save a2
sw a3，8(a0) # save a3
sw a4, 12(a0) # save a4
# decode interrupt cause
# 从 mcause 寄存器中读取异常原因到寄存器 a1
csrr a1,mcause # read exception cause
# 如果不是 interrupt，跳转到 exception
bgez a1,exception # branch if not an interrupt
# 通过掩码确认中断原因
andi a1，a1，0x3f # isolate interrupt cause
# 赋值a2
li a2， 7 # a2=timer interrupt cause
# 比较跳转，不相等，则是其他中断
bne a1，a2，otherInt # branch if not a timer interrupt
# handle timer interrupt by incrementing time comparator
# 赋值 a1
la a1, mtimecmp #a1=&time comparator
# 将时钟比较寄存器读取至 a2、a3
lw a2, 0(a1) # load lower 32 bits of comparator
lw a3，4(a1) # load upper 32 bits of comparator
# 将 a2+1000，赋值给 a4，
addi a4，a2，1000 # increment lower bits by 1000 cycles
# 比较 a4<a2?,a4 加了 1000，却小于 a2，说明寄存器产生了溢出，向 a3 进 1。
sltu a2， a4, a2 # generate carry-out
add a3， a3， a2 # increment upper bits
# 将 a3、a4 写入定时器比较寄存器，目的是让定时器在 1000 个时钟周期后再中断
sw a3, 4(a1) # store upper 32 bits
sw a4,0(a1) # store lower 32 bits
# restore registers and return
# 恢复现场
lw a4，12(a0) # restore a4
lw a3, 4(a0) # restore a3
lw a2， 4(a0) # restore a2
lw a1,0(a0) # restore a1
csrrw a0, mscratch, a0)# restore a0; mscratch = &temp storage
mret # return from handler
```

以上代码描述了一个 **产生中断->保护现场->确认定时器中断->定时器定时增加 1000 周期->恢复现场** 的流程。

通过以上流程，可以看到，当产生中断时，不像 51 单片机一样，直接跳转到了指定地址，而是通过代码逻辑，根据中断产生的原因跳转到指定地址处理中断。

两个中断处理流程的明显不同之处如下：

![image-20220711001031881](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220711001031881.png)

#### 监管者（S）模式下中断处理

监管者模式是现代操作系统的必须模式，既有中断处理的权限，又有自己的虚拟内存管理机制，能够满足现代操作系统的快速响应要求，也能运行内核的可信代码，保障底层寄存器的安全。

RISC-V 通过异常委托机制，可以使在 S 模式下产生的异常，委托给 S 模式进行处理，而不必切换到 M 模式进行处理，其中 S 模式也有自己中断处理时所用到的寄存器：sepc、stvec、scause、sscratch、stval 和 sstatus。

以下引自 [RISC-V-Reader-Chinese-v2p1][005]

> * 发生异常的指令的 PC 被存入 sepc，且 PC 被设置为 stvec。
> * scause 按图 10.3 根据异常类型设置，stval 被设置成出错的地址或者其它特定异常的信息字。
> * 把 sstatus CSR 中的 SIE 置零，屏蔽中断，且 SIE 之前的值被保存在 SPIE 中。
> * 发生例外时的权限模式被保存在 sstatus 的 SPP 域，然后设置当前模式为 S 模式

与上一小节对比可知，S 模式下的异常处理流程与 M 模式下的基本相同，只是使用的寄存器有所不同。

## Linux 下的 CPU 中断处理

以上完成了 51 单片机和 RISC-V 的 CPU 中断处理流程在汇编级别的中断处理流程梳理。那么在 Linux 系统里，对于中断在汇编级别是如何处理的呢？

通过以上给的分析，可以看到，PC 指针的存储，PC 指针的跳转到 stvec 保存的指针位置，都是由芯片自己来完成的，PC 指针跳转到中断处理函数位置，才是后续程序来掌控的。

首先分析 stvec 的地址是什么时候存进去的，确认存的是什么值。

```assembly
/* arch/riscv/kernel/head.S: 194 */
.align 2
setup_trap_vector:
	/* Set trap vector to exception handler */
	la a0, handle_exception
	/* MTVEC 和 STVEC 根据内核配置进行宏定义为 TVEC */
	csrw CSR_TVEC, a0
	/*
	 * Set sup0 scratch register to 0, indicating to exception vector that
	 * we are presently executing in kernel.
	 */
	csrw CSR_SCRATCH, zero
	ret
```

在分析 handle_exception 汇编代码之前，先要了解以下寄存器的含义。下图引自 [Volume 1, Unprivileged Spec v. 20191213][004]，下图将 32 个通用寄存器和 32 个浮点型寄存器的 API 名称和描述给了出来，方便通过以下描述，理解汇编代码。

![image-20220712225920675](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220712225920675.png)

内核在初始化异常向量时，就指定了 handle_exception 作为产生异常时的跳转地址。

```assembly
/* arch/riscv/kernel/entry.S: 21 */
ENTRY(handle_exception)
	/*
	 * If coming from userspace, preserve the user thread pointer and load
	 * the kernel thread pointer.  If we came from the kernel, the scratch
	 * register will contain 0, and we should continue on the current TP.
	 * 如果来自用户空间，则使用 csrrw 指令，进行一次指针替换 */
	csrrw tp, CSR_SCRATCH, tp
	/* 比较 tp，跳转到保存上下文 */
	bnez tp, _save_context
	/* 另一种情况，重新装载 tp 和 sp */
_restore_kernel_tpsp:
	csrr tp, CSR_SCRATCH
	REG_S sp, TASK_TI_KERNEL_SP(tp)

#ifdef CONFIG_VMAP_STACK
	addi sp, sp, -(PT_SIZE_ON_STACK)
	srli sp, sp, THREAD_SHIFT
	andi sp, sp, 0x1
	bnez sp, handle_kernel_stack_overflow
	REG_L sp, TASK_TI_KERNEL_SP(tp)
#endif
	/* 保存上下文 */
_save_context:
	REG_S sp, TASK_TI_USER_SP(tp)
	REG_L sp, TASK_TI_KERNEL_SP(tp)
	addi sp, sp, -(PT_SIZE_ON_STACK)
	REG_S x1,  PT_RA(sp)
...
	REG_S x31, PT_T6(sp)

	/*
	 * Disable user-mode memory access as it should only be set in the
	 * actual user copy routines.
	 *
	 * Disable the FPU to detect illegal usage of floating point in kernel
	 * space.
	 */
	li t0, SR_SUM | SR_FS
	/* 读取 CSR 中断相关寄存器 */
	REG_L s0, TASK_TI_USER_SP(tp)
	csrrc s1, CSR_STATUS, t0
	csrr s2, CSR_EPC
	csrr s3, CSR_TVAL
	csrr s4, CSR_CAUSE
	csrr s5, CSR_SCRATCH
	REG_S s0, PT_SP(sp)
	REG_S s1, PT_STATUS(sp)
	REG_S s2, PT_EPC(sp)
	REG_S s3, PT_BADADDR(sp)
	REG_S s4, PT_CAUSE(sp)
	REG_S s5, PT_TP(sp)

	/*
	 * Set the scratch register to 0, so that if a recursive exception
	 * occurs, the exception vector knows it came from the kernel
	 * 对 CSR_SCRATCH 清零，如果下次出现异常，则知道异常来自内核
	 */
	csrw CSR_SCRATCH, x0

	/* Load the global pointer 加载全局指针 */
.option push
.option norelax
	la gp, __global_pointer$
.option pop

#ifdef CONFIG_TRACE_IRQFLAGS
	call __trace_hardirqs_off
#endif

#ifdef CONFIG_CONTEXT_TRACKING
	/* If previous state is in user mode, call context_tracking_user_exit. */
	li   a0, SR_PP
	and a0, s1, a0
	bnez a0, skip_context_tracking
	call context_tracking_user_exit
skip_context_tracking:
#endif
	/*
	 * MSB of cause differentiates between
	 * interrupts and exceptions
	 * 根据异常原因进行中断和异常处理的跳转
	 */
	bge s4, zero, 1f

	la ra, ret_from_exception

	/* Handle interrupts 处理中断 */
	move a0, sp /* pt_regs */
	la a1, generic_handle_arch_irq
	jr a1
...
END(handle_exception)
```

整个汇编函数非常长，该函数实现了包括中断、异常、syscall、保护现场、恢复现场等操作，这里不再一点点分析。

## 小结

本文通过对比分析 51 单片机的中断处理流程，理清了 RISC-V 架构的中断处理流程，并且在 Linux 内核代码中找到了相应的寄存器配置，而且进一步对中断处理函数的汇编部分进行了初步分析。

这一系列的 3 篇文章讲清楚了，在 RISC-V 架构下 Linux 如何从汇编到最终驱动处理中断的全流程。

至此已经分析完毕 RISC-V 的中断处理流程，后续会继续分析中断的其他部分。

## 参考资料

* [articles/20220519-riscv-irq-analysis.md · 泰晓科技/RISCV-Linux - Gitee.com][001]
* [如何分析 Linux 内核 RISC-V 架构相关代码][006]
* [Volume 1, Unprivileged Spec v. 20191213][004]
* [RISC-V-Reader-Chinese-v2p1][005]
* [第 2 卷，特权规范与 20211203][003]
* [STC89C51RC-RD.pdf (stcmcudata.com)][007]

[001]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220519-riscv-irq-analysis.md
[002]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220626-riscv-irq-analysis-part2-Interrupt-handling-plic.md
[003]: https://github.com/riscv/riscv-isa-manual/releases/download/Priv-v1.12/riscv-privileged-20211203.pdf
[004]: https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf
[005]: http://riscvbook.com/chinese/RISC-V-Reader-Chinese-v2p1.pdf
[006]: https://tinylab.org/riscv-linux-quickstart/
[007]: http://www.stcmcudata.com/datasheet/stc/STC-AD-PDF/STC89C51RC-RD.pdf
