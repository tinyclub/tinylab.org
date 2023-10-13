---
layout: post
draft: false
author: 'Wang Chen'
title: "LWN 80911: xxxx"
album: 'LWN 中文翻译'
group: translation
license: "cc-by-sa-4.0"
permalink: /lwn-428230/
description: "LWN 中文翻译，CFS 带宽控制"
category:
  - 进程调度
  - LWN
tags:
  - Linux
  - schedule
---

**请点击 [LWN 中文翻译计划](/lwn)，了解更多详情。**

> 原文：[Scheduling domains](https://lwn.net/Articles/80911/)
> 原创：By Jonathan Corbet @ Apr. 19, 2004
> 翻译：By [xxx](https://github.com/xxx)
> 校对：By [unicornx](https://github.com/unicornx)

> Back in the 2.6.0-test days, there was a lot of concern that the 2.6 CPU scheduler wasn't up to the task. In particular, performance on higher-end systems - those with hyperthreaded processors, NUMA architectures, etc. - wasn't as good as the developers would have liked. The scheduler front has been quiet for some time, but it has not been forgotten; a set of hackers (including Nick Piggin, Ingo Molnar, Con Kolivas, and Rusty Russell) has been steadily working behind the scenes to improve scheduling in 2.6. The result, broadly known as "scheduling domains," has been evolving in the -mm tree for some time, but this work looks like it is getting close to ready to break into the mainline. So, it would seem that a look at scheduling domains is in order.

回到2.6.0测试的时间，很多人质疑2.6CPU调度器不能按时完成任务。尤其是，在一些高端系统上（拥有超线程，NUMA架构的处理器等等）调度性能并没有达到开发人员的期望。调度器的高层框架已经好久没有更新了，但是并没有被遗忘；一系列黑客(包括**Nick Piggin, Ingo Molnar, Con Kolivas, and Rusty Russell**)一直在幕后工作，以提高2.6内核的调度性能。结果是，广为人知的**“scheduling domains”**被纳入-mm tree中好长时间，但是这些工作看起来已经做好准备并入主线内核中。所以，是时候看一下**scheduling domains**。

> The new scheduler work is a response to the needs of modern hardware and, in particular, the fact that the processors in multi-CPU systems have unequal relationships with each other. Virtual CPUs in a hyperthreaded set share equal access to memory, cache, and even the processor itself. Processors on a symmetric multiprocessing system have equal access to memory, but they maintain their own caches. NUMA architectures create situations where different nodes have different access speeds to different areas of main memory. A modern large system can feature all of these situations: each NUMA node looks like an SMP system which may be made up of multiple hyperthreaded processors.

新的调度器的工作主要是为了满足现代硬件的发展，特别是多CPU中不同的处理器彼此之间有着不平等的关系。在一个超线程集（hyperthread）中，*Virtual CPUs*平等的拥有对内存，cache甚至是处理器本身平等的访问权力。而在SMP（对称多处理器）中，处理器拥有对内存平等的访问权力，但是每一个处理器保留有自己的cache。在NUMA架构中，不同的cpu结点对不同的内存区域有不同的访问速度。一个现代的大型系统中可能同时出现上述的所有情况：每一个NUMA结点看起来像一个由多个超线程处理器组成的SMP系统。

> One of the key problems a scheduler must solve on a multi-processor system is balancing the load across the CPUs. It doesn't do to have some processors being heavily loaded while others sit idle. But moving processes between processors is not free, and some sorts of moves (across NUMA nodes, for example, where a process could be separated from its fast, local memory) are more expensive than others. Teaching the scheduler to migrate tasks intelligently under many different types of loads has been one of the big challenges of the 2.5 development cycle.

在一个多处理器系统中，调度器要解决的核心问题是：平衡不同CPU的负载。不能让一些处理器负载很重而一些处于空闲状态。但是在处理器之间迁移进程是有代价的，一些迁移（跨NUMA结点迁移，此时进程从可以快速访问的本地内存中剥离出去）的代价是很大的。设计调度器以让调度器在许多不同负载之间智能迁移成为了2.5内核开发周期的一个大的挑战。

> The domain-based scheduler aims to solve this problem by way of a new data structure which describes the system's structure and scheduling policy in sufficient detail that good decisions can be made. To that end, it adds a couple of new structures:

基于**domain**的调度器的解决方法主要是设计新的数据结构来详细描述系统的结构（CPU结构）和调度策略，以便调度器做出好的决策。为此，加入了许多新的数据结构。

> - A scheduling domain (struct sched_domain) is a set of CPUs which share properties and scheduling policies, and which can be balanced against each other. Scheduling domains are hierarchical; a multi-level system will have multiple levels of domains.
> - Each domain contains one or more CPU groups (struct sched_group) which are treated as a single unit by the domain. When the scheduler tries to balance the load within a domain, it tries to even out the load carried by each CPU group without worrying directly about what is happening within the group.

- **scheduling domain** (`struct sched_domain`)是一组CPU的集合，这些CPU共享调度属性和调度策略，彼此之间可以互相平衡。这个数据结构是分层的；多层的系统有多个级别的*domain*；
- 每一个*domain*包含一个或者多个**CPU group (`struct sched_group`)**，这个数据结构是被domain当作单独的单元来处理的。当调度器尝试在domain内部平衡时，会尝试平衡每一个**CPU group**而不用担心每一个组内会发生什么情况。

> It's time for your editor to try to explain this structure via a series of cheesy diagrams. Imagine a system with two physical processors, each of which provides two hyperthreaded CPUs. We'll diagram the processors in this way:

现在是时候向读者通过一系列图表解释这个数据结构了，假设一个系统中有两个物理处理器，每一个处理器内部提供有两个超线程CPU。我们会将处理器这样表示：

[Two processors]

> Here, the four hyperthreaded processors are shown bonded together into two physical packages. When this system boots, it will put each pair of processors into a scheduling domain, with a result that might look something like this:

这里，四个超线程处理器被封装成两个物理包。当系统启动之后，kernel会将每一对处理器放到每一个调度域中，这样的结果看起来如下：

[Two domains]

> In this setup, our four processors are gathered into two scheduling domains. Each domain contains two CPU groups, and each group contains exactly one CPU. These domains reflect the fact that, while each CPU appears to be a distinct processor, a pair of hyperthreaded processors has a different relationship internally than with the other processors.

这样设置之后，我们的四个处理器被划分到2个调度域中。每个域包含两个 **CPU groups**,每个group恰好有一个CPU。这些**domain**的划分表述了这些事实：每一个CPU看起来像一个单独的处理器，一对超线程处理器和其它处理器对比，在内部有不同的关系。

> This system will have a two-level hierarchy of scheduling domains; when we add the top level the picture becomes:

系统现在有两个等级的**scheduling domains**视图；当我们把顶层domain加入之后，图片变成如下：

[Top-level domain]

> This top-level domain is the parent of the processor-level domains. It contains two CPU groups, each of which contains the CPUs contained within one hyperthreaded processor package.

顶层的**domian**是处理器级别**domain**的**parent**。顶层的domain包含两个**CPU groups**，每一个都包含一个超线程处理器物理封装。

> If this were a NUMA system, it would have multiple domains which look like the above diagram; each of those domains would represent one NUMA node. The hierarchy would have a third, system-level domain which contains all of the NUMA nodes.

如果这个是一个**NUMA**系统，将会有多个和上图一样的多个**domains**，每一个**domain**将会代表一个**NUMA**节点。分层将会有第三个，系统级的**domain**，这个域中包含左右的**NUMA**节点。

> Note that, in the actual code, the hierarchy is represented a little differently than has been portrayed above; each CPU has its own copy of every domain it belongs to. So our little system would actually contain eight sched_domain structures: one copy of the CPU-level domain and one copy of the top-level domain for every processor. Things are implemented this way for performance reasons: the scheduler must be very fast, which contraindicates sharing this fundamental data structure between processors. The structure is, in any case, almost entirely read-only after it has been set up, so it can be replicated without trouble.

需要注意的是,在实际的代码中，分层的视图和上边描绘的图表还是有点区别的；每一个CPU都有一份自己所隶属的所有的**domain**的拷贝。所以我们的小系统实际上将会包含八个**sched_domain**结构体：一个是**CPU**级别domain的拷贝，一个是每一个处理器顶层的domain的拷贝。这样实现的目的是出于性能的考虑：调度器必须运行非常快，这样的话禁止共享处理器间的基本数据结构。在任何情况下，这个结构体在设置完成后是只读的，所以复制不会造成任何问题。

> Each scheduling domain contains policy information which controls how decisions are made at that level of the hierarchy. The policy parameters include how often attempts should be made to balance loads across the domain, how far the loads on the component processors are allowed to get out of sync before a balancing attempt is made, how long a process can sit idle before it is considered to no longer have any significant cache affinity, and various policy flags. These policies tend to be set as follows:

每一个调度域包含有**policy**信息，这些信息控制对应层的决策的制定。**policy**参数包括:不同的domain之间应该多久尝试一次负载均衡，在一次负载均衡尝试之前，不同的处理器之间允许多大的负载差距存在，一个进程在失去有效的cache亲和性后，多长时间可以设置为**IDLE**状态，还有其它的策略标记。这些策略一般设置如下：

> - At the hyperthreaded processor level: balancing attempts can happen often (every 1-2ms), even when the imbalance between processors is small. There is no cache affinity at all: since hyperthreaded processors share cache, there is no cost to moving a process from one to another. Domains at this level are also marked as sharing CPU power; we'll see how that information is used shortly.
> - At the physical processor level: balancing attempts do not have to happen quite so often, and they are curtailed fairly sharply if the system as a whole is busy. Processor loads must be somewhat farther out of balance before processes will be moved within the domain. Processes lose their cache affinity after a few milliseconds.
> - At the NUMA node level: balancing attempts are made relatively rarely, and cache affinity lasts longer. The cost of moving a process between NUMA nodes is relatively high, and the policy reflects that.

- **超线程处理器级别**：负载均衡的尝试经常发生（每1-2ms），即使处理器之间的不平衡非常小。超线程内部的CPU根本没有**cache**亲和性：因为超线程内部的CPU共享cache，将进程从一个CPU迁移到另一个没有特别大的开销。这个级别的**domain**被标记为可以共享CPU的电源；接下来我们将会看到这些信息是如何运用的。
- **物理处理器级别**：负载均衡并不会发生的特别频繁，如果整个系统很忙，将会急剧减少。处理器之间的的负载一定程度上失衡后，进程将会在domain内部发生迁移。迁移之后，进程在几ms之后丢失cache关联。
- **NUMA节点级别**：负载均衡的操作相对来说非常少，cache关联持续的时间较长。跨**NUMA**节点迁移进程开销比较高，**policy**可以看出。

> The scheduler uses this structure in a number of ways. For example, when a sleeping process is about to be awakened, the normal behavior would be to keep it on the same processor it was using before, on the theory that there might still be some useful cache information there. If that processor's scheduling domain has the SD_WAKE_IDLE flag set, however, the scheduler will look for an idle processor within the domain and move the process immediately if one is found. This flag is used at the hyperthreading level; since the cost of moving processes is insignificant, there is no point in leaving a processor idle when a process wants to run.

调度器在很多地方使用这些数据结构。例如，当一个睡眠的进程将要被唤醒时，正常的操作应该是保持此进程在睡眠之前的CPU上，理论上cache上应该还有一些有用的信息。如果处理器的调度域被设置了**`SD_WAKE_IDLE` **标记，那么，调度器将会在对应的调度域中选择**idle**的处理器，如果找到，将唤醒的进程迁移到此处理器。这个标记使用在超线程级别；因为超线程内部的cpu之间的进程迁移的开销可以忽略，而且如果有进程要运行而让某个处理器空闲是没有意义的。

> When a process calls exec() to run a new program, its current cache affinity is lost. At that point, it may make sense to move it elsewhere. So the scheduler works its way up the domain hierarchy looking for the highest domain which has the SD_BALANCE_EXEC flag set. The process will then be shifted over to the CPU within that domain with the lowest load. Similar decisions are made when a process forks.

当一个进程调用*exec()*去运行一个新的程序后，这个进程的cache关联此时丢失。此时，可以将此进程迁移到任何CPU上执行。调度器将会沿着调度域一层一层往上找直到找到设置了`SD_BALANCE_EXEC`的最高层的调度域。进程将会被迁移到找到的调度域中负载最轻的CPU上。当一个进程 `fork`之后也会执行此操作。

> If a processor becomes idle, and its domain has the SD_BALANCE_NEWIDLE flag set, the scheduler will go looking for processes to move over from a busy processor within the domain. A NUMA system might set this flag within NUMA nodes, but not at the top level.

如果一个处理器出于*idle*状态，并且所在的调度域设置了`SD_BALANCE_NEWIDLE`标记，调度器将会在调度域中寻找负载最重的处理器，并将此处理器上的一些进程迁移到*idle* CPU上。**NUMA**系统可能设置在节点所在的域中设置此flag，但是最顶层的域不会设置。

> The new scheduler does an interesting thing with "shared CPU" (hyperthreaded) processors. If one processor in a shared pair is running a high-priority process, and a low-priority process is trying to run on the other processor, the scheduler will actually idle the second processor for a while. In this way, the high-priority process is given better access to the shared package.

新的调度器对“共享CPU”(超线程)的处理器做了一件有意思的事情。如果某个CPU正在运行高优先级进程，而另一颗CPU正在运行低优先级进程，那么调度器会将另一个CPU置于IDLE状态一会。这样，高优先级进程将会有更好的处理器访问体验。

> The last component of the domain scheduler is the active balancing code, which moves processes within domains when things get too far out of balance. Every scheduling domain has an interval which describes how often balancing efforts should be made; if the system tends to stay in balance, that interval will be allowed to grow. The scheduler "rebalance tick" function runs out of the clock interrupt handler; it works its way up the domain hierarchy and checks each one to see if the time has come to balance things out. If so, it looks at the load within each CPU group in the domain; if the loads differ by too much, the scheduler will try to move processes from the busiest group in the domain to the most idle group. In doing so, it will take into account factors like the cache affinity time for the domain.

域调度器中的最后一个部分是激活主动均衡的代码，当系统中的负载变的不均衡后，这部分code在调度域中迁移进程。每一个调度域中都有**间隔**这个信息来描述负载均衡的操作应该多长时间执行一次；如果系统趋向平衡，那么时间间隔可以允许调大。调度器`rebalance tick`函数在时钟中断的外部运行；此函数沿着调度域一层一层往上检查每个*domain*是否到达需要做负载均衡操作的时间。这样的话，此函数查看*domain*中每一个CPU group的负载；如果域中的负载差值比较大，调度器将会迁移域中最繁忙的CPU group上的进程到最空闲的CPU group上。这样做的话，需要考虑域中cache关联时间等因素。

> Active balancing is especially necessary when CPU-hungry processes are competing for access to a hyperthreaded processor. The scheduler will not normally move running processes, so a process which just cranks away and never sleeps can be hard to dislodge. The balancing code, by way of the migration threads, can push the CPU hog out of the processor for long enough to allow it to be moved and spread the load more widely.

当一个**CPU-hungry**的进程在竞争超线程处理器的访问时，主动平衡变的尤为必要。调度器正常不会迁移正在运行的进程，所以一个刚释放CPU资源并且从来不会睡眠的进程是很难被迁移走的。平衡代码，通过专门的进程迁移线程，可以将*CPU hog*推出处理器之外一段时间来允许进程被迁移并且将负载在更广的范围内平衡。

> When the system is trying to balance loads across processors, it also looks at a parameter kept within the sched_group structure: the total "CPU power" of the group. Hyperthreaded processors look like independent CPUs, but the total computation power of a pair of hyperthreaded processors is far less than that of two separate packages. Two separate processors would have a "CPU power" of two, while a hyperthreaded pair would have something closer to 1.1. When the scheduler considers moving a process to balance out the load, it looks at the total amount of CPU power currently being exercised. By maximizing that number, it will tend to spread processes across physical processors and increase system throughput.

当系统尝试在不同的处理器之间平衡负载时，也会参考保存在`sched_group`结构体中的参数：整个group的**CPU POWER**。超线程处理器里边的CPU看起来是独立的，但是一对超线程处理器的电量消耗比两个单独的CPU物理封装少很多。两个单独的处理器消耗两个**CPU power**,但是一个超线程处理器的电量消耗接近1.1。 当调度器想要通过迁移进程来平衡负载时,会查看当前CPU的总功率，调度器倾向于将进程扩散在不同的物理处理器上来最大化功率并且提高系统的吞吐量。

> The new scheduling code has been under development for some time, and it has seen a great deal of tweaking. The domain mechanism has done a lot to make it possible to make good scheduling decisions, but much of detail work was still required. It would appear that that work is now reaching a point where the domain mechanism may soon be merged into the mainline. At that point, with luck, people will be able to stop complaining about the 2.6 scheduler.

新的调度器代码已经开发了一段时间，做了大量的调整。**domain**机制做了大量工作使的调度器做出好的调度决策，但是还有很多细节的工作仍然需要完成。看起来**domain**机制在不久的将来会合并到**mainline**中。到时候，如果幸运的话，用户将不会抱怨**2.6的调度器**了。

> (Thanks to Nick Piggin for his comments on an early version of this article).

(感谢*Nick Piggin*在本文早期版本提供的建议)

**请点击 [LWN 中文翻译计划](/lwn)，了解更多详情。**

[1]: https://lwn.net/Articles/428175/

