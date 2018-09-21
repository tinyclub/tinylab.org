---
layout: post
author: 'Xiao Jun'
title: "LWN 87538: 自动扫描内核问题"
album: 'LWN 中文翻译'
group: translation
license: "cc-by-sa-4.0"
permalink: /lwn-87538-finding-kernel-problems-automatically/
description: "LWN 文章翻译，自动扫描内核问题"
category:
  - 内核调试
  - LWN
tags:
  - Linux
  - sparse
---

> 原文：[Finding kernel problems automatically](https://lwn.net/Articles/87538/)
> 原创：By corbet @ June 1, 2004
> 翻译：By [darmac](https://github.com/darmac) of [TinyLab.org][1]
> 校对：By [cee1](https://github.com/cee1)

>In past years, this page has looked at the work done by the "Stanford checker," which analyzes code in search of various types of programming errors. The checker has found a lot of problems over the years, with the result that a lot of problems have been fixed before they had a chance to bite users of production kernels. 

本文查看了近年来“斯坦福检查器”项目的成就。“斯坦福检查器”是一个通过分析代码来扫描各种类型编程错误的工具。这些年来,此检查器已经发现了很多问题，这使得大量问题在暴露给用户之前就已经被妥善修复。

>The only problem with the Stanford checker is that it is not free software; it is, in fact, completely unavailable to the world as a whole. Rather than release the code, the checker group went off and formed Coverity to commercialize the checker software (now called "SWAT" and touted, ominously, as being "patent pending"). Developers at Coverity still occasionally post reports of potential bugs found by SWAT, but, for the most part, their attention seems focused on potential revenue opportunities. 

唯一的问题是斯坦福检查器不是自由软件；事实上，整个世界是完全无法接触到它的。这个检查器小组并没有公布它的代码,而是成立 Coverity 来商业化检查器软件（可怕的是，这款“专利待决”的软件现在被吹捧“SWAT”）。Coverity 的开发人员偶尔会提交 SWAT 发现的潜在漏洞报告，但大多数情况下，他们的注意力看似集中在潜在的收入机会上。

>It is hard to complain about this outcome. Before heading on this course, the Coverity folks uncovered vast numbers of bugs, and all Linux users benefited from that work. They also demonstrated how valuable static code testing tools can be. The community, however, was left in the position of having to actually write its own checker if it wanted one. Fortunately, this is the sort of thing the community can be good at. 

很难说人们应该抱怨这个结果。因为在开始这项课题之前，Coverity 人员发现了大量的漏洞，并且所有的 Linux 用户都从这项工作中受益。他们通过这项工作演示了静态代码测试工具到底有多大的价值。然而，社区如果想要一份，它就不得不自行编写一份自己的检查器。幸运的是，这正是社区所擅长的事情。

>A while back, none other than Linus Torvalds started work on his own tool, which came to be called "sparse." There has recently been a flurry of new activity around sparse, so it seems like a good time to take a look. 

前段时间，正是 Linus Torvalds 本人开始研究他自己的工具，这项工具后来被称为“sparse”。近期有一些围绕 sparse 的开发工作，所以现在看似是个好的时机来看看这项工作。

>sparse is normally obtained by cloning the BitKeeper repository at bk://kernel.bkbits.net/torvalds/sparse. For those who don't use BK, a checked-out version is available (as a bunch of SCCS files) on kernel.org. There is a low-bandwidth sparse mailing list as well. 

sparse 通常可以通过克隆位于 bk://kernel.bkbits.net/torvalds/sparse 的 BitKeeper 仓库来获取。对那些不使用 BK 的人来说，有一个签出的版本可以在 kernel.org 上获取（实际上是一堆 SCCS 文件）。它还有一个简单的 sparse 邮件列表。

>Essentially, sparse is a parsing and analysis library for the C language. One could put a number of different backends onto it; for example, a code-generation backend would turn it into a simple compiler. For the purposes of the kernel, however, the backend of interest is the analysis code which looks for various types of errors. The analyzer checks for quite a few different types of errors. Many of these (many sorts of type mismatches, for example) are also found by the compiler, but other tests are unique to sparse. 

从本质上来说，sparse 是一个 C 语言的解析和分析库。人们可以在其上放置很多不同的后端；例如，一个代码生成器后端可以让它变成一个简单的编译器。然而，对于内核的使用场景来说，更青睐其在分析代码中，找出各种类型的错误。此分析器能够检查处多种不同的错误类型。其中许多错误（例如多种类型不匹配问题）同样也能被编译器发现，但除此之外的错误则仅能由 sparse 测出来。

>The core test done by sparse is still the check for improper use of user-space pointers. A quick look through the kernel will turn up liberal use of a type attribute called __user; for example, the read() method invoked from system calls is prototyped as: 
>>ssize_t (*read) (struct file *, char __user *, size_t, loff_t *);

sparse 完成的核心测试仍然是检查用户空间指针的非法使用。若对内核进行快速浏览，就会发现一种被称为 __user 的属性类型得到了广泛的使用；例如，系统调用唤醒的 read() 方法原型为：

    ssize_t (*read) (struct file *, char __user *, size_t, loff_t *);

>When the kernel is being compiled, __user is defined as the empty string, so gcc doesn't see it at all. When sparse is being used, instead, it marks the pointer as (1) being in a separate address space, and (2) not being legal to dereference. sparse will use those flags to catch any mixing of user- and kernel-space pointers, and any attempt to directly dereference user-space pointers. 

当内核被编译时，__user 被定义为空字符串，因此 gcc 完全无法看到它。相反，使用 sparse 时，它标记这个指针为一个独立地址空间，同时也将其标记为非法解引用。sparse 将会使用这些标识来捕获任何用户和内核空间指针的混合使用，以及任何直接解引用用户空间指针的尝试。

>These checks have turned up a surprising number of errors. The kernel normally sets up the virtual address space in such a way that direct dereferencing of user-space pointers actually works - most of the time. Using user-space addresses in this way will fail, however, if the user page is not actually resident in memory at the time. More importantly, perhaps, this sort of direct dereferencing bypasses the normal access controls; every such error could, thus, become a security hole.

这些检查发现的错误数量惊人。内核通常以此方式建立虚拟地址空间：直接解引用用户空间指针实际上在大部分时候是可行的。然而，如果在某个时间点用户空间的页面实际上没有驻留在内存中，这样使用用户空间地址则会失败。更重要的是，也许这种直接的间接引用绕过了通常的访问控制；因此，每一笔这样的错误都可能成为安全漏洞。

>Catching such mistakes automatically seems like a good idea. It does require, however, that every variable holding a user-space pointer be marked with the __user attribute. Since much of the kernel (including every device driver) deals with user-space pointers, this is not a trivial job. This job is proceeding, however; several dozen patches adding __user annotations (and fixing problems found on the way) have been merged for 2.6.7. 

自动捕获这种错误看起来是个好主意。然而，它需要每个持有用户空间指针的变量都被标记为 __user 属性。由于大部分内核（包括每个设备驱动）都要处理用户空间指针，这不是一件轻微的工作。然而，这项工作还是在进行中；几十个增加了 __user 注释的补丁（以及按这种方式修正的错误）已经合并到了 2.6.7。

>Other checks performed include finding constants which are overly long for their target type, mistakes in embedded assembly language code, empty switch statements, assignments in conditionals, and so on. Its output is rather noisy still, but one assumes that will improve over time. If you have sparse installed, running it on the kernel is simply a matter of adding "C=1" to the make command. External modules can also be checked in this way. 

其它进行的检查包括寻找常量宽度超出目标类型的错误，内嵌汇编语言代码的错误，空的 switch 声明，条件语句中的赋值，诸如此类。它的输出仍然很繁杂，但随着开发推进这种情况会逐渐好转。如果你已经安装了 sparse，在内核上运行它只要简单地在 make 指令中增加“C=1”即可。外部模块同样可以使用这种方法进行检查。

>sparse is still clearly far behind the Stanford checker in terms of the variety of errors it can find. Unlike the checker, however, sparse is free software. The core parsing infrastructure is in place, so the addition of new checks should be relatively straightforward. All that's needed is the application of a bunch of developer time.

sparse 能找到的错误类型，依然远远落后于斯坦福检查器。然而，与它不同的是 sparse 是自由软件。sparse 的核心解析基础结构已经完成，因此添加新的检查项相对比较简单。所有这些新检查功能的加入需要的是开发者继续投入时间。

[1]: http://tinylab.org