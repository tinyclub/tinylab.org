---
layout: post
author: 'tjytimi'
title: 'RISC-V Linux 进程创建与执行流程代码分析'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-task-implementation/
description: '本文基于 RISC-V 架构，分析了 Linux 进程创建与执行的流程。'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - Task Implementation
  - 进程创建
---

> Author:  tjytimi  <tjytimi@163.com>
> Date:    2022/05/22
> Revisor: Falcon <falcon@tinylab.org>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)

## 前言

本文分析进程创建流程代码，并通过进程创建过程分析 Linux 内核对 RICS-V 下进程实现的支持。

本文按照代码执行顺序进行分析，只描述实现关键功能函数，内核版本为 Linux 5.17。

## kernel_clone

Linux 新进程创建通过 `fork()` 系统调用实现。用户进程通过 `fork()` 系统调用进入内核态后，进入其系统调用原型。代码如下：

``` c

// kernel/fork.c : 2620

SYSCALL_DEFINE0(fork)
{
	struct kernel_clone_args args = {
		.exit_signal = SIGCHLD,
	};
	return kernel_clone(&args);
}

```
此函数通过简单设置 `args` 参数，调用 `kernel_clone()` 函数实现。

实际上，创建进程包括一组系统调用，包括 `clone()` , `vfork()` 等，其最终实现均通过调用 `kernel_clone()` 函数，区别仅仅在于设置 `arg` 参数不同。

通常我们在用户程序中常用的 Pthread 线程库，最终也是通过 `kernel_clone()` 完成。

熟悉之前内核版本的朋友可以发现，实际上 `kernel_clone()` 就是之前版本内核里的 `_do_fork()` 函数。其精简后代码如下:

``` c

// kernel/fork.c  : 2524
pid_t kernel_clone(struct kernel_clone_args *args)
{
	u64 clone_flags = args->flags;
	struct pid *pid;
	struct task_struct *p;

	p = copy_process(NULL, trace, NUMA_NO_NODE, args);

	pid = get_task_pid(p, PIDTYPE_PID);
	nr = pid_vnr(pid);

	wake_up_new_task(p);

	return nr;
}

```

`kernel_clone()` 依次进行以下工作：

### 完成进程描述符的复制

调用 `copy_process()` 完成子进程的生成工作，生成子进程进程描述符( `task_struct` )。

此函数根据传入参数中的 `flag` 标志确定是复制或是重用父进程数据。这是进程创建并能够得以运行的基础。

在 `copy_process()` 一节中将对此函数进行详细介绍。

### 获取新进程的进程 PID

因为 `fork()` 系统调用要在父进程返回子进程在当前进程命名空间( `namespace` )的 PID 作为返回值，用于在用户空间父进程对子进程的回收等管理工作。所以在完成 `copy_process()` 后， `kernel_clone()` 会从子进程的 PID 结构中获取当前命名空间的进程 ID 号。

### 唤醒子进程

调用 `wake_up_new_task()` 将进程描述符中的调度实体插入运行队列，完成进程唤醒功能。需要注意的是，此时的唤醒并不代表子进程开始执行了。实际该子进程的执行是由调度器在适当时机根据调度策略选中此进程使其执行。

在 `wake_up_new_task` 一节中将对此进行详细介绍。

## copy_process()

顾名思义 `copy_process()` 函数负责复制父进程的数据结构。函数定义在 `kernel/fork.c` 中。函数主要流程如下，将依次进行分析。


```
copy_process()
	- dup_task_struct()
	- sched_fork()
	- copy_xxx(copy_mm,copy_fs,copy_files,copy_thread)
	- 初始化进程 PID 实体及进程关系

```

### dup_task_struct()

`dup_task_struct()` 函数对父进程描述符进行初步复制，产生新的子进程描述符。函数具体流程如下：

1. 首先通过 SLAB 系统分配一个进程描述符( `struct task_struct *tsk` )和一个内核栈( `unsigned long *stack` )。

2. 通过 `arch_dup_task_struct()` 函数将父进程的进程描述符拷贝到新建子进程的进程描述符。 `arch_dup_task_struct()` 是处理器相关函数，代码如下。其中 `fstate_save()` 负责把 RICS-V 处理器浮点运算单元寄存器保存在父进程进程描述符的 `thread` 字段( `struct thread_struct` )所包含的 `fstate` 元素中。 `thread` 字段定义是处理器相关的，用于保存处理器相关的上下文信息，供进程切换时使用。RICS-V  中 `struct thread_struct` 定义见 `copy_thread` 一节。 `*dst = *src` 直接复制父进程进程描述符拷贝到子进程，后续流程将会对需要修改的元素进行修改。


``` c
// arch/riscv/kernel/process.c : 115

int arch_dup_task_struct(struct task_struct *dst, struct task_struct *src)
{
	fstate_save(src, task_pt_regs(src));
	*dst = *src;
	return 0;
}
```



3. 将子进程描述符的内核栈指针指向步骤 1 申请的内核栈。

4. 调用 `setup_thread_stack()` 函数，此函数用于初始化 `thread_info` 数据。在 RISC-V 架构下， `thread_info` 没有共享使用栈空间，而是显式定义在 `task_stuct` 结构体中，因此步骤 2 已经完成 `thread_info` 的复制，`setup_thread_stack()` 函数什么也不做直接返回。而在 X86 、 MIPS 架构中， `thread_info` 复用了内核栈空间，此函数会将父进程中的 `thread_info` 复制到子进程。

处理器会频繁使用当前进程的 `thread_info` ，故内核希望通过寄存器实现快速访问 。RICS-V 架构有专门的 `tp` ( `thread point` ) 寄存器，存储 `thread_info` 的地址，打开 `CONFIG_THREAD_INFO_IN_TASK` 这个配置， `thread_info` 就为 `task_struct` 的第一个成员，这样也相当于为 `task_struct` 准备了寄存器 `tp` 。


``` c

   struct task_struct {
#ifdef CONFIG_THREAD_INFO_IN_TASK
	/*
	 * For reasons of header soup (see current_thread_info()), this
	 * must be the first element of task_struct.
	 */
	struct thread_info		thread_info;
#endif

	...

```

类似的 MIPS 架构使用 `gp` 寄存器存储 `thread_info` 的地址 。 X86 没有专门准备寄存器，但由于 `thread_info` 放入内核栈中复用，通过堆栈寄存器，也可快速访问 `thread_info` 。从此处可以看出通过 RISC-V  架构学习内核相对于 X86  少了很多需要仔细思考的处理器相关的难点。

5. 初始化子进程结构体中一些元素。如调用 `clear_tsk_need_resched()` 将 `thread_info` 中进程需要被重新调度的标志复位（因为新建进程是不需要重新调度的，新建进程有可能在复制描述符的时候复制了此标志位）。


###   sched_fork

`sched_fork()` 函数负责初始化调度相关的字段，如初始化进程的优先级，初始化虚拟运行时间，初始化调度类等工作。此部分代码非常简单直白，不再做细节分析。

###  copy_xxx

这里包括一系列的形如 `copy_xxx` 的函数，通过他们的名字可知函数的作用是复制或是共享进程描述符中特定结构体对应的数据，复制共享与否，取决于 `copy_process()` 函数传入的 `flag` 标志的设置。

这里主要分析 `copy_mm()` 和 `copy_thread()` 两个部分。

####  copy_mm

`copy_mm()` 主要进行进程的内存描述符复制工作，函数主要流程如下。涉及到内存管理部分内容，可参考本项目其他相关分析文章。

```
	copy_mm()
		- dup_mm
			- mm_init
				- mm_alloc_pgd
					- pgd_malloc
			- init_new_context
		- dup_mmap
```

函数首先调用 `dup_mm()` 函数复制内存描述符，此函数主要工作由 `mm_init()` 和 `init_new_context()` 完成。

`mm_init()`进行进程内存描述符的初始化工作，最终调用处理器相关的 `pgd_malloc()` 函数申请页全局目录 `pgd` ，并从 0 号进程拷贝内核页表项的全部内容到本进程。

``` c

// arch/riscv/include/asm/pgalloc.h : 80
static inline pgd_t *pgd_alloc(struct mm_struct *mm)
{
	pgd_t *pgd;

	pgd = (pgd_t *)__get_free_page(GFP_KERNEL);
	if (likely(pgd != NULL)) {
		memset(pgd, 0, USER_PTRS_PER_PGD * sizeof(pgd_t));
		/* Copy kernel mappings */
		memcpy(pgd + USER_PTRS_PER_PGD,
			init_mm.pgd + USER_PTRS_PER_PGD,
			(PTRS_PER_PGD - USER_PTRS_PER_PGD) * sizeof(pgd_t));
	}
	return pgd;
}

```

`init_new_context()` 将内存描述符中上下文 ID 置 0 ，保证在进程切换时 ASID 无效，会直接为该内存描述符申请 ASID 版本号和硬件编号。


``` c

// arch/riscv/include/asm/mmu_context.h : 26

#define init_new_context init_new_context
static inline int init_new_context(struct task_struct *tsk,
			struct mm_struct *mm)
{
#ifdef CONFIG_MMU
	atomic_long_set(&mm->context.id, 0);
#endif
	return 0;
}
```

在进程调度时，会调用 `switch_mm()` 切换到刚刚新建的进程页全局目录 `pgd` ,该函数会调用 `csr_write` 宏将目录地址及 ASID 信息写到  `CSR_SATP` 寄存器。可参考本项目中 `context_switch()分析` 有关 `switch_mm()` 部分。

接着 `copy_mm()` 函数会调用 `dup_mmap()` 函数把父进程的进程地址空间复制到子进程，复制时逐级复制，在最后一级复制页表项时，会调用 RISC-V 下的 `pte_wrprotect` 函数对页面进行写保护，这是实现 `写时复制(COW)` 的基础性工作。


#### copy_thread

`copy_thread` 是进程创建中与 CPU 体系结构相关的关键步骤，用于创建并初始化线程上下文描述符 `thread` ,该描述符用于存储 CPU 相关状态，其对应结构体定义是处理器相关的。 RISC -V 下的 `thread_struct` 定义如下：

``` c

// arch/riscv/include/asm : 31

struct thread_struct {
	/* Callee-saved registers */
	unsigned long ra;
	unsigned long sp;	/* Kernel mode stack */
	unsigned long s[12];	/* s[0]: frame pointer */
	struct __riscv_d_ext_state fstate;
	unsigned long bad_cause;
};
```

该结构用于存储被调用者保存寄存器（ `callee saved register` ）的值。根据 RISC-V 手册寄存器描述：

- `ra` 为返回地址寄存器，存储  `ret`  等返回指令后开始执行的地址。
- `sp` 为内核栈寄存器。`s0` - `s11` 为保存寄存器（ `saved register` ），
- `fstate` 为浮点运算相关寄存器（ `dup_task_struct()` 一节中对 `fstate` 进行了描述）。

RICS-V 架构下的 `copy_thread` 函数如下：

``` c

// arch/ricsv/kernel/process.c : 122
int copy_thread(unsigned long clone_flags, unsigned long usp, unsigned long arg,
		struct task_struct *p, unsigned long tls)
{
	struct pt_regs *childregs = task_pt_regs(p);

	/* p->thread holds context to be restored by __switch_to() */
	if (unlikely(p->flags & (PF_KTHREAD | PF_IO_WORKER))) {
		/* Kernel thread */
		memset(childregs, 0, sizeof(struct pt_regs));
		childregs->gp = gp_in_global;
		/* Supervisor/Machine, irqs on: */
		childregs->status = SR_PP | SR_PIE;

		p->thread.ra = (unsigned long)ret_from_kernel_thread;
		p->thread.s[0] = usp; /* fn */
		p->thread.s[1] = arg;
	} else {
		*childregs = *(current_pt_regs());
		if (usp) /* User fork */
			childregs->sp = usp;
		if (clone_flags & CLONE_SETTLS)
			childregs->tp = tls;
		childregs->a0 = 0; /* Return value of fork() */
		p->thread.ra = (unsigned long)ret_from_fork;
	}
	p->thread.sp = (unsigned long)childregs; /* kernel sp */
	return 0;
}

```
`copy_thread` 函数首先初始化内核栈，用 `task_pt_regs(p)` 将内核栈空间强制转化为寄存器上下文 `pt_regs` 结构，此结构体用于异常及系统调用时保存寄存器的值。 RISC-V 该结构体定义如下：

``` c

struct pt_regs {

	unsigned long epc;
	unsigned long ra;
	unsigned long sp;
	unsigned long gp;
	unsigned long tp;


	...
	/* Supervisor/Machine CSRs */
	unsigned long status;
	unsigned long badaddr;
	unsigned long cause;
	/* a0 value before the syscall */
	unsigned long orig_a0;
}
```
随后根据新进程是内核线程还是用户进程决定不同的分支，下面分别进行描述。

1. 内核线程

如果新进程是内核线程，将线程上下文 `thread` 中 `ra` 设置成 `ret_from_kernel_thread` 函数地址，线程上下文的 `s[0]` 设置为 `fn` 的地址(  fn  为新建内核线程时传入执行函数)， `s[1]` 设置为 arg ( arg 为在新建内核线程传入要执行函数数 fn 的参数)。

这意味着子进程刚开始运行时，先执行 `ret_from_kernel_thread` 的代码，此函数为 RISC-V 架构相关的汇编，指明了调用 `s0` 寄存器对应的函数，并用 `s1` 寄存器作为此函数的参数。

2. 用户进程

- 调用 `current_pt_regs()` 获取当前进程（父进程）的内核栈寄存器上下文，将其复制到子进程的栈中的上下文 `childregs` 。

- 将子进程内核栈中寄存器上下文的栈寄存器 `sp` （也就是返回用户态后用户栈）赋值为 usp 。

- 如果 `clone_flags` 设置了 `CLONE_SETTLS`，则将 `tp` 赋值为 `tls`。可参考 [系统调用 CLONE_SETTLS 相关内容](https://www.man7.org/linux/man-pages/man2/clone.2.html)

- RISC-V 的 `a0` 寄存器为系统调用返回用户态后的返回值寄存器，故将 `childregs->a0` 设置为0，当 `fork()` 等系统调用子进程返回用户态前，从内核栈恢复了 `a0` 的值到 `a0` 寄存器 ，子进程返回值就是0。

- 将子进程的内核线程上下文的 `thread.ra` 设置为 `ret_from_fork` 汇编所在的地址，将内核线程上下文中内核栈 `thread.sp` 赋值为刚刚设置好的 `childregs` 的地址。用户进程完成上述流程后进程描述符如下图所示。


![Copy Thread](/wp-content/uploads/2022/03/riscv-linux/images/riscv_task_implementation/copy_thread.png)


当进程切换到子进程时，内核会从内核线程上下文恢复所有寄存器的值：内核栈将变成为上述设置的 `thread.sp` ， `ra` 寄存器将变成 `thread.ra` （ `ret_from_fork` 汇编的地址），这将会使子进程被调度后首先执行 `ret_from_fork` 。

`ret_from_fork` 完成后会把内核栈中存储的寄存器上下文恢复到 RISC-V 的寄存器中，包括将 usp 写到栈寄存器，完成内核栈到用户栈的切换，最后调用 `mret` 或 `sret` 返回用户态。`创建进程后子进程的执行`一节将对此详细介绍。

上文中涉及到内核栈，用户栈，内核栈中寄存器上下文，进程描述符中线程上下文，各种概念比较易混淆，应仔细区分。


## wake_up_new_task


在完成子进程描述符的复制后，`kernel_clone()` 调用` wake_up_new_task()` 唤醒子进程，将其加入运行队列，等待调度系统的调度。其主要的工作由 `activate_task()` 函数完成。其主要流程如下：

```
activate_task
	- enqueue_task
 		- p->sched_class->enqueue_task(rq, p, flags)
	- p->on_rq = TASK_ON_RQ_QUEUED
```

`activate_task()` 首先调用 `enqueue_task()` ，其内部主要执行进程对应的调度器类 `sched_class` 对应的插入函数，此类在 `sched_fork()` 函数中设置。插入后将进程的 `on_rq` 标识设置为  `TASK_ON_RQ_QUEUED` ，表明进程已入运行队列。

## 创建进程后子进程的执行

子进程完成建立后，只是将其加入了运行队列，并没有实际运行，只有当调度器选中子进程，子进程才会投入运行。关于调度器的内容可参考其他资料。


当进程被调度后，进程切换函数 `context_switch()` 中 `switch_to` 汇编函数把选中的 next 进程的恢复到它被切换出去之前的状态。可参考本项目 `RISC-V Linux 上下文切换分析` 中有关内容。
```
// arch/riscv/kernel/entry.S : 512

ENTRY(__switch_to)
	/* Save context into prev->thread */
	li    a4,  TASK_THREAD_RA
	add   a3, a0, a4
	add   a4, a1, a4
	REG_S ra,  TASK_THREAD_RA_RA(a3)
	REG_S sp,  TASK_THREAD_SP_RA(a3)
	REG_S s0,  TASK_THREAD_S0_RA(a3)

	....

	REG_S s11, TASK_THREAD_S11_RA(a3)
	/* Restore context from next->thread */
	REG_L ra,  TASK_THREAD_RA_RA(a4)
	REG_L sp,  TASK_THREAD_SP_RA(a4)
	REG_L s0,  TASK_THREAD_S0_RA(a4)

	...

	REG_L s11, TASK_THREAD_S11_RA(a4)
	/* The offset of thread_info in task_struct is zero. */
	move tp, a1
	ret
ENDPROC(__switch_to)
```


根据 `__switch_to` 代码可知，如果 next 进程是已经执行过的进程，在其上次被切换出去时，会在 `thread.ra` 中记录 `ra` 寄存器的值 ，此次切回后， `ra` 寄存器恢复到 next 进程存储的返回地址 ，这样 `switch_to` 最后的 `ret` 指令会让进程回到 `context_switch()` 函数中，进而执行 `context_switch()` 函数最后的 `finish_task_switch()` 函数进行进程调度收尾工作。

但新建的子进程之前未曾被切换出去，所以对于新进程而言，前述 `copy_thread()` 函数中将 `thread.ra` 赋值为 `ret_from_fork` ，使调度程序认为子进程是从 `ret_from_fork` 处被切换出去的。

所以被调度的新进程不会执行 `finish_task_switch()` ，而是首先执行 `ret_from_fork` 。

`ret_from_fork` 主要流程如下，汇编首先调用 `schedule_tail` 进行进程调度的收尾工作，实际上就是执行了类似于 `finish_task_switch()` 收尾代码类似功能。

```

ret_from_fork
	- schedule_tail
	- ret_from_exception
		- restore_all

```

然后调用 `ret_from_exception` 函数执行从异常或系统调用返回的功能。

`ret_from_exception` 函数主要流程是 `restore_all` ，其汇编代码如下。通过将系统调用时存入内核栈中的寄存器上下文加载到 RISC-V 的寄存器中完成对系统调用前状态的恢复。

```
// arch/riscv/kernel/entry.S : 268

restore_all:

	REG_L a0, PT_STATUS(sp)
	REG_L  a2, PT_EPC(sp)
	REG_SC x0, a2, PT_EPC(sp)

	csrw CSR_STATUS, a0
	csrw CSR_EPC, a2
	REG_L x1, PT_RA(sp)
	REG_L x3, PT_GP(sp)
	REG_L x4, PT_TP(sp)

	...
	REG_L x30, PT_T5(sp)
	REG_L x31, PT_T6(sp)

	REG_L x2, PT_SP(sp)

#ifdef CONFIG_RISCV_M_MODE
mret
#else
sret
#endif

```
- 首先恢复 `STATUS ` 状态寄存器。

- 恢复 `EPC` 寄存器（存储系统调用下一条指令 PC ），由于 `copy_thread()` 函数中 `*childregs = *(current_pt_regs())` 复制了父进程中的堆栈上下文，所以子进程 `EPC` 和父进程一样指向系统调用返回地址。

- 依次恢复除栈寄存器外的所有寄存器。

- 恢复堆栈寄存器 `x2` 完成内核栈到用户栈切换。

- 调用 `mret` 或 `sret` 返回用户态，开始执行系统调用后用户态代码（即 `EPC` 寄存器对应代码）。

至此，进程创建过程代码分析完毕。

## 总结

本文按照代码执行流程，分析了进程创建及其与 RISC-V 处理器架构相关的处理过程，展示了 RISC-V 处理器与进程实现相关特性。


