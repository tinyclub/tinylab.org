---
title: '开源之夏 - Summer 2024'
tagline: '“开源软件供应链点亮计划——暑期2024”项目提案'
author: Wu Zhangjin
draft: false
top: true
layout: page
permalink: /summer2024/
description: 国内第 5 届开源之夏，泰晓科技技术社区踊跃参与，携 7 个项目参加，欢迎大家报名。
update: 2024-04-28
categories:
  - 开源项目
  - Linux Lab
tags:
  - 暑期2024
  - 点亮计划
  - Linux Lab
  - Cloud Lab
  - 泰晓 Linux 系统盘
  - 泰晓 Linux 实验盘
  - 泰晓 RISC-V 实验箱
  - 开源之夏
  - 实时 Linux
  - RISC-V
  - tinyget
  - Milk-V Duo
  - Epiphany
  - Static Call
  - Buildroot
  - StratoVirt
  - OpenSBI
---

## 活动简介

中科院软件所主办了 [“开源软件供应链点亮计划”](https://summer.iscas.ac.cn/) 活动，今年为第五届。该活动旨在鼓励大家关注开源软件和开源社区，致力于培养和发掘更多优秀的开发者。

泰晓科技作为聚焦 Linux 内核近 15 年的技术社区在过去四年都参加了该活动，提报的大部分项目在 Mentor 和 Student 的精心合作下都顺利完成了。

## 往年回顾

![Summer2020](/wp-content/uploads/2021/03/29/summer2020.png)

有意向报名的同学可以提前了解一下往年的情况，相关文章链接如下：

* 2023
    * [开源之夏 - Summer 2023](https://tinylab.org/summer2023)
    * [泰晓社区开源之夏 2023 成果一览](/tinylab-ospp-2023-summary/)

* 2022
    * [开源之夏 - Summer 2022](https://tinylab.org/summer2022)

* 2021
    * [Summer2021预告：暑期来做开源项目吧，有社区老师指导，还有Bonus领取](https://tinylab.org/summer2021-intro/)
    * [“开源软件供应链点亮计划——暑期2021”项目提案](https://tinylab.org/summer2021)

* 2020
    * [“开源软件供应链点亮计划——暑期2020”项目提案](https://tinylab.org/summer2020)
    * [暑期2020：泰晓科技项目简介](https://tinylab.org/tinylab-summer2020)

## 活动概览

Summer2024 项目开发周期为 3 个月，从 7 月 1 日到 09 月 30 日，详细日程请查看 [活动规划](https://summer-ospp.ac.cn/)，期间：

* Student 提报项目申请，申请时间：4 月 30 日 - 6 月 4 日

* Mentor 负责指导报名的 Student 完成并达成预期的目标，Student 为项目实施主体和 Owner
    * 为确保活动开展质量，所有项目准备、调研、开发、测试、总结等过程需及时记录并公开发表在社区网站、公众号或其他指定仓库

* 达成目标后，活动主办方会给予 Mentor 和 Student 一定的奖励和资助
    * 数额因项目难度和完成情况而略有差异，具体情况以 [开源之夏](https://summer-ospp.ac.cn) 活动官网为准，解释权归活动主办方所有

* 社区这边主要是义务遴选合适的项目参加并组织和协调 Mentor 与 Student 的项目实施过程
    * 设立 Summer2024 微信交流群，方便学员和 Mentor 的交流
    * 组织必要的项目会议，跟进项目进度，发现项目瓶颈，协调解决项目困难，确保各个项目顺利推进
    * 开展必要的项目培训与演练

## Linux Lab 简介

![Linux Lab](/wp-content/uploads/2020/08/linux-lab-loongson.jpg)

本次提报的项目均围绕 Linux Lab 等开源项目展开或者建议采用 Linux Lab 作为实验环境，这里对 Linux Lab 做一个简单介绍：

[Linux Lab](https://tinylab.org) 是一款知名国产开源项目，由 [泰晓科技技术社区](https://tinylab.org) 创建于 2016 年，旨在提供一套开箱即用的 Linux 内核与嵌入式 Linux 系统开发环境，安装以后，可以在数分钟内开展 Linux 内核与嵌入式 Linux 系统开发，也可以用于 C、汇编、QEMU、OpenSBI、U-Boot、Buildroot 等开发。

当前 Linux Lab 已经支持包括 X86、ARM、RISC-V、Loongson 在内的 7 大国内外主流处理器架构，增加了 25 款流行虚拟或真实嵌入式开发板，支持从 v0.11, v2.6.x, v3.x, v4.x, v5.x 到 v6.x 的各种新老 Linux 内核版本，可以同时在 Linux、Windows 和 macOS 三大主流操作系统上安装与使用。

**为节省开发环境的准备时间，泰晓社区也制作了免安装、即插即跑的 Linux Lab Disk / 泰晓 Linux 实验盘，强烈推荐提前准备。实验环境的提前准备将作为项目中选的优先条件。**

![泰晓 Linux 实验盘](/wp-content/uploads/2021/04/linux-lab-disk-64g-ssd.jpg)

* 项目首页：<https://tinylab.org>
* 当前文档：<https://tinylab.org/pdfs/linux-lab-v1.3-manual-zh.pdf>
* 代码仓库：<https://gitee.com/tinylab/linux-lab>
* 视频课程：<https://space.bilibili.com/687228362>
* 实验盘文档：<https://tinylab.org/linux-lab-disk>
* 实验箱文档：<https://tinylab.org/tiny-riscv-box>
* 实验盘或实验箱选购：
    * B站：<https://space.bilibili.com/687228362>
    * 淘宝：<https://shop155917374.taobao.com/>

## 报名准备

为了最大程度地确保活动效果，社区需要遴选出准备最充分、能力最合适的学生参与相应项目，报名前请事先做好如下准备：

* 准备 Linux Lab 开发环境
    * 访问 [项目首页](https://tinylab.org/linux-lab) 了解项目详情
    * 下载 [项目文档](https://tinylab.org/pdfs/linux-lab-v1.3-manual-zh.pdf) 并浏览主要章节
    * 推荐直接选购免安装即插即跑的泰晓 Linux 实验盘，在某宝检索 “泰晓 Linux” 下单或者在 B 站 “泰晓科技” 账号的工坊内选购
        * 请参考实验盘文档: <https://gitee.com/tinylab/linux-lab-disk>
    * 或参考文档自行安装好 Linux Lab，并在如下页面登记安装信息，证明确实安装成功
        * [成功运行过的操作系统和Docker版本列表](https://gitee.com/tinylab/linux-lab/issues/I1FZBJ)

* 参考文档学习并使用 Linux Lab，撰写使用文档
    * 可以通过 CCtalk 或 B 站学习 Linux Lab 相关的视频课程
        * CCtalk：<https://www.cctalk.com/m/group/88948325>
        * B站：<https://space.bilibili.com/687228362>
    * 使用过程需公开发表在知乎、CSDN、泰晓科技等任何公开渠道

* 浏览后文的 “项目列表”，选中自己感兴趣的项目

* 提前对相关技术做充分的调研并撰写一份技术调研报告
    * 为确保调研的质量，调研报告需正式发表到社区网站或公众号
    * 社区稿件投递方式请查看：<https://tinylab.org/post>，可直接在 <https://gitee.com/tinylab/tinylab.org> 提交 PR

## 报名方式

04 月 30 日 - 06 月 04 日是学生提交项目申请阶段，可提前了解 [学生指南](https://summer-ospp.ac.cn/help/student/)。

对社区提报的项目感兴趣的同学们，现在就可以提前联系我们，**联系微信**：tinylab，**暗号**：Summer2024。

## 版权说明

本次活动中由参与的学生新开发的代码需遵循 GPL v2 等协议开放源代码，该等协议不影响相关项目原有和后续的版权协议，新增成果归贡献者和泰晓科技技术社区所有。

## 项目列表

### 项目一

1. 项目标题：为国产 Milk-V Duo 开发板移植 Real Time Preemption 补丁
2. 项目描述：Milk-V Duo 是一个基于算能 CV1800B 芯片的超紧凑嵌入式开发平台，它可以运行 Linux，为专业人士、工业ODM、AIoT爱好者、DIY爱好者和创作者提供了一个可靠、低成本和高性能的平台。泰晓 RISC-V 实验箱内置 Milk-V Duo 开发板，并提供配套的实验盘和近 20 款常见外设，可以在 10 分钟内直接开展基于 Milk-V Duo 开发板的嵌入式 Linux 系统开发。该项目旨在为这款国产 RISC-V 开发板移植 Real Time Preemption 实时 Linux 解决方案，优化潜在的 Latency 问题并达成一个较为理想的 Worst Case Latency。
3. 项目难度：进阶
4. 项目社区导师：@falcon
5. 导师联系方式：
6. 合作导师联系方式：
7. 项目产出要求：
    - 为 Milk-V Duo 的 Linux 内核移植 Real Time Preemption 补丁，输出 1 篇或以上移植文章
    - 测试移植 RT 补丁后的 Linux 内核的实时系统性能，输出 1 篇或以上测试文章
    - 优化潜在的 Latency 问题并验证优化后的效果，输出 1 篇或以上优化文章
    - 把相关成果合并进 Linux Lab 开源项目的相关分支并往相关项目的上游提交 Patch
    - 文章需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
    - 需要在泰晓社区开展 1 期与该项目开发过程与成果相关的线上技术直播分享
8. 项目技术要求：
    - 有 Linux 内核开发与使用经验
    - 有 RISC-V 架构汇编或操作系统开发经验
    - 学习过 C 语言、操作系统等课程
    - 掌握 Linux Lab 的用法或持有泰晓 Linux 实验盘优先
    - 持有 Milk-V Duo 开发板或泰晓 RISC-V 实验箱（含泰晓 Linux 实验盘）优先
9. 相关的开源软件仓库列表：
    - Linux Lab: <https://gitee.com/tinylab/linux-lab>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>

### 项目二

1. 项目标题：为 OpenSBI 增加 Section GC 功能
2. 项目描述：SBI 即 RISC-V Supervisor Binary Interface，直接运行在系统 M 模式，可以作为一个 bootloader 也可以是一个 M 模式下运行的后台程序，OpenSBI 是一种被广泛使用的 C 语言 RISC-V SBI 实现。OpenSBI 目前并不支持 Section GC，Section GC 是指 Section Garbage Collection，即段（Section）的垃圾收集。在编译程序时，GCC 会将代码和数据组织成不同的段（Sections），例如 .text 段存储可执行代码，.data 段存储已初始化的全局变量等等。而 Section GC 则是指在链接阶段对这些节进行清理，去除未使用的代码和数据，以减小最终生成的可执行文件的大小。该项目旨在通过为 OpenSBI 增加 Section GC 功能去除不必要的代码和数据，从而减小程序的尺寸并提高执行效率。
3. 项目难度：进阶
4. 项目社区导师：@bmeng
5. 导师联系方式：
6. 合作导师联系方式：
7. 项目产出要求：
    - 为 OpenSBI 增加 Section GC 功能，并验证该功能的有效性，输出 1 篇文章
    - 把相关成果合并进泰晓社区 OpenSBI 镜像仓库的 section-gc 分支，并往相关项目的上游提交 Patch
    - 撰写 1 篇开发手册，1 篇使用文档，1 份测试报告并在泰晓社区开展 1 期线上技术直播
    - 文章需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
8. 项目技术要求：
    - 学习过 C 语言、编译原理、操作系统等课程
    - 有 RISC-V 架构汇编或操作系统开发经验优先
    - 有 OpenSBI 开发与使用经验优先
    - 掌握 Linux Lab 的用法或持有泰晓 Linux 实验盘优先
9. 相关的开源软件仓库列表：
    - OpenSBI: <https://gitee.com/tinylab/opensbi>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>

### 项目三

1. 项目标题：为 StratoVirt 新增 RISC-V 架构支持
2. 项目描述：StratoVirt 是一种基于 Linux 内核的虚拟机（KVM）的开源轻量级虚拟化技术，作用与 QEMU-KVM 大体相同，保持传统虚拟化的隔离能力和安全能力，其轻量级设计降低了内存资源消耗，且提高了虚拟机启动速度。采用 Rust 开发，在安全性方面较好地避免了内存问题带来的安全漏洞。目前仅支持 x86 和 arm64。泰晓社区在 RISC-V 虚拟化方面做过很多技术分析分享，希望进一步通过实践丰富 RISC-V 虚拟化相关生态。由于 QEMU-RISCV 模拟器支持 RISCV 的虚拟化扩展，采用 QEMU-RISCV 作为 HOST CPU，在其上移植开发 StratoVirt，运行 guest os。
3. 项目难度：进阶
4. 项目社区导师：@tjytimi
5. 导师联系方式：
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 完成开发和测试环境的搭建，输出 1 篇文章
    - 分析 StratoVirt 中有关处理器架构部分的设计逻辑，输出 1 篇文章
    - 增加 RISC-V 架构支持代码，输出 2 篇设计文章
    - 把相关成果合并进泰晓社区 stratovirt 镜像的 riscv-porting 分支并往相关项目的上游提交 Patch
    - 文章需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
    - 需要在泰晓社区开展 1 期与该项目开发过程与成果相关的线上技术直播分享
8. 项目技术要求：
    - 熟悉 RUST 语言，使用过 RUST 进行过系统开发
    - 有 RISC-V 架构汇编或操作系统开发经验
    - 从事过 QEMU、KVM、虚拟化相关开发优先
    - 掌握 Linux Lab 用法或持有泰晓 Linux 实验盘优先
9. 相关的开源软件仓库列表：
    - Stratovirt: <https://gitee.com/tinylab/stratovirt>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>

### 项目四

1. 项目标题：为 Buildroot 搭建国内镜像站并新建一套面向 Buildroot 的二进制包管理服务
2. 项目描述：buildroot 是一个全球知名的嵌入式系统构建工具，可用于快速构建系统映像文件，主要用于嵌入式 Linux 系统开发，目前被各大芯片、开发板厂商用于嵌入式 Linux 系统与软件的分发。buildroot 由大量发布在全球各地的软件包构成，基于它构建系统映像的可靠性和效率严重依赖各个软件包的可访问性与下载速度，一旦某个软件包的链接失效或下载速度低下，整个 buildroot 的构建就处于失控的状态，严重威胁整个嵌入式 Linux 开发生态。该项目旨在联合多家国内镜像服务站，搭建 buildroot 以及其依赖的所有软件包的国内镜像，进而大幅提高 buildroot 在国内网络环境下的构建可靠性和构建速度。另外，buildroot 的系统映像文件需要按需构建，而未提供预编译好的二进制系统映像文件，泰晓社区在 Linux Lab 开源项目中首次为各大主流处理器提供了预先编译好的二进制系统映像文件，该项目计划进一步为 buildroot 开发二进制包管理器并在选定的某个稳定发布版之上优先为 RISC-V 处理器架构预编译并发布常用的二进制软件，进而进一步提升基于 Buildroot 的嵌入式 Linux 系统开发与升级效率。
3. 项目难度：进阶
4. 项目社区导师：@rogina
5. 导师联系方式：
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 设计 Buildroot 的镜像方法，编写镜像脚本，在国内 2-3 个镜像站上搭建 Buildroot 及相关软件包的镜像
    - 编写一个面向 Buildroot 的包管理器
    - 选定某个 Buildroot 的 release 版本，为 RISC-V 架构编译出常用的软件包以供包管理器下载和安装
    - 撰写 1 篇开发手册，1 篇使用文档，1 份测试报告并开展 1 期线上技术直播
    - 文章需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
    - 把相关成果合并进泰晓社区 Linux Lab 仓库的 buildroot 分支并按需向上游仓库提交 Patch
8. 项目技术要求：
    - 有 Buildroot 开发与使用经验
    - 熟练掌握 C、Python、Shell 等编程语言
    - 有 RISC-V 架构汇编或操作系统开发经验优先
    - 有开源软件镜像站的搭建经验优先
    - 掌握 Linux Lab 的用法或持有泰晓 Linux 实验盘优先
9. 相关的开源软件仓库列表：
    - Linux Lab: <https://gitee.com/tinylab/linux-lab>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>

### 项目五

1. 项目标题：epiphany-browser 异常卡死问题分析与解决以及 upstream
2. 项目描述：epiphany-browser 是一款简单、干净、漂亮、轻量级的知名开源网络浏览器，非常适合计算或存储资源紧张的设备。epiphany-browser 被观察到在树莓派、Windows 虚拟机等场景下访问 Web 网站时存在必现的卡死问题，该问题严重影响到该浏览器的使用体验。该项目旨在分析定位到根本原因后提出解决方案，最后向其上游仓库提交补丁。
3. 项目难度：基础
4. 项目社区导师：@iosdevlog
5. 导师联系方式：
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 复现 epiphany-browser 卡死问题
    - 定位 epiphany-browser 卡死原因，彻底修复 Bug，向上游发送修复 Patch
    - 输出 2 篇或以上技术文章，并开展 1 期线上技术直播
    - 文章需以 Markdown 格式提交进泰晓社区的 tinylab.org 仓库并获得正式发表
8. 项目技术要求：
    - 有 Linux 发行版的使用经验
    - 有 C 语言程序开发与调试经验
    - 掌握 Linux Lab 的用法或持有泰晓 Linux 实验盘优先
9. 相关的开源软件仓库列表：
    - Tinylab.org: <https://gitee.com/tinylab/tinylab.org>

### 项目六

1. 项目标题：为 RISC-V 添加 Static Call 支持并提交补丁
2. 项目描述：
    - 2018 年发现漏洞 Meltdown 和 Spectre
    - 谷歌提出 Retpolines 解决了这个安全问题，但引入了 4% 的性能影响。
    - 开发者们不断寻求解决方法：[Relief for retpoline pain] https://lwn.net/Articles/774743/
    - 2020 年使用 static calls 方法避免使用 retpolines，性能影响降低至 1.6%：[Avoiding retpolines with static calls] https://lwn.net/Articles/815908/
    - 当前 RISC-V 中还没有该功能，泰晓社区已经做了一些初步的调研工作，需要实习生进一步开发并完成 upstream。
3. 项目难度：进阶
4. 项目社区导师：@Forrestniu
5. 导师联系方式：
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 分析 static call 机制原理，以及对于内核性能影响，输出 1 篇文章
    - 在 Linux 内核中验证 static call 机制的有效性，并输出补丁，提交至内核社区。
    - 撰写 1 篇开发手册，1 篇使用文档，1 份测试报告并在泰晓社区开展 1 期线上技术直播
    - 文章需以 Markdown 格式提交进泰晓社区的 “RISC-V Linux 内核剖析” 项目仓库
8. 项目技术要求：
    - 有 Linux 内核开发与使用经验
    - 有 RISC-V 架构汇编或操作系统开发经验
    - 学习过 C 语言、编译原理、操作系统等课程
    - 了解 Static Call 原理优先
    - 掌握 Linux Lab 的用法或持有泰晓 Linux 实验盘优先
9. 相关的开源软件仓库列表：
    - Linux Lab: <https://gitee.com/tinylab/linux-lab>
    - RISC-V Linux: <https://gitee.com/tinylab/riscv-linux>

### 项目七

1. 项目标题：为包管理工具 tinyget 开发图形用户管理界面并完善相应功能
2. 项目描述：tinyget 是泰晓社区研发的一款跨平台软件包管理工具，支持 apt、 pacman 和 dnf 包管理接口，能够为不同 Linux 发行版提供完全一致的包管理使用体验，并支持了 AI 分析。tinyget 允许用户更换 Linux 发行版时无需学习新的包管理工具。该项目旨在现有的基础上完善相应功能，包括但是不限于：1) 增加图形用户管理界面；2) 自建源或增加软件源发布管理，重点增加常用国产 Linux 软件的搜索、下载与安装支持；3) 自动测速并智能配置下载镜像站；4）包管理接口模拟（例如，在 fedora 下，原生是 dnf 包管理，允许通过 tinyget 模拟新增 apt 和 pacman 包管理）。
3. 项目难度：进阶
4. 项目社区导师：@taotieren
5. 导师联系方式：
6. 合作导师联系方式：暂无
7. 项目产出要求：
    - 调研主流 Linux 发行版的图形软件包管理工具，对比分析并总结出各自的工作原理和设计异同，输出 1 篇或以上文章
    - 对常用国产 Linux 软件包的发布方式进行分析（包括但不限软件名称、开发商、发布节奏、下载地址等），据此通过自建源或同等方式在 tinyget 中实现常用国产 Linux 软件包的搜索、下载与安装支持，输出 1 篇或以上文章
    - 设计 tinyget 的图形软件以及界面，使其布局合理交互简易外观精致，输出 1 篇或以上文章
    - 为 tinyget 开发软件源自动测速和镜像站智能配置功能
    - 在完成上述接口或功能设计过程中，需要完成基础的软件的单元测试功能便于持续集成
    - 撰写 1 篇开发手册，1 篇使用文档，1 份测试报告并在泰晓社区开展 1 期线上技术直播
    - 文章需以 Markdown 格式提交进泰晓社区的 tinylab.org 项目仓库
8. 项目技术要求：
    - Linux 发烧友，熟练使用过各大 Linux 发行版以及各类常见包管理工具
    - 具有丰富的 Shell 脚本开发经验
    - 熟悉或掌握 Python 或其他编程语言
    - 有 tinyget 工具使用经验优先
    - 持有泰晓 Linux 系统盘优先
9. 相关的开源软件仓库列表：
    - Cloud Lab: <https://gitee.com/tinylab/cloud-lab>
    - tinyget: <https://gitee.com/tinylab/tinyget>
    - Tinylab.org: <https://gitee.com/tinylab/tinylab.org>
