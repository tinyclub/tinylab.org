---
layout: post
author: 'w-simon'
title: "LWN 656286: 将Linux移植到新的处理器架构,第2部分:早期代码"
draft: false
album: "LWN 中文翻译"
group: "translation"
license: "cc-by-sa-4.0"
permalink: /lwn-656286/
description: "LWN 文章翻译，将Linux移植到新的处理器架构,第2部分:早期代码"
category:
  - 体系架构
  - 移植
  - LWN
tags:
  - Linux
  - Architectures/Porting to
---

> 原文：[Porting Linux to a new processor architecture, part 2: The early code](https://lwn.net/Articles/656286/)
> 原创：By Joël Porquet @ **September 23, 2015**
> 翻译：By [w-simon](https://github.com/w-simon)
> 校对：By

> In part 1 of this series, we laid the groundwork for porting Linux to a new processor architecture by explaining the (non-code-related) preliminary steps. This article continues from there to delve into the boot code. This includes what code needs to be written in order to get from the early assembly boot code to the creation of the first kernel thread.

在这系列文章的第一篇中, 我们通过描述（代码无关）的初步步骤为将Linux移植到一个新的处理器架构建立了一个基础。本文将继续开始研究启动代码，包括从汇编启动代码到创建第一个内核线程而需要编写的代码。

### The header files

### 头文件

> As briefly mentioned in the previous article, the arch header files (in my case, located under linux/arch/tsar/include/) constitute the two interfaces between the architecture-specific and architecture-independent code required by Linux.

如上篇文章中简单提到过的，arch目录下的头文件（在我们的例子中位于linux/arch/tsar/include/目录）就是由Linux所要求的架构特定代码和架构无关代码之间的接口组成的。

> The first portion of these headers (subdirectory asm/) is part of the kernel interface and is used internally by the kernel source code. The second portion (uapi/asm/) is part of the user interface and is meant to be exported to user space—even though the various standard C libraries tend to reimplement the headers instead of including the exported ones. These interfaces are not completely airtight, as many of the asm headers are used by user space.

这些头文件的第一个部分（子目录asm/）是内核接口的一部分，由内核源代码内部使用。第二部分（uapi/asm/）是用户接口的一部分，导出到用户空间（尽管各种各样的标准C库可能会重新实现这些头文件而不是直接使用我们提供的）。所以这些接口不是完全封印在内核内部的，许多asm头文件可能会被用户空间程序使用。

> Both interfaces are typically more than a hundred header files altogether, which is why headers represent one of the biggest tasks in porting Linux to a new processor architecture. Fortunately, over the past few years, developers noticed that many processor architectures were sharing similar code (because they often exhibited the same behaviors), so the majority of this code has been aggregated into a generic layer of header files (in linux/include/asm-generic/ and linux/include/uapi/asm-generic/).

这两个接口加一起一般有一百多个头文件，这也就是为什么头文件是将Linux移植到新的处理器架构中最大的任务之一。幸运的是，在过去的几年中，开发者发现许多处理器架构可以共享相似的代码（因为它们经常表现出相同的行为），所以这些代码的大部分已经被聚集到一个通用的头文件层（在linux/include/asm-generic/和linux/include/uapi/asm-generic/中）。

> The real benefit is that it is possible to refer to these generic header files, instead of providing custom versions, by simply writing appropriate Kbuild files. For example, the few first lines of a typical include/asm/Kbuild looks like:

真正的好处是，只需编写适当的Kbuild文件，就可以引用这些通用头文件，而不用自己造轮子。例如，include/asm/Kbuild典型的头几行代码像这样：

```
    generic-y += atomic.h
    generic-y += barrier.h
    generic-y += bitops.h
    ...
```

> When porting Linux, I'm afraid there is no other choice than to make a list of all of the possible headers and examine them one by one in order to decide whether the generic version can be used or if it requires customization. Such a list can be created from the generic headers already provided by Linux as well as the customized ones implemented by other architectures.

在移植Linux时，恐怕只有一个选择就是将可能的头文件列出来然后一个一个检查通用版本是否可用，否则就需要修改。这样的一个文件列表可以从Linux提供的通用头文件或者其他架构实现的头文件中获得。

> Basically, a specific version must be developed for all of the headers that are related to the details of an architecture, as defined by the hardware or by the software through the ABI: cache (asm/cache.h) and TLB management (asm/tlbflush.h), the ELF format (asm/elf.h), interrupt enabling/disabling (asm/irqflags.h), page table management (asm/page.h, asm/pgalloc.h, asm/pgtable.h), context switching (asm/mmu_context.h, asm/ptrace.h), byte ordering (uapi/asm/byteorder.h), and so on.

基本上，移植一个Linux版本必须实现和处理器架构相关的所有头文件，比如：缓存（asm/cache.h）和TLB管理（asm/tlbflush.h），ELF格式（asm/elf.h），中断启用和禁用（asm/irqflags.h），页表管理（asm/page.h、asm/pgalloc.h、asm/pgtable.h），上下文切换（asm/mmucontext.h、asm/ptrace.h），字节顺序（uapi/asm/byteorder.h）等等。

### Boot sequence

### 启动顺序

> As explained in part 1, figuring out the boot sequence helps to understand the minimal set of architecture-specific functions that must be implemented—and in which order.

正如上一篇文章所说，弄清楚引导顺序对于理解必须按顺序实现的最小的特定于架构的函数集是非常有帮助的。

> The boot sequence always starts with a function that must be written manually, usually in assembly code (in my case, this function is called kernel_entry() and is located in arch/tsar/kernel/head.S). It is defined as the main entry point of the kernel image, which indicates to the bootloader where to jump after loading the image in memory.

系统的引导总是以一个必须手写的函数开始的，这个函数通常是用汇编代码来写的（在我们的例子中，函数名是kernel_entry()，位于arch/tsar/kernel/head.S文件中）。它被定义为内核映像的主入口点，它向bootloader指示在内存中加载映像后要跳转到哪里。

> The following trace shows an excerpt of the sequence of functions that is executed during the boot (starred functions are the architecture-specific ones that will be discussed later in this article):

下面列出了一系列在启动时需要执行的函数（被标记为*的函数是架构特定的函数，需要考虑在新的体系架构下如何实现，稍后会继续讨论）：

```
    kernel_entry*
    start_kernel
        setup_arch*
        trap_init*
        mm_init
            mem_init*
        init_IRQ*
        time_init*
        rest_init
            kernel_thread
            kernel_thread
            cpu_startup_entry
```

### Early assembly boot code
### 早期汇编引导代码

> The early assembly boot code has this special aura that scared me at first (as I'm sure it did many other programmers), since it is often considered one of the most complex pieces of code in a port. But even though writing assembly code is usually not an easy ride, this early boot code is not magic. It is merely a trampoline to the first architecture-independent C function and, to this end, only needs to perform a short and defined list of tasks.

汇编启动代码经常被认为是移植过程中最复杂的代码之一。虽然写汇编代码不是一件容易的事情，但是早期启动代码不是魔术。它仅仅是执行第一个架构特定的C函数的跳板，因此只需要执行一个短的定义好的任务列表。

> When the early boot code begins execution, it knows nothing about what has happened before: Has the system been rebooted or just been powered on? Which bootloader has just loaded the kernel in memory? And so forth. For this reason, it is safer to put the processor into a known state. Resetting one or several system registers usually does the trick, making sure that the processor is operating in kernel mode with interrupts disabled.

当早期启动代码开始执行时，它不知道之前发生了什么事：系统是重启还是刚刚开机？是哪个bootloader将内核加载到内存？由于这个原因，将处理器设置为已知的状态是安全的。重新设置一个或者几个系统寄存器就可以达到目的，以确保处理器处于内核模式并且中断是关闭的。

> Similarly, not much is known about the state of the memory. In particular, there is no guarantee that the portion of memory representing the kernel’s bss section (the section containing uninitialized data) was reset to zero, which is why this section must be explicitly cleared.

类似的，它也不知道内存的状态。尤其是无法保证放置内核bss段的内存是否被初始化为零，这就是为什么这个段必须被清零.

> Often Linux receives arguments from the bootloader (in the same way that a program receives arguments when it is launched). For example, this could be the memory address of a flattened device tree (on ARM, MicroBlaze, openRISC, etc.) or some other architecture-specific structure. Often such arguments are passed using registers and need to be saved into proper kernel variables.

通常Linux接受bootloader传递的参数（和程序启动时接受参数的方法是一样的）。例如，这可能是一个flattened device tree（FDT）的内存地址（ARM，MicroBlaze，openRISC等等）或者是一些其他的架构特定的结构体。通常这样的参数是通过寄存器传递，然后保存到适当的内核变量中。

> At this point, virtual memory has not been activated and it is interesting to note that kernel symbols, which are all defined in the kernel's virtual address space, have to be accessed through a special macro: pa() in x86, tophys() in OpenRISC, etc. Such a macro translates the virtual memory address for symbols into their corresponding physical memory address, thus acting as a temporary software-based translation mechanism.

此时虚拟内存还没有被激活，有趣的是注意观察内核符号，它们都被定义在内核虚拟地址空间中，所以必须通过一个特殊的宏来访问它：x86是pa(), OpenRISC是tophys()等等。这个宏将内核符号的虚拟地址翻译为对应的物理地址，它作为一个临时的基于软件的翻译机制。

> Now, in order to enable virtual memory, a page table structure must be set up from scratch. This structure usually exists as a static variable in the kernel image, since at this stage it is nearly impossible to allocate memory. For the same reason, only the kernel image can be mapped by the page table at first, using huge pages if possible. According to convention, this initial page table structure is called swapper_pg_dir and is thereafter used as the reference page table structure throughout the execution of the system.

为了启用虚拟内存，一个页表结构必须从头建立起来。这个结构通常以内核映像中的一个静态变量的形式存在，因为这个阶段基本上不可能分配内存。同理，一开始只有内核映像可以被页表映射，使用尽可能大的页。按照惯例，初始页表结构被称为swapper_pg_dir，它在整个系统执行过程中被用作参考页表结构。

> On many processor architectures, including TSAR, there is an interesting thing about mapping the kernel in that it actually needs to be mapped twice. The first mapping implements the expected direct-mapping strategy as described in part 1 (i.e. access to virtual address 0xC0000000 redirects to physical address 0x00000000). However, another mapping is temporarily required for when virtual memory has just been enabled but the code execution flow still hasn't jumped to a virtually mapped location. This second mapping is a simple identity mapping (i.e. access to virtual address 0x00000000 redirects to physical address 0x00000000).

在许多处理器架构中一个有趣的事情是内核实际上需要被映射两次。第一次映射就是上一节中描述的直接映射策略（即 访问虚拟地址0xC0000000被重定向为物理地址0x00000000）。然而另一次映射是临时的，当虚拟内存刚刚被使能但是执行代码还没有跳转到虚拟内存处。第二次映射是一个简单identity mapping（即 访问虚拟地址0x00000000被重定向为物理地址0x00000000）。

> With an initialized page table structure, it is now possible to enable virtual memory, meaning that the kernel is fully executing in the virtual address space and that all of the kernel symbols can be accessed normally by their name, without having to use the translation macro mentioned earlier.

页表结构体被初始化完成之后 ，可以使能虚拟内存，这表示内核现在运行在虚拟地址空间并且所有内核符号可以通过它的名字正常访问，不需要使用先前的宏翻译方法了。

> One of the last steps is to set up the stack register with the address of the initial kernel stack so that C functions can be properly called. In most processor architectures (SPARC, Alpha, OpenRISC, etc.), another register is also dedicated to containing a pointer to the current thread's information (struct thread_info). Setting up such a pointer is optional, since it can be derived from the current kernel stack pointer (the thread_info structure is usually located at the bottom of the kernel stack) but, when allowed by the architecture, it enables much faster and more convenient access.

最后的步骤之一是设置一个带有初始内核栈地址的栈寄存器，使得C函数可以被正确地调用。在大多数处理器架构中（SPARC、Alpha、openRISC等），需要另一个寄存器指针来保存当前线程的信息（struct thread_info）。设置这个指针是可选的，因为它可以从当前内核栈指针中推测得知（thread_info通常位于内核栈的底部）。但是，当架构允许的时候，它能够实现更加快速和方便的访问。

> The last step of the early boot code is to jump to the first architecture-independent C function that Linux provides: start_kernel().

早期引导代码的最后一步是跳转到Linux提供的第一个架构无关的C函数start_kernel()处。

### En route to the first kernel thread

### 创建第一个内核线程的准备

> start_kernel() is where many subsystems are initialized, from the various virtual filesystem (VFS) caches and the security framework to time management, the console layer, and so on. Here, we will look at the main architecture-specific functions that start_kernel() calls during boot before it finally calls rest_init(), which creates the first two kernel threads and morphs into the boot idle thread.

start_kernel()是很多子系统初始化的地方，从各种虚拟文件系统缓存、安全框架，到时钟管理，控制台层等等。在这里我们主要看start_kernel()在最后调用rest_init()前调用架构特定的几个函数，rest_init()函数首先创建两个内核线程，然后变为idle线程（idle线程-当CPU空闲时运行此线程）。

## setup_arch()

> While it has a rather generic name, setup_arch() can actually do quite a bit, depending on the architecture. Yet examining the code for different ports reveals that it generally performs the same tasks, albeit never in the same order nor the same way. For a simple port (with device tree support), there is a simple skeleton that setup_arch() can follow.

setup_arch()虽然名字普通但是做了很多架构特定的事情。观察这个函数在不同的移植中的版本，我们可以发现尽管采用了不同的顺序和不同的方法，它基本上完成的还是同样的任务。对于一个简单的（支持设备树）的移植，编写setup_arch()时可以参考这样一个简单的框架。

> One of the first steps is to discover the memory ranges in the system. A device-tree-based system can quickly skim through the flattened device tree given by the bootloader (using early_init_devtree()) to discover the physical memory banks available and to register them into the memblock layer. Then, parsing the early arguments (using parse_early_param()) that were either given by the bootloader or directly included in the device tree can activate useful features such as early_printk(). The order is important here, as the device tree might contain the physical address of the terminal device used for printing and thus needs to be scanned first.

第一个步骤是探测系统内存的范围。一个基于设备树（device-tree-based）的系统可以快速扫描（使用early_init_devtree()）bootloader提供的tag参数列表（flattened device tree）来得到可用的物理内存块然后将他们注册到memblock层。接下来解析（使用parse_early_param()）bootloader提供或者是直接包含在设备树中的可以激活有用的特性例如early_printk()的启动参数。这里顺序是非常重要的因为设备树可能包含终端设备用于打印显示的物理地址，因此首先需要扫描一遍。

> Next the memblock layer needs some more configuration before it is possible to map the low memory region, which enables memory to be allocated. First, the regions of memory occupied by the kernel image and the device tree are set as being reserved in order to remove them from the pool of free memory, which is later released to the buddy allocator. The boundary between low memory and high memory (i.e. which portion of the physical memory should be included in the direct mapping region) needs to be determined. Finally the page table structure can be cleaned up (by removing the identity mapping created by the early boot code) and the low memory mapped.

接下来memblock层在映射低端内存（low memory）区域前需要进一步配置，使内存可以被分配。首先，被内核映象和设备树占用的内存区域会被设置为保留区域以便于稍后被伙伴分配器（buddy allocator）从空闲内存池中移除。高端内存和低端内存的分界线（即哪个物理内存区域是直接映射区）必须确定下来。最后页表结构体可以被清除（清除早期启动代码创建的identity mapping）然后映射低端内存区。

> The last step of the memory initialization is to configure the memory zones. Physical memory pages can be associated with different zones: ZONE_DMA for pages compatible with the old ISA 24-bit DMA address limitation, and ZONE_NORMAL and ZONE_HIGHMEM for low- and high-memory pages, respectively. Further reading on memory allocation in Linux can be found in Linux Device Drivers [PDF].

内存的最后一步初始化是配置内存区域。把物理内存页和不同区域关联：ZONE_DMA兼容老的ISA 24-bit DMA地址限制，ZONE_NORMAL和ZONE_HIGHMEM分别对应低端和高端内存页，更多关于Linux内存分配的知识请看Linux Device Drivers [PDF]。

> Finally, the kernel memory segments are registered using the resource API and a tree of struct device_node entries is created from the flattened device tree.

最后内核内存段可以使用资源管理API和flattened device tree创建的结构体device_node进行注册。

> If early_printk() is enabled, here is an example of what appears on the terminal at this stage:

如果使能了early_printk()，此阶段将会在终端上打印类似下面的信息：

```
    Linux version 3.13.0-00201-g7b7e42b-dirty (joel@joel-zenbook) \
        (gcc version 4.8.3 (GCC) ) #329 SMP Thu Sep 25 14:17:56 CEST 2014
    Model: UPMC/LIP6/SoC - Tsar
    bootconsole [early_tty_cons0] enabled
    Built 1 zonelists in Zone order, mobility grouping on.  Total pages: 65024
    Kernel command line: console=tty0 console=ttyVTTY0 earlyprintk

```

## trap_init()

> The role of trap_init() is to configure the hardware and software architecture-specific parts involved in the interrupt/exception infrastructure. Up to this point, an exception would either cause the system to crash immediately or it would be caught by a handler that the bootloader might have set up (which would eventually result in a crash as well, but perhaps with more information).

trap_init()配置中断/异常基础数据结构中涉及到的软硬件体系结构相关的部分。到目前为止，一个异常会使得系统立刻崩溃或者被bootloader设置的异常处理函数抓住（最终也会崩溃，但是可能会提供更多信息）。

> Behind (the actually simple) trap_init() hides another of the more complex pieces of code in a Linux port: the interrupt/exception handling manager. A big part of it has to be written in assembly code because, as with the early boot code, it deals with specifics that are unique to the targeted processor architecture. On a typical processor, a possible overview of what happens on an interrupt is as follows:

在trap_init()之后隐藏着Linux移植的另一块更加复杂的代码：中断/异常处理管理器。它的很大一部分需要用汇编来写，因为和早期引导代码一起，它要处理目标处理器架构特有的细节。在一个典型的处理器中，当一个中断到来时可能发生的事件包括：

- The processor automatically switches to kernel mode, disables interrupts, and its execution flow is diverted to a special address that leads to the main interrupt handler.

- 处理器自动切换到内核模式，关闭中断，把它的执行流转移到一个执行主中断处理程序的特殊地址。

- This main handler retrieves the exact cause of the interrupt and usually jumps to a sub-handler specialized for this cause. Often an interrupt vector table is used to associate an interrupt sub-handler with a specific cause, and on some architectures there is no need for a main interrupt handler, as the routing between the actual interrupt event and the interrupt vector is done transparently by hardware.

- 主处理程序获取中断来源，通常跳转到对应这个来源的子处理程序。通常使用中断向量表将中断子处理程序与特定的中断原因关联起来，在一些架构上不需要主中断处理程序，因为实际中断事件和中断向量之间的路由可以由硬件透明地完成。

- The sub-handler saves the current context, which is the state of the processor that can later be restored in order to resume exactly where it stopped. It may also re-enable the interrupts (thus making Linux re-entrant) and usually jumps to a C function that is better able to handle the cause of the exception. For example, such a C function can, in the case of an access to an illegal memory address, terminate the faulty user program with a SIGBUS signal.

- 子中断处理程序先保存当前上下文，即处理器当前的状态，便于中断处理完毕后恢复。然后重新使能中断（使得Linux是可重入的），接着通常会跳转到一个能够更好的对这个异常原因进行处理的C函数。例如，在访问非法内存地址的情况下，这样的C函数可以使用SIGBUS信号终止有问题的用户程序。

> Once all of this interrupt infrastructure is in place, trap_init() merely initializes the interrupt vector table and configures the processor via one of its system registers to reflect the address of the main interrupt handler (or of the interrupt vector table directly).

一旦这些中断基础结构都准备好了，trap_init()只需初始化中断向量表，同时通过一个系统寄存器来配置处理器以指明主中断处理函数（或中断向量表）的地址。

## mem_init()

> The main role of mem_init() is to release the free memory from the memblock layer to the buddy allocator (aka the page allocator). This represents the last memory-related task before the slab allocator (i.e. the cache of commonly used objects, accessible via kmalloc()) and the vmalloc infrastructure can be started, as both are based on the buddy allocator.

mem_init()的主要作用是将memblock层的空闲内存释放给伙伴分配器（又名页面分配器）。这代表着mem_init是slab分配器（即通过kmalloc()访问的常用对象缓存）和vmalloc基础结构可以启动之前的最后一个与内存相关的任务，因为两者都基于伙伴分配器。

> Often mem_init() also prints some information about the memory system:

mem_init()通常也会打印内存系统的一些信息：
```
    Memory: 257916k/262144k available (1412k kernel code, \
        4228k reserved, 267k data, 84k bss, 169k init, 0k highmem)
    Virtual kernel memory layout:
        vmalloc : 0xd0800000 - 0xfffff000 ( 759 MB)
        lowmem  : 0xc0000000 - 0xd0000000 ( 256 MB)
          .init : 0xc01a5000 - 0xc01ba000 (  84 kB)
          .data : 0xc01621f8 - 0xc01a4fe0 ( 267 kB)
          .text : 0xc00010c0 - 0xc01621f8 (1412 kB)
```

## init_IRQ()
> Interrupt networks can be of very different sizes and complexities. In a simple system, the interrupt lines of a few hardware devices are directly connected to the interrupt inputs of the processor. In complex systems, the numerous hardware devices are connected to multiple programmable interrupt controllers (PICs) and these PICs are often cascaded to each other, forming a multilayer interrupt network. The device tree helps a great deal by easily describing such networks (and especially the routing) instead of having to specify them directly in the source code.
中断网络的规模和复杂程度可能相差很大。在简单的中断系统中，少量硬件设备的中断线直接连接到处理器的中断输入上。但在复杂的系统中，大量的硬件设备连接到许多可编程中断控制器(PICs)上，这些PICs通常互相级连，组成一个多层中断网络。设备树在这个过程中起到了很大作用，因为设备树可以很容易地描述这样的中断网络（尤其是中断路由），而不必在源代码中直接指定它们。

> In init_IRQ(), the main task is to call irqchip_init() in order to scan the device tree and find all the nodes identified as interrupt controllers (e.g PICs). It then finds the associated driver for each node and initializes it. Unless the targeted system uses an already-supported interrupt controller, that typically means the first device driver will need to be written.

在init_IRQ()中，主要任务是调用irqchip_init()，以便扫描设备树并查找标识为中断控制器的所有节点（例如PIC）。然后，为每个节点找到关联的驱动程序并进行初始化。通常第一个设备驱动是需要编写的，除非目标系统使用了已经被支持的中断控制器。

> Such a driver contains a few major functions: an initialization function that maps the device in the kernel address space and maps the controller-local interrupt lines to the Linux IRQ number space (through the irq_domain mapping library); a mask/unmask function that can configure the controller in order to mask or unmask the specified Linux IRQ number; and, finally, a controller-specific interrupt handler that can find out which of its inputs is active and call the interrupt handler registered with this input (for example, this is how the interrupt handler of a block device connected to a PIC ends up being called after the device has raised an interrupt).

这样的驱动程序包含几个主要函数：初始化函数，将设备映射到内核地址空间，并将控制器本地中断线映射到Linux 中断编号空间（通过IRQ_domain映射库）；屏蔽/取消屏蔽函数，配置控制器以屏蔽或取消屏蔽指定的Linux IRQ号；最后是特定于控制器的中断处理程序，它可以找出哪些中断输入是有效的，并调用注册到该中断输入的中断处理函数（例如，这就是连接到PIC上的块设备触发一个中断时相应的中断处理函数怎样被调用的)。

## time_init()

> The purpose of time_init() is to initialize the architecture-specific aspects of the timekeeping infrastructure. A minimal version of this function, which relies on the use of a device tree, only involves two function calls.

time_init()函数的作用是初始化timekeeping基础设施的架构特定部分。这个函数的最简版本依靠设备树, 仅仅调用两个函数。

> First, of_clk_init() will scan the device tree and find all the nodes identified as clock providers in order to initialize the clock framework. A very simple clock-provider node only has to define a fixed frequency directly specified as one of its properties.

首先, of_clk_init()函数会扫描设备树然后找到所有标明为clock provider的节点, 以便初始化时钟框架。 一个非常简单的clock provider节点只需定义一个直接指定为其属性之一的固定频率。

> Then, clocksource_of_init() will parse the clock-source nodes of the device tree and initialize their associated driver. As described in the kernel documentation, Linux actually needs two types of timekeeping abstraction (which are actually often both provided by the same device): a clock-source device provides the basic timeline by monotonically counting (for example it can count system cycles), and a clock-event device raises interrupts on certain points on this timeline, typically by being programmed to count periods of time. Combined with the clock provider, it allows for precise timekeeping.

然后，clocksource_of_init()函数将解析设备树的时钟源节点并初始化与其关联的驱动程序。如内核文档中所述，Linux实际上需要两种类型的计时抽象（通常由同一个设备提供）：一种是时钟源设备，通过单调计数提供基本的时间线（比如对系统时钟周期进行计数）；还有一种是时钟事件设备，它可以在时间线的某些点引发中断，通常通过编程来计算一段时间。它与时钟供应器相结合，可实现精确计时。

> The driver of a clock-source device can be extremely simple, especially for a memory-mapped device for which the generic MMIO clock-source driver only needs to know the address of the device register containing the counter. For the clock event, it is slightly more complicated as the driver needs to define how to program a period and how to acknowledge it when it is over, as well as provide an interrupt handler for when a timer interrupt is raised.

时钟源设备的驱动程序可以非常简单，尤其是对于内存映射设备，它的通用MMIO时钟源驱动程序只需要知道包含计数器的设备寄存器的地址。时钟事件设备的驱动程序会稍微复杂一点，因为驱动程序需要定义如何编程一段时间、在(这一段时间)结束时如何确认它，以及为定时器中断时提供一个中断处理程序。

### Conclusion

### 结论

> One of the main tasks performed by start_kernel() later on is to calibrate the number of loops per jiffy, which is the number of times the processor can execute an internal delay loop in one jiffy—an internal timer period that normally ranges from one to ten milliseconds. Succeeding in performing this calibration should mean that the different infrastructures and drivers set up by the architecture-specific functions we just presented are working, since the calibration makes use of most of them.

tart_kernel()稍后执行的主要任务是校准每jiffy的循环次数，这是处理器在一jiffy内可以执行内部延迟循环的次数——内部计时器周期通常在1到10毫秒之间。如果成功地执行了校准，就表示上述特定于处理器体系架构的功能配置都正常工作了，因为校准使用了其中的大多数功能。

> In the next article, we will present the last portion of the port: from the creation of the first kernel thread to the init process.

在下一篇文章中，我们将介绍移植的最后一部分:从创建第一个内核线程到启动init进程。
