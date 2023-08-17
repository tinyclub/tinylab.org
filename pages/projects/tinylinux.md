---
title: 'TinyLinux: Linux 小型化项目'
tagline: '由本站创始人发起于 2010 年的开源项目，已成功移植到 RISC-V 架构'
author: Wu Zhangjin
layout: page
permalink: /tinylinux/
description: 致力于裁剪 Linux，降低 磁盘和内存开销
update: 2015-10-1
categories:
  - 开源项目
  - 系统裁剪
tags:
  - RISC-V
  - Linux
  - TinyLinux
  - 内核裁剪
---

## Introduction

TinyLinux project was proposed by 'Zhangjin Wu' in 2010, it was firstly developed for MIPS architecture, currently, it is porting to RISC-V, the development is very active:

## Targets & Status

- Small Kernel Image: < 512K
    - Status: 334k Kernel Image on RISC-V 64

- Small Rootfs/Application: < 512K
    - Status: 24K rootfs

- Small GUI Program: < 1M
    - Status: 628K 3D Wave

- Small Memory Cost: < 16M

## Proposal

  * [Work on Tiny Linux Kernel][1]

## Git repository


  * [TinyLinux Git repo][2]
  * [Linux Loongson Community - tiny36 branch](https://github.com/tinyclub/linux-loongson-community/tree/tiny36)

## Paper

  * [Tiny Linux Kernel Project: Section Garbage Collection Patchset][3]

## Patch

  * [Break through the Linux kernel image size limitation of the Uboot][4]

## References

  * [Linux Kernel Tinification](http://events.linuxfoundation.org/sites/events/files/slides/tiny.pdf)
  * [Tiny Linux Kernel Wiki Page](http://tiny.wiki.kernel.org)
  * [Quick Benchmark: Gzip vs Bzip2 vs LZMA vs XZ vs LZ4 vs LZO](https://catchchallenger.first-world.info/wiki/Quick_Benchmark:_Gzip_vs_Bzip2_vs_LZMA_vs_XZ_vs_LZ4_vs_LZO)
  * [Embedded Linux System Size Optimization](https://tinylab.org/embedded-linux-system-size-optimization/)
  * [Library Optimizer Tool](http://libraryopt.sourceforge.net/)
  * [Comparison of C/POSIX standard library implementations for Linux](http://www.etalabs.net/compare_libcs.html)
  * [Buildroot v.s. Openembedded/Yocto](https://events.static.linuxfound.org/sites/events/files/slides/belloni-petazzoni-buildroot-oe_0.pdf)

 [1]: http://elinux.org/Work_on_Tiny_Linux_Kernel
 [2]: https://github.com/tinyclub/tinylinux
 [3]: https://lwn.net/images/conf/rtlws-2011/proc/Yong.pdf
 [4]: https://tinylab.org/break-through-the-linux-kernel-image-size-limitation-of-the-uboot/
