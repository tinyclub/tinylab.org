---
layout: post
author: 'w-simon'
title: "LWN 657939: 将Linux移植到新的处理器架构,第3部分:到达终点"
draft: false
album: "LWN 中文翻译"
group: "translation"
license: "cc-by-sa-4.0"
permalink: /lwn-657939/
description: "LWN 文章翻译，将Linux移植到新的处理器架构,第3部分:到达终点"
category:
  - 体系架构
  - 移植
  - LWN
tags:
  - Linux
  - Architectures/Porting to
---

> 原文：[Porting Linux to a new processor architecture, part 3: To the finish line](https://lwn.net/Articles/657939/)
> 原创：By Joël Porquet @ **September 23, 2015**
> 翻译：By [w-simon](https://github.com/w-simon)
> 校对：By

> This series of articles provides an overview of the procedure one can follow when porting the Linux kernel to a new processor architecture. Part 1 and part 2 focused on the non-code-related groundwork and the early code, from the assembly boot code to the creation of the first kernel thread. Following on from those, the series concludes by looking at the last portion of the procedure. As will be seen, most of the remaining work for launching the init process deals with thread and process management.

本系列文章概述了将Linux内核移植到新处理器体系结构时应该遵循的过程。第1部分主要关注与代码无关的基础, 第2部分介绍了早期代码(从汇编引导代码到第一个内核线程的创建)。在此基础上，本文将讨论移植过程的最后一部分。正如将要看到的，启动init进程的大部分剩余工作都是处理线程和进程管理。

### Spawning kernel threads

### 产生内核线程

> When start_kernel() performs its last function call (to rest_init()), the memory-management subsystem is fully operational, the boot processor is running and able to process both exceptions and interrupts, and the system has a notion of time.

当start_kernel()函数调用了最后一个函数rest_init()时，内存管理子系统全面开启，引导处理器开始运行并且可以处理异常和中断，系统已经具备时钟概念。

> While the execution flow has so far been sequential and mono-threaded, the main job handled by rest_init() before turning into the boot idle thread is to create two kernel threads: kernel_init, which will be discussed in the next section, and kthreadd. As one can imagine, creating these kernel threads (and any other kinds of threads for that matter, from user threads within the same process to actual processes) implies the existence of a complex process-management infrastructure. Most of the infrastructure to create a new thread is not architecture-specific: operations such as copying the task_struct structure or the credentials, setting up the scheduler, and so on do not usually need any architecture-specific code. However, the process-management code must define a few architecture-specific parts, mainly for setting up the stack for each new thread and for switching between threads.

但是执行流到目前为止还是单线程的，rest_init()函数在进入idle线程之前的主要任务是创建两个内核线程：一个是kernel_init它会在下一节进行讨论，另一个是kthreadd。创建这些线程（和其他各种线程，用户线程也是通过相同的方式创建的）需要一个复杂的进程管理结构。创建新线程的大部分代码是架构无关的：例如复制task_struct结构体或者授权证书，建立调度器等等，通常不需要架构特定的代码。然而，进程管理代码也必须定义一些架构特定的部分，主要是为了给每个新线程建立堆栈和支持线程间切换。

> Linux always avoids creating new resources from scratch, especially new threads. With the exception of the initial thread (the one that has so far been booting the system and that we have implicitly been discussing), the kernel always duplicates an existing thread and modifies the copy to make it into the desired new thread. The same principle applies after thread creation, when the new thread's execution begins for the first time, as it is easier to resume the execution of a thread than to start it from scratch. This mainly means that the newly allocated stack must be initialized such that when switching to the new thread for the first time, the thread looks like it is resuming its execution—as if it had simply been stopped earlier.

Linux总是避免从零创建新资源，尤其是新的线程，只有初始线程（这个线程正在启动系统，即kernel_init线程）是个例外。内核总是复制已有线程，然后将其改造为新线程。同样的原则也适用于线程创建之后，当新线程第一次开始执行时，因为恢复线程的执行比从头开始执行更容易。这主要意味着必须对新分配的堆栈进行初始化，以便在第一次切换到新线程时，该线程看起来像是在恢复其执行——就像它刚才只是被停止了一样。

> To further understand this mechanism, delving a bit into the thread-switching mechanism and more specifically into the switch of execution flow implemented by the architecture-specific context-switching routine switch_to() is required. This routine, which is always written in assembly language, is always called by the current (soon to be previous) thread while returning as the next (future current) thread. Part of this trick is achieved by saving the current context in the stack of the current thread, switching stack pointers to use the stack of the next thread, and restoring the saved context from it. As with a typical function, switch_to() finally returns to the "calling" function using the instruction address that had been saved on the stack of the newly current thread.

为了更加深入地理解这个机制，我们必须稍微研究一下线程切换机制，尤其是由架构特定的上下文切换函数switch_to()实现的执行流的切换。这个函数通常是用汇编代码写的，它总是由当前线程调用然后由下一个线程返回。这个功能的部分实现是通过保存当前线程的上下文到当前线程的堆栈中，切换堆栈指针指向下一个线程的堆栈，然后恢复被保存的（下一个线程的）上下文。 由于这是一个特殊函数，switch_to()返回调用函数的方法是使用新的线程堆栈中保存的指令地址。

> In the case that the next thread had previously been running and was temporarily removed from the processor, returning to the calling function would be a normal event that would eventually lead the thread to resume the execution of its own code. However, for a brand new thread, there would not have been any function to call switch_to() in order to save the thread's context. This is why the stack of a new thread must be initialized to pretend that there has been a previous function call, enabling switch_to() to return after restoring this new thread. Such a function is usually setup to be a few assembly lines acting as a trampoline to the thread's code.

在这种情况下，下一个线程是先前运行过的，只是暂时被移出了处理器，这样返回调用函数就是一个正常事件，最终会使线程恢复其自身代码的执行。然而作为一个新的线程，它之前还没有调用过switch_to()函数来保存其线程上下文。这就是为什么必须初始化新线程的堆栈，以假装之前有一个函数调用，使switch_to()能够在恢复这个新线程后返回。这样的函数通常被设置为少量的汇编代码，充当线程代码的“蹦床”。

> Note that switching to a kernel thread does not generally involve switching to another page table since the kernel address space, in which all kernel threads run, is defined in every page table structure. For user processes, the switch to their own page table is performed by the architecture-specific routine switch_mm().

注意：内核线程切换通常不涉及页表的切换，因为它们是在同一个内核地址空间中，所有内核线程的运行定义在每个页表结构体中。但对于用户进程，切换它们自己的页表要通过架构特定函数switch_mm()来完成。

### The first kernel thread

第一个内核线程

> As explained in the source code, the only reason the kernel thread kernel_init is created first is that it must obtain PID 1. This is the PID that the init process (i.e. the first user space process born from kernel_init) traditionally inherits.

就像源码中解释的那样，内核线程kernel_init第一个被创建的原因是它必须获得PID 1。这是init进程的PID（即第一个用户空间进程由kernel_init创建）。

> Interestingly, the first task of kernel_init is to wait for the second kernel thread, kthreadd, to be ready. kthreadd is the kernel thread daemon in charge of asynchronously spawning new kernel threads whenever requested. Once kthreadd is started, kernel_init proceeds with the second phase of booting, which includes a few architecture-specific initializations.

有趣的是kernel_init的第一个任务是等待第二个内核线程kthreadd的完成。kthreadd是内核线程的守护进程，负责异步生成其他的内核线程。一旦kthreadd开始启动，kernel_init会继续进行第二阶段的引导，包含一些架构特定的初始化。

> In the case of a multiprocessor system, kernel_init begins by starting the other processors before initializing the various subsystems composing the driver model (e.g. devtmpfs, devices, buses, etc.) and, later, using the defined initialization calls to bring up the actual device drivers for the underlying hardware system. Before getting into the "fancy" device drivers (e.g. block device, framebuffer, etc.), it is probably a good idea to focus on having at least an operational terminal (by implementing the corresponding driver if necessary), especially since the early console set up by early_printk() is supposed to be replaced by a real, full-featured console shortly after.

在多核处理器系统中，kernel_init首先启动其他处理器核，然后初始化驱动模型的各个子系统（devtmpfs, devices, buses, etc.），最后再初始化底层硬件设备驱动程序。在进入设备驱动程序（e.g. block device, framebuffer, etc.）之前，至少初始化一个操作终端（通过安装相应的驱动程序）是一个好主意。尤其是用一个真正的全功能的终端来取代early_printk()函数建立的早期终端。

> It is also through these initialization calls that the initramfs is unpacked and the initial root filesystem (rootfs) is mounted. There are a few options for mounting an initial rootfs but I have found initramfs to be the simplest when porting Linux. Basically this means that the rootfs is statically built at compilation time and integrated into the kernel binary image. After being mounted, the rootfs can give access to the mandatory /init and /dev/console.

这些初始化操作也会解压initramfs和挂载根文件系统（rootfs）。挂载rootfs有几种选择，但是Joël Porquet在移植tsar时发现，initramfs是最简单的方法。这个rootfs会直接编译进内核二进制镜像中。挂载之后，这个通过它可以访问/init和/dev/console。

> Finally, the init memory is freed (i.e. the memory containing code and data that were used only during the initialization phase and that are no longer needed) and the init process that has been found on the rootfs is launched.

最后init段的内存会被释放（即这段内存中包含的是只在初始化阶段使用，且以后不需要的代码和数据），最后启动rootfs中的init进程。

### Executing init

### 启动用户态init进程

> At this point, launching init will probably result in an immediate fault when trying to fetch the first instruction. This is because, as with creating threads, being able to execute the init process (and actually any user-space application) first involves a bit of groundwork.

此时，运行init可能在取得第一条指令时马上会导致错误。这是因为，与创建线程一样，能够执行init进程（实际上是任何用户空间应用程序）首先需要进行一些基础工作。

> The function that needs to be implemented in order to solve the instruction-fetching issue is the page fault handler. Linux is lazy, particularly when it comes to user applications and, by default, does not pre-load the text and data of applications into memory. Instead, it only sets up all of the kernel structures that are strictly required and lets applications fault at their first instruction because the pages containing their text segment have usually not been loaded yet.

为了解决取指问题需要实现的函数是缺页处理程序。Linux是lazy的，尤其是对于用户程序，默认上是不预先将程序的文本和数据加载到内存中的。相反，它只加载需要的内核结构，让应用在第一次取值时引发缺页中断，因为包括上下文段的内存页通常还没有加载。

> This is actually perfectly intentional behavior since it is expected that such a memory fault will be caught and fixed by the page fault handler. This handler can be seen as an intricate switch statement that is able to treat every fault related to memory: from vmalloc() faults that necessitate a synchronization with the reference page table to stack expansions in user applications. In this case, the handler will determine that the page fault corresponds to a valid virtual memory area (VMA) of the application and will consequently load the missing page in memory before retrying to run the application.

这实际上是合理的，因为它预期这样一个中断会被缺页处理程序抓住并修正。一旦页故障处理函数可以捕获内存故障，一个非常简单init进程好像可以运行。然而，它不能做很多事情因为还不能通过系统调用来请求任何服务，例如打印字符到终端。为此系统调用必须完成架构特定的部分。系统调用被视为软件中断因为它们使用用户指令使处理器自动切换到内核模式，就像硬件中断那样。除了定义支持系统调用的列表，处理系统调用还需要增加中断和异常处理函数的额外功能来接受系统调用引起的异常。

> Once the page fault handler is able to catch memory faults, it is likely that an extremely simple init process can be executed. However, it will not be able to do much as it cannot yet request any service from the kernel through system calls, such as printing to the terminal. To this end, the system-call infrastructure must be completed with a few architecture-specific parts. System calls are treated as software interrupts since they are accessed by a user instruction that makes the processor automatically switch to kernel mode, like hardware interrupts do. Besides defining the list of system calls supported by the port, handling system calls involves enhancing the interrupt and exception handler with the additional ability to receive them.

缺页处理程序能够捕获内存错误之后，一个极其简单的init就能够执行了。然而，它还有很多工作不能做，因为它不能通过系统调用向内核请求任何服务，比如打印到终端。为此，必须使用一些特定于体系结构的代码来完成系统调用基础结构。系统调用被视为软件中断，因为它们是由用户指令访问的，该指令使处理器自动切换到内核模式，就像硬件中断一样。除了定义移植支持的系统调用列表外，处理系统调用还包括增强中断和异常处理程序，使其具有接收它们的额外能力。

> Once there is support for system calls, it should now be possible to execute a "hello world" init that is able to open the main console and write a message. But there are still missing pieces in order to have a full-featured init that is able to start other applications and communicate with them as well as exchange data with the kernel.

一旦支持系统调用，现在应该可以执行一个“hello world”版的init程序，它能够打开主控制台并写入消息。但是，要想拥有一个功能齐全的init，能够启动其他应用程序并与它们通信，以及与内核交换数据，还需要继续实现一些功能

> The first step toward this goal concerns the management of signals and, more particularly, signal delivery (either from another process or from the kernel itself). If a process has defined a handler for a specific signal, then this handler must be called whenever the given signal is pending. Such an event occurs when the targeted process is about to get scheduled again. More specifically, this means that when resuming the process, right at the moment of the next transition back to user mode, the execution flow of the process must be altered in order to execute the handler instead. Some space must also be made on the application's stack for the execution of the handler. Once the handler has finished its execution and has returned to the kernel (via a system call that had been previously injected into the handler's context), the context of the process is restored so that it can resume its normal execution.

实现这个目标的第一步是信号管理，更准确地说，是信号传递（包括来自其它进程或者来自内核本身的信号）。如果一个进程为某个特定的信号定义了处理函数，则只要收到该信号，就必须调用它的信号处理函数。当目标进程即将再次被调度时，就会发生这样的事件。更具体地说，这意味着在恢复进程时，正好处于一个切换回用户模式的时刻，必须更改进程的执行流以执行信号处理函数。在应用程序栈上也必须为信号处理函数的执行留出一定空间。一旦处理程序完成执行并返回内核(通过之前注入到信号处理函数上下文中的系统调用)，就会恢复该进程的上下文，以便它可以恢复正常执行。

> The second and last step for fully running user-space applications deals with user-space memory access: when the kernel wants to copy data from or to user-space pages. Such an operation can be quite dangerous if, for example, the application gives a bogus pointer, which would potentially result in kernel panics (or security vulnerabilities) if it is not checked properly. To circumvent this problem, it is necessary to write architecture-specific routines that use some assembly magic to register the addresses of all of the instructions performing the actual accesses to the user-space memory in an exception table. As explained in this LWN article from 2001, "if ever a fault happens in kernel mode, the fault handler scans through the exception table trying to match the address of the faulting instruction with a table entry. If a match is found, a special error exit is taken, the copy operation fails gracefully, and the system call returns a segmentation fault error."

完全运行用户空间程序的第二步、也是最后一步, 就是当内核想要从用户空间存取数据时要处理好内存访问。这一个操作可能是十分危险的，比如应用程序给出了一个假的指针，在不检查的情况下可能会引起内核的安全风险。为了解决这个问题，有必要编写特定于体系结构的程序，这些程序使用一些汇编魔法来在异常表中注册在执行对用户空间内存的实际访问的所有指令的地址。就像这篇2001年的LWN文章解释的：“如果在内核模式中发生故障，则故障处理程序将扫描异常表，尝试将故障指令的地址与表条目匹配。 如果找到匹配项，则会执行特殊的错误退出代码，（引起错误的）内存访问操作将正常失败，并且系统调用将返回segmentation fault。”

### Conclusion

### 结论

> Once a full-featured init process is able to run and give access to a shell, it probably signals the end of the porting process. But it is most likely only the beginning of the adventure, as the port now needs to be maintained (as the internal APIs sometimes change quickly), and can also be enhanced in numerous ways: adding support for multiprocessor and NUMA systems, implementing more device drivers, etc.

一旦这个功能齐全的init进程能够执行并且能正常启动shell，就表示移植过程结束了。但是这也是一个新的开始开始，这个移植版本需要维护（因为内部APIs有时候变化的很快），移植版本也可以通过很多方法来完善：支持多核处理器和NUMA系统，实现更多设备驱动程序等等。

> By describing the long journey of porting Linux to a new processor architecture, I hope that this series of articles will contribute to remedying the lack of documentation in this area and will help the next brave programmer who one day embarks upon this challenging, but ultimately rewarding, experience.

通过描述将Linux移植到一个新的处理器体系结构的漫长过程，我希望本系列文章将有助于弥补内核文档这方面的缺失，并帮助下一个勇敢的程序员，他将来可能有一天也会开启这一具有挑战性的但最终会有收获的历程。 
