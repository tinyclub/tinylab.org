---
layout: post
author: 'Li Yupeng'
title: "LWN 240474: CFS组调度"
album: 'LWN 中文翻译'
group: translation
permalink: /lwn-240474-cfs-group-scheduling/
description: "LWN 文章翻译，进程调度，CFS组调度"
category:
  - 进程调度
  - LWN

tags:
  - Linux
  - processes schedule
  - CFS group schduling
---

> 原文：[CFS group scheduling](https://lwn.net/Articles/240474/)
> 原创：By Corbet @ July 2, 2007
> 翻译：By Unicornx of [TinyLab.org][1] @ 2017-10-10 05:26:32


> Ingo Molnar's [completely fair scheduler][2] (CFS) patch continues to develop; the current version, as of this writing, is [v18][3]. One aspect of CFS behavior is seen as a serious shortcoming by many potential users, however: it only implements fairness between individual processes. If 50 processes are trying to run at any given time, CFS will carefully ensure that each gets 2% of the CPU. It could be, however, that one of those processes is the X server belonging to Alice, while the other 49 are part of a massive kernel build launched by Karl the opportunistic kernel hacker, who logged in over the net to take advantage of some free CPU time. Assuming that allowing Karl on the system is considered fair at all, it is reasonable to say that his 49 compiler processes should, as a group, share the processor with Alice's X server. In other words, X should get 50% of the CPU (if it needs it) while all of Karl's processes share the other 50%.

Ingo Molnar的完全公平调度算法(completely fair scheduler,CFS)的补丁不断演变，到现在为止，完全公平调度算法的补丁已经迭代到v18。对于许多潜在的用户来说，CFS依然存在一个看似严重的缺陷。然而，完全公平调度算法只实现了独立进程间的平衡。比如，如果系统中任意时刻都有50个可运行的进程，那么CFS将会小心地保证这些进程分别都得到2%的CPU资源。但是，这些进程中有一个进程是X server进程，它属于用户Alice；其他49个进程是大规模内核构建的一部分，是由投机取巧的内核黑客karl发起的，他通过网络登录来利用一些空闲的CPU时间。假设系统允许Karl完全公平地共享资源，那么可以合理地说他的49个编译器进程作为一个整体，应该与用户Alice的X server进程共享CPU资源。换句话说，X应该得到50％的CPU（如果需要的话），而所有的Karl的进程共享另外50％的CPU。


> This type of scheduling is called "group scheduling"; Linux has never really supported it with any scheduler. It would be nice if a "completely fair scheduler" to be merged in the future had the potential to be completely fair in this regard too. Thanks to work by Srivatsa Vaddagiri and others, things may well happen in just that way.

这种新的调度方式称为“组调度”。 Linux之前没有真正支持过任何调度算法。如果将来“完全公平的调度算法”合并到Linux主线，并且在“组调度”方面也是完全公平的，那将是很好的。感谢Srivatsa Vaddagiri和其他人的工作，这些改变可能即将发生。

> The first part of Srivatsa's work was merged into v17 of the CFS patch. It creates the concept of a "scheduling entity" - something to be scheduled, which might not be a process. This work takes the per-process scheduling information and packages it up within a sched_entity structure. In this form, it is essentially a cleanup - it encapsulates the relevant information (a useful thing to do in its own right) without actually changing how the CFS scheduler works.

Srivatsa的第一部分的工作已经合并到CFS补丁的v17。在这一部分的工作中，Srivatsa创造了“调度实体”（scheduling entity）的概念用来表示将要被调度的实体，但不一定指的是单个进程。调度实体的作用是提取每个进程的调度信息并包装到“sched\_entity”结构中。在这种形式下，它本质上是一种信息隐藏的方式——它封装了相关调度信息（本身是一件有用的事情），而事实上并没有改变CFS调度器的工作方式。

> Group scheduling is implemented in [a separate set of patches][4] which are not yet part of the CFS code. These patches turn a scheduling entity into a hierarchical structure. There can now be scheduling entities which are not directly associated with processes; instead, they represent a specific group of processes. Each scheduling entity of this type has its own run queue within it. All scheduling entities also now have a parent pointer and a pointer to the run queue into which they should be scheduled.

另一组的补丁单独实现”组调度“（Group scheduling）机制。到现在为止，这组补丁还没有合并到CFS代码中。这组补丁将调度实体转换为层级结构(hierarchical structure)。现在系统中存在与进程没有直接关联的调度实体，这些调度实体是代表特定的进程组。这种类型的调度实体都有自己的运行队列。所有的调度实体都有一个父指针和一个指向自己本身的运行队列的指针。

> By default, processes are at the top of the hierarchy, and each is scheduled independently. A process can be moved underneath another scheduling entity, though, essentially removing it from the primary run queue. When that process becomes runnable, it is put on the run queue associated with its parent scheduling entity.

默认情况下，所有的进程都位于这个层级结构的顶部，并且每个进程都是独立调度的。进程既可以移动到另一个调度实体之下，其本质上是从主运行队列中移除。当某个进程的状态变成可运行状态时，它被添加至其父调度实体关联的运行队列中。


> When the scheduler goes to pick the next task to run, it looks at all of the top-level scheduling entities and takes the one which is considered most deserving of the CPU. If that entity is not a process (it's a higher-level scheduling entity), then the scheduler looks at the run queue contained within that entity and starts over again. Things continue down the hierarchy until an actual process is found, at which point it is run. As the process runs, its runtime statistics are collected as usual, but they are also propagated up the hierarchy so that its CPU usage is properly reflected at each level.

当CFS调度器选择下一个将要运行的任务时，它先查看层级结构顶层的所有的调度实体，选出被认为最期望得到CPU运行时间的调度实体；如果该实体不是表示单个进程（它是一个更高级的调度实体），那么CFS调度器将查看该调度实体中包含的运行队列，接着从这个运行队列中选出最期望得到CPU的调度实体；继续寻找下去，直至找到一个表示单个进程的调度实体，这个进程就是下一个将要运行的进程。在这个进程运行时，其运行时间统计信息将按照常规方式进行收集，但也会在这个层次结构中传播，以便在每个层都正确地反映其CPU使用情况（注1）。

> So now the system administrator can create one scheduling entity for Alice, and another for Karl. All of Alice's processes are placed under her representative scheduling entity; a similar thing happens to all of the processes in Karl's big kernel build. The CFS scheduler will enforce fairness between Alice and Karl; once it decides who deserves the CPU, it will drop down a level and perform fair scheduling of that user's processes.

所以，现在系统管理员可以分别为用户Alice和用户Karl创建各自的调度实体。 Alice的所有进程都放在代表他的调度实体之下，同样，Karl的所有的内核构建进程也都放在代表他的调度实体之下。CFS调度器将强化Alice和Karl之间的公平性; 一旦决定了谁应得的CPU，CFS调度器就会下降一层并对该用户的所有进程依照公平调度算法执行调度。

> The creation of the process hierarchy need not be done on a per-user basis; processes can be organized in any way that the administrator sees fit. The grouping could be coarser; for example, on a university machine, all students could be placed in one group and faculty in another. Or the hierarchy could be based on the type of process: there could be scheduling entities representing system daemons, interactive tools, monster cranker CPU hogs, etc. There is nothing in the patch which limits the ways in which processes can be grouped.


进程层级结构的创建不需要在每个用户的基础上完成; 所有进程可以以管理员认为合适的任何方式进行组织。这样的分组方式可能显得比较粗糙。例如，在大学组织中，所有的学生可以被安置在一个组中，而教师被分到另一个组中。或者，层次结构可以基于进程的类型分组：可以有表示系统守护进程，交互工具，monster cranker CPU等等的调度实体。补丁中没有任何规定限制进程分组的方式。

> One remaining question might be: how does the system administrator actually cause this grouping to happen? The answer is in the second part of the group scheduling patch, which integrates scheduling entities with the [process container][5] mechanism. The administrator mounts a container filesystem with the cpuctl option; scheduling groups can then be created as directories within that filesystem. Processes can be moved into (and out of) groups using the usual container interface. So any particular policy can be implemented through the creation of a simple, user-space daemon which responds to process creation events by placing newly-created processes in the right group.

还剩下的一个问题可能是：系统管理员如何真实进行分组操作？ 答案在组调度补丁的第二部分。这部分将调度实体与进程容器机制集成在一起。管理员用cpuctl选项挂载容器文件系统; 然后通过在该文件系统中创建目录来实现创建调度组（注2）。系统管理者使用容器通用接口将进程从组外移入或组内移出。因此，在用户空间中，系统管理者可以通过创建一个简单的守护进程来实现任何特定的策略，该守护进程通过将新创建的进程置于正确的组中来响应进程创建事件。

> In its current form, the container code only supports a single level of group hierarchy, so a two-level scheme (divide users into administrators, employees, and guests, then enforce fairness between users in each group, for example) cannot be implemented. This appears to be a "didn't get around to it yet" sort of limitation, though, rather than something which is inherent in the code.

在目前的形式下，容器代码只支持层级结构中的单层，因此，两级方案（例如将用户划分为管理员，员工和来宾，然后在每个组的用户之间强制公平）暂时还不能实施。这似乎是一种“没有实现组调度”的限制，而不是代码本身的问题。

> With this feature in place, CFS will become more interesting to a number of potential users. Those users may have to wait a little longer, though. The 2.6.23 merge window will be opening soon, but it seems unlikely that this work will be considered ready for inclusion at that time. Maybe 2.6.24 will be a good release for people wanting a shiny, new, group-aware scheduler.

有了这个功能，对于一些潜在的用户CFS将会变得更加有趣。不过，这些用户可能需要等一段时间。2.6.23合并窗口即将开放，但似乎不太可能将这项工作考虑在内。对于希望有一个闪亮的，新的，组感知调度器的用户来说，也许2.6.24将是一个很好的发布契机。


#### 译者注
- 注1：是由周期调度器(schedule\_tick)实现当前运行进程的运行时间统计。

- 注2：这里提到的容器文件系统现在的实现方式是cgroup虚拟文件系统，进程容器机制现在的实现方式是cgroup中CPU子系统。


[1]: http://tinylab.org
[2]: https://lwn.net/Articles/230574/
[3]: https://lwn.net/Articles/239553/
[4]: https://lwn.net/Articles/239619/
[5]:https://lwn.net/Articles/236038/
