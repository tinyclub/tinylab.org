---
layout: post
author: 'yjmstr'
title: 'RISC-V Linux SMP 技术调研与分析（1）：开机与引导流程中的 SMP'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-smp-in-boot-flow/
description: 'RISC-V Linux SMP 技术调研与分析（1）：开机与引导流程中的 SMP'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - HSM
  - SMP
---

> Corrector:   [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces autocorrect]
> Author:      YJMSTR <pyjmstr@gmail.com>
> Date:        2022/12/12
> Revisor:     Bin Meng, Falcon
> Project:     [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Environment: Ubuntu22.04 LTS
> Sponsor:     PLCT Lab, ISCAS


## 前言

在上次 [视频分享][1] 中，我对引导流程中的 SMP 处理进行了简要介绍。本文在上次视频分享的基础上，进行进一步的总结。

## 简介

### SMP

按照 Flynn 分类法，我们可以将计算机分成如下几类：

- SISD（Single Instruction Single Data，单指令流单数据流）：即常规的单处理器，顺序执行。引入流水线技术后，SISD 架构计算机同样拥有并行处理的能力。
- MISD（Multiple Instruction Single Data，多指令流单数据流）：多个处理器处理多个指令流和单个数据流。目前暂无实例。
- SIMD（Single Instruction Multiple Data，单指令流多数据流）：用单个控制器控制多个处理器执行相同的指令，对一组数据中的每一个执行相同的操作，从而实现空间上的并行。这一结构适用于需要频繁对向量或是数组进行操作的场景。
- MIMD（Multiple Instruction Multiple Data，多指令流多数据流）：多个控制器异步地控制多个处理器。其中采用共享内存方式通信的多处理器系统又可以根据内存组织方式的不同分为：
  - UMA（uniform memory access）：所有处理器共享同样的内存，每个处理器拥有自己的 cache，并且访问内存的时间相同。
  - NUMA（non-uniform memory access）：所有处理器共享同样的内存，但被共享的内存在物理上是分布式的，处理器访问内存的速度取决于内存和处理器的相对位置。
  - COMA（cache-only memory access）：可以视为 NUMA 的一种特例，各个处理器自带的 cache 构成了全部的地址空间。

在 UMA 多核处理器系统中，所有的外设对内存拥有相同的访问能力，若所有的处理器对外设 IO 也拥有相同的访问能力时（比如采用了内存映射 IO 时，所有处理器对内存具有相同的访问能力），这种多核处理器就叫做对称多处理器（SMP，symmetric multiprocessor），否则就为非对称多处理器（AMP，asymmetric multiprocessor）。

### RISC-V 启动流程

![bootflow](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/bootflow.png)

官方的启动流程是如上图所示，其中 LOADER，RUNTIME，BOOTLOADER 阶段的软件组合是 U-Boot SPL + OpenSBI + U-Boot Proper。有关启动流程及这些软件的进一步介绍可以参考 [已有的文章][3]，此处不再赘述。

接下来将按照 ROM->LOADER(U-Boot SPL)->RUNTIME(OpenSBI)->BOOTLOADER(U-Boot Proper)->OS(Linux) 这一流程介绍启动流程中对 SMP 的处理。

### SBI 规范的 HSM 扩展

HSM 指 hart state management。其引入了一系列 hart 状态，并为 S 模式的软件提供了获取和改变 hart 状态的一系列函数。更具体的介绍可以参考 [SBI 规范][4] 和 [视频分享][1] 内容。

## U-Boot SPL 和 OpenSBI 中的 SMP 处理

原先 U-Boot SPL 也是通过彩票机制随机选择一个 hart 作为主 hart，主 hart 负责让其它从 harts（secondary harts）跳转到 OpenSBI，它自己最后跳转。

OpenSBI 的早期版本（< v0.6）强制 hart0 进行重定位和早期的初始化，自 v0.6 开始，引入了彩票机制随机选择一个 hart 进行上述操作。这使得彩票机制可能会直接在 secondary harts 中进行选择，跳转到 OpenSBI 的 secondary harts 可能会在主 hart 仍运行在上一阶段时进行重定位，覆盖主 hart 的数据。

U-Boot SPL 一般与 OpenSBI 的 FW_DYNAMIC 类型固件组合使用，它们之间可以传递一个 `struct fw_dynamic_info` 结构体。

为了解决上述问题，它们随后在 `struct fw_dynamic_info` 结构体中 [引入了 boot_hart 成员][7]，来指定一个 hartid。当 harts 跳转到 FW_DYNAMIC 固件时，它们会通过 wfi 进行等待，直到 hartid 等于 boot_hart 值的 hart 到来并进行重定位。该结构体代码及注释如下所示：

```c
/** Representation dynamic info passed by previous booting stage */
struct fw_dynamic_info {
    /** Info magic */
    target_long magic;
    /** Info version */
    target_long version;
    /** Next booting stage address */
    target_long next_addr;
    /** Next booting stage mode */
    target_long next_mode;
    /** Options for OpenSBI library */
    target_long options;
    /**
     * Preferred boot HART id
     *
     * It is possible that the previous booting stage uses same link
     * address as the FW_DYNAMIC firmware. In this case, the relocation
     * lottery mechanism can potentially overwrite the previous booting
     * stage while other HARTs are still running in the previous booting
     * stage leading to boot-time crash. To avoid this boot-time crash,
     * the previous booting stage can specify last HART that will jump
     * to the FW_DYNAMIC firmware as the preferred boot HART.
     *
     * To avoid specifying a preferred boot HART, the previous booting
     * stage can set it to -1UL which will force the FW_DYNAMIC firmware
     * to use the relocation lottery mechanism.
     */
    target_long boot_hart;
};
```

OpenSBI 中进行相关判断的代码见 [此 commit][8]。

## U-Boot Proper 和 Linux 中的 SMP 处理

U-Boot proper 原先使用 [彩票机制][6]，所有 harts 在跳转到 U-Boot Proper 之后随机选择一个 hart 用于运行 U-Boot proper，挂起其它 harts。

RISC-V Linux 也曾使用彩票机制，但仅有使用 spinwait 方法进行引导的系统必须要有彩票机制。其彩票机制与 U-Boot 使用的类似（事实上，U-Boot 是从 Linux Kernel 中引入的彩票机制，详见 [这个 commit][6]），随机选择一个 main hart 来启动其它 harts。其它 harts 在被启动之前会进入 spin wait loop，直到 main hart 完成这些 hart 的初始化操作之后启动它们。

U-Boot proper 和 Linux 都运行在 S 模式，因此引入了 SBI 规范的 HSM 扩展之后，它们有能力获取和改变 hart 的状态。

在引入 HSM 扩展之后，U-Boot Proper 不再为 SMP 提供支持，所有的 harts 也不再需要都跳转到 U-Boot Proper。U-Boot Proper 只需要主 hart 来运行即可，其它 harts 会在 OpenSBI 中通过 wfi 进行挂起。

主 hart 从 S 模式的 U-Boot Proper 跳转到 S 模式的 Linux 之后，能够通过 HSM 扩展启动其它 harts。

## 总结

在引入 boot_hart 成员和 SBI 规范的 HSM 扩展之前，RISC-V SMP 系统的启动流程每一级之间主 hart 的组合是不确定的，为调试和移植带来了困难。

引入了 boot_hart 成员之后，U-Boot SPL 与 OpenSBI 就不再需要多次使用彩票机制选择主 hart，一次选择出的 main hart 可以传递到下一引导阶段。

引入了 HSM 扩展之后，S 模式的 bootloader 不再需要启动所有的 harts，S 模式的软件能够以固定的顺序启动所有 harts。

## 参考资料

1. [视频分享：RISC-V SBI 规范的 HSM 扩展，暨 SMP 支持优化][1]
2. [知乎文章：谈谈多核处理器][2]
3. [QEMU 启动方式分析（1）：QEMU 及 RISC-V 启动流程简介][3]
4. [riscv-sbi-doc][4]
5. [All Aboard, Part 6: Booting a RISC-V Linux Kernel][5]
6. [u-boot commit: 引入彩票机制][6]
7. [u-boot commit: 引入 boot_hart 成员][7]
8. [OpenSBI commit: 引入 boot hart 成员][8]

[1]: https://www.bilibili.com/video/BV1x24y1k7Xj
[2]: https://zhuanlan.zhihu.com/p/427398869
[3]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220816-introduction-to-qemu-and-riscv-upstream-boot-flow.md
[4]: https://github.com/riscv-non-isa/riscv-sbi-doc
[5]: https://www.sifive.com/blog/all-aboard-part-6-booting-a-risc-v-linux-kernel
[6]: https://source.denx.de/u-boot/u-boot/-/commit/3dea63c8445b25eb3de471410bbafcf54c9f0e9b
[7]: https://source.denx.de/u-boot/u-boot/-/commit/b86f6d1e649f237849297b5ec6b5566b7a92b2b4
[8]: https://github.com/riscv-software-src/opensbi/commit/7a13beb213266cbf6f15ddbbef5bfca274086bd3
