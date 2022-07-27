---
layout: post
author: 'Wu Zhangjin'
title: "5 秒内跨架构运行 RISC-V Ubuntu 22.04 + xfce4 桌面系统"
draft: false
album: 'RISC-V Linux'
license: "cc-by-nc-nd-4.0"
permalink: /run-riscv-ubuntu-over-x86/
description: "本文介绍并演示了如何在 X86_64 笔记本上运行 RISC-V 架构的 Ubuntu 22.04 + xfce4 桌面系统。"
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - 跨架构
  - Ubuntu 22.04
  - xfce
  - lxqt
---

> Author:  Falcon <falcon@tinylab.org>
> Date:    2022/07/27
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)

## 背景简介

随着 [RISC-V Linux 内核兴趣小组](https://tinylab.org/riscv-linux-analyse/) 活动的不断推进，我们一方面已经通过 [Linux Lab](https://tinylab.org/linux-lab) 完美支持了 [RISC-V Linux 内核 v5.17](https://www.bilibili.com/video/BV1aU4y1d7zi?spm_id_from=333.999.0.0) 的开发，另一方面已经通过 [两分钟内极速体验 RISC-V Linux 系统发行版](https://tinylab.org/riscv-linux-distros/) 一文介绍了如何跨架构运行较为完整的 RISC-V Linux 发行版文件系统（命令行方式）。

好消息是，在前述工作的基础上，泰晓科技 Linux 技术社区最近又研发了可以直接在 X86_64 主机上跨架构运行的 RISC-V Ubuntu 22.04 + xfce4 桌面系统：[RISC-V Lab](https://gitee.com/tinylab/riscv-lab)，其运行与登陆方式与 Linux Lab 完全兼容。

2022 年 7 月 25 日，相关功能已经合并进了 [Cloud Lab](https://gitee.com/tinylab/cloud-lab) 主线，手头之前安装过 Linux Lab 或者手头有 [Linux Lab Disk](https://gitee.com/tinylab/linux-lab-disk) 的同学们可以跟着极速上手体验一番，其他有 git + docker 环境的同学也可以跟着一起快速上手。

## RISC-V Lab 简介

在之前的 [两分钟内极速体验 RISC-V Linux 系统发行版](https://tinylab.org/riscv-linux-distros/) 一文中，我们已经详尽列出了业内正在适配 RISC-V 的各大主流 Linux 发行版：

* [Ubuntu](https://wiki.ubuntu.com/RISC-V)
* [Fedora](https://lwn.net/Articles/749443/)
* [Debian](https://wiki.debian.org/RISC-V)
* [ArchLinux](https://archriscv.felixc.at/)
* [AIpine](https://drewdevault.com/2018/12/20/Porting-Alpine-Linux-to-RISC-V.html)
* [Deepin](https://github.com/linuxdeepin/deepin-riscv)
* [openEuler](https://gitee.com/openeuler/RISC-V)

业内的相关工作还在如火如荼地开展中，包括 Firefox, Chrome, Libreoffice 的适配工作都取得了重要进展，其中有不少工作成果是由国内 PLCT 实验室的 Tarsier 项目贡献的。

在经过慎重的考虑后，RISC-V Lab 决定采用 Ubuntu 22.04，相关支持如下：

* 以 Ubuntu 22.04 作为基础系统
* 验证了 lxqt 和 xfce4 两款轻量级桌面环境
* 集成了 git, vim, gcc, gdb 等开发工具
* 安装了一款轻量级的 netsurf-gtk 浏览器
* 中文显示与中文输入支持
* 远程登陆与访问支持

上述功能已经能够满足基本的开发与上网需求，后续将根据用户的需求不断迭代完善。

## RISC-V Lab 使用

### 首次运行

RISC-V Lab 的运行与登陆方式完全兼容 Linux Lab，在准备好 git 和 docker 后，仅需 3 条命令就可以运行起来：

```
$ git clone https://gitee.com/tinylab/cloud-lab.git
$ cd cloud-lab
$ tools/docker/run riscv-lab
```

首先运行会自动下载我们制作好的 RISC-V Ubuntu 22.04 + xfce4 桌面系统，目前仅有 1.24GB，具体下载时长跟大家的网络环境密切相关。

运行一次以后，后续运行会非常快，一般的机器，在 5s 内就能直接启动。

### 删除、重启与恢复

如果出现故障，可以直接删除或重启容器：

```
$ tools/docker/rm riscv-lab
or
$ tools/docker/rerun riscv-lab
```

在关机以后可以直接恢复容器，通常在 1-2s 内能恢复：

```
$ tools/docker/run riscv-lab
```

### 选择登陆方式

运行起来后，会提醒选择登陆方式，比较建议选择 vnc。具体的 vnc client，在 Ubuntu 下推荐 vinagre，执行日志如下：

```
INFO: Please choose one of the login methods:

     1	bash
     2	vnc
     3	ssh
     4	webssh
     5	webvnc

INFO: Choose the login method: 2

     2	vnc
...

INFO: Available VNC Clients:

     1	vinagre
     2	xtightvncviewer

INFO: Choose the vnc client: 1

     1	vinagre

INFO: Running 'vinagre --vnc-scale 172.20.20.12'
```

**小技巧**：如果要使用快捷方式 F11 启用或者退出 vinagre 的全屏模式，需要在 vinagre 的菜单中勾选 `View` 下面的 `Keyboard shortcuts`，这个设计非常奇葩，因为如果误选了 Fullscreen 而没有勾选快捷键的话只能执行 `sudo pkill x11vnc` 退出全屏。

上述登陆方式基本覆盖了各种需求，包括命令行、图形、本地访问、远程访问，大家可按需使用。首次选择后会记住，事后想更换，可以这样：

```
// 明确指定某种方式
$ tools/docker/bash riscv-lab
$ tools/docker/ssh riscv-lab
$ tools/docker/vnc riscv-lab
$ tools/docker/webssh riscv-lab
$ tools/docker/webvnc riscv-lab

// 或者这样
$ LOGIN=bash tools/docker/login riscv-lab

// 又或者
$ LOGIN=bash tools/docker/run riscv-lab
```

如果想用图形交互方式，相比较 vnc 而言，ssh 方式更为轻量级，可以类似这样直接启动图形软件：

```
$ tools/docker/ssh riscv-lab
ubuntu@riscv-lab:/labs/riscv-lab$ qterminal
```

qterminal 的窗口将直接在 X86_64 的主系统中显示，开销更低。

### 桌面显示效果

登陆以后，可以看到桌面有个 RISC-V Lab 图标，点击会直接启动控制台并采用 `/labs/riscv-lab` 作为工作目录。

之后执行了几个命令用于展示运行效果，完整截图如下：

![RISC-V Lab 运行效果](/wp-content/uploads/2022/03/riscv-linux/riscv_lab/riscv-lab-ubuntu2204-xfce4.png)

如果需要与主系统交换数据，在主机侧，可以用 Cloud Lab 下的 `labs/riscv-lab` 目录，这个目录就对应 RISC-V Lab 中的 `/labs/riscv-lab` 工作目录，例如：

```
$ pwd
~/Develop/cloud-lab
$ ls labs/riscv-lab/
COPYING  README.en.md  README.md
```

### 切换桌面环境

实际上，除了 xfce4，RISC-V Lab 也内置了 lxqt。

```
// 换成 lxqt
$ DESKTOP=lxqt tools/docker/rerun riscv-lab

// 换回 xfce
$ DESKTOP=xfce tools/docker/rerun riscv-lab
```

从初步的验证来看，lxqt 启动比 xfce 略慢。

### 安装软件

在容器内，可以直接用 `apt` 安装软件：

```
$ tools/docker/ssh riscv-lab
ubuntu@riscv-lab://labs/riscv-lab$ apt update -y
ubuntu@riscv-lab://labs/riscv-lab$ apt install -y dia
```

如果想重启以后还能用，可以保存一下：

```
$ tools/docker/save
sha256:82538e418a35f5d7965f3eabf2a8830cafdc95d605b490c551c97a23ef1e5ef5
INFO: new image name saved to tinylab/riscv-lab:local-20220727124605
```

后续即使是重启也会保留新安装的软件：

```
$ tools/docker/rerun riscv-lab
```

为方便后续升级社区的 RISC-V Lab 更新，建议本地的修改可以另外创建一个分支保存一下。

```
$ git checkout -b my-riscv-lab
$ git commit -s -m 'my riscv lab' configs/riscv-lab/docker/name
```

想升级的时候切换回 master 分支即可。当然，大家也可以把新的软件需求提交到 [这里](https://gitee.com/tinylab/riscv-lab) 的 Issues 下面。

## 小结

由 [RISC-V Lab](https://gitee.com/tinylab/riscv-lab)  提供的这种跨架构运行 RISC-V Linux 桌面系统的方式非常方便：

* 大多数情况下，无需购买 RISC-V 开发板等硬件
* 当前 RISC-V 硬件的性能普遍较弱，这种跨架构运行的方式能充分发挥 X86_64 主机的性能优势，从而获得更高的开发效率
* 无需复杂的安装过程，基础的开发环境一应俱全，安装软件也非常方便
* 无需繁琐的交叉编译环境配置与使用，可以直接采用以往熟悉的本地开发方式
* 在首次运行自动下载完镜像后，5 秒内就能启动，快速高效

咱们之前的 [Linux Lab](https://gitee.com/tinylab/linux-lab) 完美支持了 RISC-V Linux 内核的开发，这里的 [RISC-V Lab](https://gitee.com/tinylab/riscv-lab) 则能进一步支持 RISC-V 系统与软件类的开发工作，比如说软件开发、软件优化与软件打包，甚至做汇编语言开发，指令架构研究和编译器开发等。

两者结合以后，大家就可以直接在现有的 X86_64 笔记本上轻松跨架构完成从内核、系统到软件的全栈技术开发。加上 [Linux Lab Disk](https://tinylab.org/linux-lab-disk) 后，可以进一步做到免安装，即插即跑。

除了 RISC-V Lab，我们也同步发布了 [ARM Lab](https://gitee.com/tinylab/arm-lab)，用法完全一致，欢迎体验，如需其他架构的 Lab，欢迎联系微信号：tinylab。
