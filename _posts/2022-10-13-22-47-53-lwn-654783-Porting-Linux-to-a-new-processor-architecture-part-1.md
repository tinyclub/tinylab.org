---
layout: post
author: 'w-simon'
title: "LWN 654783: 将Linux移植到新的处理器架构,第1部分:基础知识"
draft: false
album: "LWN 中文翻译"
group: "translation"
license: "cc-by-sa-4.0"
permalink: /lwn-654783/
description: "LWN 文章翻译，将Linux移植到新的处理器架构,第1部分:基础知识"
category:
  - 体系架构
  - 移植
  - LWN
tags:
  - Linux
  - Architectures/Porting to
---

> 原文：[Porting Linux to a new processor architecture, part 1](https://lwn.net/Articles/654783/)
> 原创：By Joël Porquet @ **September 23, 2015**
> 翻译：By [w-simon](https://github.com/w-simon)
> 校对：By

> Although a simple port may count as little as 4000 lines of code—exactly 3,775 for the mmu-less Hitachi 8/300 recently reintroduced in Linux 4.2-rc1—getting the Linux kernel running on a new processor architecture is a difficult process. Worse still, there is not much documentation available describing the porting process. The aim of this series of three articles is to provide an overview of the procedure, or at least one possible procedure, that can be followed when porting the Linux kernel to a new processor architecture.

虽然一个简单的移植只需要4000行左右的代码（准确的说是3775行，对于最近在Linux 4.2-rc1中支持的无MMU的Hitachi 8/300处理器而言），但是让Linux内核在一个新的处理器架构上运行起来是一个艰苦的过程。更糟糕的是没有多少文章来描述这个移植过程。本系列三篇文章的目的是概述将Linux内核移植到新处理器架构时要遵循（或至少可能遵循）的过程。

> After spending countless hours becoming almost fluent in many of the supported architectures, I discovered that a well-defined skeleton shared by the majority of ports exists. Such a skeleton can logically be split into two parts that intersect a great deal. The first part is the boot code, meaning the architecture-specific code that is executed from the moment the kernel takes over from the bootloader until init is finally executed. The second part concerns the architecture-specific code that is regularly executed once the booting phase has been completed and the kernel is running normally. This second part includes starting new threads, dealing with hardware interrupts or software exceptions, copying data from/to user applications, serving system calls, and so on.

在花了无数的时间来熟练掌握（Linux）支持的许多架构后，我发现大多数移植过程都有一个定义良好的框架。这个框架在逻辑上分为两部分，这两部分有很大的交集。第一部分（关注的）是引导代码，这意味从内核接管引导加载程序那一刻开始运行，直到最终init程序被执行为止，这一段时间内的所有特定于体系结构的代码。第二部分关注的（正常运行状态时的代码），当启动阶段已经完成且内核进入正常运行状态时经常执行的架构特定代码。第二部分包括启动新线程、处理硬件中断或软件异常、从/向用户态应用程序复制数据、为系统调用提供服务等等。
 
### Is a new port necessary?

### 有必要进行一个全新的（系统）移植吗？

> As LWN reported about another porting experience in an article published last year, there are three meanings to the word "porting".
It can be a port to a new board with an already-supported processor on it. Or it can be a new processor from an existing, supported processor family. The third alternative is to port to a completely new architecture. 

正如去年在LWN上发表的一篇文章中报道的另一种移植经验一样，“移植”一词有三种含义：
它可以是移植到是一个新单板上，该单板上的处理器已被支持；它也可以是移植到一个新处理器上，该处理器家族已被支持；它还可以是移植到一个全新的处理器架构上。

> Sometimes, the answer to whether one should start a new port from scratch is crystal clear—if the new processor comes with a new instruction set architecture (ISA), that is usually a good indicator. Sometimes it is less clear. In my case, it took me a couple weeks to figure out this first question.

有时，是否应该从头开始一个新移植的答案是非常清晰的——如果新处理器带有新的指令集(ISA)，这通常是一个很好的指标。但有时就不那么清晰了。就我而言，花了几周时间才搞清楚这个问题。

> At the time, May 2013, I had just been hired by the French academic computer lab LIP6 to port the Linux kernel to TSAR, an academic processor architecture that the system-on-chip research group was designing. TSAR is an architecture that follows many of the current trends: lots of small, single-issue, energy-efficient processor cores around a scalable network-on-chip. It also adds some nice innovations: a full-hardware cache-coherency protocol for both data/instruction caches and translation lookaside buffers (TLBs) as well as physically distributed but logically shared memory.

当时是2013年5月，我刚刚被法国学术计算机实验室LIP6雇用，负责将Linux内核移植到TSAR上，这是一个SoC研究小组正在设计的学术处理器架构。TSAR是一种遵循许多当前流行趋势的体系架构：围绕可伸缩的片上网络（network-on-chip）使用了大量小的、单发射的、低功耗的处理器核。它还增加了一些不错的创新:为数据、指令缓存和转换备用缓冲区(TLB)以及分布共享的内存提供了全硬件缓存一致性协议。

> My dilemma was that the processor cores were compatible with the MIPS32 ISA, which meant the port could fall into the second category: "new processor from an existing processor family". But since TSAR had a virtual-memory model radically different from those of any MIPS processors, I would have been forced to drastically modify the entire MIPS branch in order to introduce this new processor, sometimes having almost no choice but to surround entire files with #ifndef TSAR ... #endif.
我的困境是处理器核与MIPS32 指令集兼容，这意味着端口可能属于第二类:“现有处理器家族中的新处理器”。但是，由于TSAR的虚拟内存模型与任何MIPS处理器都完全不同，为了支持这个新处理器，我不得不大幅修改整个MIPS代码分支，有时除了用#ifndef TSAR……# endif包围整个文件，几乎别无选择。

> Quickly enough, it came down to the most logical—and interesting—conclusion:

这样，很快就得出了最合乎逻辑、也最有趣的结论（新建一个arch）:

```shell
mkdir linux/arch/tsar
```

### Get to know your hardware

### 熟悉你的硬件

> Really knowing the underlying hardware is definitely the fundamental, and perhaps most obvious, prerequisite to porting Linux to it.

真正了解底层硬件无疑是进行Linux移植的基础， 也是最明显的前提条件。

> The specifications of a processor are often—logically or physically—split into a least two parts (as were, for example, the recently published specifications for the new RISC-V processor). The first part usually details the user-level ISA, which basically means the list of user-level instructions that the processor is able to understand—and execute. The second part describes the privileged architecture, which includes the list of kernel-level-only instructions and the various system registers that control the processor status.

处理器规范通常在逻辑上或物理上被划分成至少两部分(例如，最近发布的新RISC-V处理器的规范)。第一部分通常详细介绍用户级ISA（Instruction Set Architecture），列举了处理器能够理解和执行的用户级指令列表。第二部分描述特权架构，包括内核级指令列表和控制处理器状态的各种系统寄存器。

> This second part contains the majority—if not the entirety—of the information that makes a port special and thus often prevents the developer from opportunely reusing code from other architectures.
第二部分包含了使每一个系统移植变得“千人前面”的大部分信息（如果不是全部的话），因此通常会阻止开发人员适当地重用其他体系架构中的代码。

> Among the important questions that should be answered by such specifications are:

- What are the virtual-memory model of the processor architecture, the format of the page table, and the translation mechanism?

  Many processor architectures (e.g. x86, ARM, or TSAR) define a flexible virtual-memory layout. Their virtual address space can theoretically be split any way between the user and kernel spaces—although the default layout for 32-bit processors in Linux usually allocates the lower 3GiB to user space and reserves the upper 1GiB for kernel space. In some other architectures, this layout is strongly constrained by the hardware design. For instance, on MIPS32, the virtual address space is statically split into two regions of the same size: the lower 2GiB is dedicated to user space and the upper 2GiB to kernel space; the latter even contains predefined windows into the physical address space.


  The format of the page table is intimately linked to the translation mechanism used by the processor. In the case of a hardware-managed mechanism, when the TLB—a hardware cache of limited size containing recently used translations between virtual and physical addresses—does not contain the translation for a given virtual address (referred to as TLB miss), a hardware state machine will transparently fetch the proper translation from the page table structure in memory and fill the TLB with it. This means that the format of the page table must be fixed—and certainly defined by the processor's specifications. In a software-based mechanism, a TLB miss exception is handled by a piece of code, which theoretically leaves complete liberty as to how the page table is organized—only the format of TLB entries is specified.


- How to enable/disable the interrupts, switch from privileged mode to user mode and vice-versa, get the cause of an exception, etc.?

  Although all these operations generally only involve reading and/or modifying certain bit fields in the set of available system registers, they are always very particular to each architecture. It is for this reason that, most of the time, they are actually performed by small chunks of dedicated assembly code.

- What is the ABI?

  Although one could think that the Application Binary Interface (ABI) is only supposed to concern compilation tools, as it defines the way the stack is formatted into stack-frames, the ways arguments and return values are given or returned by functions, etc.; it is actually absolutely necessary to be familiar with it when porting Linux. For example, as the recipient of system calls (which are typically defined by the ABI), the kernel has to know where to get the arguments and how to return a value; or on a context switch, the kernel must know what to save and restore, as well as what constitutes the context of a thread, and so on.

这些规范应回答的重要问题包括:

- 处理器体系结构的虚拟内存模型是什么，页表的格式和转换机制是什么?

许多处理器架构(例如x86、ARM或TSAR)定义了灵活的虚拟内存布局。它们的虚拟地址空间理论上可以在用户空间和内核空间之间以任何方式分割——尽管Linux中32位处理器的默认布局通常将较低的3GiB分配给用户空间，而将较高的1GiB保留给内核空间。但在其他体系结构中，这种布局可能会受到硬件设计的限制，例如在MIPS32上，虚拟地址空间被静态地分成两个大小相同的区域：0-2G用于用户空间，而2G-4G用于内核空间。
页表的格式与处理器使用的地址转换机制密切相关。在硬件管理的地址转化机制下，当TLB(一个有限大小的硬件缓存，包含最近使用的虚拟地址和物理地址的映射关系的转换表)不包含给定虚拟地址的转换(称为TLB miss)时，硬件状态机将透明地从内存中的页表结构中获取正确的转换关系并将其填充到TLB中。这意味着页表的格式必须是固定的（由处理器的规范定义的）。但在基于软件管理的地址转换机制下，TLB miss只是由一段代码处理，这时页表的组织方式是可以非常自由的，只要TLB的格式是固定的即可。

- 如何启用或禁用中断，如何在特权模式切和用户模式之间切换，如何获取异常？

尽管所有这些操作通常只涉及读取或者修改系统寄存器集中的某些位，但它们是和体系架构相关的。正是由于这个原因，大多数情况下，它们实际上是由一段特定的汇编代码执行的。

- 应用程序二进制接口(ABI）相关的信息

尽管人们可能认为编译器才应该关注ABI，因为它定义了栈被格式化为栈桢的方式，函数入参和返回值的传递方式等。但在移植Linux时，熟悉ABI也是必要的。例如，作为系统调用(通常由ABI定义)的接收者，内核必须知道从哪里获取参数以及如何返回值；或者在上下文切换中，内核必须知道要保存什么和恢复什么，以及线程的上下文是由什么组成的，等等。

### Get to know the kernel

###  了解Linux内核 

> Learning a few kernel concepts, especially concerning the memory layout used by Linux, will definitely help. I admit it took me a while to understand what exactly was the distinction between low memory and high memory, and between the direct mapping and vmalloc regions.

学习一些内核概念，特别是关于Linux使用的内存布局的概念，对移植工作会有帮助。比如理解低端内存和高端内存的确切区别，以及直接映射和vmalloc区域的区别。

> For a typical and simple port (to a 32-bit processor), in which the kernel occupies the upper 1GiB of the virtual address space, it is usually fairly straightforward. Within this 1GiB, Linux defines that the lower portion of it will be directly mapped to the lower portion of the system memory (hence referred to as low memory): meaning that if the kernel accesses the address 0xC0000000, it will be redirected to the physical address 0x00000000.

比如一个普通的简单移植（在32位处理器上），内核占据虚拟地址的高1GB地址空间。这1GB空间在Linux中定义为直接映射到物理内存的低端（称为low memory），这意味着如果内核访问地址0xC0000000，它会被重定向在物理地址的0x00000000处。

> In contrast, in systems with more physical memory than that which is mappable in the direct mapping region, the upper portion of the system memory (referred to as high memory) is not normally accessible to the kernel. Other mechanisms must be used, such as kmap() and kmap_atomic(), in order to gain temporary access to these high-memory pages.

相反，在一个物理内存大于直接映射的区域的系统上，超出的内存区域（称为 high memory）内核不能正常访问。所以必须使用其他辅助机制，例如kmap()和kmap_atomic()，来访问这些高端内存。

> Above the direct mapping region is the vmalloc region that is controlled by vmalloc(). This allocation mechanism provides the ability to allocate pages of memory in a virtually contiguous way in spite of the fact that these pages may not necessarily be physically contiguous. It is particularly useful for allocating a large amount of memory pages in a virtually contiguous manner, as otherwise it can be impossible to find the equivalent amount of contiguous free physical pages.

在直接映射区域之上是vmalloc区域，vmalloc可以分配虚拟地址连续但物理地址不连续的内存。这在要求分配大量连续的内存页但是物理内存却没有这么多的连续空间的时候，是非常有益的。

> Further reading about the memory management in Linux can be found in Linux Device Drivers [PDF] and this LWN article.

可以在Linux Device Divers(PDF)和这篇LWN文章阅读更多更多关于Linux内存管理的知识。

### How to start?

### 怎么开始？

> With your head full of the processor's specifications and kernel principles, it is finally time to add some files to this newly created arch directory. But wait ... where and how should we start? As with any porting or even any code that must respect a certain API, the procedure is a two-step process.

在熟悉了处理器的规范和内核原理之后，是时候向这个新创建的arch目录添加一些文件了。但是我们应该从哪里开始，如何开始？就像任何移植或任何必须遵守特定API的代码一样，此过程分为两个步骤。

> First, a minimal set of files that define a minimal set of symbols (functions, variables, defines) is necessary for the kernel to even compile. This set of files and symbols can often be deduced from compilation failures: if compilation fails because of a missing file/symbol, it is a good indicator that it should probably be implemented (or sometimes that some configuration options should be modified). In the case of porting Linux, this approach is particularly relevant when implementing the numerous headers that define the API between the architecture-specific code and the rest of the kernel.

首先，定义内核编译所必须的最小文件集，这些文件包含了符号（函数，变量，宏定义）的最小集合。这一组文件和符号经常来自编译失败——如果由于缺少某些文件或符号而导致了编译失败，那就是一个好的提示：该文件或者符号可能是需要实现的（或者某些配置选项需要修改）。在移植Linux时，这种方法是非常有效的，尤其是当需要实现大量的头文件来定义架构特定的代码和内核之间的API的时候。

> After the kernel finally compiles and is able to be executed on the target hardware, it is useful to know that the boot code is very sequential. That allows many functions to stay empty at first and to only be implemented gradually until the system finally becomes stable and reaches the init process. This approach is generally possible for almost all of the C functions executed after the early assembly boot code. However it is advised to have the early_printk() infrastructure up and working otherwise it can be difficult to debug.

(其次)在内核最终被编译并能够在目标硬件上执行以后，了解引导代码的执行顺序是很有用的。这允许许多函数一开始留空，然后逐渐实现，直到系统最终稳定并成功引导init进程。这种方法大概对于所有的在汇编引导代码执行后的C函数都适用。但是，建议先实现early_printk（）函数并使其正常工作，否则可能会很难调试。

### Finally getting started: the minimal set of non-code files

#### 终于开始:最少的非代码文件集

> Porting the compilation tools to the new processor architecture is a prerequisite to porting the Linux kernel, but here we'll assume it has already been performed. All that is left to do in terms of compilation tools is to build a cross-compiler. Since at this point it is likely that porting a standard C library has not been completed (or even started), only a stage-1 cross-compiler can be created.

将编译工具移植到新的处理器体系架构是移植Linux内核的先决条件，这里我们假设已经执行了这个操作。就编译工具而言，剩下要做的就是构建一个交叉编译器。由于此时很可能还没有完成(甚至还没有开始)移植标准C库，所以只能创建一个第1阶段的交叉编译器。

> Such a cross-compiler is only able to compile source code for bare metal execution, which is a perfect fit for the kernel since it does not depend on any external library. In contrast, a stage-2 cross-compiler has built-in support for a standard C library.

这样的交叉编译器只能编译源代码在裸机上执行，但非常适合内核，因为它不依赖于任何外部库。相比之下，一个第2阶段的交叉编译器内置了对标准C库的支持。

> The first step of porting Linux to a new processor is the creation of a new directory inside arch/, which is located at the root of the kernel tree (e.g. linux/arch/tsar/ in my case). Inside this new directory, the layout is quite standardized:

将Linux移植到新处理器的第一步是在arch/中创建一个新目录，它位于内核树的根目录(例如，例子中是Linux /arch/tsar/)。在这个新目录中，布局非常标准化:

- configs/: default configurations for supported systems (i.e. *_defconfig files)

- include/asm/ for the headers dedicated to internal use only, i.e. Linux source code

- include/uapi/asm for the headers that are meant to be exported to user space (e.g. the libc)

- kernel/: general kernel management

- lib/: optimized utility routines (e.g. memcpy(), memset(), etc.)

- mm/: memory management

> The great thing is that once the new arch directory exists, Linux automatically knows about it. It only complains about not finding a Makefile, not about this new architecture:

重要的是，一旦新的arch目录存在，Linux就会自动感知到它。Linux编译时只会提示找不到Makefile，而不会提这个新架构的事情:

```
    ~/linux $ make ARCH=tsar
    Makefile: ~/linux/arch/tsar/Makefile: No such file or directory
```

> As shown in the following example, a minimal arch Makefile only has a few variables to specify:

如下例所示，一个支持最小架构的Makefile只有几个变量要指定:

```
    KBUILD_DEFCONFIG := tsar_defconfig

    KBUILD_CFLAGS += -pipe -D__linux__ -G 0 -msoft-float
    KBUILD_AFLAGS += $(KBUILD_CFLAGS)

    head-y := arch/tsar/kernel/head.o

    core-y += arch/tsar/kernel/
    core-y += arch/tsar/mm/
    LIBGCC := $(shell $(CC) $(KBUILD_CFLAGS) -print-libgcc-file-name)
    libs-y += $(LIBGCC)
    libs-y += arch/tsar/lib/

    drivers-y += arch/tsar/drivers/
```

- KBUILD_DEFCONFIG must hold the name of a valid default configuration, which is one of the defconfig files in the configs directory (e.g. configs/tsar_defconfig).

- KBUILD_DEFCONFIG必须包含一个有效的默认配置的名称，它是configs目录中的一个defconfig文件(例如configs/tsar_defconfig)。

- KBUILD_CFLAGS and KBUILD_AFLAGS define compilation flags, respectively for the compiler and the assembler.

- KBUILD_CFLAGS和kbuild_afags分别为编译器和汇编器定义编译标志。

- {head,core,libs,...}-y list the objects (or subdirectory containing the objects) to be compiled in the kernel image (see Documentation/kbuild/makefiles.txt for detailed information)

- {head,core,…}-y列出要在内核映像中编译的对象(或包含对象的子目录)(有关详细信息，请参阅Documentation/kbuild/makefiles.txt)

> Another file that has its place at the root of the arch directory is Kconfig. This file mainly serves two purposes: it defines new arch-specific configuration options that describe the features of the architecture, and it selects arch-independent configuration options (i.e. options that are already defined elsewhere in Linux source code) that apply to the architecture.

另一个位于arch目录根目录的文件是Kconfig。这个文件主要有两个目的:它可以定义新的特定于架构的配置选项，用于描述新处理器架构的特性；它还可以选择应用于该架构的通用配置项(即已经在Linux源代码的其他地方定义的配置项)。

> As this will be the main configuration file for the newly created arch, its content also determines the layout of the menuconfig command (e.g. make ARCH=tsar menuconfig). It is difficult to give a snippet of the file as it depends very much on the targeted architecture, but looking at the same file for other (simple) architectures should definitely help.

它将是新创建的arch的主要配置文件，其内容也决定了menuconfig命令的布局(例如make arch =tsar menuconfig)。很难给出该文件的片段，因为它在很大程度上依赖于目标体系架构，但是参考查看其他(简单的)体系架构的相同配置文件肯定会有所帮助。

> The defconfig file (e.g. configs/tsar_defconfig) is necessary to complete the files related to the Linux kernel build system (kbuild). Its role is to define the default configuration for the architecture, which basically means specifying a set of configuration options that will be used as a seed to generate a full configuration for the Linux kernel compilation. Once again, starting from defconfig files of other architectures should help, but it is still advised to refine them, as they tend to activate many more features than a minimalistic system would ever need—support for USB, IOMMU, or even filesystems is, for example, too early at this stage of porting.

默认配置文件（例如 configs/tsar_defconfig）对于生成Linux内核编译系统（kbuild）所需的文件是必要的。它的作用是定义这个体系架构的默认配置项，以这些基本配置项为种子可以生成一个全配置的Linux内核。同样，可以参考其他架构下的defconfig文件，但仍然建议改进它，因为它往往会激活比极简系统所需的多得多的特性——例如支持USB，IOMMU甚至文件系统对于目前这个移植阶段来说都太早了。

> Finally the last "not really code but still really important" file to create is a script (usually located at kernel/vmlinux.lds.S) that will instruct the linker how to place the various sections of code and data in the final kernel image. For example, it is usually necessary for the early assembly boot code to be set at the very beginning of the binary, and it is this script that allows us do so.

最后需要创建的一个“不是真正的代码但是仍然很重要”的文件是一个脚本（通常位于kernel/vmlinux.lds.S)，它将指导连接器如何把代码和数据的不同部分放到最终的内核镜像中。比如说，早期汇编引导代码需要放置在二进制镜像的开头，就是这个脚本做的。

### Conclusion

### 结论

> At this point, the build system is ready to be used: it is now possible to generate an initial kernel configuration, customize it, and even start compiling from it. However, the compilation stops very quickly since the port still does not contain any code.

到这一步后，编译系统已经可以使用了。现在可以生成一个初步的内核配置文件，定制它甚至可以通过它来编译内核。但是编译会很快停止，因为到目前为止还没有任何代码。

> In the next article, we will dive into some code for the second portion of the port: the headers, the early assembly boot code, and all the most important arch functions that are executed until the first kernel thread is created.

在下一篇文章中，我们将会在移植的第二部分深入代码：头文件，早期汇编引导代码以及在内核线程创建之前执行的重要的架构相关的函数。
