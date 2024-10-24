---
layout: post
author: 'Jinyu Tang'
title: 'RISC-V 缺页异常处理程序分析（1）：do_page_fault() 和 handle_mm_fault()'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-page-fault-part1/
description: 'RISC-V 缺页异常处理程序分析（1）：do_page_fault() 和 handle_mm_fault()'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - 缺页异常处理
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [pangu]
> Author:  tjytimi  <tjytimi@163.com>
> Date:    2022/07/25
> Revisor: lzufalcon <falcon@tinylab.org>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor: PLCT Lab, ISCAS


## 前言

本系列将分析缺页异常处理，其中，与处理器架构相关的部分采用 RICS-V 架构下对应的代码。

本文为缺页异常的第一篇，此篇分析 `do_page_fault()` 函数在 RISC-V 架构下的实现以及用户态合法地址缺页异常处理中 `handle_mm_fault()` 函数流程。

内核版本为 Linux 5.17。

## 缺页异常函数流程分析（do_page_fault()）

缺页异常函数由处理器架构相关函数 `do_page_fault` 实现。实际上不同架构处理逻辑类似。内核为每个处理器架构分别实现此函数是因为内核需要从处理器的寄存器中获取缺页异常产生的地址及原因等信息，不同架构的处理器对应的寄存器和机制不尽相同。

尽管不同处理器实现方式不同，但任何架构处理器均需有寄存器和相关机制为内核提供这些信息，由此可见操作系统和处理器间互相依存的关系。

对 `do_page_fault` 函数的讲解，很多教材采取了画流程图的方式，不过我在看书时感觉这个函数因为分支较多，图看起来也会让人混乱。开发代码阶段画好图有帮助，但现在有代码，就直接在代码上放上注释，读者根据代码注释看下来，并参考代码下的总结文字就能理清此函数的流程。

```c
asmlinkage void do_page_fault(struct pt_regs *regs)
{

	unsigned long addr, cause;

	...
	/*
	 * 异常处理开始前，会将寄存器值压入内核栈，regs 即为栈内存有寄存器值的结构体
	 * cause 寄存器存有页异常原因有关信息，badaddr 寄存器存有异常对应的虚拟地址
	 */
	cause = regs->cause;
	addr = regs->badaddr;
	/* 获取获取当前进程的内存上下文 mm */
	tsk = current;
	mm = tsk->mm;

	/*
	 * Fault-in kernel-space virtual memory on-demand.
	 * The 'reference' page table is init_mm.pgd.
	 *
	 * NOTE! We MUST NOT take any locks for this case. We may
	 * be in an interrupt or a critical region, and should
	 * only copy the information from the master page table,
	 * nothing more.
	 */
        /* 在 vmalloc 区域的错误，由 vmalloc_fault() 处理 */
	if (unlikely((addr >= VMALLOC_START) && (addr < VMALLOC_END))) {
		vmalloc_fault(regs, code, addr);
		return;
	}

	...

	/*
	 * If we're in an interrupt, have no user context, or are running
	 * in an atomic region, then we must not take the fault.
	 */
        /* 内核线程、中断上下文、原子上下文或缺页处理句柄关闭，交由 no_context() 处理 */
	if (unlikely(faulthandler_disabled() || !mm)) {
		tsk->thread.bad_cause = cause;
		no_context(regs, addr);
		return;
	}

        /*
         * 同时满足缺页发生在内核态，地址在进程地址范围内，且缺页不是内核访问用户态页表里存在的地址（status 中 SUM 位未置位，在处理器处于
         * 内核态时访问用户空间地址会由处理器对该位置位），那就是一个 bug
	 */
	if (!user_mode(regs) && addr < TASK_SIZE &&
			unlikely(!(regs->status & SR_SUM)))
		die_kernel_fault("access to user memory without uaccess routines",
				addr, regs);

retry:
	mmap_read_lock(mm);
	/* 找到第一个末尾大于等于 addr 的虚拟地址空间 */
	vma = find_vma(mm, addr);
	/* 没有找到，说明该地址一定没有被包含在任何地址空间内（注：栈向下生长，也不可能由于栈没有分配），为用户态编程错误，由 bad_area() 处理 */
	if (unlikely(!vma)) {
		tsk->thread.bad_cause = cause;
		bad_area(regs, mm, code, addr);
		return;
	}
	/* 地址被该虚拟地址空间覆盖，跳到 good_area 处理，此标号表明可以抢救一下 */
	if (likely(vma->vm_start <= addr))
		goto good_area;
	/* 如果不是向下增长的虚拟地址空间（栈对应的），走到这说明错误地址不在进程地址空间，也去 bad_area() 里处理 */
	if (unlikely(!(vma->vm_flags & VM_GROWSDOWN))) {
		tsk->thread.bad_cause = cause;
		bad_area(regs, mm, code, addr);
		return;
	}
	/*
         * 如果是栈区，有可能是压栈操作栈不够导致（给栈分配虚拟地址空间机制是用完了继续扩），进一步判断后扩大一下栈对应的虚拟地址空间，
         * 如果判断地址离得的太远等则不是压栈操作，也去 bad_area() 处理
         */
	if (unlikely(expand_stack(vma, addr))) {
		tsk->thread.bad_cause = cause;
		bad_area(regs, mm, code, addr);
		return;
	}

	/*
	 * Ok, we have a good vm_area for this memory access, so
	 * we can handle it.
	 */
	/* 到这里说明缺页的地址是属于该进程 */
good_area:
	code = SEGV_ACCERR;
	/* access_error() 为真说明权限和访问操作不对应，访问不合法，也到 bad_area() 处理 */
	if (unlikely(access_error(cause, vma))) {
		tsk->thread.bad_cause = cause;
		bad_area(regs, mm, code, addr);
		return;
	}

	/*
	 * If for any reason at all we could not handle the fault,
	 * make sure we exit gracefully rather than endlessly redo
	 * the fault.
	 */
        /* 走到这里说明页异常发生在处理器处于用户态时且地址处于合法地址空间，将交由 handle_mm_fault() 进一步处理 */
	fault = handle_mm_fault(vma, addr, flags, regs);

	...
}

```

上面的代码用文字描述如下：

- 函数首先获取 `cause` 寄存器存放的缺页异常原因有关信息，并从 `badaddr` 寄存器得到产生异常的虚拟地址，接着获取当进程的内存上下文 `mm`。

- 在 `vmalloc` 区域的错误，由 `vmalloc_fault()` 处理。

- 内核线程（`mm` 为空），中断上下文、原子上下文或缺页处理句柄关闭（`faulthandler_disabled()` 函数为真），交由 `no_context()` 处理。

- 缺页发生在内核态，缺页地址在进程地址范围内（`addr < TASK_SIZE`），且缺页不是发生在内核态访问用户态页表里存在的地址时（`status` 中 `SUM` 位未置位，该位在处理器内核态访问用户空间地址时由处理器置位），那就是一个 bug，直接 `Oops` 并且杀死此进程。

- 找到第一个末尾大于等于 `addr` 的虚拟地址空间 `vma`，若没有找到，说明该地址一定没有被包含在任何地址空间内（注：由于栈是向下生长，所以此处也不可能由于栈没有分配导致的异常），用户态编程错误，由 `bad_area()` 处理。

- 找到且确定地址被该虚拟地址空间覆盖，跳到 `good_area` 标号处处理。

- 没有被虚拟地址覆盖，继续判断是不是向下增长的虚拟地址空间（栈为情况），若不是，则为错误，也去 `bad_area()` 里处理。

- 若是栈区，有可能是压栈操作栈不够导致（给栈分配虚拟地址空间是用完了才继续扩），进一步判断并扩大一下栈对应的虚拟地址空间，如果判断地址离得的太远等则不是压栈操作导致，也去 `bad_area()` 处理。

- 执行到了 `good_area` 标号处，继续调用 `access_error()` 判断权限，`access_error()` 为真说明权限和访问操作不对应，访问非法，也到 `bad_area()` 处理。

- 运行至此，终于可以确定为合法的缺页异常了，调用 `handle_mm_fault()` 处理，该异常是缺页异常最常见的原因。

## 缺页异常发生在处理器处于用户态时且地址处于合法地址空间的进一步处理

下面介绍 `handle_mm_fault()` 相关流程。`do_page_fault()` 中 `bad_area()`，`vmalloc_fault()` 等代码分支流程，将在后续连载中介绍。

### __handle_mm_fault() 函数

`handle_mm_fault()` 函数负责处理用户态缺页且地址合法的情形。该函数主要功能由 `__handle_mm_fault()` 实现，代码如下，其中精简了与巨页有关的代码，同样采用注释和文字的形式分析。

```c
// mm/memory.c:4619
static vm_fault_t __handle_mm_fault(struct vm_area_struct *vma,
		unsigned long address, unsigned int flags)
{
	struct vm_fault vmf = {
		.vma = vma,
		.address = address & PAGE_MASK,
		.flags = flags,
		.pgoff = linear_page_index(vma, address),
		.gfp_mask = __get_fault_gfp_mask(vma),
	};
	/* 获取虚拟地址空间对应的内存描述符 */
	struct mm_struct *mm = vma->vm_mm;
	pgd_t *pgd;
	p4d_t *p4d;
	vm_fault_t ret;
        /* 通过内存描述符和虚拟地址，得到该虚拟地址在页全局目录（pgd）中对应的目录项指针 */
	pgd = pgd_offset(mm, address);
        /* 通过内存描述符、pgd 项和虚拟地址，得到 p4d 项指针 */
	p4d = p4d_alloc(mm, pgd, address);
	if (!p4d)
		return VM_FAULT_OOM;

        ...

        /* 通过内存描述符、p4d 项和虚拟地址，得到 pud 项指针 */
	vmf.pud = pud_alloc(mm, p4d, address);
	if (!vmf.pud)
		return VM_FAULT_OOM;

        ...

        /* 通过内存描述符、pud 项和虚拟地址，得到 pmd 项指针 */
	vmf.pmd = pmd_alloc(mm, vmf.pud, address);
	if (!vmf.pmd)
		return VM_FAULT_OOM;

        ...

        /* 将 vmf 的地址传给 handle_pte_fault() 进行页表项的进一步处理 */
	return handle_pte_fault(&vmf);
}
```

该函数首先初始化结构体变量 `vmf`，用于整个流程的参数传递，让参数不至于那么多。随后通过以下流程一路下来得到缺页地址对应的页中间目录项的指针（`vmf.pmd`），该指针对应地址的值将会是页表的物理地址：

- 获取虚拟地址空间对应的内存描述符 `mm`。

- `pgd_offset()` 通过内存描述符和虚拟地址，得到该虚拟地址在页全局目录（`pgd`）中对应的目录项指针。

- `p4d_alloc()` 通过内存描述符、`pgd` 项和虚拟地址，得到 `p4d` 项指针，具体获取方法下文叙述。

- `pud_alloc()` 通过内存描述符、`p4d` 项和虚拟地址，得到 `pud` 项指针，具体获取方法下文叙述。

- `pmd_alloc()` 通过内存描述符、`pud` 项和虚拟地址，得到 `pmd` 项指针，具体获取方法下文叙述。

- 将存有上述结果的 `vmf` 的地址传给 `handle_pte_fault()` 进行页表项的处理。

需要说明的是，不同处理器架构，以及同处理器架构选择不同的内存方案，会有不同的分页层次。如 RISC-V 中 Rv39 分页方案就没有 `p4d` 和 `pud`，内核会将这两个目录设置成只有一项，该项直接指向下一级的目录，做到一套代码适应不同的分页层次。

### 获取各级目录项的处理方式

上文中获取各级目录项的指针代码实现如下：

```c
// include/linux/mm.h :2233
static inline p4d_t *p4d_alloc(struct mm_struct *mm, pgd_t *pgd,
		unsigned long address)
{
	return (unlikely(pgd_none(*pgd)) && __p4d_alloc(mm, pgd, address)) ?
		NULL : p4d_offset(pgd, address);
}

static inline pud_t *pud_alloc(struct mm_struct *mm, p4d_t *p4d,
		unsigned long address)
{
	return (unlikely(p4d_none(*p4d)) && __pud_alloc(mm, p4d, address)) ?
		NULL : pud_offset(p4d, address);
}
// mm/memory.c:4675
static inline pmd_t *pmd_alloc(struct mm_struct *mm, pud_t *pud, unsigned long address)
{
	return (unlikely(pud_none(*pud)) && __pmd_alloc(mm, pud, address))?
		NULL: pmd_offset(pud, address);
}
```

比较上述代码可见不同层获取目录项的实现完全类似，故仅对 `pmd_alloc()` 进行说明，读者可以自行看其它源码举一反三。

`pmd_alloc()` 函数通过内存描述符 `mm`、`pud` 项和虚拟地址，得到 `pmd` 项指针：

- 检查 `pud` 项的值是否为 `0`，不为 `0` 即 `pud_none` 宏的值为 `0`，那么 `?` 之前的结果即确定为假，编译器编出的程序会直接跳过下一步，执行第三步 `pmd_offset()`。

- `pud` 项为 `0`，说明还没有对应的 `pmd` 目录，则执行 `__pmd_alloc()` 函数（下面会详细说明此函数），为 `address` 申请一块物理地址，作为 `pmd` 目录。

- 调用 `pmd_offset()` 函数，该函数比较简单，直接根据虚拟地址 `address` 对应在在目录中的偏移，从 `pmd` 目录中得到该偏移对应的指针。

`__pmd_alloc()` 函数代码如下：

```c
 // mm/memory.c:4874
int __pmd_alloc(struct mm_struct *mm, pud_t *pud, unsigned long address)
{
	spinlock_t *ptl;
	pmd_t *new = pmd_alloc_one(mm, address);
	if (!new)
		return -ENOMEM;

	ptl = pud_lock(mm, pud);
	if (!pud_present(*pud)) {
		mm_inc_nr_pmds(mm);
		smp_wmb(); /* See comment in pmd_install() */
		pud_populate(mm, pud, new);
	} else {	/* Another has populated it */
		pmd_free(mm, new);
	}
	spin_unlock(ptl);
	return 0;
}
```

该函数首先调用 `pmd_alloc_one()` 申请一块物理地址作为 `pmd` 目录，再调用 `pud_populate()` 将刚申请的 `pmd` 目录的物理地址写到 `pud` 项中。
此函数中 `!pud_present(*pud)` 的判断，后续会专门一节写内核内存管理中类似的处理，目前可不关注。

`pmd_alloc_one()` 函数代码如下，其通过 `alloc_pages()` 接口获取一页，并最终返回该页对应的内核态虚拟地址，该虚拟地址会传给 `pud_populate()` 函数：

```c
// include/asm-generic: 119
static inline pmd_t *pmd_alloc_one(struct mm_struct *mm, unsigned long addr)
{
	struct page *page;
	gfp_t gfp = GFP_PGTABLE_USER;

	if (mm == &init_mm)
		gfp = GFP_PGTABLE_KERNEL;
	page = alloc_pages(gfp, 0);
	if (!page)
		return NULL;
	if (!pgtable_pmd_page_ctor(page)) {
		__free_pages(page, 0);
		return NULL;
	}
	return (pmd_t *)page_address(page);
}
```

`pud_populate()` 函数在 RISC-V 架构下定义如下，直接获取刚刚申请的 `pmd` 虚拟地址对应的物理地址，然后调用 `__pud` 宏，再将物理地址填入 `pud` 项中。

```c
// arch/riscv/include/asm/pgalloc.h:35
static inline void pud_populate(struct mm_struct *mm, pud_t *pud, pmd_t *pmd)
{
	unsigned long pfn = virt_to_pfn(pmd);

	set_pud(pud, __pud((pfn << _PAGE_PFN_SHIFT) | _PAGE_TABLE));
}
```

`__handle_mm_fault()` 函数的最后，会调用 `handle_pte_fault()` 进行 Legal 地址缺页异常的页表项处理流程，根据页表项的情况会有不同的分支，这包括经常听到的写时复制机制，请求调页机制等。在下一节将进行详细分析。

至此，完成 `__handle_mm_fault()` 函数流程的分析。

## 总结

本文详细分析了 `do_page_fault()` 函数在 RISC-V 架构下的实现以及用户态合法地址缺页异常处理中 `handle_mm_fault()` 函数的实现细节。涉及分支较多，可对照源码仔细阅读。

## 参考资料

- [1] DANILE.PBOVET、MARCO CESATI 著，陈莉君、张琼声、张宏伟 译。深入理解 Linux 内核 [M].北京：中国电力出版社，2007
- [2] 陈华才。用"芯"探核 基于龙芯的 Linux 内核探索解析 [M].北京：中国工信出版社/人民邮电出版社，2020.
