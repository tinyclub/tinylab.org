---
title: '开源之夏 - Summer 2023'
tagline: '“开源软件供应链点亮计划——暑期2023”项目提案'
author: Wu Zhangjin
draft: true
layout: page
permalink: /summer2023/
description: 国内第 4 届开源之夏，泰晓科技技术社区踊跃报名，携 8 个项目参加，欢迎大家报名。
update: 2023-04-25
categories:
  - 开源项目
  - Linux Lab
tags:
  - 暑期2023
  - 点亮计划
  - Linux Lab
  - Cloud Lab
  - Linux Lab Disk
  - 开源之夏
  - RISC-V
  - ELF2FLT
  - Unikernel
  - tinyget
  - LicheePi4A
  - rpcbind
  - manjaro
---

## 项目简介

中科院软件所主办了 [“开源软件供应链点亮计划——暑期2020”](https://summer.iscas.ac.cn/) 活动，今年为第四届。该活动旨在鼓励大家关注开源软件和开源社区，致力于培养和发掘更多优秀的开发者。

泰晓科技作为聚焦 Linux 内核十多年的技术社区在过去三年都参加了该活动，提报的大部分项目在 Mentor 和 Student 的精心合作下都顺利完成了。

## 往年回顾

![Summer2020](/wp-content/uploads/2021/03/29/summer2020.png)

有意向报名的同学可以提前了解一下往年的情况，相关文章链接如下：

* 2022
    * [开源之夏 - Summer 2022](https://tinylab.org/summer2022)

* 2021
    * [Summer2021预告：暑期来做开源项目吧，有社区老师指导，还有Bonus领取](https://tinylab.org/summer2021-intro/)
    * [“开源软件供应链点亮计划——暑期2021”项目提案](https://tinylab.org/summer2021)

* 2020
    * [“开源软件供应链点亮计划——暑期2020”项目提案](https://tinylab.org/summer2020)
    * [暑期2020：泰晓科技项目简介](https://tinylab.org/tinylab-summer2020)

## 活动概览

Summer2023 项目开发周期为 3 个月，从 7 月 1 日到 09 月 30 日，详细日程请查看 [活动规划](https://summer-ospp.ac.cn/#/howitworks)，期间：

* Mentor 负责指导报名的 Student 完成并达成预期的目标
    * 为确保活动开展质量，所有项目准备、调研、开发、测试、总结等过程需及时记录并公开发表在社区网站、公众号或其他指定仓库

* 达成目标后，活动主办方会给予 Mentor 和 Student 一定的奖励和资助
    * 数额因项目难度和完成情况而略有差异，具体情况以 [开源之夏](https://summer-ospp.ac.cn) 活动官网为准，解释权归活动主办方所有

* 社区这边主要是义务遴选合适的项目参加并组织和协调 Mentor 与 Student 的项目实施过程
    * 设立 Summer2023 微信交流群，方便学员和 Mentor 的交流
    * 组织必要的项目会议，跟进项目进度，发现项目瓶颈，协调解决项目困难，确保各个项目顺利推进
    * 开展必要的项目培训与演练

## Linux Lab 简介

![Linux Lab](/wp-content/uploads/2020/08/linux-lab-loongson.jpg)

本次提报的项目均围绕 Linux Lab 开源项目展开或者建议采用 Linux Lab 作为实验环境，这里对 Linux Lab 做一个简单介绍：

[Linux Lab](https://tinylab.org) 是一款知名国产开源项目，由 [泰晓科技技术社区](https://tinylab.org) 创建于 2016 年，旨在提供一套开箱即用的 Linux 内核与嵌入式 Linux 系统开发环境，安装以后，可以在数分钟内开展 Linux 内核与嵌入式 Linux 系统开发。

当前 Linux Lab 已经支持包括 X86、ARM、RISC-V、Loongson 在内的 7 大国内外主流处理器架构，增加了 20 款流行虚拟或真实嵌入式开发板，支持从 v0.11, v2.6.x, v3.x, v4.x, v5.x 到 v6.x 的各种新老 Linux 内核版本，可以同时在 Linux、Windows 和 macOS 三大主流操作系统上安装与使用，另外也制作了免安装、即插即跑的 Linux Lab Disk / 泰晓 Linux 实验盘。

![Linux Lab Disk](/wp-content/uploads/2021/04/linux-lab-disk-64g-ssd.jpg)

* 项目首页：<https://tinylab.org>
* 当前文档：<https://tinylab.org/pdfs/linux-lab-v1.1-manual-zh.pdf>
* 代码仓库：<https://gitee.com/tinylab/linux-lab>
* 视频课程：<https://www.cctalk.com/m/group/88948325>
* 实验盘文档：<https://tinylab.org/linux-lab-disk>
* 实验盘选购：<https://shop155917374.taobao.com/>

## 报名准备

为了最大程度地确保活动效果，社区需要遴选出准备最充分、能力最合适的学生参与相应项目，报名前请事先做好如下准备：

* 准备 Linux Lab 开发环境
    * 访问 [项目首页](https://tinylab.org/linux-lab) 了解项目详情
    * 下载 [项目文档](https://tinylab.org/pdfs/linux-lab-v1.1-manual-zh.pdf) 并浏览主要章节
    * 推荐直接选购免安装即插即跑的泰晓 Linux 实验盘，在某宝检索 “泰晓 Linux” 即可
        * 请参考实验盘文档: <https://gitee.com/tinylab/linux-lab-disk>
    * 或参考文档自行安装好 Linux Lab，并在如下页面登记安装信息，证明确实安装成功
        * [成功运行过的操作系统和Docker版本列表](https://gitee.com/tinylab/linux-lab/issues/I1FZBJ)

* 参考文档学习并使用 Linux Lab，撰写使用文档
    * 学习视频课程：<https://www.cctalk.com/m/group/88948325>
    * 使用过程需公开发表在知乎、CSDN、泰晓科技等任何公开渠道

* 浏览后文的 “项目列表”，选中自己感兴趣的项目

* 提前对相关技术做充分的调研并撰写一份技术调研报告
    * 为确保调研的质量，调研报告需正式发表到社区网站或公众号
    * 社区稿件投递方式请查看：<https://tinylab.org/post>，可直接在 <https://gitee.com/tinylab/tinylab.org> 提交 PR

## 报名方式

05 月 21 日 - 06 月 04 日是学生提交项目申请阶段，可提前了解 [学生指南](https://summer-ospp.ac.cn/help/student/)。

对社区提报的项目感兴趣的同学们，现在就可以提前联系我们，**联系微信**：tinylab，**暗号**：Summer2023。

## 版权说明

本次活动中由参与的学生新开发的代码需遵循 GPL v2 协议开放源代码，该等协议不影响相关项目原有和后续的版权协议，新增成果归贡献者和泰晓科技技术社区所有。

## 项目列表

### 项目一

1. 项目标题：移植 Unikernel Linux 到 RISC-V 架构
2. 项目描述：Unikernel Linux 允许把应用程序直接链接进 Linux 内核并跟内核一起运行在特权模式，这种工作方式将带来诸多特性，比如应用不再需要通过系统调用进入内核，还可以跟内核一起做 LTO 优化。这种设计对于 RISC-V 生态也非常重要，将对某些特定领域，比如 MCU、实时、低延迟网络服务等带来好处。它目前仅支持 x86，该项目旨在移植它到 RISC-V 架构上。
3. 项目难度：进阶
4. 项目社区导师：
5. 导师联系方式：
6. 合作导师联系方式：
7. 项目产出要求：
    - 学习 Unikernel Linux 的用法、原理和代码并输出 3 篇或以上文章
    - 为 Unikernel Linux 添加 RISC-V 架构的支持，可能涉及 Linux、Glibc、Gcc 等，输出 1 篇或以上文章
    - 开展充分的测试与验证，含配置、编译、启动和运行，需至少包含 3 个应用例子，输出 1 篇或以上文章
    - 把相关成果合并进 Linux Lab 开源项目的 unikernel 分支并往相关项目上游提交 Patch
    - 撰写 1 篇开发手册，1 篇使用文档，1 份测试报告并开展 1 期线上技术直播
    - 文章需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
8. 项目技术要求：
    - 有 Linux 内核开发与使用经验
    - 有 RISC-V 架构汇编或操作系统开发经验
    - 学习过 C 语言、操作系统相关课程
    - 掌握 Linux Lab 的用法
9. 相关的开源软件仓库列表：
    - Linux Lab: <https://gitee.com/tinylab/linux-lab>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>
    - Unikernel Linux: <https://github.com/unikernelLinux/linux>

### 项目二

1. 项目标题：为 ELF2FLT 完善独立编译与安装支持
2. 项目描述：ELF2FLT 是 uclibc 社区开发的一款工具，可以配合 gcc 工具链生成 FLAT 格式的可执行二进制文件格式，进而运行在不支持 MMU 的 Linux 内核上。ELF2FLT 目前的编译安装较为复杂，需集成进 Buildroot 等工具，泰晓社区已经开展了一些优化工作，该项目旨在泰晓社区工作成果的基础上进一步完善 ELF2FLT 的编译与安装，确保可以直接在 Linux 下安装完依赖的库以后，独立编译并安装 ELF2FLT，该项目将重点支持 RISC-V 架构。
3. 项目难度：进阶
4. 项目社区导师：
5. 导师联系方式：
6. 合作导师联系方式：
7. 项目产出要求：
    - 学习 ELF2FLT 支持的 FLAT 格式（含压缩格式），并跟 ELF 格式进行对比，输出 1 篇文章
    - 以 RISC-V 架构为例，学习 ELF2FLT 的用法、原理和代码并输出 3 篇以上文章
    - 以 RISC-V 架构为例，开展必要的开发与修改，确保可独立配置、编译和安装 ELF2FLT，并能正常编译出可正常运行的 FLAT 格式程序，输出 1 篇文章
    - 把相关成果合并进 Linux Lab 开源项目的 elf2flt 分支，确保能更简单的编译出 FLAT 程序，并往相关项目上游提交 Patch
    - 撰写 1 篇开发手册，1 篇使用文档，1 份测试报告并在泰晓社区开展 1 期线上技术直播
    - 文章需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
8. 项目技术要求：
    - 有 Linux 开发与使用经验
    - 有 RISC-V 架构汇编或操作系统开发经验
    - 学习过 C 语言、编译原理、操作系统等课程
    - 掌握 ELF 格式优先
    - 掌握 Linux Lab 的用法
9. 相关的开源软件仓库列表：
    - Linux Lab: <https://gitee.com/tinylab/linux-lab>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>
    - 泰晓 ELF2FLT 仓库: <https://gitee.com/tinylab/elf2flt>
    - Uclibc ELF2FLT 仓库: <https://github.com/uclinux-dev/elf2flt>

### 项目三

1. 项目标题：通过编译器解决因链接过程KEEP操作引起的Section GC失败问题
2. 项目描述：Linux 内核等项目支持 Section GC，在链接时能自动删除没有被使用到的函数和变量，但是有一类特殊的段，比如 exception table，虽然由函数调用需求触发生成，但是并没有明确的引用记录，导致这类 Section 需要通过KEEP操作强制保留，结果是，这种强制保留导致本来无人使用的函数无法被正常删除。该项目旨在通过编译器增加某种机制，确保这类特殊的段在创建时可以按需在触发生成它们的函数和这些段之间建立某种引用关系，从而避免通过KEEP来强制保留，进而解决相关函数的Section GC失败问题，并在此基础上消除内核中KEEP操作的滥用，该项目优先基于 RISC-V 架构。
3. 项目难度：进阶
4. 项目社区导师：@lzufalcon
5. 导师联系方式：falcon@tinylab.org
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 在某个编译器（GCC或/和LLVM）中新增某种机制，确保在通过 .pushsection 新建 Section 时可以自动建立当前函数对该 Section 的引用，输出 1 篇文章
    - 在 Linux 内核中验证该机制的有效性，在无 KEEP 的情况下，确保 Section GC 不能自动删除上述 Section，输出 1 篇文章
    - 把 Linux 内核中所有类似的场景全部替换为新的机制，消除 KEEP 的滥用，输出 1 篇文章
    - 把相关成果合并进 Linux Lab 开源项目的 section-gc 分支，并往相关项目的上游提交 Patch
    - 撰写 1 篇开发手册，1 篇使用文档，1 份测试报告并在泰晓社区开展 1 期线上技术直播
    - 文章需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
8. 项目技术要求：
    - 有 Linux 内核开发与使用经验
    - 有 GCC 或 LLVM 编译器的开发经验
    - 有 RISC-V 架构汇编或操作系统开发经验
    - 学习过 C 语言、编译原理、操作系统等课程
    - 掌握 Linux Lab 的用法
9. 相关的开源软件仓库列表：
    - Linux Lab: <https://gitee.com/tinylab/linux-lab>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>
    - GCC: <https://gcc.gnu.org/git/gitweb.cgi?p=gcc.git>
    - LLVM: <https://github.com/llvm/llvm-project>

### 项目四

1. 项目标题：录制基于 Linux Lab 的嵌入式 RISC-V Linux 系统开发课程
2. 项目描述：Linux Lab 和 RISC-V Lab 开源项目现在支持开展各类 RISC-V Linux 实验，包括 QEMU 模拟器、QEMU 虚拟化、Linux 内核、RISC-V 汇编、RVOS、U-Boot、OpenSBI、BuildRoot、RISC-V 应用开发等，该项目旨在基于 Linux Lab 和 RISC-V Lab 开展相关实验并录制相应视频课程。
3. 项目难度：进阶
4. 项目社区导师：
5. 导师联系方式：
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 基于 Linux Lab 开展 QEMU 模拟器、QEMU 虚拟化、Linux 内核、RISC-V 汇编、RVOS、U-Boot、OpenSBI、BuildRoot 实验并制作实验手册
    - 基于 RISC-V Lab 开展 RISC-V 应用开发实验并制作实验手册
    - 把上述实验过程录制为相应的视频课程，不少于 10 期视频，每期不少于半小时
    - 把视频课程陆续发表在泰晓社区的 B 站账号上
    - 实验手册需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
    - 需要在泰晓社区开展 1 期与该项目开发过程与成果相关的线上技术直播分享
8. 项目技术要求：
    - 有 Linux 系统使用经验
    - 有学习过计算机专业相关的课程
    - 有嵌入式 Linux 系统开发相关的学习经历
    - 掌握 Linux Lab 的用法
9. 相关的开源软件仓库列表：
    - Linux Lab: <https://gitee.com/tinylab/linux-lab>
    - RISC-V Lab: <https://gitee.com/tinylab/riscv-lab>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>

### 项目五

1. 项目标题：在新版 Manjaro 中确保 Linux Lab 正常启动 rpcbind 和 nfs 服务
2. 项目描述：在最新版的 Manjaro 中，Linux Lab 启动 rpcbind 和 nfs 服务出现衰退，无法正常工作，该项目旨在分析 rpcbind 和 nfs 服务启动失败的原因，修复该问题并提交解决方案。
3. 项目难度：进阶
4. 项目社区导师：
5. 导师联系方式：
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 在最新版的 Manajaro 中安装并运行 Linux Lab，输出 1 篇或以上文章
    - 分析新版 Manjaro 中 Linux Lab 的 rpcbind 和 nfs 服务启动失败的原因，输出 1 篇或以上分析文章
    - 修复 rpcbind 和 nfs 服务启动失败的问题并提交解决方案，需确保 `make boot ROOTDEV=nfs` 正常工作，输出 1 篇或以上技术文章
    - 把相关成果合并进 Linux Lab 开源项目，确保在 Manjaro 下正常使用 Linux Lab 的 rpcbind 和 nfs 服务
    - 文章需以 Markdown 格式提交进泰晓社区的 tinylab.org 项目仓库
    - 需要在泰晓社区开展 1 期与该项目开发过程与成果相关的线上技术直播分享
8. 项目技术要求：
    - 有 Manjaro 系统使用经验
    - 有 C 语言程序开发与调试经验
    - 掌握 Linux Lab 的用法
9. 相关的开源软件仓库列表：
    - Linux Lab: <https://gitee.com/tinylab/linux-lab>
    - Tinylab.org: <https://gitee.com/tinylab/tinylab.org>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>

### 项目六

1. 项目标题：为国产 RISC-V LicheePi4A 开发板移植 Real Time Preemption 补丁
2. 项目描述：LicheePi4A 是 Sipeed 开发的一款高性能国产 RISC-V 开发板，主频高达 1.85G，有潜在的工业场景应用前景。该项目旨在为这款国产 RISC-V 开发板移植 Real Time Preemption 实时 Linux 解决方案，优化潜在的 Latency 问题并达成一个较为理想的 Worst Case Latency。
3. 项目难度：进阶
4. 项目社区导师：
5. 导师联系方式：
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 为 LicheePi4A Linux 内核移植 Real Time Preemption 补丁，输出 1 篇或以上移植文章
    - 测试移植 RT 补丁后的 Linux 内核的实时系统性能，输出 1 篇或以上测试文章
    - 优化潜在的 Latency 问题并验证优化后的效果，输出 1 篇或以上优化文章
    - 把相关成果合并进 Linux Lab 开源项目的 licheepi4a-rt 分支并往相关项目的上游提交 Patch
    - 文章需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
    - 需要在泰晓社区开展 1 期与该项目开发过程与成果相关的线上技术直播分享
8. 项目技术要求：
    - 有 Linux 内核开发与使用经验
    - 有 RISC-V 架构汇编或操作系统开发经验
    - 学习过 C 语言、操作系统等课程
    - 掌握 Linux Lab 的用法
9. 相关的开源软件仓库列表：
    - Linux Lab: <https://gitee.com/tinylab/linux-lab>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>
    - LicheePi4A SDK: <https://gitee.com/thead-yocto>

### 项目七

1. 项目标题：调研并总结 RISC-V 处理器扩展的最新软硬件支持方案
2. 项目描述：RISC-V 处理器指令集由核心的 ISA 加一系列外围的扩展组成，在外围的扩展管理方面，最早通过 MISA 寄存器来做标识，但是随着扩展的不断扩充，MISA 已经完全无法满足要求，目前已经出现了新的扩展支持方式，QEMU 与 Linux 内核也在往新的方式上迁移，这部分对于芯片与内核厂商度至关重要。该项目旨在系统地调研 RISC-V 扩展的最新情况，包括扩展的类别、状态、支持的方式、QEMU, GCC 以及 Linux 内核的代码实现情况、应用开发时如何启用相关扩展等，从而为相关开发人员提供清晰明确的指导。
3. 项目难度：进阶
4. 项目社区导师：
5. 导师联系方式：
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 系统地调研 RISC-V 处理器扩展的最新软硬件支持方案，输出 6 篇或以上文章
    - 调研对象需包含 Spec 文档、GCC 支持、QEMU 支持、SBI 支持、Linux 内核支持以及应用开发案例等
    - 文章需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
    - 需要在泰晓社区开展 1 期与该项目开发过程与成果相关的线上技术直播分享
8. 项目技术要求：
    - 有 Linux 内核开发与使用经验
    - 有 RISC-V 架构汇编或操作系统开发经验
    - 学习过 C 语言、编译原理与操作系统等课程
    - 掌握 Linux Lab 的用法
9. 相关的开源软件仓库列表：
    - Linux Lab: <https://gitee.com/tinylab/linux-lab>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>

### 项目八

1. 项目标题：开发一个跨 Linux 发行版的软件包管理接口工具 tinyget
2. 项目描述：Linux 发行版众多造成了比较严重的碎片化，但是可喜的是，几大包管理工具的名字虽然不同，包名也不同，但是经过多年的发展，各大包管理工具日趋完善，提供的操作方式却逐步趋同，大同小异。该项目旨在 3 大主流 Linux 包管理工具（apt, pacman 与 dnf）的基础上，做进一步的抽象，在这些工具之上提供统一的 tinyget 接口，从而为各个发行版用户提供更为一致的软件安装体验，一个是解决碎片化，另外一个是解决本地化，该超级管理工具需要同时支持命令行方式和 GUI 方式。
3. 项目难度：进阶
4. 项目社区导师：
5. 导师联系方式：
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 系统地总结当前各大主流 Linux 包管理工具（至少需包括 apt, pacman 与 dnf）及其用法，做详细的对照和介绍，输出 1 篇或以上文章
    - 在上述总结的基础上抽象出更为全面的接口，并详细介绍各个接口的功能，输出 1 篇设计文章
    - 汇总各种中文常用软件包信息，包括软件名称、开发商、发布节奏、下载地址等，输出 1 篇或以上文章
    - 汇总国内各大软件镜像站的信息并做分类整理，并输出 1 篇或以上文章
    - 实现 tinyget 的原型系统，提交进泰晓社区的软件仓库并开展充分的测试与验证
    - 撰写 1 篇开发手册，1 篇使用文档，1 份测试报告并在泰晓社区开展 1 期线上技术直播
    - 需要在泰晓社区开展 1 期与该项目开发过程与成果相关的线上技术直播分享
    - 文章需以 Markdown 格式提交进泰晓社区的 tinylab.org 项目仓库
8. 项目技术要求：
    - Linux 发烧友，使用过各大 Linux 发行版
    - 具有丰富的 Shell 脚本开发经验
9. 相关的开源软件仓库列表：
    - Cloud Lab: <https://gitee.com/tinylab/cloud-lab>
    - tinyget: <https://gitee.com/tinylab/tinyget>
    - Tinylab.org: <https://gitee.com/tinylab/tinylab.org>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>

### 项目九

1. 项目标题：为 Linux Lab 提供在线代码阅读支持
2. 项目描述：本项目为 Linux Lab 内核编译系统添加一组选项，利用 LLVM 解析 Linux 源码并建立索引，精准追踪函数的跳转、符号的链接，并形成HTML前端页面，提供良好的阅读界面。
3. 项目难度：进阶
4. 项目社区导师：
5. 导师联系方式：
6. 项目产出要求：
    - 可以对在不编译源码的情况下进行启发式索引
    - 在编译源码后使用 `compile_commands.json` 进行精准索引
    - 形成前端页面并集成进 Linux Lab
    - 撰写使用文档以及开发手册
7. 项目技术要求：
    - Linux 基本操作
    - 熟悉 Linux Lab 并在此基础上开发
    - 熟悉 Makefile
    - 熟悉 Bash Script 开发
    - 熟悉 LLVM/Clang 环境配置
    - 熟悉 Web 前端环境部署
8. 相关的开源软件仓库列表：
    - Cloud Lab: https://gitee.com/tinylab/cloud-lab
    - Linux Lab: https://gitee.com/tinylab/linux-lab
