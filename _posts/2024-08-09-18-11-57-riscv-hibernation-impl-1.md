---
layout: post
author: 'sugarfillet'
title: 'RISC-V 休眠实现分析 1 -- 休眠过程'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-hibernation-impl-1/
description: 'RISC-V 休眠实现分析 1 -- 休眠过程'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - 休眠
  - 电源管理
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces header toc codeblock codeinline pangu epw]
> Author:    sugarfillet <sugarfillet@yeah.net>
> Date:      2023/05/27
> Revisor:   Falcon falcon@tinylab.org
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V Linux SMP 技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I5MU96)
> Sponsor:   PLCT Lab, ISCAS


## 前言

Linux 休眠功能是电源管理中的一个重要技术点。它能让系统在不需要工作时，将系统状态保存在硬盘上，并尽可能进入一个功耗极低的状态，这时外部的设备进入了低功耗状态或关闭电源状态，从而尽可能的减少功耗，增加产品的续航。另一方面，在用户需要系统工作的时候，系统能够快速恢复保存的系统状态，从而不影响用户的使用体验。

RISC-V 架构在 Linux v6.4-rc1 版本引入了对系统休眠的[支持][1]，本系列文章对其实现进行分析。

**说明**：

- 本文的 Linux 版本采用 `Linux v6.4-rc1`

## 休眠/唤醒的触发简介

正如 `CONFIG_HIBERNATION` 依赖（`depends on SWAP`）所描述的，系统休眠之前需要提前配好 swap 分区或者文件，之后可简单通过 `echo disk > /sys/power/state` 命令执行休眠并关机。而如果要实现系统唤醒，则需要在在内核命令行中指定 `resume=/dev/swappartition`，在系统启动时则会在指定的 swap 分区中加载休眠镜像并恢复保存的系统状态。

除了 `/sys/power/state` 接口，Linux 还向用户态提供以下几种方式以触发休眠流程：

1. 以 `LINUX_REBOOT_CMD_SW_SUSPEND` 为参数调用 reboot 系统调用，具体可参考 [man 2 reboot][2]
2. 基于 `/sys/class/misc/snapshot/dev` 设备的操作，具体可参考 [userland-swsusp.txt][3]
3. `uswsusp` 工具，具体可参考其[官网][4]

> 上述接口或者工具的使用不是本文讨论的重点，有兴趣的同学可以参考相关链接进行研究。

无论采用什么样的接口触发休眠，最终都会走到内核的 `hibernate()` 函数。

在休眠的整个过程中涉及到比较多准备工作（其他子系统的挂起和恢复操作）比如：

- PM 相关的挂起控制台 -- `SUSPEND_CONSOLE`、休眠事件通知链触发
- 文件系统的同步
- 进程的冻结与解冻
- 设备的电源管理 (DPM)
- 设备的热插拔管理

篇幅有限，这些准备工作的实现不做展开，只在下文代码中做简单的注释。

## 休眠核心代码

### hibernate

`hibernate()` 函数负责实现系统休眠。主要执行以下关键过程：

- 执行一些休眠的准备工作：文件系统同步、进程冻结、设备挂起等
- 调用 `create_basic_memory_bitmaps` 函数创建两个 bitmap -- `forbidden_pages_map`、`free_pages_map`
- 调用 `hibernation_snapshot` 函数用来创建休眠镜像
- 在 `hibernation_snapshot` 返回后，判断 `in_suspend` 变量，
  - 如果还在休眠过程中，则执行 `swsusp_write` 写入休眠镜像到 swap，并关机
  - 否则代表从唤醒过程中返回，回退之前的准备操作，返回到休眠触发之前的环境中

```c
// kernel/power/hibernate.c : 722

hibernate()
  pr_info("hibernation entry\n");

  pm_prepare_console();  // SUSPEND_CONSOLE
  pm_notifier_call_chain_robust(PM_HIBERNATION_PREPARE, PM_POST_HIBERNATION);
  ksys_sync_helper();   // 文件系统同步
  freeze_processes();   // 冻结进程
  lock_device_hotplug();  // 关闭设备热插拔
  create_basic_memory_bitmaps(); // Create bitmaps to hold basic page information.
                                 // init forbidden_pages_map and free_pages_map

  hibernation_snapshot();
    hibernate_preallocate_memory();  // 为系统要保存到休眠镜像中的内存分配拷贝空间

    freeze_kernel_threads(); // 冻结内核线程
    suspend_console();     // 挂起控制台

    create_image(platform_mode);

    // 1. after the image has been created or failed  2. after a successful restore.

    resume_console();

  if (in_suspend) {
    pm_pr_dbg("Writing hibernation image.\n");
    swsusp_write(flags); && power_down();
  else {
    pm_pr_dbg("Hibernation image restored successfully.\n");
  }

  free_basic_memory_bitmaps();
  unlock_device_hotplug();
  thaw_processes();
  pm_notifier_call_chain(PM_POST_HIBERNATION);
  pm_restore_console();

  pr_info("hibernation exit\n");

```

### hibernation_snapshot

`hibernation_snapshot` 函数用来创建休眠镜像，关键过程有：

`hibernate_preallocate_memory` 函数为休眠镜像分配内存空间，分配的大小基于以下公式进行计算（不考虑 `ZONE_HIGHMEM`）：

```
max_size = ([page frames total] - PAGES_FOR_IO - [metadata pages]) / 2  - 2 * DIV_ROUND_UP(reserved_size, PAGE_SIZE)
```

- "page frames total" 为 zone 分配器中整体可用的页（对应代码中的 `count` 变量），具体为：可保存的 (`saveable_page()`) 以及可用的 `NR_FREE_PAGES` 页之和，减掉 `min_free_kbytes` 配置保留的页）

- `PAGES_FOR_IO` 以及 `reserved_size` (`/sys/power/reserved_size`) 表示休眠过程中为设备驱动的休眠回调函数保留的页；

- "metadata pages" 计算以 `struct rtree_node` 结构表示所有 zone 的总页数 -- `zone->spanned_pages` 所需的大小。

`/sys/power/image_size` 是用户指定的休眠镜像大小，需要保证其不超过之前计算的 `max_size`。最后，如果计算的镜像大小（`size`）足以保存要保存的页 `saveable`，则调用 `preallocate_image_memory` 分配 `saveable` 数量的页，并在 `copy_bm` 中标记这些页；否则需要回收一定内存（`shrink_all_memory`）来分配。

此函数的计算过程确实比较复杂，但从整体来看，该函数为 zone 分配器中可保存的页一比一地分配拷贝页，并记录到 `copy_bm` bitmap 中。最终你会在日志中看到这样几条日志：

```
[  115.354044] PM: hibernation: Preallocating image memory
[  117.949620] PM: hibernation: Allocated 84251 pages for snapshot
[  117.950187] PM: hibernation: Allocated 337004 kbytes in 2.59 seconds (130.11 MB/s)
```

```c
// kernel/power/snapshot.c : 1736

hibernate_preallocate_memory()

  memory_bm_create(&orig_bm, GFP_IMAGE, PG_ANY);
  memory_bm_create(&copy_bm, GFP_IMAGE, PG_ANY);

  saveable = count_data_pages();  // 可保存的页
    for_each_populated_zone(zone) {
        mark_free_pages(zone);   // mark zone->free_area in free_pages_map
        for (pfn = zone->zone_start_pfn; pfn < max_zone_pfn; pfn++)
          if (saveable_page(zone, pfn))  n++;

  count = saveable;

  for_each_populated_zone(zone) {
    size += snapshot_additional_pages(zone); // 基于 `zone->spanned_pages` 计算
    count += zone_page_state(zone, NR_FREE_PAGES); // 可用的页

  avail_normal = count;
  count -= totalreserve_pages; //

  max_size = (count - (size + PAGES_FOR_IO)) / 2 - 2 * DIV_ROUND_UP(reserved_size, PAGE_SIZE);

  size = DIV_ROUND_UP(image_size, PAGE_SIZE); // /sys/power/image_size 不能大于 max_size
  if (size > max_size)
    size = max_size;

  if (size >= saveable) {  // 如果镜像大小足以保存可保存的页
    pages += preallocate_image_memory(saveable - pages, avail_normal);
      page = alloc_image_page(mask);
      memory_bm_set_bit(&copy_bm, page_to_pfn(page));
      alloc_normal++;
    goto out;
  // ...
out:
  pr_info("Allocated %lu pages for snapshot\n", pages);

```

`hibernation_snapshot` 紧接着冻结内核线程、挂起控制台，之后调用 `create_image` 函数。此函数负责在关闭其他 CPU、挂起系统设备、关中断后，调用 `swsusp_arch_suspend` 保存休眠上下文到 `hibernate_cpu_context` 变量中（下文展开分析），执行 `swsusp_save` 函数构建正式的休眠镜像。

```c
// kernel/power/hibernate.c : 293

create_image()

  pm_sleep_disable_secondary_cpus()  // 关闭其他 CPU
    freeze_secondary_cpus()
        _cpu_down(cpu, 1, CPUHP_OFFLINE);

  local_irq_disable();
  system_state = SYSTEM_SUSPEND;
  syscore_suspend(); // suspend system devices

  in_suspend = 1;
  save_processor_state();  // ARCH
    WARN_ON(num_online_cpus() != 1);

  error = swsusp_arch_suspend();
    __cpu_suspend_enter(hibernate_cpu_context)    // save hibernate_cpu_context
    swsusp_save()
  /* Restore control flow magically appears here */
  restore_processor_state();

  syscore_resume();
  system_state = SYSTEM_RUNNING;
  local_irq_enable();
  pm_sleep_enable_secondary_cpus();   // back to hibernate do swsusp_write

```

`swsusp_save` 函数用于创建最终的休眠镜像，关键过程有：

- 调用 `drain_local_pages` 释放 zone 中的可用页，重新计算需要保存的页 `nr_pages`
- 调用 `swsusp_alloc()` 在 `hibernate_preallocate_memory` 分配的拷贝页 -- `alloc_normal` 的基础上按需分配镜像内存
- 调用 `copy_data_pages` 函数在 `orig_bm` 标记当前 zone 分配器中要保留的页，遍历 `orig_bm` 中标记的页，拷贝到 `copy_bm` 分配的内存中
- 更新用于记录已拷贝页数目的变量 -- `nr_copy_pages`，用于管理已拷贝页的变量 -- `nr_meta_pages`

最终，你会看到这样日志输出：

```
[  118.051476] PM: hibernation: Creating image:
[  118.051476] PM: hibernation: Need to copy 82423 pages
[  118.051476] PM: hibernation: Image created (82423 pages copied)
```

```c
// kernel/power/snapshot.c : 2762

asmlinkage __visible int swsusp_save(void)

  pr_info("Creating image:\n");
  drain_local_pages(NULL);  // 释放 zone 中的可用页

  nr_pages = count_data_pages(); // 重新计算可保存的页
  nr_highmem = count_highmem_pages();
  pr_info("Need to copy %u pages\n", nr_pages + nr_highmem);

  swsusp_alloc(&copy_bm, nr_pages, nr_highmem); // 对比可保存页与之前分配的页的大小，按需分配内存
    nr_pages -= alloc_normal; // alloc_normal 为设备挂起之前分配的内存，如果重新计算的页总数比其小则不用再分配
    while (nr_pages-- > 0)
      page = alloc_image_page(GFP_ATOMIC);
      memory_bm_set_bit(copy_bm, page_to_pfn(page));

  copy_data_pages(&copy_bm, &orig_bm);  // 将系统要保存的页保存在 `copy_bm` 分配的内存中
    for_each_populated_zone(zone) {       // 设置要保存的页到 orig_bm
        for (pfn = zone->zone_start_pfn; pfn < max_zone_pfn; pfn++)
          if (page_is_saveable(zone, pfn))
            memory_bm_set_bit(orig_bm, pfn);

    copy_data_page(memory_bm_next_pfn(copy_bm), pfn);  // 拷贝 orig_bm 记录的内存页到 copy_bm 分配的拷贝页
      safe_copy_page(page_address(pfn_to_page(dst_pfn)), pfn_to_page(src_pfn)); // (void *dst, struct page *s_page)
       if kernel_page_present(s_page)  // else： hibernate_*map_page then do_copy_page
         do_copy_page(dst, page_address(s_page));

  nr_pages += nr_highmem;
  nr_copy_pages = nr_pages;   // Total number of saveable pages
  nr_meta_pages = DIV_ROUND_UP(nr_pages * sizeof(long), PAGE_SIZE);
  pr_info("Image created (%d pages copied)\n", nr_pages);

  return 0 ;
```

自此休眠镜像已成功创建，需要恢复系统（比如：开中断、启动其他 CPU，恢复设备），最终在 `hibernate` 函数中判断 `in_suspend == 1`（在 `create_image` 中设置）且镜像创建成功，则调用 `swsusp_write` 成功写入到 swap 分区或者文件中，之后关机。

`swsusp_write` 函数基于上文提供的 `copy_bm`、`nr_copy_pages`、`nr_meta_pages` 三个信息，调用 `snapshot_read_next`、`swap_write_page` 两个接口写入休眠镜像。

> 此处不对 `swsusp_write` 展开分析：此函数与唤醒时的 `swsusp_read` 是对称的过程，而对 `swsusp_read` 的分析是理解唤醒过程的关键，可结合后文对 `swsusp_read` 理解其实现

## RISC-V 休眠代码

在休眠流程中，`swsusp_arch_suspend` 函数执行 `if` 分支：保存休眠上下文 `struct suspend_context *hibernate_cpu_context;`、设置执行休眠的 CPU `sleep_cpu`、调用休眠核心代码提供的用于创建休眠镜像的 `swsusp_save` 函数。

而在休眠唤醒过程中，该函数执行 `else` 分支，配合该分支的 caller -- `__hibernate_cpu_resume` 恢复相关寄存器，设置 `in_suspend = 0`，通知休眠核心代码系统已唤醒，继而返回到休眠触发路径上。

```c
// arch/riscv/kernel/hibernate.c : 468

int swsusp_arch_suspend(void)
{
        int ret = 0;

        if (__cpu_suspend_enter(hibernate_cpu_context)) {  // save hibernate_cpu_context->regs return 1
                sleep_cpu = smp_processor_id();
                suspend_save_csrs(hibernate_cpu_context);  // save hibernate_cpu_context->{scratch,tvec,ie,satp}
                ret = swsusp_save();
        } else {
                suspend_restore_csrs(hibernate_cpu_context); // restore hibernate_cpu_context->{scratch,tvec,ie,satp}
                flush_tlb_all();
                flush_icache_all();

                /*
                 * Tell the hibernation core that we've just restored the memory.
                 */
                in_suspend = 0;
                sleep_cpu = -EINVAL;
        }

        return ret;
}
```

休眠上下文利用 `struct suspend_context` 结构体保存相关寄存器，此结构体也在 `sbi_cpuidle` 驱动执行失忆型挂起时用于保存相关寄存器，可参考[这篇文章][5]。与 `sbi_cpuidle` 驱动用到 `cpu_suspend` 函数类似，`swsusp_arch_suspend` 函数也采用这种巧妙的 `if/else` 格式，对该函数进行反汇编，可以看到在 `__cpu_suspend_enter` 函数中保存的 `ra` 就是下一条指令 `beqz` 的地址。休眠或者挂起过程中，`__cpu_suspend_enter` 设置 a0 = 1，执行 if 分支；恢复或者（休眠）唤醒过程中，调用者设置 a0 = 0，执行 else 分支。

```c
(gdb) disassemble swsusp_arch_suspend
   ...
   0xffffffff800095bc <+24>:    auipc   ra,0xfffff
   0xffffffff800095c0 <+28>:    jalr    1168(ra) # 0xffffffff80008a4c <__cpu_suspend_enter>  // call __cpu_suspend_enter
   0xffffffff800095c4 <+32>:    beqz    a0,0xffffffff800095f6 <swsusp_arch_suspend+82>
   ...
```

## 小结

RISC-V Linux 休眠的实现的基本思路为：明确要保存的内存 -- `orig_bm`，并为之创建拷贝内存 -- `copy_bm`，完成拷贝（`copy_data_pages`）后写入 (`swsusp_write`) swap 分区或者文件中。而在 RISC-V 架构上的实现，通过休眠上下文 `hibernate_cpu_context` 保存/恢复必要的寄存器，并采用与 cpuidle 相似的 `if/else` 结构，同时处理休眠触发和休眠唤醒的逻辑，继而返回到休眠触发路径上。整个休眠过程涉及的关键函数及其调用关系，整理如下：

```c
hibernate => hibernation_snapshot         => hibernate_preallocate_memory
          => swsusp_write && power_down   => create_image                  => swsusp_arch_suspend => swsusp_save => copy_data_pages
```

## 参考资料

- [[PATCH v8 0/4] RISC-V Hibernation Support][1]
- [RISC-V cpuidle driver][5]

[1]: https://lore.kernel.org/all/20230330064321.1008373-5-jeeheng.sia@starfivetech.com/
[2]: https://man7.org/linux/man-pages/man2/reboot.2.html
[3]: https://www.kernel.org/doc/Documentation/power/userland-swsusp.txt
[4]: http://suspend.sourceforge.net/
[5]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230205-riscv-cpuidle.md
