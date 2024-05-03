---
layout: post
author: 'unknown'
title: 'Generic entry RISC-V 补丁分析'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-irq-analysis-part5-generic-entry-backgroud-and-status/
description: 'Generic entry RISC-V 补丁分析'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - Generic IRQ
---

> Corrector:  [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [pangu autocorrect]
> Author:     牛工 - 通天塔 985400330@qq.com
> Translator: niufukun <985400330@qq.com>
> Date:       2022/09/07
> Revisor:    Falcon <falcon@ruma.tech>; iOSDevLog <iosdevlog@iosdevlog.com>
> Project:    [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:   [【老师提案】Linux IRQ 子系统分析 · Issue #I5E5EP · 泰晓科技/RISCV-Linux - Gitee.com](https://gitee.com/tinylab/riscv-linux/issues/I5E5EP)
> Sponsor:    PLCT Lab, ISCAS


## 前言

郭老师在 RISC-V 社区中的新补丁 [[PATCH V3 0/7] riscv: Add GENERIC_ENTRY, irq stack support (kernel.org)][005]

补丁描述如下：

> The patches convert RISC-V to use the generic entry infrastructure from kernel/entry/\*.
> - Add independent irq stacks (IRQ_STACKS) for percpu to prevent kernel stack overflows.
> - Add the HAVE_SOFTIRQ_ON_OWN_STACK feature for the IRQ_STACKS config.

补丁将 RISC-V 转换为使用 `kernel/entry/*` 的结构体。
- 为每个 CPU 添加独立的 irq 堆栈（IRQ_STACKS），以防止内核堆栈溢出。
- 为 IRQ_STACKS 配置添加 HAVE_SOFTIRQ_ON_OWN_STACK 特性。

RISC-V 引入了新的特性 Generic entry，本篇文章将对该特性的背景、好处、各架构的支持情况、RISC-V 的迁移情况进行讲述。

## 背景

### Thomas 与 Generic Entry

Thomas Gleixner 是 Linux 基金会研究员、Linutronix GmbH 首席技术官、PREEMPT_RT 实时内核补丁集项目负责人，Thomas Gleixner 自 2008 年以来一直是 Linux 内核中 x86 架构，通用中断子系统（generic interrupt subsystem）和时间子系统的（timer subsystem）的主要维护者。

Thomas Gleixner 在 2020 年完成了 Generic entry 的合入。

补丁链接：[[patch V5 00/15] entry, x86, kvm: Generic entry/exit functionality for host and guest (kernel.org)][006]

#### Linus 合入记录

```
commit 3f0d6ecdf1ab35ac54cabb759f748fb0bffd26a5
Merge: 442489c21923 3135f5b73592
Author: Linus Torvalds <torvalds@linux-foundation.org>
Date:   Tue Aug 4 21:00:11 2020 -0700
Merge tag 'core-entry-2020-08-04' of git: // git.kernel.org/pub/scm/linux/kernel/git/tip/tip
tag 'core-entry-2020-08-04' of git: // git.kernel.org/pub/scm/linux/kernel/git/tip/tip:
entry: Correct __secure_computing() stub
entry: Correct 'noinstr' attributes
entry: Provide infrastructure for work before transitioning to guest mode
entry: Provide generic interrupt entry/exit code
entry: Provide generic syscall exit function
entry: Provide generic syscall entry functionality
seccomp: Provide stub for __secure_computing()
```

> Pull generic kernel entry/exit code from Thomas Gleixner: "Generic implementation of common syscall, interrupt and exception entry/exit functionality based on the recent X86 effort to ensure correctness of entry/exit vs RCU and instrumentation.

从 Thomas Gleixner 那里拉取通用内核 entry/exit 代码，基于最近在 x86 的努力，通用的系统调用，中断和异常的进入、退出函数得到了实现。这保证了 entry/exit 对于 RCU 和可检测性的正确性

> As this functionality and the required entry/exit sequences are not architecture specific, sharing them allows other architectures to benefit instead of copying the same code over and over again.

由于此功能和所需的 entry/exit 时序不是特定于架构的，因此共享它们可以让其他架构受益，而不是一遍又一遍地复制相同的代码。

> This branch was kept standalone to allow others to work on it. The conversion of x86 comes in a seperate pull request which obviously is based on this branch"

这个分支过去一致保持独立，以允许其他人在上边工作。x86 的转换来自一个独立的 Pull Request，该 Pull Request 很显然是基于这个分支的。

#### Thomas 的提交记录

Thomas 第一次导入 Generic Entry 是在 2020 年 7 月 22 日。

提交如下：

```
commit 142781e108b13b2b0e8f035cfb5bfbbc8f14d887
Author: Thomas Gleixner <tglx@linutronix.de>
Date:   Wed Jul 22 23:59:56 2020 +0200

Signed-off-by: Thomas Gleixner <tglx@linutronix.de>
Acked-by: Kees Cook <keescook@chromium.org>
Link: https://lkml.kernel.org/r/20200722220519.513463269@linutronix.de
```

> entry: Provide generic syscall entry functionality

入口：提供通用 syscall 入口函数

> On syscall entry certain work needs to be done:
> - Establish state (lockdep, context tracking, tracing)
> - Conditional work (ptrace, seccomp, audit...)

在 syscall 入口确定要做的：
- 确定状态（锁深度，上下文追踪，追踪）
- 条件工作（进程追踪，seccomp，审核...）

> This code is needlessly duplicated and different in all architectures.
>
> Provide a generic version based on the x86 implementation which has all the RCU and instrumentation bits right.
>
> As interrupt/exception entry from user space needs parts of the same functionality, provide a function for this as well.
>
> syscall_enter_from_user_mode() and irqentry_enter_from_user_mode() must be called right after the low level ASM entry.
>
> The calling code must be non-instrumentable. After the functions returns state is correct and the subsequent functions can be instrumented.

在所有架构中，这些代码是不必要重复和不同的。

提供一个基于 x86 实现的通用版本，它拥有所有的 RCU 和检测（Instrumentation）位。

由于来自用户空间的中断/异常入口需要部分相同的功能，因此也要为此提供一个函数。

syscall_enter_from_user_mode() 和 irqentry_enter_from_user_mode() 必须在低级汇编入口之后被调用。

调用代码必须是不可检测的。在函数返回后，状态是正确的，后续的函数可以检测。

### RISC-V 与 Generic Entry

在引入该补丁之前，RISC-V 中关于中断的处理很多都是自定义实现的，没有使用内核提供的一些好的中断处理接口，导致代码比较冗余。

还有对于 syscall 的处理函数也不够简洁可读，郭老师对于此处的代码进行了优化。

补丁 `[PATCH V3 4/7] riscv: convert to generic entry` 是进行 generic entry 接口转换的一个关键补丁。

补丁中的描述：

```
 - More clear entry.S with handle_exception and ret_from_exception
 - Get rid of complex custom signal implementation
 - More readable syscall procedure
 - Little modification on ret_from_fork & ret_from_kernel_thread
 - Wrap with irqentry_enter/exit and syscall_enter/exit_from_user_mode
 - Use the standard preemption code instead of custom
```

- 使 `handle_exception` 和 `ret_from_exception` 在 entry.S 中更清晰
- 摆脱复杂的自定义信号实现
- 更可读的 syscall 过程
- 对 `ret_from_fork` 和 `ret_from_kernel_thread` 进行了一些修改
- 新增 `irqentry_enter/exit` 和 `syscall_enter/exit_from_user_mode` 调用
- 使用标准抢占代码，不使用自定义抢占代码

## Generic Entry 架构简介

### 整体架构

Generic Entry 的核心函数在 `include/linux/entry-common.h` 列举了出来。主要是将一些通用的入口、出口函数进行了抽象，减少了各个架构对于中断入口、出口的重复实现。各个架构将其自身的 `entry-common.h` 部分进行实现，中断处理时直接调用 `kernel/entry/common.c` 即可。

![image-20221009233522433](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20221009233522433.png)

### 架构相关部分

RISC-V 的 Generic Entry 的支持是通过修改跳转的函数以及中断的处理流程实现的。

![image-20221009223022027](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20221009223022027.png)

架构相关部分：

- 汇编部分 Entry.s 中有着中断处理函数的跳转地址，通过汇编修改中断时跳转函数才可以使用 Generic Entry 的接口。

- 中断处理函数 `do_riscv_irq`，是汇编部分要跳转到的中断处理函数，此处对 Generic Entry 接口进行调用，要单独进行实现。
- syscall 处理函数 `do_sys_ecall_u`，新增了 Generic Entry 的接口调用，单独进行了实现。
- Generic Entry 的底层接口也有许多基于架构的实现，具体文件为 `arch/riscv/include/asm/entry-common.h`

## RISC-V 迁移情况

该节基于之前的代码对本次新增的补丁的好处进行深入分析。

```
 arch/riscv/Kconfig                    |   1 +
 arch/riscv/include/asm/csr.h          |   1 -
 arch/riscv/include/asm/entry-common.h |   8 +
 arch/riscv/include/asm/ptrace.h       |  10 +-
 arch/riscv/include/asm/stacktrace.h   |   5 +
 arch/riscv/include/asm/syscall.h      |   6 +
 arch/riscv/include/asm/thread_info.h  |  13 +-
 arch/riscv/kernel/entry.S             | 228 +++-----------------------
 arch/riscv/kernel/irq.c               |  15 ++
 arch/riscv/kernel/ptrace.c            |  40 -----
 arch/riscv/kernel/signal.c            |  21 +--
 arch/riscv/kernel/sys_riscv.c         |  27 +++
 arch/riscv/kernel/traps.c             |  11 ++
 arch/riscv/mm/fault.c                 |  12 +-
 14 files changed, 117 insertions(+), 281 deletions(-)
 create mode 100644 arch/riscv/include/asm/entry-common.h
```

通过补丁可以看到本次删除掉了很多的代码，使代码更加简洁了。

本次改动主要涉及 4 个部分：抢占式中断处理流程、上下文保存、do_riscv_irq 函数的实现、syscall 处理函数的实现。

我之前写过一篇文章介绍了中断的处理流程：[RISC-V 中断子系统分析——CPU 中断处理][002]，其中分析了 `handle_exception`，该函数是产生异常时的跳转地址，主要用于中断处理、异常处理、syscall 处理、保护现场、恢复现场。

### 抢占式中断处理流程改动

此处就是对于 **标准抢占代码** 替代 **自定义抢占代码** 的相关处理。

当前的修改后：

```assembly
@@ -14,10 +14,6 @@
 #include <asm/asm-offsets.h>
 #include <asm/errata_list.h>
/* 当未设置抢占时，定义 resume_kernel 函数为 restore_all */
-#if !IS_ENABLED(CONFIG_PREEMPTION)
-.set resume_kernel, restore_all
-#endif
-
 ENTRY(handle_exception)
```

此处删除了如果未使能抢占的一个配置。

#### 自定义的抢占代码

当定义了抢占宏 `CONFIG_PREEMPTION` 时：

```assembly
/* arch/riscv/kernel/entry.S */
/* version:Linux 6.0-rc4 */
ret_from_exception:
	REG_L s0, PT_STATUS(sp)
	csrc CSR_STATUS, SR_IE
#ifdef CONFIG_TRACE_IRQFLAGS
	call __trace_hardirqs_off
#endif
#ifdef CONFIG_RISCV_M_MODE
	/* the MPP value is too large to be used as an immediate arg for addi */
	li t0, SR_MPP
	and s0, s0, t0
#else
	andi s0, s0, SR_SPP
#endif
	bnez s0, resume_kernel
```

当使能了抢占之后，执行的是以下代码。

```assembly
/* arch/riscv/kernel/entry.S */
/* version:Linux 6.0-rc4 */
#if IS_ENABLED(CONFIG_PREEMPTION)
resume_kernel:
/* 判断此处是否需要进行抢占式的中断处理 */
	REG_L s0, TASK_TI_PREEMPT_COUNT(tp)
	bnez s0, restore_all
	REG_L s0, TASK_TI_FLAGS(tp)
	andi s0, s0, _TIF_NEED_RESCHED
	beqz s0, restore_all
	call preempt_schedule_irq /* 符合抢占要求，call 抢占调度函数 */
	j restore_all
#endif
```

#### 标准抢占代码

上一小节描述了自定义抢占代码的实现，改动之后，在 entry.S 中的抢占相关的判断等代码被删除，不再对抢占进行处理。

标准的抢占代码如下代码：

```c
// arch/riscv/kernel/irq.c
// version：https://github.com/guoren83/linux/tree/generic_entry_v3
asmlinkage void noinstr do_riscv_irq(struct pt_regs *regs)
{
...
	irqentry_exit(regs, state);
}
```

```c
// kernel/entry/common.c
// version：https://github.com/guoren83/linux/tree/generic_entry_v3
noinstr void irqentry_exit(struct pt_regs *regs, irqentry_state_t state)
{
...
		if (IS_ENABLED(CONFIG_PREEMPTION))
			irqentry_exit_cond_resched();
...
}
```

```c
// kernel/entry/common.c
// version：https://github.com/guoren83/linux/tree/generic_entry_v3
void raw_irqentry_exit_cond_resched(void)
{
	if (!preempt_count()) {
		...
			preempt_schedule_irq();
	}
}
```

之前的抢占相关的代码是在汇编文件 `arch/riscv/kernel/entry.S` 中进行实现的，未使用内核现有的接口。

新增了 `do_riscv_irq` 之后，调用了公共函数 `irqentry_exit`，完成了抢占检测和调度的工作。

充分利用了内核现有接口，使得 RISC-V 代码更加整洁。

### 上下文保存改动

```assembly
@@ -106,19 +102,8 @@ _save_context:
 .option norelax
 	la gp, __global_pointer$
 .option pop
-
-#ifdef CONFIG_TRACE_IRQFLAGS
-	call __trace_hardirqs_off
-#endif
-
-#ifdef CONFIG_CONTEXT_TRACKING_USER
-	/* If previous state is in user mode, call user_exit_callable(). */
-	li   a0, SR_PP
-	and a0, s1, a0
-	bnez a0, skip_context_tracking
-	call user_exit_callable
-skip_context_tracking: /* 删除了跳过上下文切换追踪的函数标签 */
-#endif
+	move a0, sp /* pt_regs */
+	la ra, ret_from_exception

 	/*
 	 * MSB of cause differentiates between
```

删除了关于 `CONFIG_TRACE_IRQFLAGS` 和 `CONFIG_CONTEXT_TRACKING_USER` 的相关调用，用于中断的调试。新增代码设置返回地址 `ret_from_exception`。

```assembly
@@ -126,134 +111,26 @@ skip_context_tracking:
 	 */
 	bge s4, zero, 1f

-	la ra, ret_from_exception /* 代码上移，删除了跳过上下文追踪标签 */
-
 	/* Handle interrupts */
-	move a0, sp /* pt_regs */
-	la a1, generic_handle_arch_irq
-	jr a1
+	tail do_riscv_irq /* 更换了中断处理函数 */

/* 以下关于异常的代码被删除 */
 1:
-	/*
-	 * Exceptions run with interrupts enabled or disabled depending on the
-	 * state of SR_PIE in m/sstatus.
- */
-	andi t0, s1, SR_PIE
-	beqz t0, 1f
-	/* kprobes, entered via ebreak, must have interrupts disabled. */
-	li t0, EXC_BREAKPOINT
-	beq s4, t0, 1f
-#ifdef CONFIG_TRACE_IRQFLAGS
-	call __trace_hardirqs_on
-#endif
-	csrs CSR_STATUS, SR_IE
-
-1:
-	la ra, ret_from_exception
-	/* Handle syscalls */
-	li t0, EXC_SYSCALL
-	beq s4, t0, handle_syscall
-
/* 以上关于处理异常的代码被删除 */

/* 处理一些其他的异常 */
 	/* Handle other exceptions */
 	slli t0, s4, RISCV_LGPTR
 	la t1, excp_vect_table
 	la t2, excp_vect_table_end
-	move a0, sp /* pt_regs */
 	add t0, t1, t0
 	/* Check if exception code lies within bounds */
-	bgeu t0, t2, 1f
+	bgeu t0, t2, 2f /* 修改 t0>t2 之后的 PC 指针偏移，此处不明白为什么从 1f->2f */
 	REG_L t0, 0(t0)
 	jr t0 /* 跳转到异常代码处理地址 */
-1:
+2:
 	tail do_trap_unknown
+END(handle_exception)
/* 再往下则删除了 syscall 的相关处理代码 */
```

以上修改了中断的处理流程，改变了中断处理函数，删除了异常处理代码，修改了出现异常代码时的 PC 指针地址，删除了 syscall 的相关处理代码。

删除了汇编部分的 syscall 相关代码，放到了以下位置进行处理，`do_sys_ecall_u` 函数在 `arch/riscv/kernel/sys_riscv.c` 代码中进行了实现，提高了代码可读性。

```assembly
@@ -582,7 +398,7 @@ ENTRY(excp_vect_table)
 	RISCV_PTR do_trap_load_fault
 	RISCV_PTR do_trap_store_misaligned
 	RISCV_PTR do_trap_store_fault
-	RISCV_PTR do_trap_ecall_u /* system call, gets intercepted */
+	RISCV_PTR do_sys_ecall_u /* system call */
 	RISCV_PTR do_trap_ecall_s
 	RISCV_PTR do_trap_unknown
 	RISCV_PTR do_trap_ecall_m
```

### do_riscv_irq 函数实现

之前在 [RISC-V 中断子系统分析——PLIC 中断处理][003] 这篇文章中，对中断处理的流程进行了分析。

```
[nfk test] goldfish_rtc_interrupt
CPU: 0 PID: 0 Comm: swapper/0 Not tainted 5.17.0-dirty #85
Hardware name: riscv-virtio,qemu (DT)
Call Trace:
[<ffffffff80004750>] dump_backtrace+0x1c/0x24
[<ffffffff806a1bb8>] show_stack+0x2c/0x38
[<ffffffff806a6da8>] dump_stack_lvl+0x40/0x58
[<ffffffff806a6dd4>] dump_stack+0x14/0x1c
[<ffffffff806ad02c>] goldfish_rtc_interrupt+0x22/0x74
[<ffffffff8004c168>] __handle_irq_event_percpu+0x52/0xe0
[<ffffffff8004c208>] handle_irq_event_percpu+0x12/0x4e
[<ffffffff8004c2a2>] handle_irq_event+0x5e/0x94
[<ffffffff8005013a>] handle_fasteoi_irq+0xac/0x18e
[<ffffffff8004b54a>] generic_handle_domain_irq+0x28/0x3a
[<ffffffff802d67e2>] plic_handle_irq+0x8a/0xec
[<ffffffff8004b54a>] generic_handle_domain_irq+0x28/0x3a
[<ffffffff802d6610>] riscv_intc_irq+0x34/0x5c
[<ffffffff806ae0c8>] generic_handle_arch_irq+0x4a/0x74
[<ffffffff8000302a>] ret_from_exception+0x0/0xc
[<ffffffff8005b0e2>] rcu_idle_enter+0x10/0x18
```

以上是之前的中断处理流程，当前补丁修改了 `generic_handle_domain_irq` 为 `do_riscv_irq`。

```c
/*
 * generic_handle_arch_irq - root irq handler for architectures which do no
 *                           entry accounting themselves
 * @regs:	Register file coming from the low-level handling code
 */
```

根据 `generic_handle_domain_irq` 的注释可知，该函数是架构没有自己的中断处理入口的时候才会使用的一个接口。现在 RISC-V 已经有了自己的中断处理接口 `do_riscv_irq`。

`````c
diff --git a/arch/riscv/kernel/irq.c b/arch/riscv/kernel/irq.c
index 7207fa08d78f..24c2e1bd756a 100644
--- a/arch/riscv/kernel/irq.c
+++ b/arch/riscv/kernel/irq.c
@@ -5,6 +5,7 @@

  * Copyright (C) 2018 Christoph Hellwig
    */

+#include <linux/entry-common.h>
 #include <linux/interrupt.h>
 #include <linux/irqchip.h>
 #include <linux/seq_file.h>
@@ -22,3 +23,17 @@ void __init init_IRQ(void)
 	if (!handle_arch_irq)
 		panic("No interrupt controller found.");
 }
+
+asmlinkage void noinstr do_riscv_irq(struct pt_regs *regs)
+{
// 该函数在 [PATCH V3 5/7] riscv: Support HAVE_IRQ_EXIT_ON_IRQ_STACK 又进行了修改
+	struct pt_regs *old_regs;
+	irqentry_state_t state = irqentry_enter(regs); // 新增入口状态获取
+
+	irq_enter_rcu(); // 接口
+	old_regs = set_irq_regs(regs); // 与 generic_handle_arch_irq 一致
+	handle_arch_irq(regs); // 与 generic_handle_arch_irq 一致
+	set_irq_regs(old_regs); // 与 generic_handle_arch_irq 一致
+	irq_exit_rcu();
  +
+	irqentry_exit(regs, state); // 新增状态+退出
  +}
`````

[Entry/exit handling for exceptions, interrupts, syscalls and KVM — The Linux Kernel documentation][001] 中描述了关于 `irqentry_exit` 和 `irqentry_enter` 的作用。

### syscall 修改

补丁删除了 `arch/riscv/kernel/ptrace.c` 中 syscall 相关的代码，在 `arch/riscv/kernel/sys_riscv.c` 中新增了 `do_sys_ecall_u` 函数，用于处理 syscall，**这使 syscall 的调用过程更加的可读。**

在 `arch/riscv/kernel/traps.c` 和 `arch/riscv/mm/fault.c` 中新增了关于 `irqentry_exit` 和 `irqentry_enter` 的调用。

[[PATCH V5 00/11] riscv: Add GENERIC_ENTRY support and related features - guoren (kernel.org)][004]

当前郭老师已经升级补丁至 V5，还在持续进行中。

## 各架构的支持

各架构对于 Generic entry  的支持情况主要看对于 `kernel/entry/common.c` 的使用情况。

![image-20220921233758928](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220921233758928.png)

当前使用 `irqentry_exit` 函数的架构主要有：loongarch、RISC-V、s390、x86；

arm64 架构实现了自己的 entry-common.c，与公共接口不同。

该接口是在 2020 年第一次引入内核，目前在各个架构上的支持还不完善，需要大家共同完成。

```
commit 142781e108b13b2b0e8f035cfb5bfbbc8f14d887
Author: Thomas Gleixner <tglx@linutronix.de>
Date:   Wed Jul 22 23:59:56 2020 +0200

    entry: Provide generic syscall entry functionality

    On syscall entry certain work needs to be done:

       - Establish state (lockdep, context tracking, tracing)
       - Conditional work (ptrace, seccomp, audit...)

    This code is needlessly duplicated and  different in all
    architectures.

    Provide a generic version based on the x86 implementation which has all the
    RCU and instrumentation bits right.

    As interrupt/exception entry from user space needs parts of the same
    functionality, provide a function for this as well.

    syscall_enter_from_user_mode() and irqentry_enter_from_user_mode() must be
    called right after the low level ASM entry. The calling code must be
    non-instrumentable. After the functions returns state is correct and the
    subsequent functions can be instrumented.

    Signed-off-by: Thomas Gleixner <tglx@linutronix.de>
    Acked-by: Kees Cook <keescook@chromium.org>
    Link: https://lkml.kernel.org/r/20200722220519.513463269@linutronix.de

 kernel/entry/common.c | 88 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
 1 file changed, 88 insertions(+)
```

## 小结

本文分析了郭老师在 V3 版本上的补丁提交，对 generic entry 的背景、好处、各架构的支持情况进行了讲述，希望大家能根据本文加深对中断处理的理解，后续我会继续跟进郭老师的补丁提交情况，向大佬学习！

## 参考资料

- [[PATCH V3 0/7] riscv: Add GENERIC_ENTRY, irq stack support (kernel.org)][005]
- [[PATCH V5 00/11] riscv: Add GENERIC_ENTRY support and related features - guoren (kernel.org)][004]
- [Entry/exit handling for exceptions, interrupts, syscalls and KVM — The Linux Kernel documentation][001]
- [RISC-V 中断子系统分析——CPU 中断处理][002]
- [RISC-V 中断子系统分析——CPU 中断处理][002]

[001]: https://docs.kernel.org/core-api/entry.html
[002]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220712-riscv-irq-analysis-part3-Interrupt-handling-cpu.md
[003]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220919-riscv-irq-analysis-part2-interrupt-handling-plic.md
[004]: https://lore.kernel.org/all/20220918155246.1203293-1-guoren@kernel.org/
[005]: https://lore.kernel.org/linux-riscv/CAJF2gTS0Oe7AHcNf1+uGHX=S0bZoKHX2nS-+O72tjjrjq4wScA@mail.gmail.com/T/#t
[006]: https://lore.kernel.org/all/20200722220519.513463269@linutronix.de/T/#u
