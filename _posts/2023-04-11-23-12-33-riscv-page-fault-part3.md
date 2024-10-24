---
layout: post
author: 'Jinyu Tang'
title: 'RISC-V 缺页异常处理程序分析（3）：文件映射缺页异常分析'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-page-fault-part3/
description: 'RISC-V 缺页异常处理程序分析（3）：文件映射缺页异常分析'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - 缺页异常处理
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [pangu autocorrect epw]
> Author:    tjytimi  <tjytimi@163.com>
> Date:      2022/11/04
> Revisor:   lzufalcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

本系列将分析缺页异常处理，其中，与处理器架构相关的部分采用 RICS-V 架构下对应的代码。

本文为缺页异常的第三篇，此篇分析文件映射缺页异常。

文件映射的缺页异常处理中，内核代码对不同类型的文件映射抽象出相同的流程进行代码复用，清晰易懂，值得我们借鉴学习。

## do_fault() 函数分析

`do_fault()` 函数主要用于处理文件映射的缺页异常。根据文件映射类型，该函数分别对读文件映射的页、写私有文件映射的页以及写共享文件映射的页导致的异常进行分类处理：

```
 do_fault()
	-> do_read_fault()  读文件映射的页
	-> do_cow_fault()   写私有文件映射的页
	-> do_share_fault() 写共享文件映射的页
```

以下分别对这三种类型进行分析。

`do_read_fault()` 函数用于处理读文件映射的缺页异常：

```c
// mm/memory.c : 4165
static vm_fault_t do_read_fault(struct vm_fault *vmf)
{
	struct vm_area_struct *vma = vmf->vma;
	vm_fault_t ret = 0;

	/*
	 * Let's call ->map_pages() first and use ->fault() as fallback
	 * if page by the offset is not ready to be mapped (cold cache or
	 * something).
	 */

	/*
	 * 多读附近的几页，局部性原理，减少缺页异常次数，对大部分文件系统来说
	 * do_fault_around() 最后会执行 filemap_map_pages() 函数。
	 */
	if (vma->vm_ops->map_pages && fault_around_bytes >> PAGE_SHIFT > 1) {
		if (likely(!userfaultfd_minor(vmf->vma))) {
			ret = do_fault_around(vmf);
			if (ret)
				return ret;
		}
	}

	/* 完成所缺页对应文件页缓存（file cache）获取 */
	ret = __do_fault(vmf);
	if (unlikely(ret & (VM_FAULT_ERROR | VM_FAULT_NOPAGE | VM_FAULT_RETRY)))
		return ret;

	/* 将对应页面的物理地址写入页表项 */
	ret |= finish_fault(vmf);
	unlock_page(vmf->page);
	if (unlikely(ret & (VM_FAULT_ERROR | VM_FAULT_NOPAGE | VM_FAULT_RETRY)))
		put_page(vmf->page);
	return ret;
}

```

`do_read_fault()` 函数主要流程总结如下：

- 读异常地址附近的几页，根据局部性原理，可减少读文件映射缺页异常次数。对大部分文件系统来说，`do_fault_around()` 最后会执行 `filemap_map_pages()` 函数完成读附近页的功能。

- 调用 `__do_fault()` 完成所缺页对应文件页缓存（file cache）页面的获取。

- 调用 `finish_fault()` 将对应页面的物理地址写入页表项。

`do_cow_fault()` 函数用来处理写私有文件映射的情形：

```c
// mm/memory.c : 4194
static vm_fault_t do_cow_fault(struct vm_fault *vmf)
{
	struct vm_area_struct *vma = vmf->vma;
	vm_fault_t ret;

	if (unlikely(anon_vma_prepare(vma)))
		return VM_FAULT_OOM;

	/*
	 * 申请一个新页，因为写私有文件映射后，就和原来的文件没有关系了，相当于变成了
	 * 一个私有匿名页。用新申请的页可以保护原来干净的 file cache，别的进程可以
	 * 直接用原来的 file cache
	 */
	vmf->cow_page = alloc_page_vma(GFP_HIGHUSER_MOVABLE, vma, vmf->address);
	if (!vmf->cow_page)
		return VM_FAULT_OOM;

	...

	/* 完成所缺页对应文件页缓存（file cache）获取 */
	ret = __do_fault(vmf);
	if (unlikely(ret & (VM_FAULT_ERROR | VM_FAULT_NOPAGE | VM_FAULT_RETRY)))
		goto uncharge_out;
	if (ret & VM_FAULT_DONE_COW)
		return ret;
	/*
	 * 把 file cache 的内容拷贝一份到 vmf->cow_page，完成私有文件页的写时复制，
	 * 后面该进程使用就是 cow_page，与磁盘中的文件对应的缓存无关了
	 */
	copy_user_highpage(vmf->cow_page, vmf->page, vmf->address, vma);
	__SetPageUptodate(vmf->cow_page);

	/* 将对应页面的物理地址写入页表项 */
	ret |= finish_fault(vmf);
	unlock_page(vmf->page);
	put_page(vmf->page);
	if (unlikely(ret & (VM_FAULT_ERROR | VM_FAULT_NOPAGE | VM_FAULT_RETRY)))
		goto uncharge_out;
	return ret;
uncharge_out:
	put_page(vmf->cow_page);
	return ret;
}
```

`do_cow_fault()` 函数主要流程总结如下：

- 申请一个新页。写私有文件映射后，页就和原来的文件没有关系了，相当于变成了一个私有匿名页。用新申请的页可以保护原来干净的 file cache，保证别的进程可以直接用原来的 file cache。

- 调用 `__do_fault()` 函数完成所缺页对应文件页缓存（file cache）的获取。

- 把 file cache 的内容拷贝一份到 `vmf->cow_page`，完成私有文件页的写时复制，后面该进程写的是 cow_page，而不是 file cache 对应的页了。

- 调用 `finish_fault()` 将 cow_page 的物理地址写入页表项。

`do_shared_fault()` 用来处理写共享内存文件映射的情形：

```c
// mm/memory.c : 4233
static vm_fault_t do_shared_fault(struct vm_fault *vmf)
{
	struct vm_area_struct *vma = vmf->vma;
	vm_fault_t ret, tmp;
	/* 完成所缺页对应文件页缓存（file cache）获取 */
	ret = __do_fault(vmf);
	if (unlikely(ret & (VM_FAULT_ERROR | VM_FAULT_NOPAGE | VM_FAULT_RETRY)))
		return ret;

	/*
	 * Check if the backing address space wants to know that the page is
	 * about to become writable
	 */
	/* page_mkwrite 用于回写机制，这一步保证了被写过的页能够被及时回写到磁盘 */
	if (vma->vm_ops->page_mkwrite) {
		unlock_page(vmf->page);
		tmp = do_page_mkwrite(vmf);
		if (unlikely(!tmp ||
				(tmp & (VM_FAULT_ERROR | VM_FAULT_NOPAGE)))) {
			put_page(vmf->page);
			return tmp;
		}
	}

	/* 将对应页面的物理地址写入页表项 */
	ret |= finish_fault(vmf);
	if (unlikely(ret & (VM_FAULT_ERROR | VM_FAULT_NOPAGE |
					VM_FAULT_RETRY))) {
		unlock_page(vmf->page);
		put_page(vmf->page);
		return ret;
	}

	ret |= fault_dirty_shared_page(vmf);
	return ret;
}
```

`do_shared_fault()` 函数主要流程总结如下：

- 调用 `__do_fault()` 完成所缺页对应文件页缓存（file cache）获取。

- 调用 `do_page_mkwrite()` 将页标识为已写。对大部分文件系统而言，该函数最终会调用 `folio_mark_dirty(folio)` 将页标识为脏，从而保证回写机制能够及时将脏页回写到磁盘。注意此处映射的页是要回写的，应区分和写私有文件映射的不同。

- 调用 `finish_fault()` 将对应页面的物理地址写入页表项。

以上三个处理文件内存映射的函数流程比较清晰，在获取文件数据页面时均使用 `__do_fault()` 函数，将页面地址写入对应页表项时均使用 `finish_fault()` 函数。下文将对这两个函数进行分析。

## __do_fault() 函数分析

`__do_fault()` 函数主要完成缺页对应文件页缓存（file cache）的获取：

```c
// mm/memory.c : 3842
static vm_fault_t __do_fault(struct vm_fault *vmf)
{
	struct vm_area_struct *vma = vmf->vma;
	vm_fault_t ret;

	/* 会预先分配一下页表的页，避免死锁，memcg 机制会产生这种逻辑，此处暂时不做研究 */
	if (pmd_none(*vmf->pmd) && !vmf->prealloc_pte) {
		vmf->prealloc_pte = pte_alloc_one(vma->vm_mm);
		if (!vmf->prealloc_pte)
			return VM_FAULT_OOM;
	}
	/*
	 * 调用该文件映射页的虚拟地址区域 fault 钩子函数，一般文件系统对应 filemap_fault()
	 * filemap_fault() 简单来说就是先看以前有没有留下来文件页的缓存（file cache），如果
	 * 还有，则直接用留存的 file cache，赋给 vmf—>page，如果没有，则需要先新申请页作为
	 * file cache，再从磁盘中读取文件的数据到 cache。file cache 使得第二次映射同一个文件
	 * 读取会比第一次快。
	 */
	ret = vma->vm_ops->fault(vmf);

	...

	return ret;
}
```

`__do_fault()` 函数主要流程总结如下：

- 首先预先分配一下页表的页，避免死锁，memcg 机制会产生这种逻辑，此处暂时不做研究。

- 通过 `vma->vm_ops->fault` 调用文件映射页的虚拟地址区域的 fault 钩子函数，一般文件系统对应 `filemap_fault()` 函数，也就是说 `vm_ops` 一般定义为 `generic_file_vm_ops`：

```c
// mm/filemap.c : 3417
const struct vm_operations_struct generic_file_vm_ops = {
	.fault		= filemap_fault,
	.map_pages	= filemap_map_pages,
	.page_mkwrite	= filemap_page_mkwrite,
};

```

- `filemap_fault()` 函数会判断内存中有没有以前访问后留下的文件页缓存（file cache），如果还有，则直接把留存的 file cache 赋给 `vmf—>page`。如果没有，则需要先新申请页作为 file cache，再从磁盘中读取文件的数据到 file cache。file cache 的存在使得第二次映射同一个文件时，读取会比第一次快很多。这种缓存的设计体现了 Linux 充分利用内存的设计思想。

## finish_fault() 函数分析

`finish_fault()` 函数将页面地址写入对应页表项，最终完成文件映射异常处理流程：

```c
// mm/memory.c : 4019
vm_fault_t finish_fault(struct vm_fault *vmf)
{
	struct vm_area_struct *vma = vmf->vma;
	struct page *page;
	vm_fault_t ret;

	/*
	 * 如果是写私有页，新页是新申请的 cow_page，而不是
	 * 复用 file cache 对应的 page，因为私有页是不会
	 * 回写到磁盘的。
	 */
	/* Did we COW the page? */
	if ((vmf->flags & FAULT_FLAG_WRITE) && !(vma->vm_flags & VM_SHARED))
		page = vmf->cow_page;
	else
		page = vmf->page;

	/*
	 * check even for read faults because we might have lost our CoWed
	 * page
	 */
	/*
	 * 确认一下页有没有被别的进程占用，私有页申请的内存在内存紧缺的时候可能会被占用
	 */
	if (!(vma->vm_flags & VM_SHARED)) {
		ret = check_stable_address_space(vma->vm_mm);
		if (ret)
			return ret;
	}

	...
	/* 获取 pte 指针，一定要加锁，因为有可能不同线程同时产生缺页异常，会有冲突 */
	vmf->pte = pte_offset_map_lock(vma->vm_mm, vmf->pmd,
				      vmf->address, &vmf->ptl);
	ret = 0;
	/* Re-check under ptl */
	if (likely(pte_none(*vmf->pte)))
	/* 将页的物理地址写入页表项，完成物理地址和虚拟地址之间的连接，函数内部进行了分类处理 */
		do_set_pte(vmf, page, vmf->address);
	else
		ret = VM_FAULT_NOPAGE;
	/* 此函数只对 MIPS 架构有用，因为 MIPS 是 TLB 中没有相关项就报异常，这样同步一下能减少一次缺页异常 */
	update_mmu_tlb(vma, vmf->address, vmf->pte);
	pte_unmap_unlock(vmf->pte, vmf->ptl);
	return ret;
}
```

`finish_fault()` 函数主要流程如下：

- 如果是写私有页，用新申请的 cow_page 赋给 `page`，否则用 file cache 对应的页面赋给 `page`。

- 确认一下页有没有被别的进程占用，私有页申请的内存紧缺的时候有可能会被占用。

- 获取 pte 指针，且一定要加锁，因为有可能不同线程同时产生缺页异常。

- 调用 `do_set_pte()` 将页的物理地址写入页表项，完成物理地址和虚拟地址之间的连接，该函数内部进行了分类处理，下文将进行详细叙述。

- 调用 `update_mmu_tlb()` 刷新一下 tlb。此函数只对 MIPS 架构有用，因为 MIPS 是 TLB 中没有相关项就报异常，此处同步一下能减少一次缺页异常。

`do_set_pte()` 函数将缺页异常处理流程中获取的物理地址写入页表项，完成物理地址和报异常的虚拟地址之间的连接：

```c
// mm/memory.c: 3975
void do_set_pte(struct vm_fault *vmf, struct page *page, unsigned long addr)
{

	...
	/* 如果是写异常，将页表项的脏位置位，同时将写权限 W 位也置位 */
	if (write)
		entry = maybe_mkwrite(pte_mkdirty(entry), vma);

	/* copy-on-write page */
	/*
	 * 如果是私有写文件映射，由于其已经独立了，不再会影响文件页，所以视为
	 * 私有匿名页管理，将其加入私有匿名页的反射机制管理结构中，同时也将该
	 * 页加入 LRU 不活跃链表中，第一次访问不能证明其经常会被访问，所以暂且
	 * 放入不活跃链表。
	 * 如果是共享的文件页，将其加入文件页反射机制管理结构中。
	 * 上述两种情况都会调用 inc_mm_counter_fast() 增加该虚拟地址空间的引用
	 * 次数
	 */
	if (write && !(vma->vm_flags & VM_SHARED)) {
		inc_mm_counter_fast(vma->vm_mm, MM_ANONPAGES);
		page_add_new_anon_rmap(page, vma, addr, false);
		lru_cache_add_inactive_or_unevictable(page, vma);
	} else {
		inc_mm_counter_fast(vma->vm_mm, mm_counter_file(page));
		page_add_file_rmap(page, false);
	}
	/* 将页对应的物理地址写入页表项，完成该缺页虚拟地址到物理页的最终映射 */
	set_pte_at(vma->vm_mm, addr, vmf->pte, entry);
}
```

`do_set_pte()` 流程总结如下：

- 如果是写文件映射的异常，将页表项的脏位置位，同时将写权限 W 位也置位。

- 将新获取的页面加入对应的管理结构中：

  - 如果是私有写文件映射，由于其已经独立了，不会影响文件页，所以视为私有匿名页管理，将其加入私有匿名页的反射机制管理结构中，同时也将该页加入 LRU 不活跃链表中，因为第一次访问不能证明其会经常被访问，所以暂且放入不活跃链表。

  - 如果是共享文件页，将其加入文件页反射机制管理结构中。

  - 上述两种情况都会调用 `inc_mm_counter_fast()` 增加该虚拟地址空间的引用次数。

- 最后调用 `set_pte_at()` 将页对应的物理地址写入页表项，完成该缺页的虚拟地址到物理页的最终映射。

## 总结

本文分析了文件映射缺页异常处理流程。分别对三种类型的文件映射缺页异常进行了分析，并介绍了三种类型均复用的 `__do_fault()` 函数和 `finish_fault()` 函数。读者可以借鉴其中的代码复用思路到日常开发中。

## 参考资料

- [1] DANILE.PBOVET、MARCO CESATI 著，陈莉君、张琼声、张宏伟 译。深入理解 Linux 内核 [M].北京：中国电力出版社，2007
- [2] 陈华才。用"芯"探核 基于龙芯的 Linux 内核探索解析 [M].北京：中国工信出版社/人民邮电出版社，2020.
