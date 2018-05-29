---
layout: post
author: 'WangBoJing'
title: "支持块IO上下文"
# tagline: " 子标题，如果存在的话 "
album: "LWN 中文翻译"
group: "translation"
permalink: /lwn-502472-supporting-block-IO-contexts/ 
description: " 文章摘要 支持阻塞IO上下文"
plugin: mermaid
category:
  - 文件系统
  - block IO
tags:
  - tag1
  - tag2
---

> 原文：[Supporting block I/O contexts](https://lwn.net/Articles/502472/)
> 原创：By Jonathan Corbet @ June 18, 2012
> By WangBoJing of [TinyLab.org][1]
> May 29, 2018

> Memory storage devices, including flash, are essentially just random-access devices with some peculiar restrictions. Given direct access to the device, Linux kernel developers could certainly come up with drivers that would provide optimal performance and device lifetime. In the real world, though, these devices are hidden behind their own proprietary operating systems and software stacks; much of the real (commercial) value seems to be in the software bundled inside. As a result, the kernel must try to coax the device's firmware into doing an optimal job. Over time, the storage industry has added various mechanisms by which an operating system can pass hints down to the device; the "trim" or "discard" mechanism is one of those. Newer eMMC and unified flash storage (UFS) devices add a new hint in the form of "contexts"; patches exist to support this feature, but they seem to have raised more questions than they have answered.

内存存储设备，包括闪存，基本上只是具有一些特殊限制的随机访问设备。考虑到直接访问设备，Linux内核开发人员致力设计出能够提供最佳性能和最长设备寿命的驱动程序。但在现实世界中，这些设备被他们自己的专有操作系统和软件栈所抽象化; 大部分真正的（商业）价值似乎都集中在捆绑的软件中。因此，内核必须尝试去诱导存储设备的固件做最佳工作。随着时间的推移，存储行业增加了各种机制，操作系统可以将信息传递给设备; “修剪”或“丢弃”机制就是其中之一。较新的eMMC和统一闪存（UFS）设备以“上下文”的形式添加新信息；存在补丁以支持此功能，但他们似乎提出的问题比他们所回答的问题更多。

> The standards documents describing contexts do not appear to be widely available—or at least findable. From what your editor has been able to divine, "contexts" are a small number added to I/O requests that are intended to help the device optimize the execution of those requests. They are meant to differentiate different types of I/O, keeping large, sequential operations separate from small, random requests. I/O can be placed into a "large unit" context, where the operating system promises to send large requests and, possibly, not attempt to read the data back until the context has been closed.

在可以找到的文档，描述上下文的标准文档看起来并不广泛。根据您的编辑器能够发挥的作用，“上下文”是以一个小数字的形式，添加I / O请求，主要是帮助存储设备优化这些I / O请求的执行。这些优化的方式主要是区分不同类型的I / O，将大型顺序操作与小型随机请求分开。 I / O可以放置在“大单元”上下文中，操作系统承诺在上下文关闭之前会对其写入大量请求并且不会读取数据。

> Saugata Das recently posted a small patch set adding context support to the ext4 filesystem and the MMC block driver. At the lower level, context numbers are associated with block I/O requests by storing the number in the newly-added bi_context (in struct bio) and context (in struct request) fields. The virtual filesystem layer takes responsibility for setting those fields, but, in the end, it defers to the actual filesystems to come up with the proper context numbers. There is a new address space operation (called get_context()) by which the VFS can call into the filesystem code to obtain a context number for a specific request. The block layer has been modified to avoid merging block I/O requests if those requests have been assigned to different contexts.

Saugata Das最近发布了一个小补丁集，为ext4文件系统和MMC块驱动程序增加了上下文支持。在较低级别，上下文编号通过将数字存储在新添加的bi_context（在struct bio中）和上下文（在struct request中）字段与块I / O请求相关联。虚拟文件系统层负责设置这些字段，但最终它会根据实际的文件系统提供适当的上下文编号。有一个新的地址空间操作（称为get_context() ），VFS通过该操作可以调用文件系统代码来获取特定请求的上下文编号。如果这些请求已分配给不同的上下文，则块层已被修改以避免合并块I / O请求。

> There was little discussion of the lower-level changes, which apparently make sense to the developers who have examined them. The filesystem-level changes have seen rather more discussion, though. Saugata's patch set only touches the ext4 filesystem; those changes cause ext4 to use the inode number of the file under I/O as the context number. Thus, all I/O requests to a single file will be assigned to the same context, while requests to different files would go into different contexts (within limits—eMMC hardware, for example, only supports 15 contexts, so many inode numbers will be mapped onto a single context number at the lower levels). The question that came up was: is using the inode number the right policy? Coming up with an answer involves addressing two independent questions: (1) what does the "context" mechanism actually do?, and (2) how can Linux filesystems provide the best possible context information to the storage devices?

几乎没有关于低级别变更的讨论，这对于审查这些变更的开发者显然是有意义的。不过，文件系统级别的更改已经有了更多的讨论。 Saugata的补丁集只涉及ext4文件系统; 这些更改导致ext4使用I / O下的文件的inode号作为上下文编号。因此，对单个文件的所有I / O请求将分配给相同的上下文，而对不同文件的请求将进入不同的上下文（在limits-eMMC硬件中，比如：仅支持15个上下文，因此将有很多inode数字映射到较低级别的单个上下文编号）。提出的问题是：是否使用了inode id正确策略？回答问题涉及到两个独立的问题：（1）“上下文”机制实际上做了什么？（2）Linux文件系统如何向存储设备提供最佳可能的上下文信息？

> Arnd Bergmann (who has spent a lot of time understanding the details of how flash storage works) has noted that the standard is deliberately vague on what the context mechanism does; the authors wanted to create something that would outlive any specific technology. He went on to say:

Arnd Bergmann（花费大量时间了解闪存存储的工作细节）指出，该标准故意模糊了上下文机制的作用;作者想创造一种超越任何特定技术的东西。他接着说：

> That said, I think it is rather clear what the authors of the spec had in mind, and there is only one reasonable implementation given current flash technology: You get something like a log structured file system with 15 contexts, where each context writes to exactly one erase block at a given time.

也就是说，我认为这个规范的作者脑子里想的是什么，而且根据当前的闪存技术，只有一个合理的实现：你得到类似于具有15个上下文的日志结构化文件系统，其中在确定时间内每个上下文精确写入一个擦除块。

> The effect of such an implementation would be to concentrate data written under any one context into the same erase block(s). Given that, there are at least a couple of ways to use contexts to optimize I/O performance.

这种实现的效果是将在任何一个上下文中，被写入的数据集中到相同的擦除块中。鉴于此，至少有几种方法可以使用上下文来优化I / O性能。

> For example, one could try to concentrate data with the same expected lifetime, so that, when part of an erase block is deleted, all of the data in that erase block will be deleted. Using the inode number as the context number could have that effect; deleting the file associated with that inode will delete all of its blocks at the same time. So, as long as the file is not subject to random writes (as, say, a database file might be), using contexts in this manner should reduce the amount of garbage collection and read-modify-write cycles needed when a file is deleted.

例如，可以尝试集中具有相同预期寿命的数据，这样，当删除部分擦除块时，该擦除块中的所有数据都将被删除。使用inode id作为上下文编号可能会产生这种效果; 删除与该inode相关联的文件将同时删除其所有块。因此，只要文件不受随机写入的影响（比如说可能是数据库文件），在文件被删除时，这种方式使用上下文应该减少了所需的垃圾回收和读 - 修改 - 写周期的数量。

> Another helpful approach might be to use contexts to separate large, long-lived files from those that are shorter and more ephemeral. The larger files would be well-placed on the medium, and the more volatile data would be concentrated into a smaller number of erase blocks. In this case, using the inode number to identify contexts may or may not work well. Large files would be nicely separated, but the smaller files could be separated from each other as well, which may not be desirable: if several small files would fit into a single erase block, performance might be improved if all of those files were written in the same context. In this case, some other policy might be more advisable.

另一种有用的方法可能是使用上下文分离 较大且长生命周期的文件 与 较短且较短暂生命周期的文件。较大的文件可以很好地放在介质上，而更易变的数据将集中到较少数量的擦除块中。在这种情况下，使用inode编号来识别上下文可能会或可能不会运行良好。大文件可以很好地分开，但较小的文件也可以彼此分开，这可能并不理想：如果几个小文件适合单个擦除块，如果所有这些文件都写入，性能可能会提高相同的上下文。在这种情况下，其他一些政策可能更适合。

> But what should that policy be? Arnd suggested that using the inode number of the directory containing the file might work better. Various commenters thought that using the ID of the process writing to the file could work, though there are some potential difficulties when multiple processes write the same file. Ted Ts'o suggested that grouping files written by the same process in a short period of time could give good results. Also useful, he thought, might be to look at the size of the file relative to the device's erase block size; files much smaller than an erase block would be placed into the same context, while larger files would get a context of their own.

但该策略应该是什么？ Arnd建议使用包含该文件的目录的inode号也许会工作地更好。各种评论者认为使用写入文件的进程的ID可以起作用，但是当多个进程写入相同的文件时存在一些潜在的困难。 Ted Ts'o建议：在短时间内对同一进程所写的文件进行分组可能会给出好的结果。他认为，也可以考虑相对于设备擦除块大小的文件大小；比擦除块小得多的文件将被放置在相同的上下文中，而较大的文件将得到它们自己的上下文。

> A related idea, also from Ted, was to look at the expected I/O patterns. If an existing file is opened for write access, chances are good that a random I/O pattern will result. Files opened with O_CREAT, instead, are more likely to be sequential; separating those two types of files into different contexts would likely yield better results. Some flags used with posix_fadvise() could also be used in this way. There are undoubtedly other possibilities as well. Choosing a policy will have to be done with care; poor use of contexts could just as easily reduce performance and longevity instead of increasing them.

Ted也提出了一个相关的想法，即查看预期的I / O模式。如果打开一个现有文件进行写入访问，那么很可能会产生一个随机I / O模式。相反，使用O_CREAT打开的文件更有可能是顺序的;将这两种类型的文件分成不同的上下文可能会产生更好的结果。一些与posix_fadvise（）一起使用的标志也可以用这种方式使用。毫无疑问，其他的可能性也是如此。选择一项策略必须小心谨慎地完成; 上下文使用不当可能会降低性能和寿命，而不会增加性能和寿命。

> Figuring all of this out will certainly take some time, especially since devices with actual support for this feature are still relatively rare. Interestingly, according to Arnd, there may be an opportunity in getting ext4 to supply context information early:

将所有这些都归纳出来肯定需要一些时间，尤其是因为实际支持此功能的设备仍然相对较少。有趣的是，根据Arnd的说法，有机会让ext4尽早提供上下文信息：

> Having code in ext4 that uses the contexts will at least make it more likely that the firmware optimizations are based on ext4 measurements rather than some other file system or operating system. From talking with the emmc device vendors, I can tell you that ext4 is very high on the list of file systems to optimize for, because they all target Android products.

在使用上下文的ext4中编写代码至少会使固件优化更可能基于ext4度量，而不是某些其他文件系统或操作系统。从与emmc设备供应商的交谈中，我可以告诉你，ext4在文件系统列表中非常优秀，因为它们都针对Android产品。

> Ext4 is, of course, the filesystem of choice for current Android systems. So, conceivably, an ext4 implementation could drive hardware behavior in the same way that much desktop hardware is currently designed around what Windows does.

当然，Ext4是当前Android系统的首选文件系统。因此，可以想象，ext4的实现可以驱动硬件行为，就像目前围绕Windows所设计的桌面硬件一样。

> Given that the patches are relatively small and that policies can be changed in the future without user-space compatibility issues, chances are good that something will be merged into the mainline as soon as the 3.6 development cycle. Then it will just be a matter of seeing what the hardware manufacturers actually do and adjusting accordingly. With luck, the eventual result will be longer-lasting, better-performing memory storage devices.

考虑到补丁相对较小，并且未来可能会改变策略而没有用户空间兼容性问题，所以很有可能在3.6开发周期后立即将某些内容合并到主线中。那么它只是看到硬件制造商实际做了什么并相应地进行调整。幸运的是，最终的结果将是更持久，性能更好的内存存储设备。

[1]: http://tinylab.org
