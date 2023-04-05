---
layout: post
author: 'Jinyu Tang'
title: 'RISC-V 缺页异常处理程序分析（2）：handle_pte_fault() 和 do_anonymous_page()'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-page-fault-part2/
description: 'RISC-V 缺页异常处理程序分析（2）：handle_pte_fault() 和 do_anonymous_page()'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [comments codeblock pangu autocorrect]
> Author:    tjytimi  <tjytimi@163.com>
> Date:      2022/11/03
> Revisor:   lzufalcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

本系列将分析缺页异常处理，其中，与处理器架构相关的部分采用 RICS-V 架构下对应的代码。

本文为缺页异常的第二篇，此篇分析 `handle_pte_fault()` 函数以及私有匿名映射缺页异常 `do_anonymous_page()` 函数的流程。

内核版本为 Linux 5.17。

## handle_pte_fault() 函数分析

上篇说到，`_handle_mm_fault()` 函数最后会调用 `handle_pte_fault()` 函数具体处理缺页异常。`handle_pte_fault()` 函数将处理缺页异常地址对应的页表项。主要代码及注释如下，读者根据代码并参考代码下的文字梳理就能理解该函数的逻辑：

```c
// mm/memory.c: 4515
static vm_fault_t handle_pte_fault(struct vm_fault *vmf)
{
	pte_t entry;

	/* pmd 项为 0，此涉及巨页机制相关，暂不作讨论 */
	if (unlikely(pmd_none(*vmf->pmd))) {

		vmf->pte = NULL;
	} else {

		/* 找到虚拟地址对应页表项指针，并将该项的值赋值给 vmf->orig_pte */
		vmf->pte = pte_offset_map(vmf->pmd, vmf->address);
		vmf->orig_pte = *vmf->pte;

		/*
		 * some architectures can have larger ptes than wordsize,
		 * e.g.ppc44x-defconfig has CONFIG_PTE_64BIT=y and
		 * CONFIG_32BIT=y, so READ_ONCE cannot guarantee atomic
		 * accesses.  The code below just needs a consistent view
		 * for the ifs and we later double check anyway with the
		 * ptl lock held. So here a barrier will do.
		 */
		/* 内存屏障，保证前面的赋值完成后再进行下面的页表项是否为 0 的判断，防止编译器优化 */
		barrier();
		/*
		 * 如果页表项为 0，解除其指针的临时映射，将页表项指针指向空
		 * 为什么要解除呢？如果不解除后面继续用可以吗？
		 * 实际上这是对 32 位有高端内存的系统而设计的，临时映射用于访存
		 * 的地址范围有限，属于珍贵资源，后续会有一些阻塞流程，
		 * 一直占着不合理，此处解除后面用了再申请。
		 * 对 64 位系统，不需要临时映射的方式，pte_unmap() 什么也不做。
		 */
		if (pte_none(vmf->orig_pte)) {
			pte_unmap(vmf->pte);
			vmf->pte = NULL;
		}
	}

	/*
	 * 判断页表项是否为空，若为空，说明目前还没有为该项分配页表
	 * 这当然不是 fork() 后复用父进程的进程地址空间，因为在 fork() 中
	 * 会复制父进程的页表。也不可能是交换，交换意味着该地址已经存在页表了。
	 */
	if (!vmf->pte) {
		/* 属于匿名映射，调用 do_anonymous_page() 处理 */
		if (vma_is_anonymous(vmf->vma))
			return do_anonymous_page(vmf);
		else
			/* 文件映射的异常，调用 do_fault() 处理 */
			return do_fault(vmf);
	}
	/* 页表项 P 位为 0，说明页被交换出去了，调用 do_swap_page() 换回来 */
	if (!pte_present(vmf->orig_pte))
		return do_swap_page(vmf);
	/* 页所在节点不正确，暂不做分析 */
	if (pte_protnone(vmf->orig_pte) && vma_is_accessible(vmf->vma))
		return do_numa_page(vmf);

	vmf->ptl = pte_lockptr(vmf->vma->vm_mm, vmf->pmd);
	spin_lock(vmf->ptl);
	entry = vmf->orig_pte;
	/* 看看有没有被其他线程修改，*vmf->pte 和 entry 不同说明修改了，就不用再继续处理了，mips 架构会刷新 tlb */
	if (unlikely(!pte_same(*vmf->pte, entry))) {
		update_mmu_tlb(vmf->vma, vmf->address, vmf->pte);
		goto unlock;
	}
	if (vmf->flags & FAULT_FLAG_WRITE) {
		/* 写内存的异常，页表项又无 W 权限，说明是写保护的情形，调用 do_wp_page() 处理 */
		if (!pte_write(entry))
			return do_wp_page(vmf);

		/*
		 * 写内存的异常，页表项又有 W 权限，说明是软件管理 W 位的处理器架构，这种 CPU 会抛出异常，让软件处理
		 */
		entry = pte_mkdirty(entry);
	}
	/* 将 Access 位置位，原因和上面的 Dirty 位一样 */
	entry = pte_mkyoung(entry);
	/*
	 * 将上面修改好的 entry 写入页表项，并刷新 MMU cache 相关内容，工作做到位，这样同样的位置就不会再出现缺页异常了。
	 * ptep_set_access_flags() 函数规定专门用于更新页表项的 Access，Dirty 或者 Write 权限位。
	 */
	if (ptep_set_access_flags(vmf->vma, vmf->address, vmf->pte, entry,
				vmf->flags & FAULT_FLAG_WRITE)) {
		update_mmu_cache(vmf->vma, vmf->address, vmf->pte);
	} else {
		/* Skip spurious TLB flush for retried page fault */
		if (vmf->flags & FAULT_FLAG_TRIED)
			goto unlock;
		/*
		 * This is needed only for protection faults but the arch code
		 * is not yet telling us if this is a protection fault or not.
		 * This still avoids useless tlb flushes for .text page faults
		 * with threads.
		 */
		if (vmf->flags & FAULT_FLAG_WRITE)
			flush_tlb_fix_spurious_fault(vmf->vma, vmf->address);
	}
unlock:
	pte_unmap_unlock(vmf->pte, vmf->ptl);
	return 0;
}
```

下面总结一下 `handle_pte_fault()` 函数的流程：

- 首先找到缺页虚拟地址对应的页表项指针，并将该项的值赋值给 `vmf->orig_pte`，且赋值后增加了内存屏障指令，防止编译器优化。为什么要用 `vmf->orig_pte` 先存着，而不是在执行的过程中从指针里取值呢？因为别的线程可能也进到这个地址缺页异常并率先把页表项改了。所以必须预先存着，并在后面必要的时候检查页表项有没有变化，防止重复处理同一地址的异常。

- 如果页表项为 0，说明其是刚分配的项，则用 `pte_unmap()` 解除其指针的临时映射，将页表项指针赋 NULL。为什么要解除呢？如果不解除后面继续用可以吗？实际上这是为 32 位有高端内存的系统设计的，用于访存临时映射的地址范围有限，属于珍贵资源，后续会有一些阻塞流程，一直占着不合理，此处解除后面用了再申请。对 64 位系统，不需要临时映射的方式，所以 `pte_unmap()` 什么也不做。

- 判断页表项是否为空，若为空，说明目前还没有为该项分配页表。这当然不是 `fork()` 后复用父进程的进程地址空间，因为在 `fork()` 中会复制父进程的页表。也不可能是交换，交换意味着该地址已经存在页表了。只可能是以下两类：

  - 属于私有匿名映射，调用 `do_anonymous_page()` 处理。将在下文进行详细叙述。

  - 文件映射的异常，调用 `do_fault()` 处理。本函数将在本系统后续部分详细叙述。

- 页表项不为空，但 P 位为 0，说明被交换出去了，调用 `do_swap_page()` 换回来。本函数将在本系统后续部分详细叙述。

- 对页表项访问加锁后看看有没有被其他线程修改，`*vmf->pte` 和 `entry` 不同说明被其他线程修改了，就不用再继续处理了，MIPS 架构会刷新 tlb。我认为 RISC-V 架构也可以刷一下 tlb，只不过没有 MIPS 更有价值而已。

- 继续判断是否是写内存异常，若页表项无写权限，调用 `do_wp_page()` 处理。此函数不仅包含匿名页的写时复制，也包括共享文件映射回写相关的写保护机制处理。本函数将在本系统后续部分详细叙述。

- 写内存的异常，但页表项有写权限，这部分逻辑主要是处理处理器硬件不负责管理 A 位和 W 位的情况。某些架构的处理器硬件不管理 A 位和 W 位，第一次读或写的时候会进入缺页异常，交给软件处理，软件将 A 位和 W 位置位。RISC-V 架构的文档中表示管理或者不管理都可以。也就是说，如果是管理 A 位和 W 位的 CPU ，则不会出现写内存的异常但页表项有写权限的情形。

上文说到 `do_anonymous_page()` 用来具体处理私有匿名映射的缺页，下面具体分析：

```c
// mm/memory.c: 3726
static vm_fault_t do_anonymous_page(struct vm_fault *vmf)
{
	struct vm_area_struct *vma = vmf->vma;
	struct page *page;
	vm_fault_t ret = 0;
	pte_t entry;

	...
	/* 先申请页表，因为私有匿名页在建立的时候根本就没有为其分配页表 */
	if (pte_alloc(vma->vm_mm, vmf->pmd))
		return VM_FAULT_OOM;

	/* 如果不是写异常，直接用公用的 zero-page 页给进程 */
	/* Use the zero-page for reads */
	if (!(vmf->flags & FAULT_FLAG_WRITE) &&
			!mm_forbids_zeropage(vma->vm_mm)) {
		/* 将 zero-page 页的物理地址及一些权限位写入 entry，用于写入 pte */
		entry = pte_mkspecial(pfn_pte(my_zero_pfn(vmf->address),
						vma->vm_page_prot));
		/* 获取该虚拟地址对应的页表项指针 */
		vmf->pte = pte_offset_map_lock(vma->vm_mm, vmf->pmd,
				vmf->address, &vmf->ptl);
		/*
		 * 检查一下，如果目前 pte 的值已经不为空了，说明其他线程已经做好此工作，
		 * 对 mips 而言需要刷一下 tlb 再退出，其他架构，什么也不做就退出。
		 * 罕见的现象，因为应用程序不同线程处理同一地址不加锁是不常见的。
		 */
		if (!pte_none(*vmf->pte)) {
			update_mmu_tlb(vma, vmf->address, vmf->pte);
			goto unlock;
		}
		...
		/* 跳转到 setpte 标号处，将准备好的 entry 真正写入 pte */
		goto setpte;
	}
	/* 以下为分配私有页面的流程 */
	/* Allocate our own private page. */

	/* 分配 anon_vma，并和 vma 建立关联，这在反射机制时有用 */
	if (unlikely(anon_vma_prepare(vma)))
		goto oom;
	/* 分配一个物理页，且会将该页置零 */
	page = alloc_zeroed_user_highpage_movable(vma, vmf->address);
	if (!page)
		goto oom;

	if (mem_cgroup_charge(page_folio(page), vma->vm_mm, GFP_KERNEL))
		goto oom_free_page;
	cgroup_throttle_swaprate(page, GFP_KERNEL);

	/*
	 * The memory barrier inside __SetPageUptodate makes sure that
	 * preceding stores to the page contents become visible before
	 * the set_pte_at() write.
	 */
	/* 新申请的页面设置 update 标志 */
	__SetPageUptodate(page);

	/* 以下会根据物理页的物理地址，以及相应权限设置页表项，预先保存在 entry 中 */
	entry = mk_pte(page, vma->vm_page_prot);
	entry = pte_sw_mkyoung(entry);
	if (vma->vm_flags & VM_WRITE)
		entry = pte_mkwrite(pte_mkdirty(entry));

	/* 取得 pte 的指针，加锁，保证不会同时有 CPU 线程修改该 pte */
	vmf->pte = pte_offset_map_lock(vma->vm_mm, vmf->pmd, vmf->address,
			&vmf->ptl);
	/* 再判断一下，有没有之前被别的线程改过，改过就不处理了，直接刷新本 CPU 线程的 MMU 相关缓存 */
	if (!pte_none(*vmf->pte)) {
		update_mmu_cache(vma, vmf->address, vmf->pte);
		goto release;
	}

	ret = check_stable_address_space(vma->vm_mm);
	if (ret)
		goto release;

	...
	/* 把页加入匿名页反射机制的结构中 */
	page_add_new_anon_rmap(page, vma, vmf->address, false);
	/* 把页加入 LRU 链表中，回收相关机制会使用 */
	lru_cache_add_inactive_or_unevictable(page, vma);
setpte:
	/* 将刚刚暂存的 entry 的值写到 pte 中，刷新本 CPU 线程的 MMU 相关缓存 */
	set_pte_at(vma->vm_mm, vmf->address, vmf->pte, entry);

	/* No need to invalidate - it was non-present before */
	update_mmu_cache(vma, vmf->address, vmf->pte);
unlock:
	pte_unmap_unlock(vmf->pte, vmf->ptl);
	return ret;
release:
	put_page(page);
	goto unlock;
oom_free_page:
	put_page(page);
oom:
	return VM_FAULT_OOM;
}
```

- 先申请页表，因为私有匿名页在建立的时候根本就没有为其分配页表。

- 如果读私有匿名页异常，直接把公用的 zero-page 页给进程，防止程序员申请的太多又并没有真正使用

  - 将 zero-page 页的物理地址及一些权限位写入 `entry` 变量暂存。

  - 获取该虚拟地址对应的页表项指针并加锁。

  - 检查一下 pte 的值，如果目前 pte 的值已经不为 0 了，说明其他线程已经做好异常处理工作，对 MIPS 架构而言需要同步一下 tlb 再退出，其他架构，什么也不做就退出。

  - 跳转到 `setpte` 标号处，将准备好的 `entry` 真正写入 pte。

- 如果是写或者用户指定不可用零页，需要进行真正的分配私有页面流程

  - 分配 anon_vma，并和 vma 建立关联，这在反射机制时有用。

  - 申请一个物理页，将该页数据清零，并设置 update 标志。

  - 根据物理页对应的物理地址，以及相应权限设置页表项，预先保存在 entry 中。

  - 取得 pte 的指针并加锁，保证不会同时有别的 CPU 线程修改该 pte。

  - 再判断一下目前 pte 有没有被别的线程改过，改过就不处理了，调用 `update_mmu_cache()` 刷新本 CPU 线程的 MMU 相关缓存，这个地方实际上写错了应该为 `update_mmu_tlb()`，因为仅对 MIPS 才需要此处理，目前已经有人提 PATCH 进行了修改，也得到原作者的肯定。

  - 把页加入匿名页反射机制的结构中，再加入 LRU 链表中供回收相关机制使用。

- 将刚刚暂存的 `entry` 的值写到 pte 中。

- 调用 `update_mmu_cache()` 刷新本 CPU 线程的 MMU 相关缓存，Linus 之前的注释写道不必作废 TLB。因为匿名页缺页异常原本就没有 PTE 项，TLB 中当然也不会有该项。当然对于 MIPS 架构来说，这一步还是很有用的，因为 `update_mmu_cache()` 对 MIPS 架构而言不仅是使原来的 TLB 项无效，还会同步 pte 中到 TLB 中。对 RISC-V 架构来说，这一步没有用，因为 RISC-V 目前刷新 TLB 的操作是仅使原来的 TLB 项无效。

## 总结

本文详细分析了 `handle_pte_fault()` 函数以及私有匿名映射缺页异常 `do_anonymous_page()` 函数的实现细节。涉及细节较多，可对照源码仔细阅读。

## 参考资料

- [1] DANILE.PBOVET、MARCO CESATI 著，陈莉君、张琼声、张宏伟 译。深入理解 Linux 内核 [M].北京：中国电力出版社，2007
- [2] 陈华才。用"芯"探核 基于龙芯的 Linux 内核探索解析 [M].北京：中国工信出版社/人民邮电出版社，2020.
