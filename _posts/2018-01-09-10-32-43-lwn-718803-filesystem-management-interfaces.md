---
layout: post
author: 'Zhao Yimin'
title: "LWN 718803: 文件系统管理接口"
# tagline: " 子标题，如果存在的话 "
album: "LWN 中文翻译"
group: translation
permalink: /lwn-718803-filesystem-management-interfaces/
description: "在LSFMM 2017的文件系统的专题会上，Steven Whitehouse 讨论了文件系统管理接口"
plugin: mermaid
category:
  - LWN
  - 文件系统
tags:
  - Linux
  - filesystem
---

> 原文：[Filesystem management interfaces](https://lwn.net/Articles/718803/)
> 原创：By By Jake Edge @ Apr 5, 2017
> 翻译：By Tacinight of [TinyLab.org][1]
> 校对：By ??? of [TinyLab.org][1]

> In a filesystem-only session at LSFMM 2017, Steven Whitehouse wanted to discuss an interface for filesystem management. There is currently no interface for administrators and others to receive events of interest from filesystems (and their underlying storage devices), though two have been proposed over the years. Whitehouse wanted to describe the need for such an interface and see if progress could be made on adding something to the kernel.

在 LSFMM 2017 文件系统的专题会上，Steven Whitehouse 讨论了文件系统管理的接口。目前，并没有对外的接口能够让系统管理员或者其他人来接收他们可能感兴趣的、来自文件系统（及其底层存储设备）事件通知，虽然这些年来已经有两个方案被提出。Whitehouse 想要通过描述这种接口的需求，看看是否可以在向内核添加些内容，从而取得一些进展。

> Events like ENOSPC (out of space) for thin-provisioned volumes or various kinds of disk errors need to get to the attention of administrators. There are two existing proposals for an interface for filesystems to report these events to user space. Both use netlink sockets, which is a reasonable interface for these kinds of notifications, he said.

由于精简配置卷或者磁盘错误导致的像 ENOSPC（空间不足）这样的事件通常需要引起管理员的注意。目前两个现有的关于文件系统管理接口的方案，都提议将这些事件通知到用户空间。Whitehouse 说，两个方案都使用 netlink 套接字，这样的方式用于这种通知也相当合理。

> Lukas Czerner posted one back in 2011, while Beata Michalska proposed another in 2015. The latter is too detailed, Whitehouse said, and has some performance issues. It notifies on events like changes to the block allocation in the filesystem, which is overkill for the kind of monitoring he is looking for.

第一个方案是 Lukas Czerner 在 2011 年发布的，而第二个方案则是由 Beata Michalska 提出于 2015 年。Whitehouse 说，第二个方案内容太过详细，并且有一些性能问题。它会通知如文件系统中块分配的更改这样的事件，而这样事件对于他正在寻找的那种监控方案来说，有些杀鸡用牛刀了。

> The interface needs to provide a way to enumerate the superblocks of filesystems that are mounted on the system. Applications would register their interest in particular mounts and get notification messages from them. The messages would consist of two parts, a key that identified the kind of event being reported along with a set of messages with further information about the event.

理想的接口需要能枚举操作系统上安装的文件系统的超级块。应用程序应当注册他们感兴趣的文件系统，并获取来自他们的消息通知。这些消息应当由两部分组成，一个是标识报告事件类型的关键字，以及一组关于该事件更多描述的消息。

> The messages would have a unique ID to identify the mount, which would consist of a device number (either the real one or one that was synthesized by the subsystem), supplemented with a UUID and/or volume label. Some kind of generation number might also be needed to distinguish between different mounts of the same filesystem.

这些消息中将有一个唯一的 ID 来标识挂载，其中包含一个设备编号（无论是真实的还是由子系统合成的），一个 UUID 或者卷标。也可能需要某种类型的编号来区分同一个文件系统不同的挂载方式。

> Steve French asked which filesystems can provide a UUID; network filesystems can do so easily, but what about others? Ted Ts'o said that all server-class filesystems have a way to generate a UUID. He also said that the device number would be useful to help correlate device errors. Trond Myklebust suggested that the information returned by /proc/self/mountinfo might be enough to uniquely identify mounts.

Steve French 问了哪些文件系统可以提供 UUID; 网络文件系统可以这么做，但其他的文件系统怎么办？ Ted Ts'o 表示，所有的服务器级文件系统都可以生成一个 UUID。他还表示，设备号码还有助于校正设备的错误。Trond Myklebust 建议，由 `/proc/self/mountinfo` 返回的信息已经足够用来唯一地标识装载。

> Ts'o said that this management interface is really only needed for servers, since what Whitehouse is looking for is a realtime alarm that some attention needs to be paid to a volume. That might be because it is thin-provisioned and is running out of space or because it has encountered disk errors of some sort.

Ts'o 说，这个管理接口实际上只是服务器需要，而 Whitehouse 寻找的是一个能够实时关注卷动态的警报系统。而这些情况可能只是因为存储卷精简了配置，空间用完了或者因为遇到了某种类型的磁盘错误。

> There was some discussion of how management applications might filter the messages so that they only process those of interest. Ts'o said that filtering based on device, message severity, filesystem type, and others would probably be needed. There was general agreement for the need for this kind of interface, though it was not clear what the next step would be.

之后还有一些讨论，关于管理应用程序如何进行过滤，以便只处理他们感兴趣的消息。 Ts'o 表示，可以基于设备、消息严重性、文件系统类型以及其他类型等进行过滤。对于这种接口的需求，大家普遍表示同意，但是尚不清楚下一步行动如何。

[1]: http://tinylab.org
