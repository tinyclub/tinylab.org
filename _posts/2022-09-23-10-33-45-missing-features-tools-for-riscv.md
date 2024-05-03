---
layout: post
author: 'unknown'
title: 'RISC-V 缺失的 Linux 内核功能-Part1'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /missing-features-tools-for-riscv/
description: 'RISC-V 缺失的 Linux 内核功能'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - KMSAN
  - optprobes
  - queued-spinlocks
  - user-ret-profiler
  - virt-cpuacct
  - membarrier-sync-core
---

> Author:  牛工 - 通天塔 985400330@qq.com
> Date:    2022/08/28
> Revisor: Falcon <falcon@ruma.tech>; iOSDevLog <iosdevlog@iosdevlog.com>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [Missing Features/Tools for RISC-V](https://gitee.com/tinylab/riscv-linux/issues/I5L9H0)
> Sponsor: PLCT Lab, ISCAS


## 前言

RISC-V 架构下还是存在非常多的功能需要大家填坑，很多的功能都是优先在 x86、ARM 上进行了实现，有很多的新功能都还几乎没有资料，需要大家一起去建设，以下是我从内核 Documents 上找到的 RISC-V 下的各类 TODO 功能，并做了简单分析，提供了一些资料，希望大家能找到自己感兴趣的方向，早日向社区提交自己的补丁！

## KMSAN (Kernel Feature)

- 功能：

  > KernelMemorySanitizer (KMSAN) is a detector of errors related to uses of uninitialized memory. It relies on compile-time Clang instrumentation (similar to MSan in the userspace) and tracks the state of every bit of kernel memory, being able to report an error if uninitialized value is used in a condition, dereferenced, or escapes to userspace, USB or DMA.

  KernelMemorySanitizer (KMSAN) 是一个用于检测 **使用未初始化内存** 的错误检测器。它依赖于编译时的 Clang 工具（类似于用户空间中的 MSan），并跟踪内核内存每一比特的状态，如果在条件中使用了未初始化的值、解引用或转义到用户空间、USB 或 DMA 时，能够报告错误。

  > KMSAN has reported more than 300 bugs in the past few years, most of them with the help of syzkaller. Such bugs keep getting introduced into the kernel despite new compiler warnings and other analyses (the 5.16 cycle already resulted in several KMSAN-reported bugs). Mitigations like total stack and heap initialization are unfortunately very far from being deployable.

  KMSAN 在过去几年中报告了 300 多个错误，其中大部分是在 syzkaller 的帮助下发生的。尽管有新的编译器警告和其他分析（5.16 周期已经导致了几个 kmsan 报告的错误），但这样的错误仍然被引入内核。不幸的是，像全部的堆栈初始化检测这样的缓解措施离部署还很远。

  > The proposed patchset contains KMSAN runtime implementation together with small changes to other subsystems needed to make KMSAN work.

  申请合入的补丁集包含 KMSAN 运行时的实现，以及使 KMSAN 工作所需的其他子系统的小更改。

- 状态

  - 社区刚提交 [v4 patchset for x86][004]
  - 其他架构都还没有

- 资料

  - [v4: Add KernelMemorySanitizer infrastructure][004]
  - [邮件列表最新动态][005]

## optprobes(Kernel Feature)

- 功能：

  > If your kernel is built with CONFIG_OPTPROBES=y (currently this flag is automatically set ‘y’ on x86/x86-64, non-preemptive kernel) and the “debug.kprobes_optimization” kernel parameter is set to 1 (see sysctl(8)), Kprobes tries to reduce probe-hit overhead by using a jump instruction instead of a breakpoint instruction at each probepoint.

  如果您的内核是使用 CONFIG_OPTPROBES=y（当前该标志在 x86/x86-64 非抢占内核上自动设置为' y '）和内核参数 kprobes_optimization 设置为 1（请参阅 sysctl(8)），Kprobes 将试图通过在每个探测点使用跳转指令而不是断点指令来减少探测访问开销。

  > Kprobes enables you to dynamically break into any kernel routine and collect debugging and performance information non-disruptively. You can trap at almost any kernel code address , specifying a handler routine to be invoked when the breakpoint is hit.

  Kprobes 使您能够动态地进入任何内核程序，并在不中断的情况下收集调试和性能信息。您可以在几乎任何内核代码地址中设置陷阱，指定在遇到断点时要调用的处理程序。

- 状态
  - 社区刚提交 [[PATCH] arch/riscv: kprobes: implement optprobes - Chen Guokai (kernel.org)][033]
  - **ok**: arm, powerpc, x86
  - **TODO**: alpha, arc, arm64 csky, hexagon, ia64, loong m68k, microblaze, mips nios2, openrisc, parisc riscv, s390, sh, sparc, um xtensa

- 资料
  -  [[PATCH] arch/riscv: kprobes: implement optprobes - Chen Guokai (kernel.org)][033]
  - [邮件列表最新动态][034]

## user-ret-profiler(Kernel Feature)

- 功能：

  ```
  HAVE_USER_RETURN_NOTIFIER
  ```
  > arch supports user-space return from system call profiler.

  架构支持从内核态到用户态切换时的通知。

  > Provide a kernel-internal notification when a CPU is about to switch to user mode.

  当内核切换到用户模式时，提供一个内核内部的消息通知。

- 状态

  - 社区提交 [[tip:core/documentation] Documentation/features/debug: Add feature description and arch support status file for ' user-ret-profiler' - tip-bot for Ingo Molnar (kernel.org)][020]
  - **ok**: x86
  - **TODO**: alpha, arc, arm arm64, csky, hexagon, ia64 loong, m68k, microblaze mips, nios2, openrisc parisc, powerpc, riscv, s390, sh, sparc, um, xtensa

- 资料

  -  [[tip:core/documentation] Documentation/features/debug: Add feature description and arch support status file for ' user-ret-profiler' - tip-bot for Ingo Molnar (kernel.org)][020]
  -  [邮件列表最新动态][018]
  -  [[01/42] core, x86: Add user return notifiers - Patchwork (kernel.org)][025]

## queued-spinlocks(Kernel Feature)

- 功能：

  ```
  ARCH_USE_QUEUED_SPINLOCKS
  ```

  > arch supports queued spinlocks

  架构支持队列锁。

  队列自旋锁能够增强多核 CPU 的性能，减少在自旋锁的开销。

  与传统的锁的不同是，B 线程不需要再不断的轮询锁是否被释放，而是询问一次之后，就会把自己加入到队列当中，当 A 线程释放掉锁之后，自动的将锁给到 B 线程，可以有效的降低开销。

- 状态

  - 社区提交 [[PATCH 01/17] powerpc/qspinlock: powerpc qspinlock implementation - Nicholas Piggin (kernel.org)][008]
  - **ok**: arm64, mips openrisc, powerpc, sparc x86, xtensa
  - **TODO**: alpha, arc, arm csky, hexagon, ia64, loong m68k, microblaze, nios2 parisc, riscv, s390, sh, um

- 资料

  -  [[PATCH 01/17] powerpc/qspinlock: powerpc qspinlock implementation - Nicholas Piggin (kernel.org)][008]
  -  [邮件列表最新动态][017]
  -  [队列自旋锁-Linux 内核揭密 (cntofu.com)][027]

## membarrier-sync-core(Kernel Feature)

- 功能：

  ```
  ARCH_HAS_MEMBARRIER_SYNC_CORE
  ```

  > arch supports core serializing membarrier

  架构支持内核内存屏障。

  用于实现内存屏障，主要解决多核的运行过程中乱序执行导致的逻辑混乱，开启内存屏障之后，可以将某一核上的数据锁住，不允许其他核进行读写，可以防止乱序执行，导致的逻辑混乱。

  ![image-20220822235007653](/wp-content/uploads/2022/03/riscv-linux/images/missing-features-tools-for-riscv/image-20220822235007653.png)

- 状态

  - 社区提交 [[PATCH 07/23] membarrier: Rewrite sync_core_before_usermode() and improve documentation - Andy Lutomirski (kernel.org)][011]
  - **ok**: arm, arm64, powerpc x86
  - **TODO**: alpha, arc, csky hexagon, ia64, loong, m68k microblaze, mips, nios2 openrisc, parisc, riscv s390, sh, sparc, um, xtensa

- 资料

  -  [[PATCH 07/23] membarrier: Rewrite sync_core_before_usermode() and improve documentation - Andy Lutomirski (kernel.org)][011]
  -  [邮件列表最新动态][015]
  -  [membarrier（个人学习理解）_What’smean 的博客-CSDN 博客][002]

## virt-cpuacct(Kernel Feature)

- 功能：

  ```
  HAVE_VIRT_CPU_ACCOUNTING
  ```

  > arch supports precise virtual CPU time accounting

  使架构支持精确的虚拟 CPU 时间计算。

  > Select this option to enable task and CPU time accounting on full dynticks systems. This accounting is implemented by watching every kernel-user boundaries using the context tracking subsystem.The accounting is thus performed at the expense of some significant overhead.

  选择这一选项，能够在全动态系统上启用任务和 CPU 计时。这种计时是通过使用 **上下文跟踪子系统** 监视每个 **内核用户分界线** 来实现的。因此，计时的执行是以牺牲一些重要的开销为代价的。

  cpuacct 是用来统计 cgroup 的进程所使用的 CPU 时间的。

- 状态

  - 社区提交 [[PATCH 0/5] xtensa: enable context tracking and VIRT_CPU_ACCOUNTING_GEN - Max Filippov (kernel.org)][007]
  - **ok**: alpha, arm, arm64 csky, ia64, loong, mips parisc, powerpc, s390 sparc, x86, xtensa
  - **TODO**: arc, hexagon m68k, microblaze, nios2 openrisc, riscv, sh, um

- 资料

  -  [[PATCH 0/5] xtensa: enable context tracking and VIRT_CPU_ACCOUNTING_GEN - Max Filippov (kernel.org)][007]
  -  [邮件列表最新动态][019]
  -  [理解 docker - control group - 知乎 (zhihu.com)][029]

## batch-unmap-tlb-flush(Kernel Feature)

- 功能：

  ```
  ARCH_WANT_BATCHED_UNMAP_TLB_FLUSH
  ```
  > arch supports deferral of TLB flush until multiple pages are unmapped.

  架构支持延迟刷新 TLB，直到多个页面取消映射之后。

  > For architectures that prefer to flush all TLBs after a number of pages are unmapped instead of sending one IPI per page to flush. The architecture must provide guarantees on what happens if a clean TLB cache entry is written after the unmap. Details are in mm/rmap.c near the check for should_defer_flush. The architecture should also consider if the full flush and the refill costs are offset by the savings of sending fewer IPIs.

  适用于倾向于取消多个页面映射后刷新所有 TLB，而不是在每个页面发送一个 IPI 来刷新的架构。如果在 unmap 之后写入干净的 TLB 缓存入口，架构必须保证会触发的事件。详细信息在 mm/rmap.c 中为 should_defer_flush 检查附近。该架构还应该考虑是否可以通过减少发送 IPI 来抵消完全刷新和重新填充的成本。

- 状态
    - 社区已经好久没有这方面的提交了，[[PATCH 3/6] mm: Defer TLB flush after unmap as long as possible (narkive.com)][006]，找到了比较早的一些关于 TLB 刷新的一些补丁。
  - **ok**: x86
  - **TODO**: alpha, arc, arm csky, hexagon, ia64, mips nds32, parisc, powerpc, riscv, s390, sh, sparc xtensa
  - **N/A**: arm64
  - **Not compatible**: h8300 m68k, microblaze, nios2 openrisc, um
- 资料

  -  [[PATCH 3/6] mm: Defer TLB flush after unmap as long as possible (narkive.com)][006]
  -  [邮件列表最新动态][012]
  -  [TLB 之 flush 操作（一）- 知乎 (zhihu.com)][030]

## huge-vmap(Kernel Feature)

- 功能：

  ```
  HAVE_ARCH_HUGE_VMAP
  ```

  > arch supports the `arch_vmap_pud_supported()` and `arch_vmap_pmd_supported()` VM APIs

  架构将支持 `arch_vmap_pud_supported()` 和 `arch_vmap_pmd_supported()` 虚拟化接口。

  > Archs that select this would be capable of PMD-sized vmaps (i.e.,arch_vmap_pmd_supported() returns true), and they must make no assumptions that vmalloc memory is mapped with PAGE_SIZE ptes. The VM_NO_HUGE_VMAP flag can be used to prohibit arch-specific allocations from using hugepages to help with this (e.g., modules may require it).

  选择该选项之后，架构可以使用 PMD 大小的内存申请（即 `arch_vmap_pmd_supported()` 返回 true）,并且它们必须假设 vmalloc 内存不是用 PAGE_SIZE ptes 映射的。VM_NO_HUGE_VMAP 标志可以用来禁止特定的分配使用超大页来帮助完成（例如，模块可能需要它）。

  这个功能是 2020 年 8 月引入到内核中的，国内关于这块的资料还是比较少，使用该功能以后，能够优化内存的分配，降低 TLB 的 miss 概率，提高 CPU 效率。

  具体原理分析的资料还非常少。

- 状态
  - 社区提交 [Re: Re: [PATCH v4 0/4] riscv, mm: detect svnapot CPU support at runtime - Qinglin Pan (kernel.org)][010]
  - **ok**: arm64, powerpc, x86
  - **TODO**: alpha, arc, arm csky, hexagon, ia64, loong m68k, microblaze, mips nios2, openrisc, parisc riscv, s390, sh, sparc, um xtensa
- 资料

  -  [Re: Re: [PATCH v4 0/4] riscv, mm: detect svnapot CPU support at runtime - Qinglin Pan (kernel.org)][010]
  -  [邮件列表最新动态][013]
  -  [huge vmalloc mappings LWN.net][024]

## ioremap_prot(Kernel Feature)

- 功能：

  ```
  HAVE_IOREMAP_PROT
  ```

  arch has ioremap_prot()

  资料非常少，不分析代码的话，只能通过该函数的一些注释来了解其功能。

  ```
  /*
   * ioremap with access flags
   * Cache semantics wise it is same as ioremap - "forced" uncached.
   * However unlike vanilla ioremap which bypasses ARC MMU for addresses in
   * ARC hardware uncached region, this one still goes thru the MMU as caller
   * might need finer access control (R/W/X)
   */
  ```

  通过 flags 进行 ioremap。

  该函数与 ioremap 作用基本一致，但是该函数有用“强制”禁止缓存的功能，ioremap_prot 使调用者能够控制缓存相关属性 (CCA)，翻译起来也比较困难，需要有对 ioremap 有足够的理解，再结合 ioremap_prot 的代码，才能够理解该函数的意义。

- 状态
  - 社区提交 [Re: [PATCH v2 1/4] RISC-V: Fix ioremap_cache() and ioremap_wc() for systems with Svpbmt - Conor.Dooley (kernel.org)][032]
  - **ok**: arc, arm64, loong mips, powerpc, s390, sh x86
  - **TODO**: alpha, arm, csky hexagon, ia64, m68k microblaze, nios2, openrisc parisc, riscv, sparc, um xtensa

- 资料

  -  [Re: [PATCH v2 1/4] RISC-V: Fix ioremap_cache() and ioremap_wc() for systems with Svpbmt - Conor.Dooley (kernel.org)][032]
  -  [邮件列表最新动态][014]
  -  [ioremap.c - arch/arc/mm/ioremap.c - Linux source code (v4.8) - Bootlin][003]

## PG_uncached(Kernel Feature)

- 功能：

  ```
  ARCH_USES_PG_UNCACHED
  ```

  > arch supports the PG_uncached page flag

  可以支持对某一页标记未缓存的状态。

  开启该宏后，在 `include/linux/page-flags.h` 路径下的页状态枚举变量中，就会有 PG_uncached，可以对内存页状态标记为未缓存。

  具体的应用场景，需要找到对用该枚举变量的使用的相关代码。

- 状态
  - 社区提交 [[PATCH v3 3/7] mm: Add PG_arch_3 page flag - Peter Collingbourne (kernel.org)][009]
  - **ok**: ia64, x86
  - **TODO**: alpha, arc, arm arm64, csky, hexagon, loong m68k, microblaze, mips nios2, openrisc, parisc powerpc, riscv, s390, sh sparc, um, xtensa

- 资料

  -  [[PATCH v3 3/7] mm: Add PG_arch_3 page flag - Peter Collingbourne (kernel.org)][009]
  -  [邮件列表最新动态][016]
  -  [Linux 內存描述之內存頁面 page--Linux 內存管理（四） - 开发者知识库 (itdaan.com)][028]

## 小结

本文针对内核文档中的 RISC-V 架构下需要做的内核功能进行了梳理，很多功能的资料非常的稀少，是一些前沿的技术，我根据有限的信息结合自己的理解，对功能进行了概述，做这篇文章的最大困难在于很多的应用场景找不到，导致对于功能的理解不到位，希望大家能够在后面找到各个功能的应用场景，进一步的对功能进行剖析，然后在 RISC-V 架构上进行实现，早日实现为 Linux 社区提交补丁的目标！

## 参考资料

- [Feature status on RISC-V architecture — The Linux Kernel documentation (siqueira.tech)][026]

[001]: https://blog.51cto.com/u_15015138/2554269
[002]: https://blog.csdn.net/weixin_42492218/article/details/123568548
[003]: https://elixir.bootlin.com/linux/v4.8/source/arch/arc/mm/ioremap.c#L45
[004]: https://gitee.com/link?target=https%3A%2F%2Flore.kernel.org%2Fall%2F20220701142310.2188015-1-glider%40google.com%2F
[005]: https://gitee.com/link?target=https%3A%2F%2Flore.kernel.org%2Fall%2F%3Fq%3DKMSAN%2B-Re%3A
[006]: https://linux.kernel.narkive.com/lyq4OE2m/patch-3-6-mm-defer-tlb-flush-after-unmap-as-long-as-possible
[007]: https://lore.kernel.org/all/20220418171205.2413168-1-jcmvbkbc@gmail.com/
[008]: https://lore.kernel.org/all/20220728063120.2867508-2-npiggin@gmail.com/
[009]: https://lore.kernel.org/all/20220810193033.1090251-4-pcc@google.com/
[010]: https://lore.kernel.org/all/44d9f65f-52d1-fb0b-b523-7a930a368c46@iscas.ac.cn/
[011]: https://lore.kernel.org/all/d2f76c148fa039d2dea404c03e5fcd2f3dbf3750.1641659630.git.luto@kernel.org/
[012]: https://lore.kernel.org/all/?q=batch-unmap-tlb-flush
[013]: https://lore.kernel.org/all/?q=huge-vmap
[014]: https://lore.kernel.org/all/?q=ioremap_prot
[015]: https://lore.kernel.org/all/?q=membarrier-sync-core
[016]: https://lore.kernel.org/all/?q=PG_uncached
[017]: https://lore.kernel.org/all/?q=queued-spinlocks
[018]: https://lore.kernel.org/all/?q=user-ret-profiler
[019]: https://lore.kernel.org/all/?q=virt-cpuacct&r
[020]: https://lore.kernel.org/all/tip-5d5cd30e6a897fead07639d9684e9c6910e2527c@git.kernel.org/
[021]: https://lore.kernel.org/all/YwspB8OP8%2FPhv+tO@li-4a3a4a4c-28e5-11b2-a85c-a8d192c6f089.ibm.com/
[022]: https://lore.kernel.org/lkml/1635858706-27320-1-git-send-email-jianhua.ljh@gmail.com/
[023]: https://lore.kernel.org/lkml/?q=optprobes+-Re%3A
[024]: https://lwn.net/Articles/839107/
[025]: https://patchwork.kernel.org/project/kvm/patch/1258373983-8693-2-git-send-email-avi@redhat.com/
[026]: https://siqueira.tech/doc/drm/riscv/features.html
[027]: https://www.cntofu.com/book/104/SyncPrim/sync-2.md
[028]: https://www.itdaan.com/tw/6f054b10b4b18604c4eac59346539f4f
[029]: https://zhuanlan.zhihu.com/p/143253843
[030]: https://zhuanlan.zhihu.com/p/66971714

[032]: https://lore.kernel.org/linux-riscv/04b2941a-a8c9-76e8-3189-76c51b811174@microchip.com/
[033]: https://lore.kernel.org/linux-riscv/20220831041014.1295054-1-chenguokai17@mails.ucas.ac.cn/
[034]: https://lore.kernel.org/linux-riscv/?q=optprobes
