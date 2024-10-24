---
title: 'Linux 内核实验环境'
tagline: '可快速构建，支持 Docker, Qemu, Ubuntu, Mac OSX, Windows, Web'
author: Wu Zhangjin
layout: page
permalink: /linux-lab/
description: 基于 Qemu 的 Linux 内核开发环境，支持 Docker, 支持 Ubuntu / Windows / Mac OS X，也内置支持 Qemu，支持通过 Web 远程访问。
update: 2022-06-16
categories:
  - 开源项目
  - Linux Lab
tags:
  - 实验环境
  - Lab
  - Qemu
  - Docker
  - Uboot
  - 内核
  - 嵌入式
---

## 项目描述

该项目致力于快速构建一个基于 Qemu 的 Linux 内核开发环境。

  * 使用文档：[README_zh.md][2]
      * [Linux Lab v1.4 中文手册](https://tinylab.org/pdfs/linux-lab-v1.4-manual-zh.pdf)
      * [Linux Lab v1.4 英文手册](https://tinylab.org/pdfs/linux-lab-v1.4-manual-en.pdf)

  * 视频教程
      * [Linux Lab 公开课](https://www.cctalk.com/m/group/88948325)
          * Linux Lab 简介
          * 龙芯 Linux 内核开发
      * [《360° 剖析 Linux ELF》](https://www.cctalk.com/m/group/88089283)
          * 该课程全程采用 Linux Lab 开展实验，提供了上百个实验案例

  * 代码仓库
      * [https://gitee.com/tinylab/linux-lab.git][10]
      * [https://github.com/tinyclub/linux-lab.git][3]

  * 基本特性：
      * 跨平台，支持 Linux, Windows 和 Mac OSX。
      * Qemu 支持的大量虚拟开发板，统统免费，免费，免费。
      * 基于 Docker，一键安装，几分钟内就可构建，节约生命，生命，生命。
      * 直接通过 Web 访问，非常便捷，便捷，便捷。
      * 已内置支持 7 大架构：ARM, MIPS, PowerPC, X86, Risc-V, Loongson, Csky。
      * 已内置支持 18 款开发板：i386+X86_64/PC, PowerPC/G3beige, MIPS/Malta, ARM/versatilepb, ARM/vexpress-a9, ARM/mcimx6ul-evk, ARM/ebf-imx6ull, ARM64/Virt, ARM64/Raspi3, Riscv32+64/Virt, Loongson/{ls1b, ls232, ls2k, ls3a7a}, Csky/ck810 全部升级到了最新的 v5.1（其中 Riscv32/Virt 仅支持 V5.0）。
      * 已内置支持从 Ramfs, Harddisk, NFS rootfs 启动。
      * 一键即可启动，支持 串口 和 图形 启动。
      * 已内建网络支持，可以直接 ping 到外网。
      * 已内建 Uboot 支持，可以直接启动 Uboot，并加载内核和文件系统。
      * 预编译有 内核镜像、Rootfs、Qemu、Toolchain，可以快速体验实验效果。
      * 可灵活配置和扩展支持更多架构、虚拟开发板和内核版本。
      * 支持在线调试和自动化测试框架。
      * 正在添加 树莓派raspi3 和 risc-v 支持。

## 泰晓 Linux 实验盘

  Linux Lab v0.7 版开始支持 [泰晓 Linux 实验盘](/linux-lab-disk)），实现 Linux Lab 的即插即用，完全免安装，进一步提升 Linux Lab 使用体验，快速高效地开展 Linux 相关实验与开发。

[![泰晓 Linux 实验盘](/wp-content/uploads/2021/03/linux-lab-disk.png)](/linux-lab-disk)

  **产品特性**：

  * 智能启动，开创了三种全新的智能化 “傻瓜式” 使用方式，可自动检测后并行启动、可免关机直接来回切换、还可以智能记忆自动启动。
  * 相互套娃，多支 Linux Lab Disk 可相互启动或来回切换，因此，可根据喜好同时使用多个不同的 Linux 系统发行版。
  * 透明倍容，透明提供接近翻倍的可用容量空间，“零成本”获得接近一倍的额外存储空间。
  * 时区兼容，自动兼容 Windows, MacOS 和 Linux 的时区设定，跟主系统来回任意切换后时间保持一致。
  * 自动共享，在 Windows 或 Linux 主系统下并行运行时，自动提供多种与主系统的文件与粘贴板共享方式。
  * 零损编译，支持“半内存”与“全内存”的编译方式，可实现磁盘“零”写，极大地提升磁盘寿命，并提升实验效率。
  * 即时实验，集成自研 Linux Lab，Linux 0.11 Lab 等实验环境，可在 1 分钟内开展 Linux 内核、嵌入式 Linux、Uboot、汇编、C、Python、数据库、网络等实验。
  * 出厂恢复，全系 6 大 Linux 发行版已全部支持出厂恢复功能，在 "rm -rf /" 后都能启动并恢复出厂系统，同时支持自动备份和急救模式，用起来更安心！


  **购买地址**：

  * [在某宝搜索 “泰晓 Linux” 即可选购](https://shop155917374.taobao.com/)
  * [在 B 站 “泰晓科技” 的工房也可选购](https://gf.bilibili.com/item/detail/1105063021)

## 泰晓 RISC-V 实验箱

  Linux Lab v0.6 版开始实现了对真实嵌入式开发板的完美支持，从此，不仅可以使用 Linux Lab 学习 Linux 内核，还可以用它来做 Linux 驱动开发。

![泰晓 RISC-V 实验箱 —— 箱内集成外设，仅作参考，以收到的实物为准](/images/box/tiny-riscv-box-devices.jpg)

  **使用方法**:

  - [泰晓 RISC-V 实验箱照片以及演示小视频](https://www.bilibili.com/video/BV15N4y1W7ES/)
  - [三分钟内快速上手体验泰晓 RISC-V 实验箱](https://www.bilibili.com/video/BV18c41187co/)

  更多视频会连载到 [第 2 期 RISC-V Linux 系统开发公开课](https://space.bilibili.com/687228362/channel/collectiondetail?sid=2021659) 和 [泰晓 RISC-V 实验箱（合集，陆续更新）](https://space.bilibili.com/687228362/channel/collectiondetail?sid=2464425) 合集中，敬请期待……

  **购买地址**：

  * [在某宝搜索 “泰晓 Linux” 即可选购](https://shop155917374.taobao.com/)
  * [在 B 站 “泰晓科技” 的工房也可选购](https://gf.bilibili.com/item/detail/1105470021)

## 更多用法

* [Linux Lab：难以抗拒的十大理由 V1.0](https://tinylab.org/why-linux-lab)
* [Linux Lab：难以抗拒的十大理由 V2.0](https://tinylab.org/why-linux-lab-v2)
* [Linux Lab 龙芯实验手册 V0.2](https://tinylab.org/pdfs/linux-lab-loongson-manual-v0.2.pdf)
* Linux Lab 视频公开课
    * [CCTALK](https://www.cctalk.com/m/group/88948325)
    * [B 站](https://space.bilibili.com/687228362/channel/detail?cid=152574)
* 采用 Linux Lab 作为实验环境的视频课程
    * [《360° 剖析 Linux ELF》](https://www.cctalk.com/m/group/88089283)

## 五分钟教程

以 Ubuntu 为例，请先参考其他资料安装好 Docker。

### 下载

    $ git clone https://gitee.com/tinylab/cloud-lab.git
    $ cd cloud-lab && tools/docker/choose linux-lab

### 安装

    $ tools/docker/run            # 加载镜像，拉起一个 Linux Lab 容器

### 快速尝鲜

执行 `tools/docker/webvnc` 后会打开一个 VNC 网页，根据 console 提示输入密码登陆即可，之后打开桌面的 `Linux Lab` 控制台并执行：

    $ make boot

启动后，会打印如下登陆提示符，输入 root，无需密码直接按下 Enter 键即可。

    Welcome to Linux Lab

    linux-lab login: root

    # uname -a
    Linux linux-lab 5.1.0 #3 SMP Thu May 30 08:44:37 UTC 2019 armv7l GNU/Linux

默认会启动一个 `versatilepb` 的 ARM 板子，要指定一块开发板，可以用：

    $ make list                   # 查看支持的列表
    $ make BOARD=malta            # 这里选择一块 MIPS 板子：malta
    $ make boot

### 配置

    $ make kernel-checkout        # 检出某个特定的分支（请确保做该操作前本地改动有备份）
    $ make kernel-defconfig       # 配置内核
    $ make kernel-menuconfig      # 手动配置内核

### 编译

    $ make kernel       # 编译内核，采用 Ubuntu 和 emdebian.org 提供的交叉编译器

### 保存所有改动

    $ make save         # 保存新的配置和新产生的镜像

    $ make kconfig-save # 保存到 boards/BOARD/

    $ make kernel-save

### 启动新的内核

只要有新编译的内核，就会自动启动：

    $ make boot

### 启动串口

    $ make boot G=0	# 使用组合按键：`CTL+a x` 退出，或者另开控制台执行：`pkill qemu`

### 选择 Rootfs 设备

    $ make boot ROOTDEV=/dev/nfs
    $ make boot ROOTDEV=/dev/ram

### 扩展

通过添加或者修改 `boards/BOARD/Makefile`，可以灵活配置开发板、内核版本以及 BuildRoot 等信息。通过它可以灵活打造自己特定的 Linux 实验环境。

    $ cat boards/arm/versatilepb/Makefile
    ARCH=arm
    XARCH=$(ARCH)
    CPU=arm926t
    MEM=128M
    LINUX=2.6.35
    NETDEV=smc91c111
    SERIAL=ttyAMA0
    ROOTDEV=/dev/nfs
    ORIIMG=arch/$(ARCH)/boot/zImage
    CCPRE=arm-linux-gnueabi-
    KIMAGE=$(PREBUILT_KERNEL)/$(XARCH)/$(BOARD)/$(LINUX)/zImage
    ROOTFS=$(PREBUILT_ROOTFS)/$(XARCH)/$(CPU)/rootfs.cpio.gz

默认的内核与 Buildroot 信息对应为 `boards/BOARD/linux_${LINUX}_defconfig` 和 `boards/BOARD/buildroot_${CPU}_defconfig`，如果要添加自己的配置，请注意跟 `boards/BOARD/Makefile` 里头的 CPU 和 Linux 配置一致。

### 更多用法

详细的用法这里就不罗嗦了，大家自行查看帮助。

    $ make help

### 实验效果图

![Linux Lab Demo](/wp-content/uploads/2016/06/docker-qemu-linux-lab.jpg)

 [2]: https://gitee.com/tinylab/linux-lab/blob/master/README_zh.md
 [3]: https://github.com/tinyclub/linux-lab
[10]: https://gitee.com/tinylab/linux-lab
 [4]: /take-5-minutes-to-build-linux-0-11-experiment-envrionment/
 [5]: /build-linux-0-11-lab-with-docker/
 [6]: https://tinylab.org/docker-qemu-linux-lab/
 [7]: https://tinylab.org/using-linux-lab-to-do-embedded-linux-development/
