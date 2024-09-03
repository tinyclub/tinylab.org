---
layout: post
author: 'Jia Xianhua'
title: '在 QEMU 上运行 RISC-V Linux RealTime 补丁'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-real-time-linux-1/
description: '在 QEMU 上运行 RISC-V Linux RealTime 补丁'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - QEMU
  - PREEMPT_RT
  - Real Time
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces]
> Author:    Jia Xianhua <jiaxianhua@tinylab.org>
> Date:      2022/12/01
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [【老师提案】RISC-V RealTime 分析、优化与 CPU 设计建议][002]
> Sponsor:   PLCT Lab, ISCAS


## 背景简介

吴金章老师于 2022/06/29 发起了一个提案：[【老师提案】RISC-V RealTime 分析、优化与 CPU 设计建议][002]，本来是作为实习生的暑期计划。

可能是学生暑期时间精力不够，并且这个提案要求确实有点门槛，10 月的时候，吴老师建议我接下这个提案，为 Linux Kernl 贡献一些代码。

我直到 11 月才将负责人改为自己，之后又有一些事情耽搁了。

11 月 23 日，收到了泰晓社区设计的开发板。

12 月 1 日，也就是今天，收到了 CNRV 寄来的荔枝派开发板。

再加上泰晓社区的哪吒 D1 开发板，可以有多个板子用于测试 RealTime Linux。

从 12 月开始，要开始把一些成果记录下来。

我们先在 QEMU 上运行一下打上 RT Patch 的 Linux 内核，之后再在真实开发板上测试。

## 测试环境

本次实验是在 [Linux Lab](https://gitee.com/tinylab/linux-lab) 的 riscv64/virt 虚拟开发板上测试，先来配置一下运行环境。

当然最方便的还是直接使用 [泰晓 Linux 实验盘][001]，已经集成好了 Linux Lab 并下载好了几个 G 的 Linux 内核源代码，免安装，即插即跑。

我使用的主机系统是：Ubuntu 20.04.5 LTS。

### 安装 Cloud Lab

Cloud Lab 依赖 Docker，不过用 Ubuntu 真是超级简单，只要执行下面的命令，会自动安装 Docker。

```
$ git clone https://gitee.com/tinylab/cloud-lab.git
$ cd cloud-lab
$ tools/docker/run linux-lab
```

不过，我们可能会遇到一个小问题：

> Without logout or reboot, please issue 'newgrp docker' as a temp solution.

解决起来也很简单：

```
$ newgrp docker
$ tools/docker/run linux-lab
```

## 下载 Patch

Linux Lab 运行起来了，接下来我们要下载 Patch。

我们要下载 2 组 patchset：

1. 基于官方 Linux Kernel 版本的 RT 主线 Patch
2. 在 RT 主线 Patch 基础上开发的 RISC-V PREEMPT_RT Patch，还没有合并进 RT 主线

Linux Lab 的 `riscv64/virt` 虚拟开发版默认已经支持 Linux v6.0.7，我们直接基于这个版本来打 Patch 开展实验即可。

### 下载 Patches

在 Linux Lab 里面打 Patch 很简单，先把 Patches 放到 `src/patch/linux/v6.0/` 目录下。

首先下载 RT 主线 Patch，参照 [PREEMPT_RT patch versions 指南][003] 就好了：

```
$ cd src/patch/linux/v6.0/
$ wget -c https://cdn.kernel.org/pub/linux/kernel/projects/rt/6.0/older/patch-6.0-rt11.patch.gz
$ gzip -d patch-6.0-rt11.patch.gz
$ ls patch-6.0-rt11.patch
patch-6.0-rt11.patch
```

这样就会生成 patch-6.0-rt11.patch 的 Patch 文件。

接着下载为 RISC-V 开发的 PREEMPT_RT Patch。

这里我们需要先安装一个 `b4` 工具帮助我们下载 Patch。

```
$ sudo apt update -y && \
    sudo apt install -y python3-pip && \
    sudo pip install b4 && \
    b4 am 20220831175920.2806-1-jszhang@kernel.org
```

![b4](/wp-content/uploads/2022/03/riscv-linux/images/riscv-rtl/b4.png)

下载完了以后，为了确保依次打上 RT 主线 Patch 和 RISC-V RT Patch，建议给两笔 patch 加个序号：

```
$ mv patch-6.0-rt11.patch 0.patch-6.0-rt11.patch
$ mv v2_20220901_jszhang_riscv_add_preempt_rt_support.mbx 1.v2_20220901_jszhang_riscv_add_preempt_rt_support.mbx
```

## 开展 Real Time Linux 实验

### 准备开发板

首先，配置开发板，我们选择 `riscv64/virt`。

```
$ make BOARD=riscv64/virt
```

### 配置 Linux 内核版本

接着配置 Kernel 版本为 v6.0.7。

要使用最新的 v6.0.7，需要更新 Linux Lab 仓库和相应的 BSP 仓库。当然，我们也可以从临近的 v5.17 复制一份出来。

```
$ make kernel-clone LINUX=v5.17 LINUX_NEW=v6.0.7
$ make local-config LINUX=v6.0.7
```

之后，请确保 Linux Kernel 源代码仓库是干净的：

```
$ make kernel-cleanup
$ make kernel-cleanall
```

### 打上 RT Patches

接下来，打补丁。可以直接使用 `make kernel-patch`：

```
$ make kernel-patch
```

### 配置使能 PREEMPT_RT

补丁打完后，我们还要启用 `PREEMPT_RT`。

```
$ make kernel-menuconfig
$ make kernel-saveconfig
```

![preempt_rt](/wp-content/uploads/2022/03/riscv-linux/images/riscv-rtl/preempt_rt.png)

### 编译新内核

之后，就可以编译打上 PREEMPT_RT 补丁的 v6.0.7 内核了。

```
$ make kernel
```

### 运行新内核

最后，启动虚拟开发板。

```
$ make boot
```

### 测试验证

这里检测一下 Kernel 版本，再看一下当前 Kernel 的 `.config` 配置。

```
Welcome to Linux Lab
linux-lab login: root
# uname -a
Linux linux-lab 6.0.7-rt11-dirty #1 SMP PREEMPT_RT Thu Dec 1 22:58:12 CST 2022 riscv64 GNU/Linux
# zcat /proc/config.gz | grep PREEMPT
CONFIG_HAVE_PREEMPT_LAZY=y
CONFIG_PREEMPT_LAZY=y
# CONFIG_PREEMPT_NONE is not set
# CONFIG_PREEMPT_VOLUNTARY is not set
# CONFIG_PREEMPT is not set
CONFIG_PREEMPT_RT=y
CONFIG_PREEMPT_COUNT=y
CONFIG_PREEMPTION=y
CONFIG_PREEMPT_RCU=y
CONFIG_DEBUG_PREEMPT=y
CONFIG_PREEMPTIRQ_TRACEPOINTS=y
CONFIG_TRACE_PREEMPT_TOGGLE=y
CONFIG_PREEMPT_TRACER=y
# CONFIG_PREEMPTIRQ_DELAY_TEST is not set
```

可以看到确实有 `PREEMPT_RT` 配置项，说明 Patch 打成功了。

## 总结

通过本文的实验，我们在 QEMU 上成功运行并简单验证了 RISC-V Linux 的 PREEMPT_RT 补丁。

接下来，为了更准确地验证应用 PREEMPT_RT 补丁后的系统实时性数据，我们将在真实开发板上打补丁，并使用 `cyclictest` 等专门的测试工具来进行实时性测试，敬请期待！

## 推荐资料

1. [Linux Lab Disk / Linux Lab 真盘][001]
2. [【老师提案】RISC-V RealTime 分析、优化与 CPU 设计建议][002]
3. [PREEMPT_RT patch versions][003]
4. [[PATCH v2 0/5] riscv: add PREEMPT_RT support][004]

[001]: https://tinylab.org/linux-lab-disk
[002]: https://gitee.com/tinylab/riscv-linux/issues/I5ENMI
[003]: https://wiki.linuxfoundation.org/realtime/preempt_rt_versions
[004]: https://lore.kernel.org/linux-riscv/ea5cdba4-7a79-56b3-f8d7-7785569dedd6@microchip.com/T/#t
