---
layout: post
author: 'tjytimi'
title: 'multi-gen lru 官方文档翻译'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /translation-multi-gen-lru-design-documentation/
description: 'multi-gen lru 官方文档翻译'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - MGLRU
---

> Corrector:  [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces header codeinline]
> Title:      [Multi-Gen LRU](https://docs.kernel.org/mm/multigen_lru.html)
> Author:     Yu Zhao <yuzhao@google.com>
> Translator: Jinyu Tang <tjytimi@163.com>
> Date:       2023/01/03
> Revisor:    lzufalcon <falcon@tinylab.org>
> Project:    [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:    PLCT Lab, ISCAS


## 多代 LRU（Multi-Gen LRU）

> The multi-gen LRU is an alternative LRU implementation that optimizes page reclaim and improves performance under memory pressure. Page reclaim decides the kernel's caching policy and ability to overcommit memory. It directly impacts the kswapd CPU usage and RAM efficiency.

多代 LRU 是一种替代的 LRU 实现，它可以优化页面回收，并能在内存压力下提高性能。页面回收决定了内核的缓存策略，也决定了内核过载使用内存的能力。它直接影响 kswapd 内核线程的 CPU 占用率和 RAM 的利用效率。

## 设计概述（Design overview）

### 目标（Objectives）

> The design objectives are:
> * Good representation of access recency
> * Try to profit from spatial locality
> * Fast paths to make obvious choices
> * Simple self-correcting heuristics

设计目标是：

* 很好的表示页面访问的最近性
* 尝试从空间位置中获利
* 对明显的选择具有快速路径
* 使用简单自校正启发式机制

> The representation of access recency is at the core of all LRU implementations. In the multi-gen LRU, each generation represents a group of pages with similar access recency. Generations establish a (time-based) common frame of reference and therefore help make better choices, e.g., between different memcgs on a computer or different computers in a data center (for job scheduling).

访问最近性的表示是所有 LRU 实现的核心。在多代 LRU 中，每一代都代表一组具有相似访问最近性的页面。“代”建立了（基于时间的）公共参考框架，因此有助于做出更好的选择，例如，在内存回收在一台计算机上的不同 memcgs 之间或数据中心的不同计算机之间（作业调度）的场景。

> Exploiting spatial locality improves efficiency when gathering the accessed bit. A rmap walk targets a single page and does not try to profit from discovering a young PTE. A page table walk can sweep all the young PTEs in an address space, but the address space can be too sparse to make a profit. The key is to optimize both methods and use them in combination.

利用空间局部性提高了收集访问位时的效率。rmap 遍历以单个页面为目标，不会试图从发现一个年轻的 PTE 中获利。页表遍历可以扫描地址空间中的所有的年轻 PTE，但这种方式由于地址空间太稀疏导致无法获利。所以问题的关键是优化这两种方法并将其结合使用。

> Fast paths reduce code complexity and runtime overhead. Unmapped page do not require TLB flushes; clean pages do not require writeback.
These facts are only helpful when other conditions, e.g., access recency, are similar. With generations as a common frame of reference, additional factors stand out. But obvious choices might not be good choices; thus self-correction is necessary.

快速路径减少了代码复杂性和运行时开销。如：未映射页面不需要 TLB 刷新；干净的页面不需要回写。
这些事实只有在其他条件，如访问最近性，相似时才有用。以“代”为共同参照系，其他因素能够显现（译者注：这里的意思是“代”为参考的设计保证了访问最近性在相同“代”里相似，从而确保了快速路径有效）。但显而易见的选择（译者注：快速路径做出的经验选择）可能不是好的选择；因此需要自校正。

> The benefits of simple self-correcting heuristics are self-evident.Again, with generations as a common frame of reference, this becomes attainable. Specifically, pages in the same generation can be categorized based on additional factors, and a feedback loop can statistically compare the refault percentages across those categories and infer which of them are better choices.

简单自校正的启发法的好处不言自明。同样，以“代”为共同参照系，这种算法是可实现的。具体来说，同一代中的页面可以根据其他因素进行分类，反馈回路可以统计比较这些类别中 refault 的百分比并推断出哪些是更好的选择。（译者注：refault 是指已经被回收的页，再次发生缺页异常，说明可能回收的选择需要调整）

## 假定（Assumptions）

> The protection of hot pages and the selection of cold pages are based on page access channels and patterns. There are two access channels:
> * Accesses through page tables
> * Accesses through file descriptors
> The protection of the former channel is by design stronger because:
> 1. The uncertainty in determining the access patterns of the former channel is higher due to the approximation of the accessed bit.
> 2. The cost of evicting the former channel is higher due to the TLB flushes required and the likelihood of encountering the dirty bit.
> 3. The penalty of underprotecting the former channel is higher because applications usually do not prepare themselves for major page faults like they do for blocked I/O. E.g., GUI application commonly use dedicated I/O threads to avoid blocking rendering threads.

热页面的保护和冷页面的选择基于页面访问通道和模式。有两个访问通道：
* 通过页表访问
* 通过文件描述符访问（译者注：即 `read()`，`write()` 读写文件描述符访问页面，这种方式并没有通过页表对 page cache 进行映射，而是复制 page cache 再映射复制的页。这里通过文件描述符访问就是指访问 page cache 对应的页面。实际上 `read()`，`write()` 函数的 `buf` 参数对应的内存页是通过页表访问的）前一个方式需要更强的设计，因为：
1. 由于访问位是近似的，确定页表访问的访问模式的不确定性更高。
2. 由于所需的 TLB 刷新和遇到脏位的可能性，回收通过页表访问的页成本更高。
3. 页表访问的页保护不足的代价更大，因为应用程序通常不会像处理阻塞 I/O 那样为缺页异常做好准备。例如，GUI 应用程序通常使用专用 I/O 线程来避免阻塞渲染线程。

> There are also two access patterns:
> * Accesses exhibiting temporal locality
> * Accesses not exhibiting temporal locality

还有两种访问模式：
* 体现时间局部性的访问
* 不体现时间局部性的访问

> For the reasons listed above, the former channel is assumed to follow the former pattern unless `` VM_SEQ_READ `` or `` VM_RAND_READ `` is present, and the latter channel is assumed to follow the latter pattern unless outlying refaults have been observed

由于上面列出的原因，假设前一个信道遵循前一个模式，除非出现 “VM_SEQ_READ” 或 “VM_RAND_READ” 访问标识。并且假设后一个信道遵守后一种模式，除非观察到外部 refaults。（译者注：也就是说通过文件描述符访问文件页时，不经过页表，所以无法通过 ACCESSD 位来体现时间局部性）

## 工作流概述（Workflow overview）

> Evictable pages are divided into multiple generations for each `` lruvec ``. The youngest generation number is stored in `` lrugen->max_seq `` for both anon and file types as they are aged on an equal footing. The oldest generation numbers are stored in `` lrugen->min_seq[] `` separately for anon and file types as clean file pages can be evicted regardless of swap constraints. These three variables are monotonically increasing.

对于每个 "lruvec"，可收回页面分为多个“代”。对于匿名和文件类型，最年轻的“代”存储在 "lrugen->max_seq" 中，因为它们处于相同地位。最老的“代”分别存储在 "lrugen->min_seq[]" 中，分别用于匿名和文件类型，因为无论交换约束如何，都可以清除干净的文件页（译者注：最老的代号，是按照类型分别存在不同的数组元素中，因为匿名页是否能够被换出还取决于 swap constraints，所以要做区分）。这三个变量都是单调增加的。

> Generation numbers are truncated into `` order_base_2(MAX_NR_GENS+1) `` bits in order to fit into the gen counter in `` folio->flags ``. Each truncated generation number is an index to `` lrugen->lists[] ``. The sliding window technique is used to track at least `` MIN_NR_GENS `` and at most `` MAX_NR_GENS `` generations. The gen counter stores a value within `` [1, MAX_NR_GENS] `` while a page is on one of `` lrugen->lists[] ``; otherwise it stores zero.

代号被截断为 "order_base_2（MAX_NR_GENS+1）" 位，以适应 "folio->flags" 中的代计数器。每个截断的代都是 "lrugen->lists[]" 的索引（译者注：这里的截断是指会取模，比如代数是 7，MAX_NR_GENS 为 4，7 mod 4 = 3，那索引就是 3）。滑动窗口技术用于跟踪至少 "MIN_NR_GENS" 和最多 "MAX_NR_GENS" 代。当页面位于 "lrugen->lists[]" 中时，就在 "folio->flags" 代计数器中存储一个 [1，MAX_NR_GENS] 内的值；否则它存储零。（译者注：为什么存在 flags 中的代要从 1 开始而不是从 0 开始？因为 flag 对应位初始化的时候是 0，这样通过是否为 0 就可以判断页是否在 muti-lru list 中）

> Each generation is divided into multiple tiers. A page accessed `` N `` times through file descriptors is in tier `` order_base_2(N) ``. Unlike generations, tiers do not have dedicated `` lrugen->lists[] ``. In contrast to moving across generations, which requires the LRU lock, moving across tiers only involves atomic operations on `` folio->flags `` and therefore has a negligible cost. A feedback loop modeled after the PID controller monitors refaults over all the tiers from anon and file types and decides which tiers from which types to evict or protect.

每一代都分为多个层次。通过文件描述符访问 "N" 次的页面位于层 "order_base_2（N）" 中。与代不同，层没有专用的 "lrugen->list[]"。与需要 LRU 锁的跨代移动不同，跨层移动只涉及 "folio->flags" 上的原子操作，因此成本可忽略不计。在 PID 控制器之后的反馈回路模型用来监控来自匿名和文件类型的所有层的 refaults，并决定从哪些类型中逐出或保护哪些层。

> There are two conceptually independent procedures: the aging and the eviction. They form a closed-loop system, i.e., the page reclaim.

有两个概念上独立的过程：老化和驱逐。它们形成一个闭环系统，即页面回收。

### 老化（Aging）

> The aging produces young generations. Given an `` lruvec ``, it increments `` max_seq `` when `` max_seq-min_seq+1 `` approaches `` MIN_NR_GENS ``. The aging promotes hot pages to the youngest generation when it finds them accessed through page tables; the demotion of cold pages happens consequently when it increments `` max_seq ``. The aging uses page table walks and rmap walks to find young PTEs. For the former, it iterates `` lruvec_memcg()->mm_list `` and calls `` walk_page_range() `` with each `` mm_struct `` on this list to scan PTEs, and after each iteration, it increments `` max_seq ``. For the latter, when the eviction walks the rmap and finds a young PTE, the aging scans the adjacent PTEs. For both, on finding a young PTE, the aging clears the accessed bit and updates the gen counter of the page mapped by this PTE to `` (max_seq%MAX_NR_GENS)+1 ``.

老化产生年轻一代。给定 "lruvec"，当 "max_seq - min_seq+1" 接近 "min_NR_GENS" 时，它递增 "max_seq"。当发现通过页表访问页时，老化会将热页提升到最年轻的一代；与此同时，递增 "max_seq" 会发生冷页降级。（译者注：最年轻的代数变大的，原本的冷页离的更远，当然就降级了）老化使用页表遍历和 rmap 遍历来查找年轻 PTE。对于页表遍历，它迭代 "lruvec_memcg（）->mm_list"，并调用 `` walk_page_range（）`` 和该链表上的每个 `` mm_struct `` 来扫描 PTE，每次迭代后，它都递增 "max_seq"。对于 rmap 遍历，当驱逐流程 rmap 遍历并发现一个年轻的 PTE 时，老化扫描相邻的 PTE。对于这两种情况，在找到一个年轻的 PTE 时，老化会清除页表的访问位，并将此 PTE 映射的页面的代计数器更新为 "（max_seq%max_NR_GENS）+1"。（译者注：（max_seq%max_NR_GENS）+1 就是最年轻的一代）

### 驱逐（Eviction）

> The eviction consumes old generations. Given an `` lruvec ``, it increments `` min_seq `` when `` lrugen->lists[] `` indexed by `` min_seq%MAX_NR_GENS `` becomes empty. To select a type and a tier to evict from, it first compares `` min_seq[] `` to select the older type.If both types are equally old, it selects the one whose first tier has a lower refault percentage. The first tier contains single-use unmapped clean pages, which are the best bet. The eviction sorts a page according to its gen counter if the aging has found this page accessed through page tables and updated its gen counter. It also moves a page to the next generation, i.e., `` min_seq+1 ``, if this page was accessed multiple times through file descriptors and the feedback loop has detected outlying refaults from the tier this page is in. To this end, the feedback loop uses the first tier as the baseline, for the reason stated earlier.

驱逐消耗老的一代。给定 "lruvec"，当由 "min_seq%MAX_NR_GENS" 索引的 "lrugen->lists[]" 变为空时，它将增加 "min_seq"。当选择一种类型和一个要退出的层时，首先比较 "min_seq[]" 以选择较旧的类型（译者注：选择匿名页或者文件页两种类型）。如果两种类型都相同，则选择第一层的 refault 百分比较低的类型。第一层包含一次性未映射的干净页面，这是最好的选择。如果老化机制发现该页面通过页表访问，并更新了其代计数器，则驱逐机制将根据其代计数器对页面进行排序。如果通过文件描述符多次访问该页面，并且反馈回路检测到该页面所在层的外部 refaults，则它还会将页面移动到下一代，即 “min_seq+1”。为了这个目的，反馈回路使用第一层作为基线，原因如上所述。

## 总结(Summary)

> The multi-gen LRU can be disassembled into the following parts:
> * Generations
> * Rmap walks
> * Page table walks
> * Bloom filters
> * PID controller

多代 LRU 可分解为以下部件：

* 代
* Rmap 遍历
* 页表遍历
* Bloom 过滤器
* PID 控制器

> The aging and the eviction form a producer-consumer model;specifically, the latter drives the former by the sliding window over generations. Within the aging, rmap walks drive page table walks by inserting hot densely populated page tables to the Bloom filters.Within the eviction, the PID controller uses refaults as the feedback to select types to evict and tiers to protect.

老化和驱逐形成了生产者-消费者模型；具体而言，驱逐机制通过代的滑动窗口驱动老化机制。在老化过程中，rmap 遍历通过向 Bloom 过滤器插入热密度填充的页表来驱动页表遍历。在逐出过程中，PID 控制器使用 refaults 作为反馈，用来选择要逐出的类型和要保护的层。

## 参考资料

1. [Multi-Gen LRU][1]

[1]: https://docs.kernel.org/mm/multigen_lru.html
