---
layout: post
author: 'Guo Chumou'
title: "LWN 158211: xxx"
album: 'LWN 中文翻译'
group: translation
license: "cc-by-sa-4.0"
permalink: /lwn-159110/
description: "LWN 文章翻译，xxx"
category:
  - 内存子系统
  - LWN
tags:
  - Linux
  - memory
---

> 原文：[More on fragmentation avoidance](https://lwn.net/Articles/159110/)
> 原创：By corbet @ Nov. 8, 2005
> 翻译：By [simowce](https://github.com/simowce) of [TinyLab.org][1]
> 校对：By [xxx](https://github.com/xxx)

> [Last week's article](http://lwn.net/Articles/158211/) on fragmentation avoidance concluded with these famous last words:

[本系列文章的上篇](/lwn-101230/)在最后提到：

>     But there are legitimate reasons for wanting this capability in the kernel, and the issue is unlikely to go away. Unless somebody comes up with a better solution, it could be hard to keep Mel's patch out forever.

    有很多合情合理的理由觉得内核需要这个补丁，同时这个补丁带来的问题也是无法避免的。所以除非有一个人能够想到一个更好的解决方案，不然很难让 Mel 的这个补丁永远不合入。

> One thing which *can* keep a patch out of the kernel, however, is opposition from Linus, and that is what has happened in this case. His [position](https://lwn.net/Articles/159111/) is that fragmentation avoidance is "totally useless," and he concludes:

有一种情况能够让这个补丁不合入到内核中，那就是 Linus 的反对，并且在这件事上他确实这么做了。他的[立场][2]是避免碎片化是“完全没用的”，他如是说：

>     Don't do it. We've never done it, and we've been fine.

    别这么干。我们从来没有这么做过，并且一切安好。

> The right solution, according to Linus, is to create a special memory zone on the (rare) systems which need to be able to free up large, contiguous blocks of memory. Kernel memory allocations would not be allowed in that zone, so it would only contain user-space pages. Those pages are relatively easy to move when the need arises, so most needs would be satisfied. A certain amount of kernel tuning would be required, but that is the price to be paid for running highly-specialized applications.

对于 Linus 来说，正确的解决方案是在那些（少数）需要能够清理出大量物理连续的内存块的系统中创建一个特殊的 zone。这个 zone 中不允许内核态的内存分配，因此只会有用户态的内存页。当物理连续的分配需求增加时，这些内存页相对来说比较容易去移动，因此大部分的需求能够被满足。这个需要一些在内核上的调优，但是这是运行高度专业化软件需要付出的代价。

> This approach is not pleasing to everybody involved. Andi Kleen [noted](https://lwn.net/Articles/159112/):

但是这个方案并没有让所有人满意。Andi Kleen [指出](https://lwn.net/Articles/159112/):

>     You have two choices if a workload runs out of the kernel allocatable pages. Either you spill into the reclaimable zone or you fail the allocation. The first means that the huge pages thing is unreliable, the second would mean that all the many problems of limited lowmem would be back.

    如果当前的负载消耗完内核的可分配内存，你有两个选择。要么把内存分配需求涌向可回收区域，要么这次分配请求将会失败。第一种意味着巨型页是不可靠的，而第二种则意味着那些低内存造成的问题都会暴露出来。

> Others have noted that it can be hard to tune a machine for all workloads, especially on systems with a large number of users. Objections notwithstanding, it begins to look like active fragmentation avoidance is not likely to go into the 2.6 kernel anytime soon.

还有人指出，对一个机器的所有工作负载情况进行调优是非常困难的，特别是那些有大量用户的系统。因此，尽管有很多的异议，但是避免内存碎片的补丁可能不会很快被 2.6 版本的内核合入。


  [1]: http://tinylab.org
  [2]: https://lwn.net/Articles/159111/
