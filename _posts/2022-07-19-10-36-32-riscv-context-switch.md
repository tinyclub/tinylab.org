---
layout: post
author: 'Jack.Y'
title: "RISC-V Linux 上下文切换分析"
draft: false
album: 'RISC-V Linux'
license: "cc-by-nc-nd-4.0"
permalink: /riscv-context-switch/
description: "本文主要基于 Linux 5.17 版本代码，讨论在 RISC-V 架构中上下文切换的诸多细节。"
category:
  - 开源项目
  - Risc-V
tags:
  - RISC-V
  - Linux
  - Context Switch
  - 上下文切换
---

> Author:  Jack Y. <eecsyty@outlook.com>
> Date:    2022/05/01
> Revisor: Falcon <falcon@tinylab.org>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)

# RISC-V Linux 上下文切换分析

## 前言

为了在一个处理器上能实现多个任务的并发运行，操作系统要负责在各个任务之间完成调度，这是操作系统最基本的功能之一。

在 Linux 中，所有调度程序最终都归结到完成上下文切换(Context Switch)，即前后两个任务之间运行环境的切换，本文主要基于 Linux 5.17 版本代码，讨论在 RISC-V 架构中上下文切换的诸多细节。

本文仅讨论上下文切换本身的流程，而何时进行上下文切换、切换到什么任务的问题，涉及到调度算法和策略，将在后续文章进行介绍。

## 纵览 Linux 上下文切换

Linux 上下文切换的入口在 `context_switch()` 函数，在其函数注释中已经明确概括了其主要内容：

```c
// kernel/sched/core.c:4940
/*
 * context_switch - switch to the new MM and the new thread's register state.
 */
static __always_inline struct rq *
context_switch(struct rq *rq, struct task_struct *prev,
	       struct task_struct *next, struct rq_flags *rf)
{
	prepare_task_switch(rq, prev, next);
	arch_start_context_switch(prev);
	if (!next->mm) {                                // to kernel
		enter_lazy_tlb(prev->active_mm, next);
		next->active_mm = prev->active_mm;
		if (prev->mm)                           // from user
			mmgrab(prev->active_mm);
		else
			prev->active_mm = NULL;
	} else {                                        // to user
		membarrier_switch_mm(rq, prev->active_mm, next->mm);
		switch_mm_irqs_off(prev->active_mm, next->mm, next);
		if (!prev->mm) {                        // from kernel
			rq->prev_mm = prev->active_mm;
			prev->active_mm = NULL;
		}
	}
	rq->clock_update_flags &= ~(RQCF_ACT_SKIP|RQCF_REQ_SKIP);
	prepare_lock_switch(rq, next, rf);
	switch_to(prev, next, prev);
	barrier();
	return finish_task_switch(prev);
}
```

`context_switch()` 函数主要就负责两方面的切换，一是切换到新线程的 `mm_struct`，二是切换到新线程的寄存器状态。函数整体不长，去掉空行和注释后总共22行。

其函数入参共 $4$ 个：
* 第一个是 `rq`，即 Running Queue，每个 CPU 核有一个 Running Queue，大致可以理解为该 CPU 上的任务队列，每次从 Running Queue 中取出一个任务进行调度；
* 第二个是 `prev`，即切换之前正在执行的任务；
* 第三个是 `next`，即切换后要执行的任务；
* 第四个是 `rf`，在本函数中与 Running Queue 的锁有关。

`prepare_task_switch()` 函数主要是任务切换前的一些准备工作，里面主要涉及 `kcov`、`perf` 等与调测和性能监测相关的内容，与本文核心内容联系不大。

`arch_start_context_switch()` 函数给各个体系结构专有的开始上下文切换的工作提供了入口，但 RISC-V 架构对此函数无专门定义，各体系结构在通用的定义中，该函数为空。

接下来的 `if-else` 语句就到了本文第一个核心部分，即 `mm_struct` 的切换，将在下文中详述。

`rq->clock_update_flags &= ~(RQCF_ACT_SKIP|RQCF_REQ_SKIP);` 这一行与 Running Queue 的时钟更新有关，具体细节将在后续关于 Schedule 的文章中介绍。

下一行 `prepare_lock_switch()` 与死锁检测 `lockdep` 有关，本文将忽略这些离题较远的内容。

然后就到了 `switch_to()`，即 `context_switch()` 的第二个核心内容——寄存器的切换。

最后在加了一个内存屏障 `barrier()` 后，就到了结束环节 `finish_task_switch()`，这个函数和前面的 `prepare_lock_switch()` 相互对应。

下文将对 `mm_struct` 的切换和 `switch_to()` 寄存器内容的切换这两大部分进行详细分析。

## `mm_struct` 的切换

### 背景知识

我们先回顾《操作系统》课程中的两个基本概念：
* 进程是资源分配的最小单位
* 线程是CPU调度的最小单位

上文中所提到的「任务」，其实就是线程。同一个进程的不同线程之间，共享内存资源，即他们拥有同一个 `mm_struct`。

对于 CPU 来说，不同线程之间在内存方面的主要区别是他们拥有不同的地址空间，即与地址翻译相关的页表（Page Table）及其缓存 TLB 不同。因此在上下文切换过程中，和内存相关的内容主要就涉及到页表指针的切换和 TLB 的刷新。

Linux 把整个虚拟地址空间分成两部分，一部分是用户空间，另一部分是内核空间。对于用户线程来说，它只能访问用户空间的内存，当用户线程陷入内核态后，它可以访问用户空间，也可以访问内核空间；对于内核线程来说，它只会访问内核空间的内存。每个用户进程之间是内存隔离的，因此他们拥有自己独有的用户空间的映射关系；而内核空间的是整个系统共有的，因此所有进程共享同样的内核空间的映射关系。

我们可以发现，在 `task_struct` 类中，有两个 `mm_struct*` 类型的成员，名字分别是 `mm` 和 `active_mm`（见`include/linux/sched.h:860`），在一封 [二十多年前的电子邮件中](https://www.kernel.org/doc/html/latest/vm/active_mm.html)，Linus Tolvalds 向开发者解释了这两个指针的区别。我们把这封邮件的内容加以总结和提炼，得到 `mm` 和 `active_mm` 用法如下：

1. `mm` 成员是用户进程（线程）所正常使用的 `mm_struct`；
2. 内核进程（线程）由于无专有的内存空间，而与所有其他进程共享同样的内核空间，为了方便与优化性能，内核线程借用了该 CPU 中上一个运行的用户线程所使用的 `mm_struct`；
3. 内核线程的 `mm` 成员是空指针 `NULL`；
4. 内核线程将其借用的 `mm_struct` 地址存储在 `active_mm` 中，用户线程的 `active_mm == mm`。

### 切换逻辑分析

接下来我们看这一段 `if-else` 语句，在语句前的注释中，已经对切换前和切换后分别是内核线程和用户线程这排列组合的四种情况进行了分类讨论：

```c
// kernel/sched/core.c:4956
/*
* kernel -> kernel   lazy + transfer active
*   user -> kernel   lazy + mmgrab() active
*
* kernel ->   user   switch + mmdrop() active
*   user ->   user   switch
*/
```

在代码中首先处理的是「切换到 Kernel 线程」部分，即`if (!next->mm)`（如上文所说，内核线程的 `mm` 是空指针）。

按照上面注释，凡是切换到内核线程的首先要做一个「lazy」，即 `enter_lazy_tlb()` 函数的调用。
这个函数在 x86 等架构中有实现，RISC-V 中未实现该函数，其默认实现为空。在 x86 中，「Lazy TLB」主要用于减少切换上下文时不必要的 TLB 清空，以免切换后因地址翻译变慢造成性能下降。 RISC-V 借鉴 ARM 设计了 ASID 来实现类似的优化，下文中会详细介绍。

下一行 `next->active_mm = prev->active_mm;` 把上一个线程的 `active_mm` 「借」到了下一个内核线程中。

之后对上一个线程的类别加以区分：如果上一个线程是用户线程(`prev->mm != NULL`)，则需要增加这个被借用的 `mm_struct` 的引用计数，这个引用计数记录了当前有多少个内核线程正在借用该 `mm_struct`，如果该 `mm_struct` 对应的用户线程已经死亡，则 Linux 需要等到其引用计数为 $0$，即不再有内核线程借用它，才能将其销毁；如果上一个线程是内核线程，则把上一个线程的 `active_mm` 清空，结束其对于该 `mm_struct` 的借用（这只是把借用它的内核线程从一个转换到了另一个，引用计数无需增加）。

接下来我们看「切换到 User 线程」的情况，即 `else` 语句中的内容。

首先 `membarrier_switch_mm(rq, prev->active_mm, next->mm);` 使用了一个内存屏障，来保证上一个线程访问其内存空间与下一个线程访问其内存空间之间的先后顺序，避免在访存进行过程中发生 `mm_struct` 的切换导致的访存错误。（顺便补充一句，前面切换到内核线程因为没有切换 `mm_struct`，而不需要这样的内存屏障。）

接着就到了重头戏 `switch_mm_irqs_off(prev->active_mm, next->mm, next);`，即真正切换 `mm_struct`。RISC-V 中没有定义 `switch_mm_irqs_off()` 函数，由通用宏定义转为 `switch_mm()` 函数。

最后如果切换之前的线程是内核线程，则需要设置 `rq->prev_mm` 用于后续清除其引用计数，并且解除上一个线程对它的借用。

### RISC-V 的 `switch_mm()` 实现

```c
// include/linux/mmu_context.h:8
/* Architectures that care about IRQ state in switch_mm can override this. */
#ifndef switch_mm_irqs_off
# define switch_mm_irqs_off switch_mm
#endif
```

RISC-V 的 `switch_mm()` 函数本身也很简单，只有短短 9 行：

```c
// arch/riscv/mm/context.c:305
void switch_mm(struct mm_struct *prev, struct mm_struct *next,
	struct task_struct *task)
{
	unsigned int cpu;
	if (unlikely(prev == next))
		return;
	cpu = smp_processor_id();
	cpumask_clear_cpu(cpu, mm_cpumask(prev));
	cpumask_set_cpu(cpu, mm_cpumask(next));
	set_mm(next, cpu);
	flush_icache_deferred(next, cpu);
}
```

首先是处理了 `prev == next` 的情况（同一个进程的不同线程之间切换，或者借用了某用户线程地址空间的内核线程切换到该用户线程），这种情况直接返回。

接着清除了该 CPU 的 `cpumask` 中之前的 `mm_struct` 的标志，并设置了新的 `mm_struct` 标志。

然后就到了 `set_mm()` 这个实际设置 `mm_struct` 的环节。

`set_mm()` 根据 `use_asid_allocator` 标志来区分，调用包含 `ASID` 的版本或者不包含 `ASID` 的版本：

```c
// arch/riscv/mm/context.c:208
static inline void set_mm(struct mm_struct *mm, unsigned int cpu)
{
	if (static_branch_unlikely(&use_asid_allocator))
		set_mm_asid(mm, cpu);
	else
		set_mm_noasid(mm);
}
```

`use_asid_allocator` 是系统初始化阶段时在 `asids_init()` 函数中设置的，下一小节再详细介绍 RISC-V 的 ASID 机制，这里先看一下不包含 ASID 情况下的 `set_mm()`：

```c
// arch/riscv/mm/context.c:201
static void set_mm_noasid(struct mm_struct *mm)
{
	/* Switch the page table and blindly nuke entire local TLB */
	csr_write(CSR_SATP, virt_to_pfn(mm->pgd) | satp_mode);
	local_flush_tlb_all();
}
```

`set_mm_noasid()` 还是很简单的，在 `satp` CSR 中设置一下页表指针（来自于 `mm->pgd`）和页表模式（32 位情况下为 `sv32`，64 位时根据 `CONFIG_XIP_KERNEL` 的配置选择 `sv39` 或 `sv48`），然后直接把所有的 TLB 项全部清空即可。

### RISC-V 的 ASID 机制

在不带 ASID 的 `set_mm_noasid()` 中，我们在设置页表后，简单地把所有的 TLB 项全部清空了，这就会导致切换到新的线程后，在一开始取址、访存时，会出现大量的 TLB Miss 的情况，需要反复到内存中查找页表，导致性能降低。ASID 机制是为了缓解这个问题而诞生的。

ASID 的全称是 Address Space Identifier，总而言之，每个用户进程（即每个 `mm_struct`）拥有一个唯一的 ASID，用于在 TLB 中与其他进程的表项区隔开来。这样在 TLB 中可以同时存在多个进程的表项，在地址翻译时增加表项的 ASID 与当前运行进程的 ASID 的匹配。经过这种优化后，如果两个用户进程之间频繁切换时，不用每次都清空 TLB，导致后续大量 TLB Miss，提高了取址和访存效率。

当前运行进程的 ASID 和页表指针一样，都写在 `satp` CSR 中，下图分别是 RV32 和 RV64 下该 CSR 的值设计：

![RV32 CSR](/wp-content/uploads/2022/03/riscv-linux/images/riscv_context-switch/satp-sv32.png)

![RV64 CSR](/wp-content/uploads/2022/03/riscv-linux/images/riscv_context-switch/satp-sv39.png)

从上面两图中可以看出，RV32 和 RV64 下，ASID 最长分别可以到 9 位和 16 位。但这只是理论最大值，实际硬件实现中不一定有这么多位（因为 ASID 的位数越多，在 TLB 中其比较逻辑、存储空间占用就会越大，这里也是性能与面积/功耗的取舍）。

软件上判断 ASID 实现位数的方式是，先往 `satp` CSR 中理论上最多的 ASID 位上都写 $1$，然后再把这些位读出来，有多少位被写上了 $1$，就是硬件支持多少位。在 ASID 的初始化函数 `asids_init()` 中，Linux 也就是通过这种方式判断 ASID 的位数，从而决定是否开启 ASID。

```c
// arch/riscv/mm/context.c:220
	/* Figure-out number of ASID bits in HW */
	old = csr_read(CSR_SATP);
	asid_bits = old | (SATP_ASID_MASK << SATP_ASID_SHIFT);
	csr_write(CSR_SATP, asid_bits);
	asid_bits = (csr_read(CSR_SATP) >> SATP_ASID_SHIFT)  & SATP_ASID_MASK;
	asid_bits = fls_long(asid_bits);
	csr_write(CSR_SATP, old);
```

在这个初始化函数中，如果 ASID 的位数 `asid_bits` 大于当前 CPU 核数的两倍，就会开启 ASID，即设置 `use_asid_allocator` 为 `TRUE`，否则不会开启 ASID。

硬件上 ASID 的数量是有限的，为了在有限的硬件 ASID 上实现出「无限」的虚拟 ASID，RISC-V 借鉴 ARM 实现了如下的 Version 机制：
RISC-V 在 `mm_struct` 的体系结构特异字段 `context` 中增加了一个成员 `atomic_long_t id;`，其低位用于保存 ASID，而高位用于保存 ASID 的 version。
这个 version 可以理解为 ASID 的有效版本，在当前版本的 ASID 空间耗尽时，版本号会自增 $1$，同时属于旧版本的所有 ASID 均将失效。

现在我们来开始分析开启 ASID 后，`set_mm_asid()` 函数中上下文切换时 ASID 的更新逻辑（见 `arch/riscv/mm/context.c:145`）。

首先读出下一个执行线程的 `mm_struct` 的 `context.id` 为 `cntx`，以及当前 CPU 正在执行线程的 `context.id` 为 `old_active_cntx`，如果 `old_active_cntx` 有效且 `cntx` 属于当前版本，那么直接 goto 到 `switch_mm_fast`，更新当前 CPU 的 `context.id` 为 `cntx` 以及设置 `satp` CSR 的 ASID 和页表指针即可：

```c
// arch/riscv/mm/context.c:151
cntx = atomic_long_read(&mm->context.id);
old_active_cntx = atomic_long_read(&per_cpu(active_context, cpu));
if (old_active_cntx &&
	((cntx & ~asid_mask) == atomic_long_read(&current_version)) &&
	atomic_long_cmpxchg_relaxed(&per_cpu(active_context, cpu),
				old_active_cntx, cntx))
	goto switch_mm_fast;
```

如果 `cntx` 不属于当前版本，则需要调用 `__new_context()` 生成一个新的 context。生成新的 context 的逻辑大致是，先尝试 ASID 不改，只更新 version，如果新的 context 有效，则无需清空 TLB；但如果新的 context 无效（该 ASID 已经被别的进程在新版本中使用），则需要在当前版本中从小到大找一个有效的 ASID 赋给该进程，如果当前版本 ASID 已经用光，则大版本 version 向前前进一次，同时将所有目前的 context 全部无效掉（具体内容读者可自行阅读这部分代码）。生成新的 context 后，存储在下一个进程的 `mm_struct` 当中：

```c
// arch/riscv/mm/context.c:178
/* Check that our ASID belongs to the current_version. */
cntx = atomic_long_read(&mm->context.id);
if ((cntx & ~asid_mask) != atomic_long_read(&current_version)) {
	cntx = __new_context(mm);
	atomic_long_set(&mm->context.id, cntx);
}
```

后面就是更新一下当前 CPU 核的 `active_context`，更新一下 `satp` CSR，按需刷新一下 TLB 即可。

```c
// arch/riscv/mm/context.c:185
if (cpumask_test_and_clear_cpu(cpu, &context_tlb_flush_pending))
	need_flush_tlb = true;

atomic_long_set(&per_cpu(active_context, cpu), cntx);

raw_spin_unlock_irqrestore(&context_lock, flags);

switch_mm_fast:
csr_write(CSR_SATP, virt_to_pfn(mm->pgd) |
		((cntx & asid_mask) << SATP_ASID_SHIFT) |
		satp_mode);

if (need_flush_tlb)
	local_flush_tlb_all();
```

到目前为止，页表指针和 TLB 项需要更新的都已经更新，`mm_struct` 的切换已经完成。

注：有关 RISC-V ASID 的设计读者也可以参考这封作者提交代码时的 [邮件](https://patchwork.kernel.org/project/linux-riscv/patch/20190327100201.32220-1-anup.patel@wdc.com/)。

另外，[这篇文章](https://zhuanlan.zhihu.com/p/118244515) 也生动地介绍了 ASID 管理，但其中对于 ASID 不足时处理方面的描述比较简略，未能反映出全部的情况，请读者阅读时注意鉴别。

## 切换寄存器内容

`context_switch()` 函数的下一个重要内容就是 `switch_to()`，即切换寄存器状态和栈（在 RISC-V 中栈指针也是若干通用寄存器中的一个，所以其实也属于切换寄存器内容）。

RISC-V 的 `switch_to()` 函数是一个带参宏，先是判断了这个核有没有 FPU，如果有还需要切换浮点寄存器，这部分我们就不深追究了；然后就是调用汇编写的 `__switch_to()` 函数：

```c
// arch/riscv/include/asm/switch_to.h:74
#define switch_to(prev, next, last)			\
do {							\
	struct task_struct *__prev = (prev);		\
	struct task_struct *__next = (next);		\
	if (has_fpu())					\
		__switch_to_aux(__prev, __next);	\
	((last) = __switch_to(__prev, __next));		\
} while (0)
```

`__switch_to()` 函数的位置在 `arch/riscv/kernel/entry.S:512`，基本内容就是把当前的各个寄存器保存在 `prev->thread` 中，然后从 `next->thread` 中恢复出各个寄存器的内容，受篇幅所限这里就不贴出代码了，感兴趣的读者可自行浏览。


## 本文小结

本文介绍了 RISC-V 架构下 Linux 上下文切换的流程，并着重介绍了 `mm_struct` 的切换以及寄存器内容的切换 `switch_to()`，同时带大家了解了 RISC-V 中 ASID 的设计与实现。

## 参考文档

1. [进程切换分析（2）：TLB处理](http://www.wowotech.net/process_management/context-switch-tlb.html)
2. [Commit Message](https://patchwork.kernel.org/project/linux-riscv/patch/20190327100201.32220-1-anup.patel@wdc.com/)
3. [Active MM](https://docs.kernel.org/vm/active_mm.html)
