---
layout: post
author: 'Zhao Yimin'
title: "容器感知的文件系统"
# tagline: " 子标题，如果存在的话 "
album: "LWN 中文翻译"
group: translation
permalink: /lwn-718639-container-aware-filesystems/
description: "本文介绍了一个在无特权容器中挂载文件系统的问题，探索了解决该问题的一些方法。"
plugin: mermaid
category:
  - 文件系统
  - LWN
tags:
  - Container
  - Filesystem
---

> 原文：[Container-aware filesystems](https://lwn.net/Articles/718639/)
> 原创：By Jake Edge @ April 3, 2017
> 翻译：By Tacinight of [TinyLab.org][1] 
> 校对：By ???

> We are getting closer to being able to do unprivileged mounts inside containers, but there are still some pieces that do not work well in that scenario. In particular, the user IDs (and group IDs) that are embedded into filesystem images are problematic for this use case. James Bottomley led a discussion on the problem in a session at the 2017 Linux Storage, Filesystem, and Memory-Management Summit.

目前我们离能够在容器内部进行非特权挂载的目标越来越近了，但是仍然有一些部件在这种情况下效果不佳。具体而言，就是嵌入到文件系统映像中的用户ID（和组ID）还不能够很好的工作。James Bottomley 在 2017 年的 Linux 存储，文件系统和内存管理峰会上主持了一个关于该问题的讨论。

> The various containerization solutions in Linux (Docker, LXC, rkt, etc.) all use the same container interfaces, he said. That leads to people pulling in different directions for different use cases. But the problem with UIDs stored in filesystem images affects all of them. These images are typically full root filesystems for the containers that have lots of files owned by the root user.

他提到，Linux 中的各种容器解决方案（Docker，LXC，rkt等）都使用相同的容器接口。不同容器通常针对不同的用例需求开发。但是 UID 存储在文件系统映像中的问题会影响到所有这些发展。这些文件系统映像通常是拥有许多文件的完整根文件系统，这些文件一般都归属于 root 用户。

> Bottomley has proposed shiftfs as a potential solution to this problem. It is similar to a bind mount, but translates the filesystem UIDs based on the user namespace mapping. It can be used by unprivileged containers to mount a subtree that has been specifically marked by the administrator as being shiftfs-mountable.

Bottomley 提出了使用 shiftfs 作为这个问题的一个潜在的解决方案。它类似于一个绑定挂载，但是能基于用户命名空间映射来转换文件系统的 UID。这样非特权容器可以使用它来安装一个由管理员明确标记为“可基于 shiftfs 挂载”的子树。

> An earlier effort to solve the problem added the s_userns field to the superblock in order to do UID translations, but that is a per-superblock solution that does not work well for containers that want to share a specific mounted filesystem among containers with different UID mappings. With shiftfs, an inode operation will translate the UID based on the namespace mapping to that of the underlying filesystem before passing the operation the lower level. That means the virtual filesystem (VFS) does not need changes, which makes for a cleaner solution, Bottomley said.

早期为了解决此问题所提的方案是，将 s_userns 字段添加到超级块以执行 UID 转换，但是这是一个超级块级别解决方案，对于希望在具有不同 UID 的容器之间共享一个特定的已挂载的文件系统并不能很好的奏效。使用 shiftfs，inode 操作将基于命名空间映射，在把命令传递到更底层的指令之前，将 UID 转换到底层文件系统中。Bottomley 说，这意味着虚拟文件系统（VFS）不需要改变，就可以获得一个干净利落的解决方案。

> There are some significant security implications to allowing arbitrary directory trees to be shift-mounted in unprivileged containers, including the ability for users to create setuid-root binaries. So the administrator must mark those subtrees (using extended attributes in his prototype) that are safe to be mounted that way.

但是允许任意目录树在非特权容器中进行 shift 挂载也会有一些重要的安全隐患，其中包括了允许用户创建 setuid-root 二进制文件的能力。因此，管理员必须标记这些是可以安全挂载的子树（在他的原型中使用了一些扩展属性）。

> Al Viro asked if there is a plan to allow mounting hand-crafted XFS or ext4 filesystem images. That is an easy way for an attacker to run their own code in ring 0, he said. The filesystems are not written to expect that kind of (ab)use. When asked if it really was that easy to crash the kernel with a hand-crafted filesystem image, Viro said: "is water wet?"

Al Viro 询问是否有计划允许安装手工制作的 XFS 或 ext4 文件系统映像。他说，这是一个很容易可以让攻击者在 ring 0 环境中运行自己的代码的方式。文件系统的初衷并不是为了那种（胡乱）用法而编写的。当被问及用手工制作的文件系统映像是否真的容易使内核崩溃时，Viro说：“水是湿的吗？（答案是显而易见的）“

> Amir Goldstein said that the current mechanism is to use FUSE to mount the filesystems in the unprivileged containers. But Bottomley is concerned that the FUSE daemon can be exploited, so it should run in the unprivileged container as well. If you restrict the mounts to USB sticks, it means an attacker would need physical access, which has plenty of other paths for system compromise so it is "safe" in that sense. But if loopback mounting of filesystems is to be supported at some point, the filesystem code will need to have no exploitable bugs.

Amir Goldstein 表示，目前的机制是使用 FUSE 将文件系统安装在非特权容器中。但 Bottomley 担心 FUSE 的守护进程可能被利用，所以它也应该在非特权容器中运行。如果将安装媒介限制在 U 盘上，则意味着攻击者需要进行物理访问，这时系统还可以在其他路径上妥协，因此某种意义上还是“安全”的。但是，如果文件系统的回送挂载将来在某个时候被支持，那么文件系统代码还需要保证没有被利用的漏洞才行。

> In something of an aside, Goldstein reminded filesystem developers that their filesystems may be running under overlayfs. He suggested that there needs to be more testing of different filesystems underneath overlayfs.

除此之外，Goldstein 提醒文件系统开发者他们的文件系统可以运行在 overlayfs 之下。他建议，需要对 overlayfs 下的不同文件系统进行更多的测试。

> While the attendees recognized the problem for unprivileged containers, there does not seem to be a consensus on the right route to take to solve it.

虽然与会者认识到了这个无特权容器的问题，但在到底如何解决这个问题似乎并没有达成共识。

[1]: http://tinylab.org
