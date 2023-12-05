---
layout: post
author: 'Gege-Wang'
title: '在通用式操作系统中集成 Unikernel 优化'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /porting-riscv-ukl-translate/
description: '在通用式操作系统中集成 Unikernel 优化'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector:  [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [spaces refs pangu autocorrect]
> Title:      [Integrating Unikernel Optimizations in a General Purpose OS](https://arxiv.org/pdf/2206.00789.pdf)
> Author:     Ali Raza
> Translator: Gege-Wang <2891067867@qq.com>
> Date:       2023/07/14
> Revisor:    Falcon <falcon@tinylab.org>
> Project:    [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:    PLCT Lab, ISCAS


## 1 前言（Introduction）

> There is growing evidence that the structure of today’s general purpose operating systems is problematic for a number of key use cases. For example, applications that require highperformance I/O use frameworks like DPDK and SPDK to bypass the kernel and gain unimpeded access to hardware devices. In the cloud, client workloads are typically run inside dedicated virtual machines, and a kernel designed to multiplex the resources of many users and processes is instead being replicated across many single-user, often single process, environments.

越来越多的证据表明，当今通用操作系统的结构在许多关键用例中存在问题。例如，需要高性能 I/O 的应用程序使用像 DPDK 和 SPDK 这样的框架来绕过内核并获得对硬件设备的无障碍访问。在云中，客户端工作负载通常运行在专用虚拟机中，而一个旨在将多个用户和进程的资源复用的内核却被复制到多个单用户（通常是单进程）环境中。

> In response, there has been a resurgence of research systems exploring the idea of a libraryOS, or a unikernel, where an application is linked with a specialized kernel and deployed directly on virtual hardware. Compared with Linux, unikernels have demonstrated significant advantages in boot time, security, resource utilization, and I/O performance.

作为回应，一些研究系统重新开始探索库操作系统（libraryOS）或单内核（unikernel）的概念，其中应用程序与专门的内核相关联，并直接部署在虚拟硬件上。和 Linux 相比，unikernels 在启动引导时间、安全性、资源利用率和 I/O 性能方面表现出了显著的优势。

> As with any operating system, widespread adoption of a unikernel will require enormous and ongoing investment by a large community. Justifying this investment is difficult since unikernels target only niche portions of the broad use-cases of general-purpose OSes. In addition to their intrinsic limitation as single application environments, with few exceptions, existing unikernels support only virtualized environments and, in many cases, only run on a single processor core. Moreover, they do not support accelerators (e.g., GPUs and FPGAs) that are increasingly critical to achieving high performance in a post Dennard scaling world.

与任何操作系统一样，广泛采用单内核将需要大型社区的大量持续投资。证明这种投资的合理性是困难的，因为 unikernels 只针对通用操作系统的广泛用例中的一小部分。除了作为单一应用程序环境的固有限制外，现有的 unikernels 只支持虚拟化环境，而且在许多情况下，只在单个处理器核心上运行。此外，它们不支持加速器（例如 GPU 和 FPGAs），而在 Dennard 定理逐渐失效的情况下，加速器对实现高性能越来越重要。

> Some systems have demonstrated that it is possible to create a unikernel that re-uses much of the battle-tested code of a general-purpose OS and supports a wide range of applications. Examples include NetBSD based Rump Kernel, Windows based Drawbridge and Linux based Linux Kernel Library (LKL). These systems, however, require significant changes to the general-purpose OS, resulting in a fork of the codebase and community. As a result, ongoing investments in the base operating system are not necessarily applicable to the forked unikernel.

一些系统已经证明，重用通用操作系统大量的经过实战测试的代码去创建一个 Unikernel 并使其支持广泛的应用程序，是可能的，例如，基于 NetBSD 的 Rump Kernel、基于 Windows 的 Drawbridge 和基于 Linux 的 Linux 内核库 (LKL)。然而，这些系统需要对通用操作系统进行重大更改，从而导致代码库和社区的分支。因此，对基本操作系统的持续投资不一定适用于派生的 unikernel。

> To avoid the investment required for a different OS, the recent Lupine and X-Containers projects explore exploiting Linux’s innate configurability to enable application specific customizations. These projects avoid the hardware overhead of system calls between user and kernel mode, but to avoid code changes to Linux, they do not explore deeper optimizations. Essentially these systems preserve the boundary between the application and the underlying kernel, giving up on any unikernel performance advantages that depend on linking the application and kernel code together.

为了避免不同操作系统所需的投资，最近的 Lupine 和 X-Containers 项目探索利用 Linux 固有的可配置性来实现特定于应用程序的自定义。这些项目避免了用户模式和内核模式之间系统调用的硬件开销，但是为了避免对 Linux 进行代码更改，它们没有探索更深入的优化。从本质上讲，这些系统保留了应用程序和底层内核之间的边界，放弃了依赖于将应用程序和内核代码链接在一起的全部单内核性能优势。

> The Unikernel Linux (UKL) project started as an effort to exploit Linux’s configurability to try to create a new unikernel in a fashion that would avoid forking the kernel. If this is possible, we hypothesized that we could create a unikernel that would support a wide range of Linux’s applications and hardware, while becoming a standard part of the ongoing investment by the Linux community. Our experience has led us to a different, more powerful goal; enabling a kernel that can be configured to span a spectrum between a general-purpose operating system and a pure unikernel.

Unikernel Linux (UKL) 项目最初是为了开发 Linux 的可配置性，以一种避免分叉内核的方式创建一个新的 Unikernel。如果这是可能的，我们假设我们可以创建一个单内核，它将支持广泛的 Linux 应用程序和硬件，同时成为 Linux 社区持续投资的标准部分。我们的经验把我们引向了一个不同的、更强大的目标；启用一个可以配置为跨越通用操作系统和纯单内核之间的范围的内核。

> At the general-purpose end of the spectrum, if all UKL configurations are disabled, a standard Linux kernel is generated. The simplest base model configuration of UKL supports many applications, albeit with only modest performance advantages. Like unikernels, a single application is statically linked into the kernel and executed in privileged mode. However, the base model of UKL preserves most of the invariants and design of Linux, including a separate page-able application portion of the address space and a pinned kernel portion, distinct execution modes for application and kernel code, and the ability to run multiple processes. The changes to Linux to support the UKL base model are modest (~550 LoC), and the resulting kernel support all hardware and applications of the original kernel as well as the entire Linux ecosystem of tools for deployment and performance tuning. UKL base model shows a modest 5% improvement in syscall latency.

在通用的情况下，如果禁用所有 UKL 配置，将生成一个标准的 Linux 内核。尽管只有适度的性能优势，最简单的 UKL 基本模型配置支持许多应用程序。与 unikernels 类似，单个应用程序被静态地链接到内核中，并以特权模式执行。但是，UKL 的基本模型保留了 Linux 的大多数不变量和设计，包括地址空间中单独的可分页应用程序部分和固定的内核部分、应用程序和内核代码的不同执行模式，以及运行多个进程的能力。为支持 UKL 基本模型而对 Linux 进行的更改是适度的 (~550 LoC)，生成的内核支持原始内核的所有硬件和应用程序，并且支持用于部署和性能调优的整个 Linux 生态系统工具。UKL 基本模型显示系统调用延迟有 5% 的适度改善。

> Once an application is running in the UKL base model, a developer can move along the spectrum towards a unikernel by 1) adapting additional configuration options that may improve performance but will not work for all applications, and/or 2) modifying the applications to directly invoke kernel functionality. Example configuration options we have explored avoid costly transition checks between application and kernel code, use simple return (rather than iret) from page faults and interrupts, and use shared stacks for application and kernel execution etc. Application modifications can, for example, avoid scheduling and exploit application knowledge to reduce the overhead of synchronization and polymorphism. Experiments show up to 83% improvement in syscall latency and substantial performance advantages for real workloads, e.g., 26% improvement in Redis throughput while improving tail latency by 22%. A latency sensitive workloads show 100 times improvement. The full UKL patch to Linux, including the base model and all configurations, is 1250 LoC.

一旦应用程序在 UKL 基本模型中运行，开发人员就可以通过以下方式向单内核方向发展：1) 采用可能提高性能但不适用于所有应用程序的附加配置选项，和/或 2) 修改应用程序以直接调用内核功能。我们探讨的示例配置选项避免了应用程序和内核代码之间代价高昂的转换检查，在页面错误和中断时使用简单的 return（而不是 iret），以及在应用程序和内核执行时使用共享堆栈等。应用程序修改有很多好处，例如可以避免调度，并利用应用程序知识来减少同步和多态性的开销。实验表明，系统调用延迟提高了 83%，在实际工作负载中具有显著的性能优势，例如，Redis 吞吐量提高了 26%，尾延迟提高了 22%。对延迟敏感的工作负载性能提高了 100 倍。Linux 的完整 UKL 补丁，包括基本模型和所有配置，是 1250 LoC。

> Contributions of this work include:
> - An existence proof that unikernel techniques can be integrated into a general-purpose OS in a fashion that does not need to fragment/fork it.
> - A demonstration that a single kernel can be adopted across a spectrum between a unikernel and a general purpose OS.
> - A demonstration that performance advantages are possible; applications achievemodest gainswith no changes, and incremental effort can achieve more significant gains.

这项工作的贡献包括：
- 证明单内核技术可以以一种不需要碎片化/分叉的方式集成到通用操作系统中。
- 演示单个内核可以在单内核和通用操作系统之间的范围内被采用。
- 证明性能优势是可能的；应用程序在不进行更改的情况下可以获得适度的收益，而增量的工作可以获得更显著的收益。

> We discuss our motivations and goals for this project in Section 2, and ur overall approach to bring unikernel techniques to Linux in Section 3. Section 4 describes key implementation details. In Section 5, we evaluate and discuss the implications of the current design and implementation. Finally, Section 6 and 7 contrast UKL to previous work and describe research directions that this work enables.

我们将在第 2 节中讨论这个项目的动机和目标，并在第 3 节中讨论将单内核技术引入 Linux 的总体方法。第 4 节描述了关键的实现细节。在第 5 节中，我们将评估和讨论当前设计和实现的含义。最后，第 6 节和第 7 节将 UKL 与以前的工作进行了对比，并描述了这项工作能够实现的研究方向。

## 2 动机 & 目标（Motivation & Goals）

> UKL seeks to explore a spectrum between a general-purpose operating system and a unikernelin order to:(1) enable unikernel optimizations demonstrated by earlier systems while preserving a general-purpose operating system’s (2) broad application support, (3) broad hardware support, and (4) the ecosystem of developers, tools and operators. We motivate and describe each of these four goals.

UKL 试图探索通用操作系统和统一内核之间的范围，以便：
1. 启用早期系统演示的单内核优化，同时保留通用操作系统的单内核优化
2. 广泛的应用程序支持
3. 广泛的硬件支持
4. 具有开发人员、工具和操作人员的生态系统。
同时，我们受激发于并且描述这四个目标。

### 2.1 Unikernel 优化（Unikernel optimizations）

> Unikernels fundamentally enable optimizations that rely on linking the application and kernel together in the same address space. Example optimizations that previous systems have adopted include
> 1. avoiding ring transition overheads;
> 2. exploiting the shared address space to pass pointers rather than copying data;
> 3. exploiting fine-grained control over scheduling decisions, e.g., deferring preemption in latency-sensitive routines;
> 4. enabling interrupts to be efficiently dispatched to application code;
> 5. exploiting knowledge of the application to remove code that is never used;
> 6. employing kernel-level mechanisms to optimize locking and memory management, for instance, by using Read-Copy-Update (RCU), per-processor memory, and DMA-aided data movement; and
> 7. enabling compiler, link-time, and profile-driven optimizations between the application and kernel code.

Unikernels 从根本上实现了那些依赖于将应用程序和内核链接在同一地址空间中的优化。以前系统采用的优化示例包括：
1. 避免特权模式转换开销；
2. 利用共享地址空间传递指针，而不是复制数据；
3. 采用对调度决策的细粒度控制，例如，在延迟敏感例程中的推迟抢占；
4. 使中断能够有效地分配给应用程序代码；
5. 利用应用程序的知识来删除从未使用过的代码；
6. 采用内核级机制来优化锁和内存管理，例如，通过使用读-复制 - 更新 (RCU)、per-processor 内存和 dma 辅助的数据移动；
7. 在应用程序和内核代码之间，启用编译器、链接时和以性能分析驱动的优化。

> Ultimately our goal with UKL is to explore the full spectrum between general purpose and highly specialized unikernels. For this paper, our goal is to enable applications to be linked into the Linux kernel, and explore what, if any, improvements can be achieved by modest changes to the application and general-purpose system.

我们使用 UKL 的最终目标是探索通用操作系统和高度专门化 unikernels 之间的全部范围。
在本文中，我们的目标是使应用程序能够链接到 Linux 内核中，并探索通过对应用程序和通用系统进行适度更改可以实现哪些改进（如果有的话）。

### 2.2 应用程序支持（Application support）

> One of the fundamental problems with unikernels is the limited set of applications that they support. By their nature, unikernels only enable a single process, excluding any application that requires helper processes, scripts, etc. Moreover, the limited set of interfaces typically requires substantial porting effort for any application, and library that the application uses.

unikernels 的一个基本问题是它们支持的应用程序有限。就其本质而言，unikernels 只启用单个进程，不支持任何需要辅助进程、脚本等的应用程序。此外，有限的接口集意味着通常需要为所有应用程序和应用程序使用的库进行大量的移植工作。

> UKL seeks to enable unikernel optimizations to be broadly applicable. Our goal is to enable any unmodified Linux application and library to use UKL, with a re-compilation, as long as only one application needs to be linked into the kernel. Once the application is functional, the developer can incrementally enable unikernel optimizations/configurations. A large set of applications should be able to achieve some gain on the general-purpose end of the spectrum, while a much smaller set of applications will be able to achieve more substantial
gains as we move toward the unikernel end.

UKL 寻求的是单内核优化的广泛适用。我们的目标是允许任何未经修改的 Linux 应用程序和库使用 UKL，通过重新编译，只要有一个应用程序链接到内核中就可以。一旦应用程序运行正常，开发人员就可以增量地启用单内核优化/配置。大型应用程序应该能够在通用端获得一些增益，而较小的应用程序集将能够在我们向单内核端移动时获得更大的增益。

### 2.3 硬件支持（Hardware support）

> Another fundamental problem with unikernels is the lack of support for physical machines and devices. While recent unikernel research has mostly focused on virtual systems, some recent and previous systems have demonstrated the value of per-application specialized
operating systems on physical machines. Unfortunately, even these systems were limited to very specific hardware platforms with a restricted set of device drivers. This precludes a wide range of infrastructure applications (e.g., storage systems, schedulers, networking toolkits) that are typically deployed bare-metal. Moreover, the lack of hardware support is an increasing problem in a post-Dennard scaling world, where performance depends on taking advantage of the revolution of heterogeneous computing.

unikernels 的另一个基本问题是缺乏对物理机器和设备的支持。虽然最近的 unikernel 研究主要集中在虚拟系统上，但一些最近的和以前的系统已经证明了在物理机上运行每个应用程序专用操作系统的价值。不幸的是，即使是这些系统也仅限于非常特定的硬件平台和有限的设备驱动程序集。这就排除了大量通常部署在裸机上的基础设施应用程序（例如，存储系统、调度程序、网络工具包）。此外，在 dennard 定理逐渐失效的情况下，缺乏硬件支持是一个日益严重的问题，性能依赖于异构计算革命。

> Our goal with UKL is to provide a unikernel environment capable of supporting the complete HCL of Linux, allowing applications to exploit any hardware (e.g. GPUs, TPUs, FPGAs) enabled in Linux. Our near term goal, while supporting all Linux devices, is to focus on x86-64 systems. Much like KVM became a feature of Linux on x86 and was then ported to other platforms; we expect that, if UKL is accepted upstream, communities interested in non-x86 architectures will take on the task of porting and optimizing UKL for their platforms.

我们使用 UKL 的目标是提供一个能够支持 Linux 的完整 HCL 的单内核环境，允许应用程序利用 Linux 中启用的任何硬件（例如 gpu, tpu, fpga）。在支持所有 Linux 设备的同时，我们的近期目标是专注于 x86-64 系统。就像 KVM 在 x86 上成为 Linux 的一个特性，然后被移植到其他平台；我们期望，如果 UKL 在上游被接受，对非 x86 架构感兴趣的社区将承担为他们的平台移植和优化 UKL 的任务。

### 2.4 生态系统（Ecosystem）

> While application and hardware support are normally thought of as the fundamental barriers for unikernel adoption, the problem is much larger. Linux has a huge developer community, operators that know how to configure and administer it, a massive body of battle-tested code, and a rich set of tools to support functional and performance debugging and configuration.

虽然应用程序和硬件支持通常被认为是采用单内核的基本障碍，但问题要大得多。Linux 有一个庞大的开发人员社区、有知道如何配置和管理它的操作人员、有大量经过实战测试的代码，以及一组丰富的工具来支持功能和性能的调试和配置。

> Our goal with UKL is, while enabling developers to adopt extreme optimizations that are inconsistent with the broader ecosystem, the entire ecosystem should be preserved on the general-purpose end of the spectrum. This means operational as well as functional and performance debugging tools should just work. Standard application and library testing systems should, similarly, just work. Most of all, the base changes needed to enable UKL need to be of a nature that they don’t
break assumptions of the battle tested Linux code, can be accepted by the community, and can be tested and maintained as development on the system progresses.

我们使用 UKL 的目标是，在使开发人员能够采用与更广泛的生态系统不一致的极端优化的同时，整个生态系统继续保留在通用端。这意味着操作、功能和性能调试工具都应该正常工作。类似地，标准应用程序和库测试系统应该能够正常工作。最重要的是，使能 UKL 的基本改变需要具有这样的性质：它们不会打破经过实战测试的 Linux 代码的假设，可以被社区接受，并且可以随着系统开发的进展进行测试和维护。

## 3 设计（Design）

> UKL’s base model enables an application to be linked into the kernel while preserving the (known and unknown) invariants and assumptions of applications and Linux. Once an application runs on UKL, an expert programmer can then adopt specific unikernel optimizations by choosing(additional) configuration options and/or modifying the application to invoke kernel functionality directly.We first describe the base model and then some of the unikernel optimizations we have explored.

UKL 的基本模型允许将应用程序链接到内核中，同时保留应用程序和 Linux 的（已知和未知的）不变量和假设。一旦应用程序在 UKL 上运行，专业程序员就可以通过选择（额外的）配置选项和/或修改应用程序来直接调用内核功能，从而采用特定的单内核优化。我们首先描述基本模型，然后介绍一些我们已经探索过的单内核优化。

### 3.1 基础模型（Base Model）

> UKL is similar to many unikernels in that it involves modifications to a base library and a kernel, and has a build process that enables a single application to be statically linked with kernel code to create a bootable kernel. In the case of UKL, the modifications are to glibc and the Linux kernel. As a result of the wide variety of architectures supported by glibc and Linux, it was possible to introduce the majority of changes we required in a new UKL target architecture; most of the hooks we require to override code already exist in common code.

UKL 与许多 unikernels 相似，因为它涉及对基本库和内核的修改，并且具有一个构建过程，该过程将单个应用程序与内核代码静态链接，以创建可引导的内核。对于 UKL，修改是针对 glibc 和 Linux 内核的。由于 glibc 和 Linux 支持各种各样的体系结构，我们有可能在新的 UKL 目标体系结构中引入我们需要的大部分更改；我们需要重写代码的大多数钩子已经存在于公共代码中。

> The base model of UKL differs from unikernels in 1) support for multiple processes, 2) address space layout, and 3) in maintaining distinct execution models for applications and kernel.

UKL 的基本模型与 unikernels 的不同之处在于：1）支持多进程，2）地址空间布局，以及 3）为应用程序和内核维护不同的执行模型。

> Support formultiple processes: One key area where UKL differs from unikernels is that, while only one application can be linked into the kernel, UKL enables other applications to run unmodified on top of the kernel. Support for multiple processes is critical to support many applications that are logically composed of multiple processes(§2.2), standard configuration and initialization scripts for device bring-up (§2.3), and the tooling used for operations, debugging and testing (§2.4).

**支持多进程：** UKL 与 unikernels 的一个关键区别在于，虽然只有一个应用程序可以链接到内核中，但 UKL 允许其他应用程序在内核之上不加修改地运行。对于支持许多逻辑上由多个进程构成（§2.2）、设备启动的标准配置和初始化脚本（§2.3）以及用于操作、调试和测试的工具（§2.4）组成的应用程序来说，支持多进程至关重要。

> Address space layout: UKL preserves the standard Linux virtual address space split between application and kernel. The application heap, stacks, and mmapped memory regions are all created in the user portion of the address space. Kernel data structures (e.g., task structs, file tables, buffer cache) and kernel memory management services (e.g., vmalloc and kmalloc) all use the kernel portion of the address space. Since the kernel and application are compiled and linked together,
the application (and kernel) code and data are all allocated in the kernel portion of the virtual address space.

**地址空间布局：** UKL 保留了在应用程序和内核之间划分的标准 Linux 虚拟地址空间。应用程序堆、堆栈和映射的内存区域都在地址空间的用户部分创建。内核数据结构（例如，任务结构，文件表，缓冲缓存）和内核内存管理服务（例如，vmalloc 和 kmalloc）都使用地址空间的内核部分。由于内核和应用程序被编译并链接在一起，所以应用程序（和内核）代码和数据都分配在虚拟地址空间的内核部分。

> We found it necessary to adapt this address space layout because Linux performs a simple address check to see if an address being accessed is pinned or not; modifying this layout would have resulted in changes that would be difficult to get accepted (2.4). Unfortunately, this layout has two negative implications for application compatibility. First, (see 4) applications have to be compiled with different flags to use the higher portion of the address space. Second, it may be problematic for applications with large initialized data sections that in UKL are pinned.

我们发现有必要调整这个地址空间布局，因为 Linux 执行一个简单的地址检查，查看正在访问的地址是否固定；修改这个布局会导致难以被接受的变化 (2.4)。不幸的是，这个布局有两个对应用程序兼容性的负面影响。首先，（见 4）应用程序必须使用不同的标志来编译，以使用地址空间的较高部分。其次，对于使用 UKL 固定的大型初始化数据段的应用程序可能会有问题。

> Execution models: Even though the application and kernel are linked together, UKL differs from unikernels in providing fundamentally different execution models for application and kernel code. Application code uses large stacks (allocated from the application portion of the address space), is fully preemptable, and uses application-specific libraries. This model is critical to enabling a large set of applications to be supported without modification (2.2).

**执行模型：** 尽管应用程序和内核是链接在一起的，但 UKL 与 unikernels 的不同之处在于为应用程序和内核代码提供了根本不同的执行模型。应用程序代码使用大型堆栈（从地址空间的应用程序部分分配），是完全可抢占的，并使用特定于应用程序的库。这个模型对于在不修改的情况下支持大量应用程序是至关重要的（2.2）。

> Kernel code, on the other hand, runs on pinned stacks, accesses pinned data structures, and uses kernel implementation of common routines. This model was required to avoid substantial modifications to Linux that would not have been accepted by the community (2.4).

另一方面，内核代码运行在固定的堆栈上，访问固定的数据结构，并使用通用例程的内核实现。这个模型是为了避免对 Linux 进行不被社区接受的实质性修改 (2.4)。

> On transition between the execution models, UKL performs the same entry and exit code of the Linux kernel, with the difference that: 1) transitions to kernel code are done with a procedure call rather than a syscall, and 2) transitions from the kernel to application code are done via a ret rather than a sysret or iret. This transition code includes changing between application and kernel stacks, RCU handling, checking
if the scheduler needs to be invoked, and checking for signals. In addition, it includes setting a per-thread ukl_mode to identify the current mode of the thread so that subsequent interrupts, faults and exceptions will go through normal transition code when resuming interrupted application code.

在执行模型之间的转换，UKL 执行与 Linux 内核相同的入口和退出代码，不同之处在于：1）到内核代码的转换是通过过程调用而不是系统调用完成的，2）从内核到应用程序代码的转换是通过 ret 而不是 sysret 或 iret 完成的。这个转换代码包括在应用程序栈和内核栈之间的转换，RCU 处理，检查是否需要调用调度器，检查是否有信号。此外，它还包括设置每个线程的 ukl_mode，以识别线程的当前模式，以便在恢复被中断的应用程序代码时，后续中断、故障和异常将通过正常的转换代码。

### 3.2 Unikernel 优化（Unikernel Optimizations）

> While preserving existing execution modes enables most applications to run with no modifications on UKL, the performance advantages of just avoiding syscall, sysret, and iret operations are, as expected, modest. However, once an application is linked into the kernel, different unikernel optimizations are possible. First, a developer can apply a number of configuration options that may improve performance. Second, a knowledgeable developer can improve performance by modifying the application to call internal kernel routines and violating, in a controlled fashion, the normal assumptions of kernel versus application code.

虽然保留现有的执行模式使大多数应用程序无需修改就可以在 UKL 上运行，但正如预期的那样，仅仅避免 syscall、sysret 和 iret 操作的性能优势并不大。但是，一旦将应用程序链接到内核中，就可以进行不同的单内核优化。首先，开发人员可以应用许多可能提高性能的配置选项。其次，有经验的开发人员可以通过修改应用程序来调用内部内核例程，并以一种受控的方式违反内核代码与应用程序代码之间的常规假设，从而提高性能。

1. 配置选项。这里我们将讨论影响最大的配置选项

> Bypassing entry/exit code: On Linux, whenever control transitions between application and kernel through system calls, interrupts, and exceptions, some entry and exit code is executed, and it is expensive. We introduced a configuration (UKL_BYP) that allows the application, on a per-thread basis, to tell UKL to bypass entry and exit code for some number of transitions between application and kernel code. As we will see, this model results in significant performance gains for applications that make many small kernel requests.

**绕过进入/退出代码：** 在 Linux 上，只要通过系统调用、中断和异常在应用程序和内核之间进行控制转换，就会执行一些进入和退出代码，而且代价很高。我们引入了一个配置（UKL_BYP），它允许应用程序在每个线程的基础上告诉 UKL 在应用程序和内核代码之间进行一定数量的转换时绕过入口和退出代码。正如我们将看到的，对于发出许多小内核请求的应用程序，该模型会带来显著的性能提升。

> A developer can invoke an internal kernel routine directly, where no automatic transition paths exist, e.g., invoking vmalloc to allocate pinned pre-allocated kernel memory rather than normal application routines. The use of such memory not only avoids subsequent faults but also results in less overhead when kernel interfaces have to copy data to and from that memory.

开发人员可以在没有自动转换路径存在的情况下直接调用内部内核例程，例如，调用 vmalloc 来分配固定的预分配内核内存，而不是普通的应用程序例程。使用这种内存不仅可以避免随后的错误，而且在内核接口必须从该内存中复制数据时，也会减少开销。

> Avoiding stack switches: Linux runs applications on dynamically sized user stacks, and kernel code on fixed-sized, pinned kernel stacks. This stack switch, every time kernel functionality is invoked, breaks the compiler’s view and limits cross-layer optimizations, e.g., link-time optimizations,etc. The developer can select between two UKL configurations that avoid stack switching(UKL_NSS and UKL_NSS_PS); where (see implementation) each is appropriate for a different class of application. Currently, LTO in Linux is only possible with Clang and glibc, and some other libraries can only be compiled with gcc. There are efforts underway in the community to both enable glibc to be compiled with Clang and to enable Linux LTO with gcc. We hope by the time this paper is published, we will be able to demonstrate the results of LTO with one or the other of these.

**避免堆栈切换：** Linux 在动态大小的用户堆栈上运行应用程序，而在固定大小的内核堆栈上运行内核代码。每次调用内核功能时，这个堆栈切换都会破坏编译器的视图并限制跨层优化，例如链接时优化等。开发人员可以在两种避免堆栈切换的 UKL 配置（UKL_NSS 和 UKL_NSS_PS）之间进行选择；每个配置（请参阅实现）适用于不同类型的应用程序。目前，Linux 中的 LTO 只能使用 Clang 和 glibc，而其他一些库只能使用 gcc 进行编译。社区正在努力使 glibc 能够用 Clang 编译，并使 Linux LTO 能够用 gcc 编译。我们希望在这篇论文发表的时候，我们能够用其中一个或另一个来证明 LTO 的结果。

> ret versus iret: Linux uses iret when returning from interrupts, faults and exceptions. iret can be an expensive instruction when compared to a simple ret instruction, but it makes sense when control has to be returned to user mode because it guarantees atomicity while changing the privilege level, updating instruction and stack pointers, etc. UKL_RET configuration option uses ret and ensures atomicity by enabling interrupts only after returning to the application stack.

**ret vs iret：** Linux 在从中断、错误和异常返回时使用 iret。与简单的 ret 指令相比，iret 可能是一个开销很大的指令，但是当必须将控制权返回到用户模式时，它是有意义的，因为它在更改特权级别、更新指令和堆栈指针等操作的时候保证了原子性。UKL_RET 配置选项使用 ret，并通过仅在返回到应用程序堆栈后启用中断来确保原子性。

2. 应用修改

> Along with the above mentioned configurations, applications can be modified to gain further performance benefits. Developers can, by taking advantage of application knowledge, explore deeper optimizations. For example, they may be able to assert that only one thread is accessing a file descriptor and avoid costly locking operations. As another example, they may know a priority that an application is using TCP and not UDP and that a particular write operation in the application will always be to a TCP socket, avoiding the substantial overhead of polymorphism in the kernel’s VFS implementation. As we optimize specific operations, we are building up a library of helper functions that cache and simplify common operations.

除了上述配置之外，还可以修改应用程序以获得进一步的性能优势。通过利用应用程序知识，开发人员可以探索更深层次的优化。例如，他们可以断言只有一个线程正在访问文件描述符，避免代价高昂的锁操作。另一个例子是，他们可以预先知道应用程序正在使用 TCP 而不是 UDP，并且应用程序中的特定写操作将始终指向 TCP 套接字，从而避免了在内核 VFS 中实现多态性的大量开销。在优化特定操作时，我们正在构建一个辅助函数库，用于缓存和简化常见操作。

> UKL base model ensures that the application and kernel execution models stay separate, with proper transitions between the two. But applications may find it beneficial to run under the kernel execution model, even for short times. Applications can toggle a per-thread flag which switches them to the kernel-mode execution, allowing application threads to be treated as kernel threads, so they won’t be preempted. This can be used as a 'run-to-completion' mode where performance-critical paths of the application can be accelerated.

UKL 基础模型确保应用程序和内核执行模型保持分离，并在两者之间进行适当的转换。但是应用程序可能会发现在内核执行模型下运行是有益的，即使是很短的时间。应用程序可以切换 per-thread 标志，将它们切换到内核模式执行，允许应用程序线程被视为内核线程，这样它们就不会被抢占。这可以用作 “run-to-completion” 模式，其中应用程序的性能关键路径可以加速。

## 4 实现（Implementation）

> The size of the UKL base model patch to Linux kernel 5.14 is approximately 550 lines and the full UKL patch (base model plus all the configuration options mentionedin Table 1)is 1250 lines. The vast majority of these changes are target-specific, i.e., in the x86 architecture directory.

Linux 内核 5.14 的 UKL 基本模型补丁的大小大约是 550 行，完整的 UKL 补丁（基础模型加上表 1 中提到的所有配置选项）是 1250 行。这些更改中的绝大多数都是特定于目标的，即在 x86 体系结构目录中。

<div align=center><img src="/wp-content/uploads/2023/12/ukl/translate-table-1.PNG"></div>

> UKL takes advantage of the existing kernel Kconfig and glibc build systems. These allow target-specific functionality to be introduced that doesn’t affect generic code or code for other targets. All code changes made in UKL base model and subsequent versions are wrapped in macros which can be turned on or off through kernel and glibc build time config options. All the changes required are compiled out when Linux and glibc are configured for a different target.

UKL 利用了现有的内核 Kconfig 和 glibc 构建系统。它们允许引入特定目标的功能，而不会影响通用代码或其他目标的代码。在 UKL 基础模型和后续版本中所做的所有代码更改都包装在宏中，这些宏可以通过内核和 glibc 构建时的配置选项控制打开或关闭。当 Linux 和 glibc 是为不同的目标配置的时候，所需的所有更改都将编译出来。

> We found that UKL patch can be so small due to many favorble design decisions by the Linux community. For instance, Linux’s low level transition code has recently undergone massive rewritings to reduce assembly code and move functionality to C language. This has allowed UKL transition code changes to be localized to that assembly code. Further, the ABI for application threads dedicates a register (fs to point to
thread-local storage, while kernel threads have no such concept but instead dedicate a register (gs to point to processor-specific memory. If a register was used by both Linux and glibc, UKL would have had to add code to save and restore it on transitions; instead, both registers can be preserved.

我们发现，由于 Linux 社区做出了许多有利的设计决策，UKL 补丁可以如此之小。例如，Linux 的底层转换代码最近经历了大规模的重写，以减少汇编代码并将功能转移到 C 语言。这允许将对 UKL 转换代码的更改缩小化到汇编代码。此外，应用程序线程的 ABI 专用寄存器（fs) 专用于指向线程本地存储，而内核线程没有这样的概念，而是将寄存器（gs) 专用于指向特定处理器的内存。如果 Linux 和 glibc 都使用寄存器，UKL 将不得不添加代码来保存它，并且在转换时恢复它；相反，两个寄存器都可以保留。

> In addition to the kernel changes, about 4,700 lines of code are added or changed in glibc. These number is inflated because according to the glibc development approach, any file that needs to be modified has to be first copied to a new subdirectory and then modified. All the UKL changes are well contained in a separate directory. At build time, this directory is searched first for a target file before searching the default location.

除了内核更改之外，还在 glibc 中添加或更改了大约 4700 行代码。这个数字被放大了，因为根据 glibc 开发方法，任何需要修改的文件都必须首先复制到一个新的子目录，然后再进行修改。所有 UKL 更改都包含在一个单独的目录中。在构建时，首先在此目录中搜索目标文件，然后再搜索默认位置。

> Building UKL:. UKL codein Linux(protected by #ifdefs) is enabled by building with specific Kconfig options. UKL requires the application’s and the needed user libraries’ code to be compiled and statically linked with the kernel, so dynamically loadable system libraries cannot be used. All code must be built with two special flags. The first flag disables the red zone (-mno-red-zone). Hermitux takes the design approach of forcing all faults, interrupts, and exceptions to use dedicated stacks through the Intel interrupt stack table (IST) mechanism. This allows the red zone to remain safe while all interrupts etc., are serviced on dedicated kernel stacks. While we could have adopted this technique into UKL, it would have required drastic code changes. The second flag (-mcmodel=kernel) generates the code for kernel memory model. This is needed because application code has to link with kernel code and be loaded in the highest 2GB of address space instead of the lower 2GB that is the default for user code.

**构建 UKL：** Linux 中的 UKL 代码（由 `#ifdefs` 保护）通过使用特定的 Kconfig 选项来启用。UKL 要求编译应用程序和所需的用户库代码，并与内核静态链接，因此不能使用可动态加载的系统库。所有代码都必须使用两个特殊标志构建。第一个标志禁用红色区域（-mno-red-zone）。Hermitux 采用了通过 Intel 中断堆栈表（interrupt stack table, IST）机制强制所有故障、中断和异常使用专用堆栈的设计方法。这允许红色区域在所有中断等在专用内核堆栈上服务时保持安全。虽然我们可以在 UKL 中采用这种技术，但这需要对代码进行剧烈的修改。第二个标志（-mcmodel=kernel）生成内核内存模型的代码。这是必须的，因为应用程序代码必须与内核代码链接，并加载在最高的 2GB 地址空间中，而不是用户代码默认的较低的 2GB 地址空间中。

> The modified kernel build system combines the application object files, libraries, and the kernel into a final vmlinux binary which can be booted bare-metal or virtual. To avoid name collisions, before linking the application and kernel together, all application symbols (including library ones) are prefixed with ukl_. Kernel code typically has no notion of thread-local storage or C++ constructors, so the kernel’s linker script is modified to link with user-space code and ensure that thread-local storage and C++ constructors work. Appropriate changes to kernel loader are also made to load the new ELF sections along with the kernel.

修改后的内核构建系统将应用程序对象文件、库和内核组合到最终的 vmlinux 二进制文件中，该二进制文件可以裸机启动或虚拟启动。为了避免名称冲突，在将应用程序和内核链接在一起之前，所有应用程序符号（包括库符号）都以 `ukl_` 为前缀。内核代码通常没有线程本地存储或 C++ 构造函数的概念，因此内核的链接器脚本被修改为与用户空间代码链接，并确保线程本地存储和 C++ 构造函数正常工作。还对内核加载程序进行了适当的更改，以便新的 ELF 部分能够与内核一起加载。

> Changes to execve: We modified execve to skip certain steps (like loading the application binary, which does not exist in UKL), but most steps run unmodified. Of note, execve will jump straight to the glibc entry point when running the UKL thread instead of trying to read the application binary for an entry point. glibc initialization happens almost as normal, but when initializing thread-local storage, changes had to be made to allow glibc to read symbols set by the kernel linker script instead of trying to read them from the (non-existent) ELF binary. C++ constructors run in the same way as in a normal process. Command-line parameters to main are extracted from a part of the Linux kernel command line, allowing these to be changed without recompilation.

**对 execve 的更改：** 我们修改了 execve 以跳过某些步骤（比如加载应用程序二进制文件，它在 UKL 中不存在），但是大多数步骤都是未经修改的运行。值得注意的是，在运行 UKL 线程时，execve 将直接跳转到 glibc 入口点，而不是尝试读取应用程序二进制文件以获取入口点。Glibc 初始化几乎与正常情况一样，但是在初始化线程本地存储时，必须进行更改，以允许 Glibc 读取内核链接器脚本设置的符号，而不是尝试从（不存在的）ELF 二进制文件中读取。C++ 构造函数的运行方式与普通进程相同。main 的命令行参数是从 Linux 内核命令行的一部分提取出来的，允许在不重新编译的情况下更改这些参数。

> Transition between application and kernel code: On transitions between application and kernel code, the normal entry and exit code of the Linux kernel is executed, with the only change being that transitions code use call/ret instead of syscall/sysret.

**应用程序代码和内核代码之间的转换：** 在应用程序代码和内核代码之间的转换时，执行 Linux 内核的正常入口和退出代码，唯一的变化是转换代码使用 call/ret 而不是 syscall/sysret。

> The different configurations of UKL, mentioned in Table 1 involve changes to the transitions between application and kernel code. All changes were made through Linux(SYSCALL_DEFINE)macros andglibc(INLINE_SYSCALL)macros.
For example, to enable UKL_BYP mode, we generate a stub in the kernel SYSCALL_DEFINE macro that is invoked by the corresponding glibc macro. We use a per-thread flag (ukl_byp) to identify if the bypass optimization is turned on or off for that thread.

表 1 中提到的 UKL 的不同配置涉及到对应用程序和内核代码之间转换的更改。所有更改都是通过 Linux 的（SYSCALL_DEFINE）宏和 glibc (INLINE_SYSCALL) 宏进行的。例如，为了启用 UKL_BYP 模式，我们在内核 SYSCALL_DEFINE 宏中生成一个插赃（stub），由相应的 glibc 宏调用。我们使用每线程（per-thread）标志（ukl_byp）以确定是否为该线程打开或关闭了旁路优化。

> Linux tracks whether a process is running in user mode or kernel mode through the value in the CS register, but UKL is always in kernel mode (except for the normal user-space, which runs in user mode). So the UKL thread tracks this in a flag (ukl_mode) in the kernel’s thread control block i.e., task_struct.

Linux 通过 CS 寄存器中的值跟踪进程是在用户模式下运行还是在内核模式下运行，但是 UKL 总是在内核模式下运行（普通用户空间用户模式下运行）。因此，UKL 线程通过内核的线程控制块（即 task_struct）中的一个标志（ukl_mode）进行跟踪。

> The UKL_RET configuration option replaces iret after application code is interrupted by a page fault or interrupt with a ret. The challenge is that we cannot enable interrupts until we have switched from the kernel stack to the application stack, or the system might land in an undefined state. To do so, we first copy the return address and user flags from the current stack to the user stack. Then we switch to the user stack, and this ensures that even if interrupts are enabled now, we are on the correct stack where we can return to again. We then pop the flags, and then do a simple ret because return address is already on stack. We make sure to restore user flags at the very end, because restoring user flags would turn interrupts on. This has allowed us performance improvement while also ensuring correct functionality.

在应用程序代码页面错误中断或 ret 中断后，UKL_RET 配置选项替换了 iret。挑战在于，在我们从内核堆栈切换到应用程序堆栈之前，我们无法启用中断，否则系统可能会处于未定义状态。为此，首先将返回地址和用户标志从当前堆栈复制到用户堆栈。然后我们切换到用户堆栈，这确保了即使现在启用了中断，我们也在正确的堆栈上，可以再次返回。然后弹出标志，然后执行一个简单的 ret 操作，因为返回地址已经在堆栈上了。我们确保在最后恢复用户标志，因为恢复用户标志将打开中断。这使我们能够在确保功能正确的同时提高性能。

> Enabling shared stacks: In the UKL base model, a stack switch occurs between user and kernel stack when transition between user and kernel code happens. To enable link-time optimizations, it is important to avoid those transitions. The UKL_NSS configuration option involves changes to the low level transition code to avoid stack switch. While this works, it limits how UKL can be deployed because it breaks the expectation that different processes can run alongside the UKL application. To illustrate the problem, consider the case of an inter-processor interrupt to another processor for TLB invalidation. In this case, Linux stores information on the current process stack, which is a user stack if stack switching is turned off. On the other processor, some non-UKL thread might be running, which is interrupted by the IPI. Kernel will inherit that other process’s page tables and then try to access the information stored on the UKL thread’s user stack, essentially trying to access user pages that might not be mapped in the current page tables, resulting in a kernel panic. When this configuration option is used, required tools and setup scripts need to run before the UKL application runs, and clean up scripts, etc., run after the UKL application finishes execution.

**启用共享堆栈：** 在 UKL 基础模型中，当发生用户和内核代码之间的转换时，用户和内核堆栈之间将会进行堆栈切换。为了实现链接时优化，避免这些转换非常重要。UKL_NSS 配置选项涉及对底层转换代码的更改，以避免堆栈切换。虽然这样可以运行，但它限制了 UKL 的部署方式，因为它打破了不同进程可以与 UKL 应用程序一起运行的期望。为了说明这个问题，考虑核间中断到另一个处理器时发生的 TLB 失效问题。在这种情况下，Linux 将信息存储在当前进程堆栈上，如果堆栈切换被关闭，它就是一个用户堆栈。在另一个处理器上，可能正在运行一些非 ukl 线程，这些线程被 IPI 中断。内核将继承其他进程的页表，然后尝试访问存储在 UKL 线程的用户堆栈上的信息，本质上是尝试访问可能没有映射到当前页表中的用户页，从而导致内核 panic。当使用此配置选项时，需要在 UKL 应用程序运行之前运行所需的工具和安装脚本，并在 UKL 应用程序完成执行后运行清理脚本等。

> The inability to run concurrent processes alongside the UKL application precluded a class of applications. So the UKL_NSS_PS configuration option allocates large, fixed-sized stacks in the kernel part of the address range. This allowed multiple processes to run concurrently. This, however precluded a different class of applications, i.e., those which create a large number of threads or forks, etc., which might exhaust the kernel part of the address space.

不能在运行 UKL 进程的同时运行并发应用程序排除了一类应用程序。因此，UKL_NSS_PS 配置选项在内核地址范围分配大的、固定大小的堆栈。这允许多个进程并发运行。然而，这排除了另一类应用程序，即那些创建大量线程或进程的应用程序，这些应用程序可能耗尽内核的地址空间。

> Page-faults: If UKL_NSS configuration option is on, deadlocks can occur. Imagine if some kernel memory management code was being executed, e.g., mmap, the current thread must have taken a lock on the memory control struct (mm_struct). During the execution of that code, if a stack page fault occurs (which is normal for user stacks), control moves to the page
fault handler, which then tries to take the lock of mm_struct to read which virtual memory area(VMA) the faulting address belongs to and how to handle it. Since the lock was already taken, the page fault handler waits. But the lock will never be given up because that same thread is in the page fault handler. We solved this by saving a reference to user stack VMA when a UKL thread or process is created. In case of page faults, while user stacks are used throughout, we first check if the faulting address is a stack address by comparing it against the address range given in the saved VMA. If so, we know it’s a stack address, and the code knows how to handle it without taking any further lock. If not, we first take a lock to retrieve the correct VMA and move forward normally.

**页面错误：** 如果打开了 UKL_NSS 配置选项，则可能发生死锁。想象一下如果有一些内核内存管理正在执行的代码，例如 mmap，当前线程必须在内存控制结构（mm_struct）上获取锁。
在执行该代码期间，如果发生堆栈页错误（这对于用户栈来说是正常的），控制转移到页面故障处理程序，然后该处理程序尝试获取 mm_struct 的锁，以读取故障地址属于哪个虚拟内存区域（VMA）以及如何处理它。由于锁已经被占用，页面错误处理程序将等待。但是这个锁永远不会被放弃，因为同一个线程在页面错误处理程序中。我们通过在创建 UKL 线程或进程时保存对用户堆栈 VMA 的引用来解决这个问题。在页面错误的情况下，当用户堆栈一直使用时，我们首先通过将故障地址与保存的 VMA 中给出的地址范围进行比较来检查故障地址是否为堆栈地址。如果是，我们就知道它是一个堆栈地址，并且代码知道如何在不采取任何另外的锁的情况下处理它。如果没有，我们首先获取一个锁来检索正确的 VMA 并正常向前推进。

> In kernel mode, on a page fault, the hardware does not switch to a fresh stack. It tries to push some state on its current (user) stack. Since there is no stack left to push this state, UKL gets a double fault. We fix this through the UKL_PF_DF configuration option by causing the hardware to raise a double fault and then checking, in the double fault handler, if the fault is to a stack page, and if so, branch to the regular page fault handler (double fault always gets a dedicated stack, so it does not triple fault).

在内核模式下，当出现页面错误时，硬件不会切换到新的堆栈。它尝试在当前（用户）堆栈上推送一些状态。因为没有堆栈可以推入这个状态，UKL 犯了双重错误。我们通过 UKL_PF_DF 配置选项来解决这个问题，方法是让硬件引发一个双重错误，然后在双重错误处理程序中检查该错误是否指向堆栈页面，如果是，则分支到常规的页面错误处理程序（双重错误总是得到一个专用的堆栈，所以它不会三重错误）。

> We also came up with the UKL_PF_SS configuration option to solve this problem, i.e., by updating the IDT to ensure that the page fault handler always switches to a dedicated stack through the Interrupt Stack Table (IST) mechanism.

我们还提出了 UKL_PF_SS 配置选项来解决这个问题，即通过更新 IDT 来确保页面错误处理程序总是通过中断堆栈表（IST）机制切换到专用堆栈。

> Clone and Fork: To create UKL threads, the user-space pthread library runs pthread_create which further calls clone. We modified this library to pass a new flag CLONE_UKL to ensure the correct initial register state is copied into the new task either from the user stack or kernel stack, depending on whether the parent is configured to switch to kernel stack or not.

**Clone 和 Fork：** 要创建 UKL 线程，用户空间的 pthread 库运行 pthread_create，它进一步调用 Clone。我们修改了这个库来传递一个新的标志 CLONE_UKL，以确保从用户堆栈或内核堆栈将正确的初始寄存器状态复制到新任务中，这取决于父进程是否被配置为切换到内核堆栈。

## 5 评估（Evaluation）

> After our experimental environment (§5.1), §5.2 discusses our experience with UKL supporting the fundamental non-performance goals of enabling Linux’s application support, HCL, and ecosystem. In Section 5.3 microbenchmarks are used to evaluate the performance of UKL on simple system calls (§5.3.1), more complex system calls (§5.3.2) and page faults (§5.3.3). We find that, while the advantage of just avoiding the hardware overhead of system calls is small, the advantage of adopting unikernel optimizations is large for simple kernel calls (e.g., 83%) and significant for page faults (e.g., 12.5%). Moreover, the improvement is significant even for expensive kernel calls that transfer 8KB of data (e.g., 24%).

在我们的实验环境（§5.1）之后，§5.2 讨论了我们使用 UKL 支持的基本非性能目标的经验，包括允许 Linux 应用程序支持，HCL（Hardware Compatibility List）和生态系统。在 5.3 节中，微基准测试用于评估 UKL 在简单系统调用（第 5.3.1 节）、更复杂系统调用（第 5.3.2 节）和页面错误（第 5.3.3 节）上的性能。我们发现，虽然仅仅避免系统调用的硬件开销的优势很小，但采用单内核优化的优势对于简单的内核调用很大（例如，83%），对于页面错误也很重要（例如，12.5%）。此外，即使对于传输 8KB 数据的昂贵内核调用（例如，24%），这种改进也是显著的。

> In Section 5.4 we evaluate applying unikernel optimizations to both throughput (Redis §5.4.1, Memcached §5.4.2) and latency bound (Secrecy §5.4.3) applications. We find that configuration options provided by UKL can enable significant throughput improvements (e.g., 12%) and a simple 10 line change in Redis code results in more significant gains (e.g., 26%). The results are even more dramatic for latency-sensitive applications where configuration changes result in 15% improvement and a trivial application change enables a 100x improvement in performance.

在 5.4 节中，我们评估将单内核优化应用于吞吐量（Redis§5.4.1,Memcached§5.4.2）和延迟敏感（Secrecy§5.4.3）的应用程序。我们发现，UKL 提供的配置选项可以显著提高吞吐量（例如，12%），Redis 代码中简单的 10 行更改会带来更显著的收益（例如，26%）。对于对延迟敏感的应用程序，结果更加显著，其中配置更改导致 15% 的改进，而一个微不足道的应用程序更改可以使性能提高 100 倍。

### 5.1 实验设置（Experimental Setup）

> Experiments are run on Dell R620 servers configured with 128G of ram arranged as a single NUMA node. The servers have two sockets, each containing an Intel Xeon CPU E5-26600 @ 2.20GHz, with 8 real cores per socket. The processors are configured to disable Turbo Boost,hyper-threads, sleep states, and dynamic frequency scaling. The servers are connected through a 10Gb link and use Broadcom NetXtremeII BCM57800 1/10 Gigabit Ethernet NICs. Experiments run on multiple computers use identically configured machines attached to the same top of rack switch to reduce external noise. On the software side, we use Linux 5.14 kernel and glibc version 2.31. Linux and different configurations of UKL were built with same compile-time config options. We ran experiments on virtual and physical hardware and got consistent and repeatable results. In the interest of space, we only report bare-metal numbers unless stated otherwise.

实验运行 Dell R620 服务器上，服务器配置的 128G RAM 被安排为单个 NUMA 节点。服务器有两个插槽，每个插槽都包含一个英特尔至强处理器 E5-26600 @ 2.20GHz，每个插槽有 8 个 real core。处理器被配置为禁用 Turbo Boost、超线程、睡眠状态和动态频率缩放。服务器通过 10Gb 的链路连接，并使用 Broadcom NetXtremeII BCM57800 1/10 千兆以太网网卡。实验在多台计算机上运行，使用相同配置的机器连接到相同的机架顶部开关，以减少外部噪音。在软件方面，我们使用 Linux 5.14 内核和 glibc 2.31 版本。Linux 和不同的 UKL 配置是用相同的编译时配置选项构建的。我们在虚拟和物理硬件上进行了实验，得到了一致和可重复的结果。由于篇幅的关系，除非另有说明，否则我们只报告裸金属数据。

### 5.2 Linux 应用程序、硬件及生态系统（Linux application hardware & ecosystem）

> The fundamental goals of the UKL project are to integrate unikernel optimizations without losing Linux’s broad support for applications, hardware, and ecosystem. We discuss each of these three goals in turn.

UKL 项目的基本目标是在不失去 Linux 对应用程序、硬件和生态系统的广泛支持的情况下集成单内核优化。我们依次讨论这三个目标。

> Application support: As expected, we have had no difficulty running any Linux application as normal user-level processes on our modified kernel. We have used hundreds of unmodified binaries running as normal user-level processes without effort. That includes all the standard UNIX utilities, bash, different profilers, perf, and eBPF tools.

应用程序支持：正如预期的那样，在修改后的内核上运行任何 Linux 应用程序作为普通用户级进程都没有任何困难。我们使用了数百个未经修改的二进制文件作为普通的用户级进程运行。这包括所有标准的 UNIX 实用程序、bash、不同的分析器、perf 和 eBPF 工具。

> Dozens of unmodified applications have been tested as optimization targets for UKL. These include Memcached, Redis, Secrecy, a small TCP echo server, simple test programs for C++ constructors and the STL, a complex C++ graph based benchmark suite, a performance benchmark called LEBench, and a large number of standard glibc and pthread unit test programs.
数十个未经修改的应用程序已经作为 UKL 的优化目标进行了测试。其中包括 Memcached，Redis，Secrecy，一个小型的 TCP 回显服务器，一些简单的用于测试 c++ 构造器和 STL 测试程序，一个复杂的基于 c++ 图形的基准测试套件，一个名为 LEBench 的性能基准测试，以及大量标准的 glibc 和 pthread 单元测试程序。

> There are some challenges in getting some applications running on UKL. First, as expected, one needs to be able to re-compile and statically link both the application and all its dependencies. Second, we have hit a number of programs that by default invoke fork followed by exec e.g., Postgress, and many that are dependent on the dynamic loader through calls to dlopen and others. Third, we have run into issues of proprietary applications available in only binary form, e.g., user-level libraries for GPUs.

让一些应用程序在 UKL 上运行存在一些挑战。首先，正如预期的那样，需要能够重新编译和静态链接应用程序及其所有依赖项。其次，我们遇到了一些默认情况下先调用 fork 再调用 exec 的程序，例如 Postgress，以及许多依赖于动态加载器的程序调用 dlopen 和其他。第三，我们遇到了闭源应用程序仅以二进制形式可用的问题，例如，用于 GPU 的用户级库。

> Hardware support: For hardware, we have not run into any compatibility issues and have booted or kexeced to UKL on five different x86-64 servers and virtualization platforms. The scripts and tools used to deploy and manage normal Linux machines were used for UKL deployments as well.

硬件支持：对于硬件，我们没有遇到任何兼容性问题，并且已经在五个不同的 x86-64 服务器和虚拟化平台上启动或执行到 UKL。用于部署和管理普通 Linux 机器的脚本和工具也用于 UKL 部署。

> Ecosystem: Due to having a full-fledged userspace, we have been able to run all the different applications, utilities, and tools that can run on unmodified Linux. This has been extremely critical in building UKL, i.e., we use all the debugging tools and techniques available in Linux. We have been able to profile UKL workloads with perf and able to identify
code paths that could be squashed for performance benefits(see fig. 5).

生态系统：由于拥有一个成熟的用户空间，我们已经能够运行所有不同的应用程序、实用程序和工具，这些都可以在未经修改的 Linux 上运行。这在构建 UKL 时非常关键，也就是说，我们使用 Linux 中可用的所有调试工具和技术。我们已经能够对具有性能的 UKL 工作负载进行概要分析，并能够识别可以压缩以获得性能优势的代码路径（见图 5）。

> The UKL patch size for the base model is around 550 lines, and the full UKL patch with all the configurations is 1250 lines. Since the patch is small and non-invasive, we are hopeful that we can work with the Linux community towards upstream acceptance.
基本模型的 UKL 补丁大小约为 550 行，而具有所有配置的完整 UKL 补丁大小为 1250 行。由于该补丁很小且非侵入性，我们希望能够与 Linux 社区合作，使其得到上游的接受。

> Table 2 compares the UKL patch to Kernel-Mode Linux (KML) and a selection of Linux features described in Linux Weekly News (LWN) articles in 2020. For comparison, the KML patch, used in the recent Lupine work, that runs applications in kernel mode is 3177 LOC, a complexity that has resulted in the patch not being accepted upstream. In contrast, UKL both provides richer functionality than KML, and is much simpler. This simplicity is due to three fortuitous changes since KML was introduced. First, UKL, takes advantage of recent changes to the Linux kernel that make the changes to assembly much less intrusive. Second, UKL supports only x86-64, while KML was introduced at a time when it was necessary to support i386 to be relevant. Third, UKL does not deal with older hardware, like the i8259 PIC, that had to be supported by KML.
表 2 将 UKL 补丁与 Kernel-Mode Linux (KML) 以及 2020 年 Linux Weekly News (LWN) 文章中描述的一些 Linux 特性进行了比较。相比之下，在最近的 Lupine 工作中使用的 KML 补丁，在内核模式下运行应用程序是 3177 LOC，这种复杂性导致补丁不被上游接受。相比之下，UKL 既提供了比 KML 更丰富的功能，又简单得多。这种简单性是由于引入 KML 以来的三个偶然变化。首先，UKL 利用了最近对 Linux 内核的修改，使得对汇编的修改干扰性大大降低。其次，UKL 只支持 x86-64，而 KML 是在需要支持 i386 的时候引入的。第三，UKL 不处理旧的硬件，比如必须由 KML 支持的 i8259 PIC。

<div align=center>
	<img src="/wp-content/uploads/2023/12/ukl/translate-table-2.PNG"/>
</div>

### 5.3 微基准测试（Microbenchmarks）

> Unikernels offer the opportunity to dramatically reduce the overhead of interactions between application and kernel code. We evaluate how UKL optimizations impact the overhead of simple system calls (§5.3.1), more expensive system calls (§5.3.2), and page faults (§5.3.3). Our results contradict recent work that suggests that the advantages are modest; we see that the reduction in overhead is larger (e.g., 90%) than previously reported and has a significant impact even for requests with large payloads (e.g., 24% with 8KByte recvfrom()).

Unikernels 提供了显著减少应用程序和内核代码之间交互开销的机会。我们评估了 UKL 优化如何影响简单系统调用（§5.3.1）和更昂贵的系统调用的开销（第 5.3.2 节）和页面错误（第 5.3.3 节）。我们的结果与最近的研究结果相矛盾，该研究表明，这种优势是适度的；我们看到开销的减少比之前报告的更大（例如，90%），甚至对于具有大效负载的请求也有显著的影响（例如，对于 8KByte 的 recvfrom()，减少了 24%）。

#### 5.3.1 系统调用的基础性能（System call base performance）

> Figure 1, compares the overhead of simple system calls between Linux, UKL’s base model, and UKL_BYP. Results were gathered using the (slightly modified4 LEBench) microbenchmark to measure thebaselatency of getppid read,write, sendto, and recvfrom (all with 1 byte payloads).

图 1 比较了 Linux、UKL 的基本模型和 UKL_BYP 之间简单系统调用的开销。使用（稍作修改的 LEBench）微基准测试，用于测量 getppid()、read（）、write()、sendto() 和 recvfrom() 这些系统调用的基本延迟（都是 1 字节的有效负载）。

<div align=center>
	<img src="/wp-content/uploads/2023/12/ukl/translate-figure-1.PNG"/>
</div>

> We find that the advantage of the base model of UKL that essentially replacessyscall/sysretinstructionswithcall/ret is modest, i.e., less than 5%. However, the UKL BYP configuration that avoids expensive checks on transitions between application and kernel code can be up to 83% for a getppid; suggesting that optimizing the transition between application code may have a significant performance impact.

我们发现，UKL 的基本模型的优势本质上是用 call/ret 代替 syscall/sysret 指令，这种优势是适度的，即小于 5%。然而，UKL BYP 配置可以避免在应用程序和内核代码之间的转换上进行昂贵的检查，对于 getppid 来说，这种配置可以达到 83%;这表明优化应用程序代码之间的转换可能会对性能产生重大影响。

#### 5.3.2 大请求（Large requests）

> Figure 2 contrasts the performance of Linux to UKL and UKL_BYP for read, write, sendto and recvfrom as we use LEBench microbenchmark to vary the payload up to 8KB of data. Again, baseline UKL shows very little improvement over Linux, but UKL_BYP shows a significant constant improvement. The right vertical axis also shows the downward trend of percentage improvement of UKL_BYP compared to Linux. As the time spent in the kernel increases, the percentage gain decreases. But even for payloads of up to 8KB, the percentage improvement is still significant, i.e., between 11% and 22%.

图 2 对比了 Linux 与 UKL 和 UKL_BYP 在 read()、write()、sendto() 和 recvfrom() 方面的性能，我们使用 LEBench 微基准测试将有效载荷改变为 8KB 的数据。基线 UKL 再次显示在 Linux 上几乎没有改进，但是 UKL_BYP 显示出显著的持续改进。右纵轴也显示了 UKL_BYP 与 Linux 的比较百分比改善的下降趋势。随着在内核中花费的时间的增加，百分比增益减少。但是，即使对于高达 8KB 的有效负载，改进的百分比仍然很大，即在 11% 到 22% 之间。

<div align=center>
	<img src="/wp-content/uploads/2023/12/ukl/translate-figure-2.PNG"/>
</div>

> It is interesting to contrast our results with those from the recent Lupine work. Surprisingly they observed that just eliminating the system call overhead is significant (40%) for a null system call, but since they found that (like us) the improvement dropped to below 5% in most cases, they concluded that the benefit of co-locating the application and kernel is minimal. Our results suggest that the major performance gain comes not from eliminating the hardware cost but from eliminating all the checks on the transition between the application and kernel code and that reducing this overhead has a significant impact on even expensive system calls.

将我们的结果与最近 Lupine 的研究结果进行对比是很有趣的。令人惊讶的是，他们发现仅仅消除系统调用开销就很重要 (40%)，但是由于他们发现（和我们一样）在大多数情况下，改进下降到 5% 以下，将应用程序和内核放在一起的好处是最小的。我们的结果表明，主要的性能增益不是来自消除硬件成本，而是来自消除应用程序和内核代码之间转换的所有检查，并且减少这种开销对昂贵的系统调用也有重大影响。

#### 5.3.3 页面故障处理（Page Faulthandling）

> Figure 3 compares three different schemes we have for handing page faults, i.e., UKL_PF_DF, UKL_PF_SS and (UKL_RET_PF_DF). For UKL_PF_DF, we see close to 5% improvement in page fault latency compared to Linux. UKL_PF_SS is also comparable to the previous case, which means that stack switch on every page fault is not too costly, and most of the benefit over Linux in both these cases is due to handling page faults in kernel mode and avoiding ring transition. (UKL_RET_PF_DF) gives us more than 12.5% improvement over normal Linux. In all these cases, since the time taken to service more page faults increases, the improvement over normal Linux also increases, which is why we see a constant percentage improvement. Unmodified applications can choose anyone of these options through build time Linux config options.

图 3 比较了处理页面错误的三种不同方案，即 UKL_PF_DF、UKL_PF_SS 和 (UKL_RET_PF_DF)。对于 UKL_PF_DF，我们看到页面错误延迟比相比于 Linux 有将近 5% 的改进。UKL_PF_SS 也与前一种情况类似，这意味着在每个页面错误上进行堆栈切换的成本不会太高，而且在这两种情况下相对于 Linux 的大部分好处是由于在内核模式下处理页面错误并避免了环转换。(UKL_RET_PF_DF) 比普通 Linux 改进了 12.5% 以上。在所有这些情况下，由于处理更多页面错误所需的时间增加了，因此相对于普通 Linux 的改进也增加了，这就是为什么我们看到一个恒定百分比的改进。未修改的应用程序可以通过构建时 Linux 配置选项选择这些选项中的任何一个。

<div align=center>
	<img src="/wp-content/uploads/2023/12/ukl/translate-figure-3.PNG"/>
</div>

> We repeated this experiment for non-stack page faults, i.e., on mapped memory and got the same results.

我们对非栈页面错误（即在映射内存上）重复这个实验，得到了相同的结果。

### 5.4 应用性能（Application performance）

> We want to see how real world applications perform on UKL. We chose three different types of applications: a simple application (Redis) used by previous works as well, a more complex application (Memcached) that many unikernels don’t support unmodified, and a latency-sensitive application (Secrecy). Our results show significant advantages in Redis (26%), Memcached (8%), and Secrecy (100x).

我们想看看真实世界的应用程序在 UKL 上的表现。我们选择了三种不同类型的应用程序：一个以前的研究也使用过的简单的应用程序（Redis），一个未修改的、并且其他 unikernels 不支持的更复杂的应用程序（Memcached），和一个延迟敏感的应用程序（Secrecy）。我们的结果显示具有显著的优势，Redis（26%）、Memcached（8%）和 Secrecy（100x）。

#### 5.4.1 简单应用：Redis（Simple Application: Redis）

> We use Redis, a widely usedin-memory database, tomeasure the performance of UKL and its different configurations in real world applications. For this experiment, we ran Redis server on UKL on bare metal and ran the client on another physical node in the network.

我们使用 Redis，一个广泛使用的内存数据库，来衡量在现实世界的应用程序中的性能和它的不同配置。在这个实验中，我们在裸机上的 UKL 上运行 Redis 服务器，在网络中的另一个物理节点上运行客户端。

> We use the Memtier benchmark to test Redis. Through Memtier benchmark, we create 300 clients, each sending 100 thousand requests to the server. The ratio of get to set operations in 1 to 10. We ran Redis on Linux, UKL_RET_BYP and UKL_RET_BYP with deeper shortcuts. Figure 4 helps us visualize the latency distribution for these requests.

我们使用 Memtier 基准测试来测试 Redis。通过在 Memtier 基准测试中，我们创建 300 个客户端，每个客户端向服务器发送 10 万个请求。get 和 set 操作的比率为 1 比 10。我们在 Linux 上，分别开启 UKL_RET_BYP 和具有更深捷径的 UKL_RET_BYP 来运行 Redis。图 4 帮助我们可视化这些请求的延迟分布。

<div align=center>
	<img src="/wp-content/uploads/2023/12/ukl/translate-figure-4.PNG"/>
</div>

> To better understand where the time was being spent, we profiled Redis UKL with perf. Figure 5, which is part of the flame graph we generated, shows two clear opportunities for performance improvement. Blue arrows show how we could shorten the execution path by bypassing the entry and exit code for read and write system calls and invoke the underlying functionality directly. Figure 4 shows how Redis on UKL_RET shows improvement in average and 99th percentile tail latency when it bypasses the entry and exit code (UKL_RET_BYP). Table 3 shows that UKL_RET_BYP has 11% better tail latency and 12% better throughput.
<div align=center>
	<img src="/wp-content/uploads/2023/12/ukl/translate-table-3.PNG"/>
</div>

为了更好地了解时间消耗在哪里，我们用 perf 对 Redis UKL 进行了分析。图 5 是我们生成的 flame graph 的一部分，它显示了两个明显的性能改进机会。蓝色箭头显示了我们如何通过绕过读写系统调用的入口和退出代码来缩短执行路径，并直接调用底层功能。图 4 显示了当 Redis 绕过进入和退出代码（UKL_RET_BYP）时，UKL_RET 上的平均和第 99 百分位尾部延迟是如何改善的。表 3 显示，UKL_RET_BYP 的尾部延迟提高了 11%，吞吐量提高了 12%。

<div align=center>
	<img src="/wp-content/uploads/2023/12/ukl/translate-figure-5.PNG"/>
</div>

> Looking at Figure 5 again, the green arrows show that read and write calls, after all the polymorphism, eventually translate into tcp_recvmsg and tcp_sendmsg respectively. To investigate any potential benefit of shortcutting deep into the kernel, we wrote some code in the kernel to interface read and write with tcp_recvmsg and tcp_sendmsg respectively. We then modified Redis (10 lines modified) to call our interface functions instead of read and write. Our results show (Figure 4) further improvement in average and 99th percentile tail latency i.e., UKL_RET_BYP (shortcut). Table 3 shows that UKL_RET_BYP (shortcut) has 22% better tail latency and 26% better throughput.

再次查看图 5，绿色箭头显示在所有多态性之后，读和写调用最终分别转换 tcp_recvmsg 和 tcp_sendmsg。为了研究深入内核的快捷方式的潜在好处，我们在内核中编写了一些代码，分别使用 tcp_recvmsg 和 tcp_sendmsg 进行读写操作。然后我们修改了 Redis（修改了 10 行）来调用我们的接口函数，而不是读写。我们的结果显示（图 4）平均和第 99 百分位尾部延迟的进一步改善，即 UKL_RET_BYP（快捷方式）。表 3 显示 UKL_RET_BYP（快捷方式）的尾部延迟提高 22%，吞吐量提高 26%。

> Figure 4 provides us some nice insights into future possibilities. There is almost a 0.5ms difference in the shortest latencies for Linux versus UKL_RET_BYP (shortcut) case. This means that there is an opportunity to further reduce the average and tail latencies to sit closer to the smallest latency case.

图 4 为我们提供了一些关于未来可能性的深刻见解。Linux 与 UKL_RET_BYP（快捷方式）相比，最短延迟几乎相差 0.5ms。这意味着有机会进一步减少平均和尾部延迟，使其更接近最小延迟情况。

> Lupine shows slightly better results than baseline Linux for Redis, but it does so in virtualization on a lightweight hypervisor. It would be interesting to see how UKL performs in that setting, even though there is a huge difference in kernel versions used by Lupine and UKL.

Lupine 在 Redis 上显示的结果略好于基线 Linux，但它是在轻量级管理程序上进行虚拟化的。尽管 Lupine 和 UKL 使用的内核版本存在巨大差异，但看看 UKL 在这种情况下的表现将是一件很有趣的事情。

#### 5.4.2 复杂应用：Memcached（Complex Application: Memcached）

> Memcached is a multithreaded workload that relies heavily on pthreads library and glibc ’s internal synchronization mechanisms. It is an interesting application because unikernels generally don’t support complex applications, and systems like EbbRT first have to port Memcached. To evaluate Memcached, we use the Mutilate benchmark. This benchmark uses multiple clients to generate a fixed queries-per-second load on the server and then measures the latency. We ran the clients in userspace on the same node as Memcached UKL to remove any network delays, and we pinned the Memcached server and clients to separate cores. We used Mutilate to generate queries based on Facebook’s workloads. For different configurations of UKL, we measured how many queries per second Memecached can serve while keeping the 99% tail latency under the 500 us service level agreement. Figure 6 shows Memcached with UKL_RET performs similar to Memcached on Linux, i.e., both serve around 73 thousand queries before exceeding the 500 us threshold. Memcached on UKL_RET_BYP can serve around 77 thousand queries(around 5% improvement), and Memcached on UKL_RET_BYP (shortcut) can serve up to 79 thousand queries (around 8% improvement) before going over the 500 us threshold.

Memcached 是一个严重依赖 pthread 库和 glibc 的内部同步机制的多线程工作负载。这是一个有趣的应用程序，因为 unikernels 通常不支持复杂的应用程序，像 EbbRT 这样的系统首先必须移植 Memcached。为了评估 Memcached，我们使用了 mutlate 基准测试。此基准测试使用多个客户机在服务器上生成固定的每秒查询数负载，然后测量延迟。我们在用户空间中与 Memcached UKL 在同一个节点上运行客户端，以消除任何网络延迟，并且我们将 Memcached 服务器和客户端固定在不同的核心上。我们使用 mutinate 来生成基于 Facebook 工作负载的查询。对于不同的 UKL 配置，我们测量了 Memecached 每秒可以处理多少查询，同时在 500 us 服务级别协议下保持 99% 的尾部延迟。图 6 显示了具有 UKL_RET 的 Memcached 执行类似于 Linux 上的 Memcached，例如，它们都在超过 500 个请求的阈值之前提供大约 73000 个查询。Memcached 上 UKL_RET_BYP 可以提供大约 77000 个查询而在 UKL_RET_BYP（快捷方式）上的 Memcached 在超过 500 us 阈值之前可以提供多达 79000 个查询（大约提高 8%）。

<div align=center>
	<img src="/wp-content/uploads/2023/12/ukl/translate-figure-6.PNG"/>
</div>

> This experiment also serves as a functionality and compatibility result; a comparatively large application with multiple threads etc. can run on UKL.
本实验也作为功能性和兼容性的结果；具有多个线程等的较大应用程序可以在 UKL 上运行。

#### 5.4.3 对延迟敏感的应用：Secrecy（Latency Sensitive Application: Secrecy）

> Secrecy is a multi-party computation framework for secure analytics on private data. While Redis and Memcached are throughput sensitive, Secrecy is latency-sensitive. This represents an important class of applications, e.g., highspeed financial trading, etc. Secrecy is a three node protocol with each node sending data to its successor and receiving from its predecessor with the third node sending to the first. Computation is done row by row with a round of messages that act as a barrier between each row.

Secrecy 是一个多方计算框架，用于对私有数据进行安全分析。Redis 和 Memcached 是吞吐量敏感的，而 secrecy 是延迟敏感的。这代表了一类重要的应用，例如高速金融交易等。Secrecy 是一个三节点协议，每个节点向后继节点发送数据，并从前一个节点接收数据，第三个节点向第一个节点发送数据。计算逐行进行，并使用一轮消息作为每行之间的屏障。

> We used a test in the Secrecy implementation for a GROUPBY operator which groups rows in a table by key attributes and counts the number of rows per group. Messages used in a round of communication are each very small, between 8 and 24 bytes each, so we configured each TCP socket to use TCP_NODELAY to avoid stalls caused by congestion control. Using this test executable, we ran experiments with 100, 1000, and 10,000 input rows and measured the time required to complete the GROUP-BY. Each system and row size combination was run 20 times, and the worst two runs for each combination were discarded.

我们在 Secrecy 实现中对 GROUPBY 操作符进行了测试，该操作符根据键属性对表中的行进行分组，并计算每组的行数。在一轮通信中使用的每个消息都非常小，每个消息在 8 到 24 字节之间，因此我们配置了要使用的每个 TCP 套接字 TCP_NODELAY 避免拥塞控制造成的延时。使用这个测试可执行文件，我们运行了 100、1000 和 10000 个输入行的实验，并测量了完成 GROUPBY 所需的时间。每个系统和行大小组合运行 20 次，每个组合的最差的两次运行被丢弃。

> Figure 7 shows the run times of the three systems normalized to the run time of Linux and the error bars show the coefficient of variation for each configuration. As with other experiments, the UKL_BYP configuration shows a modest improvement in run time. However, when we use the deeper shortcut to the TCP send and receive functions, we see significant (100x) runtime improvements.

图 7 显示了三个系统的运行时间归一化为 Linux 的运行时间，误差条显示了每种配置的变异系数。与其他实验一样，UKL_BYP 配置在运行时显示出适度的改进。然而，当我们对 TCP 发送和接收函数使用更深的快捷方式时，我们看到了显著的（100x）运行时改进。

<div align=center>
	<img src="/wp-content/uploads/2023/12/ukl/translate-figure-7.PNG"/>
</div>

> The improvement of the shortcut system over the others was larger than anticipated, so we reran the experiments and achieved the same level of performance. To verify that the work was still happening, we collected a capture of all the inter-node traffic using Wireshark and verified that the same number of TCP packets traveled between nodes in all three system setups for a 100 row experiment.We also instrumented the send and receive paths in Secrecy to collect individual times for send and receive calls in each system for a 100 row run. The mean and standard deviation of send times for Linux were 2.23us and 1.14us, respectively, and the values for receive times on Linux were 1,100us and 3,300us, respectively. The shortcut showed send mean and standard deviation of 896ns and 1,755ns, which is a significant speed up, but the receive numbers were 638ns and 3,888ns.

快捷系统相对于其他系统的改进比预期的要大，因此我们重新进行了实验，并达到了相同的性能水平。为了验证工作是否仍在进行，我们使用 Wireshark 收集了所有节点间流量的捕获，并验证了在所有三个系统设置中，在 100 行实验中，节点之间传输的 TCP 数据包数量相同。我们还检测了 Secrecy 中的发送和接收路径，以收集每个系统中 100 行的发送和接收调用的单独时间运行。Linux 系统的发送次数均值和标准差分别为 2.23us 和 1.14us，Linux 系统的接收次数均值和标准差分别为 1100 us 和 3300 us。快捷方式显示发送均值和标准差分别为 896ns 和 1755ns，速度明显加快，但接收数分别为 638ns 和 3888ns。

> It appears that, with the shortcut, the systemis never having to wait on packet delivery on top of bypassing system call entry and exit paths, so the shortcut system is never put to sleep waiting on incoming messages. We believe that because Secrecy is latency-sensitive and because we accelerate the send path, we ensure that no node ever has to wait for data and can move to the next round of processing immediately. Moreover, the shortcut implicitly disables scheduling on transitions, ensuring that the application is always run to completion. This is critical for an application with frequent barriers.

看起来，使用快捷方式，系统在绕过系统调用进入和退出路径的基础上永远不必等待数据包传递，因此快捷方式系统永远不会在等待传入消息时处于休眠状态。我们相信，因为 Secrecy 是延迟敏感的，因为我们加速了发送路径，我们确保没有节点需要等待数据，可以立即进入下一轮处理。此外，该快捷方式隐式地禁用了转换调度，确保应用程序始终运行到完成。这对于具有频繁障碍的应用程序至关重要。

## 6 相关工作（Related Work）

> There has been a huge body of research on unikernels that we categorize as clean slate designs, forks of existing operating systems, and incremental systems.

我们已经对 unikernels 进行了大量的研究，我们将其归类为全新设计、通用操作系统的分支和增量系统。

> CleanSlateUnikernels: Many unikernel projects arewritten from scratch or use a minimal kernel like MiniOS for bootstrapping. These projects have complete control over the language and methodology used to construct the kernel. MirageOS uses OCaml to implement the unikernel and uses the language and compiler level features to ensure robustness against vulnerabilities and small attack surface. Similarly, OSv uses lock-free scheduling algorithms to gain performance benefits for unmodified applications. Implementations in clean-slate unikernels can also be fine-tuned for performance of specific applications, e.g., Minicache optimizes Xen and MiniOS for CDN based use case. Further, from scratch implementations can easily expose efficient, low-level interfaces to applications e.g., EbbRT. Different clean slate unikernels can often be polar opposites in some regards, exposing the wide range of choices available to them. Forinstance, some might target custom APIs for performance while like HermiTux target full Linux ABI compatibility. Recently, efforts like Unikraft provide strong POSIX support while also allowing custom APIs for further performance gains.

全新设计。许多 unikernel 项目都是从头开始编写的，或者使用像 MiniOS 这样的最小内核来引导。这些项目完全控制用于构造内核的语言和方法。MirageOS 使用 OCaml 实现单内核，并使用语言和编译器级别的特性来确保对漏洞的鲁棒性和较小的攻击面。同样，OSv 使用无锁调度算法来获得未修改应用程序的性能优势。在全新 unikernel 中的实现也可以针对特定应用程序的性能进行微调，例如，Minicache 优化了 Xen 和基于 CDN 的 MiniOS 用例。此外，从头开始实现可以很容易地将高效、低级的接口暴露给应用程序，例如 EbbRT。不同的全新单内核在某些方面通常是截然相反的，这就为它们提供了广泛的选择。例如，有些可能针对自定义 API 的性能，而像 HermiTux 目标是完全兼容 Linux ABI。最近，像 Unikraft 这样的努力提供了强大的 POSIX 支持，同时还允许自定义 API 来进一步提高性能。

> These unikernel offer compelling trade-offs to general purpose operating systems. These include improved security and smaller attack surfaces e.g., Xax and MirageOS, shorter boot times e.g., ClickOS and LightVM, efficient memory use through single address space e.g., OSv and many others, and better run-time performance e.g., EbbRT, Unikraft and SUESS. Some approaches target direct access to virtual or physical hardware. A number of researchers have directly confronted the problem of compatibility, e.g., OSv is almost Linux ABI compatible and HermiTux is fully ABI compatible with Linux binaries. Other projects aim to make building unikernels easier e.g., EbbRT, Libra and Unikraft.

这些 unikernel 为通用操作系统提供了令人信服的折衷。这些包括改进的安全性和更小的攻击面，例如 Xax 和 MirageOS，更短的启动时间，例如 ClickOS 和 LightVM，通过单个地址空间高效地使用内存，例如 OSv 和许多其他，以及更好的运行时性能，例如，EbbRT、Unikraft、SUESS。一些方法针对直接访问虚拟或物理硬件。许多研究者直接面对兼容性问题，例如 OSv 几乎与 Linux ABI 兼容，HermiTux 与 Linux 二进制文件完全 ABI 兼容。其他项目旨在使构建 unikernel 更容易，例如 EbbRT，Libra 和 Unikraft。

> The UKL effort was inspired by the tremendous results demonstrated by clean slate unikernels. Our research targets trying to find ways to integrate some of the advantages these systems have shown into a general-purpose OS.

UKL 的努力受到了由全新 unikernels 所展示的巨大结果的启发。我们的研究目标是试图找到将这些系统所显示的一些优点集成到通用操作系统中的方法。

> Forks of General Purpose OS. A number of projects either fork an existing general-purpose OS code base or reuse a significant portion of one. Examples include Drawbridge which harvests code from Windows, Rump kernel which uses NetBSD drivers and Linux Kernel Library (LKL) which borrows code from Linux. These systems, although constrained by the design and structure of the original OS, generally have better compatibility with existing applications. The codebase these systems fork are well tested and can serve as building blocks for other research projects, e.g., Rump has been used in other projects.

通用操作系统的分支。许多项目要么派生现有的通用操作系统代码库，要么重用其中的很大一部分。例如，Drawbridge 从 Windows 中获取代码，Rump kernel 使用 NetBSD 驱动程序，Linux kernel Library (LKL) 从 Linux 中借用代码。这些系统虽然受到原始操作系统的设计和结构的限制，但通常与现有应用程序具有更好的兼容性。这些系统分叉的代码库经过了良好的测试，可以作为其他研究项目的构建块，例如：Rump 已在其他项目中使用。

> Our goal in UKL is to try to find a way to integrate unikernel optimizations without having the fork the original OS.

我们在 UKL 中的目标是尝试找到一种方法来集成单内核优化，而不需要在原始操作系统上进行分支。

> IncrementalSystems. There are systems, e.g.,KernelMode Linux (KML), Lupine and X-Containers which use an existing general-purpose operating system (Linux) but make comparatively fewer changes. This way, a lot of working knowledge of users of Linux can easily transfer over to these systems, but in doing so, these systems only expose the system call entry points to applications and don’t make any further specializations. Unlike UKL, they don’t co-optimize the application and kernel together. Lupine and X-Containers demonstrate opportunities in customizing Linux through build time configurations, and that is orthogonal and complementary to UKL. UKL can also benefit from a customized Linux and then add unikernel optimizations on top of that.

增量系统。有一些系统，例如 KernelModeLinux (KML)，Lupine 和 X-Containers，它们使用现有的通用操作系统 (Linux)，但进行的更改相对较少。这样，Linux 用户的许多工作知识可以很容易地转移到这些系统中，但是这样做，这些系统只向应用程序公开系统调用入口点，而不进行任何进一步的专门化。与 UKL 不同的是，它们不会共同优化应用程序和内核。Lupine 与 X-Containers 展示了通过构建时配置定制 Linux 的机会，这与 UKL 是正交的和互补的。UKL 还可以从定制的 Linux 中受益，然后此基础上添加单内核优化。

## 7 总结（Concluding remarks）

> UKL creates a unikernel target of glibc and the Linux kernel. The changes are modest, and we have shown even with these, it is possible to achieve substantial performance advantages for real workloads, e.g., 26% improvement in Redis throughput while improving tail latency by 22%. UKL supports both virtualized platforms and bare-metal platforms. While we have not tested a wide range of devices, we have so far experienced no issues using any device that Linux supports. Operators can configure and control UKL using the same tools they are familiar with, and developers have the ability to use standard Linux kernel tools like BPF and perf to analyze their programs.

UKL 创建 glibc 和 Linux 内核的单内核目标。这些变化是适度的，我们已经证明，即使有了这些，也有可能在实际工作负载中实现实质性的性能优势，例如，在 Redis 吞吐量提高 26% 的同时将尾部延迟提高 22%。UKL 同时支持虚拟化平台和裸机平台。虽然我们没有测试过大量的设备，但到目前为止，我们在使用 Linux 支持的任何设备时都没有遇到任何问题。操作人员可以使用他们熟悉的相同工具配置和控制 UKL，开发人员可以使用标准的 Linux 内核工具（如 BPF 和 perf）来分析他们的程序。

> UKL differs in a number of interesting ways from unikernels. First, while application and kernel code are statically linked together, UKL provides very different execution environments for each; enabling applications to run in UKL with no modifications while minimizing changes to the invariants (whatever they are) that the kernel code expects. Second, UKL enables a knowledgable developer to incrementally optimize performance by modifying the application to directly take advantage of kernel capabilities, violating the normal assumptions of kernel versus application code. Third, processes can run on top of UKL, enabling the entire ecosystem of Linux tools and scripting to just work.

UKL 在许多有趣的方面与 unikernels 不同。首先，虽然应用程序和内核代码是静态链接在一起的，但 UKL 为两者提供了非常不同的执行环境；使应用程序无需修改就可以在 UKL 中运行，同时最大限度地减少对内核代码所期望的不变量的更改（不管它们是什么）。其次，UKL 使开发人员能够通过修改应用程序来直接利用内核功能，从而逐步优化性能，这违反了内核代码与应用程序代码之间的常规假设。第三，进程可以在 UKL 之上运行，使整个 Linux 工具和脚本的生态系统能够正常工作。

> We have repeatedly thought that we were only a few weeks away from a stable system, and it has only been recently that we had a design and a set of changes that met our fundamental goals. While the set of changes to create UKL ended up being very small, it has taken us several years of work to get to this point. The unique design decisions are a result of multiple, typically much more pervasive, changes to Linux as we changed directions and gained experience with how the capability we wanted could be integrated into Linux. It is in some sense an interesting experience that the very modularity of Linux that enables a broad community to participate both: 1) makes it very difficult to understand how to integrate a change like UKL and, 2) can be harnessed to enable the change in a very small number of lines of code.

我们一再认为，我们离一个稳定的系统只有几周的时间了，直到最近，我们才有了一个设计和一系列的改变，达到了我们的基本目标。虽然创建 UKL 的更改集最终非常小，但我们花了几年的时间才达到这一点。这种独特的设计决策是对 Linux 的多次（通常是更普遍的）更改的结果，因为我们改变了方向，并获得了如何将我们想要的功能集成到 Linux 中的经验。从某种意义上说，Linux 的模块化使广泛的社区能够参与其中，这是一种有趣的体验：1）很难理解如何集成这样的更改可以利用 UKL 和 2）在非常少的代码行中启用更改。

> The focus of our work so far has been on functionality and just a proof of concept of a performance advantage in order to justify integrating the code into Linux. Now that we have achieved that, we plan to start working on getting UKL upstreamed as a standard target of Linux so that the community will continue to enhance it.

到目前为止，我们的工作重点一直放在功能上，只是为了证明将代码集成到 Linux 中是合理的，从而证明了性能优势的概念。现在我们已经实现了这一点，我们计划开始将 UKL 作为 Linux 的标准目标进行升级，以便社区将继续增强它。

> We have only started performance optimizing UKL. As our knowledge of Linux has increased, a whole series of simple optimizations that can be readily adopted have become apparent beyond the current efforts. How hard will it be to introduce and/or exploit zero-copy interfaces to the application? How hard will it be to reduce some of the privacy assumptions implicit in the BSD socket interface when only one application consumes incoming data?

我们才刚刚开始对 UKL 进行性能优化。随着我们对 Linux 知识的增加，一系列易于采用的简单优化已经变得明显，超出了当前的努力。在应用程序中引入和/或利用零复制接口有多难？当只有一个应用程序使用传入数据时，减少 BSD 套接字接口中隐式的一些隐私假设有多难？

> These kernel-centric optimizations are just the start. From an application perspective, we believe that UKL will provide a natural path for improving performance and reducing the complexity of complex concurrent workloads. Concurrent operations on shared resources must be regulated. Often the burden falls onto the user code. From the user-level, it is hard to determine whether synchronization is needed, and the controlling operations and controlled entities usually live in the kernel. If the user code moves into the kernel and has the same privileges, some operations might become faster or possible in the first place. For instance, in a garbage collector, it might be necessary to prevent or at least detect whether concurrent accesses happen. With easy and fast access to the memory infrastructure (e.g., page tables) and the scheduler, many situations in which explicit, slow synchronization is needed might get away with detecting and cleaning up violations of the assumptions.

这些以内核为中心的优化仅仅是个开始。从应用程序的角度来看，我们相信 UKL 将为提高性能和降低复杂并发工作负载的复杂性提供一条自然的途径。必须规范对共享资源的并发操作。通常负担落在用户代码上。从用户级别来看，很难确定是否需要同步，并且控制操作和控制实体通常位于内核中。如果用户代码移到内核中并具有相同的特权，那么某些操作可能会变得更快，或者可能首先变得更快。例如，在垃圾收集器中，可能需要防止或至少检测并发访问是否发生。通过对内存基础设施（例如页表）和调度器的简单快速访问，在许多需要显式缓慢同步的情况下，可以检测和清除违反假设的情况。

> If the Linux community accepts UKL, we believe it will not only impact Linux but may become a very important platform for future research. While the benefits to researchers of broad applications on HCL support are obvious. Perhaps less obvious, as unikernel researchers, is the ability to use tools like ktest to deploy and manage experiments, BPF and perf to be able to understand performance, have been incredibly valuable.

如果 Linux 社区接受 UKL，我们相信它不仅会影响 Linux，而且可能成为未来研究的一个非常重要的平台。而 HCL（Hardware Compatibility List）支持的广泛应用对研究人员的好处是显而易见的。也许不太明显的是，作为 unikernel 研究人员，使用像 ktest 这样的工具来部署和管理实验的能力，使用 BPF 和 perf 理解性能，已经非常有价值。

## 参考文献

- Dpdk - data plane development kit. https://www.dpdk.org/. Accessed on 2021-10-7.
- Storage Performance Development Kit. https://spdk.io/, 2018.(Accessed on 01/16/2019).
- Glenn Ammons, Jonathan Appavoo, Maria Butrico, Dilma Da Silva, David Grove, Kiyokuni Kawachiya, Orran Krieger, Bryan Rosenburg, Eric Van Hensbergen, and Robert W Wisniewski. Libra: a library operating system for a jvm in a virtualized execution environment.
In Proceedings of the 3rd international conference on Virtual execution environments, pages 44–54, 2007.
- Thomas E Anderson. The case for application-specific operating systems. University of California, Berkeley, Computer Science Division, 1993.
- Berk Atikoglu, Yuehai Xu, Eitan Frachtenberg, Song Jiang, and Mike Paleczny. Workload analysis of a large-scale key-value store. In Proceedings of the 12th ACM SIGMETRICS/PERFORMANCE joint international conference on Measurement and Modeling of Computer Systems, pages 53–64, 2012.
- Paul Barham, Boris Dragovic, Keir Fraser, Steven Hand, Tim Harris, Alex Ho, Rolf Neugebauer, Ian Pratt, and Andrew Warfield. Xen
and the art of virtualization. ACM SIGOPS operating systems review, 37(5):164–177, 2003.
