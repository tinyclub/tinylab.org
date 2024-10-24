---
layout: post
author: 'Yixun Lan'
title: 'LWN 867818: 将不再那么匿名的虚拟内存域'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /not-so-anonymous-virtual-memory-areas/
description: 'LWN 867818: 将不再那么匿名的虚拟内存域'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
---

> Title:      [Not-so-anonymous virtual memory areas](https://lwn.net/Articles/867818/)
> Author:     Jonathan Corbet@**September 3, 2021**
> Date:       2022/06/18
> Translator: Yixun Lan <yixun.lan@gmail.com>
> Revisor:    Falcon <falcon@tinylab.org>
> Project:    [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor: PLCT Lab, ISCAS


> Computing terminology can be counterintuitive at times, but even a longtime participant in the industry may have to look twice at the notion of named anonymous memory.  That, however, is just the concept that [this patch set][1] posted by Suren Baghdasaryan proposes to add.  There are, it seems, developers who find the idea useful enough to not only overcome the initial cognitive dissonance that comes with it, but also to resurrect an eight-year-old patch to get it into the kernel.

计算术语有时会是反直觉的，即使是该产业界的长期从业者也可能不得不重新审视 "有名称的匿名内存" 的概念。 然而，这也恰好是 Suren Baghdasaryan 发布的[这个补丁][1]所提出的概念。 并且，一些开发人员还会觉得这个想法非常有价值，因为不仅克服了伴随而来的最初的认知偏差，还重新激活一个已经提交了 8 年之久的补丁，并有望将其并入内核（译者注：这个补丁已经被官方内核所合入）。


 > Memory used by user space is divided into two broad categories: file-backed and anonymous.  A file-backed page of memory has a direct correspondence to a page in a file in persistent storage; when the page is clean, its contents are identical to what is found on disk.  An anonymous page, instead, is not associated with a file in the filesystem; these pages hold a process's data areas, stacks, and so on.  If an anonymous page must be written to persistent storage (to reclaim the page for another user, usually), space must be allocated in the swap area to hold its contents.

用户空间使用的内存分为两大类：基于文件的内存和匿名内存。 基于文件的一个内存页会直接对应到磁盘存储器中的文件的一个页； 当页面没有被写入时，其内容与磁盘存储器上的页里的内容相同。相对的，匿名页就不会与文件系统中的文件相关联；这些匿名页面包括了进程的数据区、栈等。 如果必须将要匿名页写入磁盘存储器中（通常是回收页面，给其他用户所使用），则必须在交换分区中也分配数量相等的空间来保存这些匿名页的内容。

> Whether a given process's memory use is dominated by file-backed or anonymous pages varies from one workload to the next.  In many cases, the bulk of a  process's pages will be anonymous; this, it seems, is more likely in workloads with a lot of cloud-computing clients, which tend not to use many local files.  Android devices are one place where this sort of behavior can be found.  If one is trying to optimize the memory usage of such a workload, anonymous pages can pose a challenge; since the pages are anonymous, with no information about how they were created, it is difficult to know what any given anonymous page is being used for.

在一个特定进程中，内存占用绝对主导的对象到底是基于文件的内存页，还是匿名内存页，在不同负载工作下是不一样的。 在许多情况下，进程的大部分内存页都是匿名页； 这也似乎更普便的存在于倾向于不使用许多本地文件的带有大量云计算负载类型的客户端中。 安卓的设备就是有上述类似情况的一个典型例子。 如果有人想尝试优化此类工作负载的内存使用情况，那么匿名页将带来巨大挑战； 由于这些内存页是匿名的，没有任何信息可描述他们是如何建立出来的，因此也就很难知道一个给定的匿名内存页所对应的用途。

> That situation can be improved by making anonymous pages just a bit less anonymous.  If it were possible to know which user-space subsystem or library created  a given page, it would become easier to figure out who the biggest users are.  Information on, say, how many anonymous pages in the system were created by the [jemalloc library][2], for example, could help determine whether jemalloc users are the best target for optimization efforts.  Linux systems, however, do not make it easy (or even possible) to get that sort of information.
 Making things better requires obtaining some cooperation from user space, since the kernel cannot know which subsystem is allocating any given page. To that end, at the core of the patch set is [this patch from Colin Cross][3], which was [originally posted in 2013][4].  It adds a new [prctl()][5] operation:

上述这种情况其实可以通过减少匿名内存页的匿名性来改善。 如果有可能知道哪个应用空间的子系统或库创建了一个指定的内存页，则就能更加容易找出谁是最大的内存使用者。例如，能查看到系统中有多少匿名页面是由 [jemalloc 库][2]创建的这种信息，就可以帮助我们确定 `jemalloc` 的使用者是否可以作为内存优化工作的最佳目标。 然而， `Linux` 系统并不容易（有时甚至不可能）获得这类信息。想让事情得到改善就需要从用户空间得到一些配合，因为内核无法知道哪个子系统所对应分配指定的内存页。 为此目的，当前这个补丁的核心思路就是来源于 [Colin Cross 的补丁][3]，[它最初发布于 2013 年][4]。它引入了一个新的 `prctl()` [调用][5]：

>
> ```
>     prctl(PR_SET_VMA, PR_SET_VMA_ANON_NAME, start, len, name);
> ```

> This operation will cause the given name to be associated with the len anonymous pages beginning at start.  In truth, the name is  associated with the virtual memory area (VMA) structure describing a range of memory.  Thus, what actually happens is that all pages that are part of the VMAs in the given range will have the name assigned to them, even if the pages themselves are not within that range.  Each mmap() call usually creates a VMA (though there are complications), so all pages associated with any given VMA will normally have been created in the same way.

这个调用将使指定的名字 `name` 与起始地址为 `start` 长度为的 `len` 对应的匿名内存页相关联起来。实际上，该名字会与描述内存范围的虚拟内存区域 (`VMA`) 结构相关联。 因此，实际发生的情况是，在给定范围内属于 `VMA` 的所有页面都将获得相同的预先分配给它们的名字，即使页面本身不在该范围内。 每个 `mmap()` 调用通常都会创建一个 `VMA` （尽管这很复杂），因此与任何给定 `VMA` 关联的所有内存页都会以相同的方式被创建出来。

> The maps and smaps files in each process's /proc directory already contain a lot of information about that process's VMAs. With this patch set applied, those files will also contain the name that has been associated with the anonymous VMAs, if any; the name is duly checked for printability before being accepted.  Using that information, system tools can associate pages with those names and, from there, with the subsystems that created them.

每个进程的 `/proc` 目录下的 `maps` 和 `smaps` 文件包含了有关该进程的 `VMA` 的大量信息。 应用上此补丁后，这些文件还将添加一个与匿名 `VMA` 关联的名字（假设这个名字存在的话）； 当然了，该名字在被接受之前，会做一些检查，比如是否符合打印的格式化。 系统工具可以通过这个信息将内存页与这些名字相关联起来，从而也能找到对应的创建这些匿名内存的子系统。

> Assigning a name to a VMA does not seem like a difficult endeavor, but it has proved to be the trickiest part of this patch.  A system can have a lot of processes, each of which can have a lot of VMAs, so the management of these names needs to scale reasonably well.  Previous versions of the patch set have tried just pointing to the provided names in user space; this avoids the need to allocate memory in the kernel but, as [Kees Cook pointed out][6], it presents some interesting security problems as well.  At the time, Cook suggested simply copying the strings into kernel space.

为 VMA 分配一个名字似乎并不困难，但事实证明它是这个补丁中最棘手的部分。一个系统可以有很多进程，每个进程都可以有很多 `VMA`，因此管理这些名字需要做到高度可扩展化。先前版本的补丁尝试仅用指针的方式指向用户空间提供的名字； 这避免了需要从内核里分配内存，但也正如 [Kees Cook 指出][6]的那样，它也带来了一些有明显的安全问题。 在当时，为了应对这个问题， Cook 建议单纯地将字符串复制到内核空间。

> While copying the strings  works, there is still a little problem: when a process forks, its VMAs  are copied for the new child.  Now all of those name strings must be copied too.  Baghdasaryan ran a worst-case test, with a process creating 64,000 VMAs, assigning a long name to each, then calling fork(), the result was a nearly 40% performance regression.  Even if such numbers will not be seen in real-world workloads, a slowdown of that magnitude is sure to raise eyebrows.

虽然复制字符串有效，但仍有一个小问题：当一个进程被复制时，它的 `VMA` 会被复制给新的子进程。 现在所有这些名字的字符串也必须被复制过去。 Baghdasaryan 进行了最坏情况测试，一个进程创建了64,000 个 `VMA` ，为每个 `VMA` 分配一个长名字，然后调用 `fork()`，结果是性能下降了近 40%。 即使在现实世界的工作负载中看不到这样的情况，但这种幅度的性能下降也一定会引起人们的注意。

> As a way of avoiding excessive eyebrow elevation, [Baghdasaryan added a mechanism][7] to use shared, reference-counted names.  A fork() call now need only increase the reference counts rather than allocate memory and copy a string.  With this added machinery in place, the performance cost is "reduced 3-4x" in the worst case, and is said to not be measurable for more reasonable test cases.

为了避免受到过多的抱怨，[Baghdasaryan 添加了一种使用共享的、引用计数的机制][7]（译者注：用于解决名字占用内存空间过多的问题）。当执行 `fork()` 调用时，现在的方案只需要增加引用计数，而不是重新分配内存和复制字符串。随着这个机制的引入，在最坏的情况下性能开销也能降低到原来的 1/3-1/4，据说对于更加合理的测试用例几乎观察不出来性能的降低。

> This functionality is evidently useful; Android has been using it for years, having kept the original patch going for all of that time.  Thus far, the review comments have focused on relatively minor issues — which characters should be allowed in names, for example.  So there would not appear to be a lot of obstacles to overcome before this work can be merged.  For this feature, it seems, eight years of waiting on the sidelines should be enough, and anonymous pages may soon lose a bit of their anonymity.

这个功能显然是非常有用的； 安卓平台多年来一直在使用它，并且原始补丁也一直被沿用下来。到目前为止，审查，反馈意见都集中在相对较小的问题上 —— 例如，哪些字符在名字中是应该被允许的。因此，这项补丁在合并之前似乎并没有很多障碍需要克服。为了这项功能，似乎八年时间的等待实在是足够了。在可预见的将来，匿名内存页也很可能会失去一点点他们的匿名性了。


[1]: https://lwn.net/ml/linux-kernel/20210827191858.2037087-1-surenb@google.com/
[2]: https://github.com/jemalloc/jemalloc
[3]: https://lwn.net/ml/linux-kernel/20210827191858.2037087-3-surenb@google.com/
[4]: https://lore.kernel.org/linux-mm/1383170047-21074-2-git-send-email-ccross@android.com/
[5]: https://man7.org/linux/man-pages/man2/prctl.2.html
[6]: https://lwn.net/ml/linux-mm/202009031031.D32EF57ED@keescook/
[7]: https://lwn.net/ml/linux-kernel/20210827191858.2037087-4-surenb@google.com/
