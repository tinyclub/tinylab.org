---
layout: post
author: 'unknown'
title: 'RISC-V 中断子系统分析——中断优先级'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-irq-analysis-part4-interrupt-priority/
description: 'RISC-V 中断子系统分析——中断优先级'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc1 - [header]
> Author:   牛工 - 通天塔 985400330@qq.com
> Date:     2022/07/12
> Revisor:  Falcon <falcon@ruma.tech>; iOSDevLog <iosdevlog@iosdevlog.com>
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [Linux IRQ 子系统分析](https://gitee.com/tinylab/riscv-linux/issues/I5E5EP)
> Sponsor:  PLCT Lab, ISCAS


## 前言

之前三篇文章从硬件的触发，汇编处理，中断控制器 PLIC 处理讲述了一个中断的处理流程。

* [RISC-V 中断子系统分析——硬件及其初始化][002]
* [RISC-V 中断子系统分析——PLIC 中断处理][003]
* [RISC-V 中断子系统分析——CPU 中断处理][004]

了解完中断的处理流程后，本文再讲述一下 CPU 的中断优先级是怎么实现的。

在开始讲实现中断优先级之前，先搞清楚中断优先级的概念（引自 [中断优先级_百度百科 (baidu.com)][001]）：

> 1. 有可能出现两个或两个以上中断源同时发出中断请求的情况。多个中断源同时请求中断时，CPU 必须先确定为哪一个中断源服务，要能辨别优先级最高的中断源并进行响应。
> 2. CPU 在处理中断时也要能响应更高级别的中断申请，而屏蔽掉同级或较低级的中断申请。

本文还是先从单片机的中断优先级的实现来讲，然后再拓展到 CPU 的中断优先级的实现。

## 51 单片机中断优先级的实现

51 单片机通过寄存器可以配置 4 个中断优先级，在相同优先级的情况下，由终端查询次序决定哪个中断被优先响应。

### 单片机中断优先级配置表

下表列出了中断查询次序及中断优先级（参考 STC89C51 芯片手册）。

| 中断源  | 中断向量地址 | 相同优先级内查询次序 | 中断优先级设置（IPH,IP） |
| :-----: | :----------: | :------------------: | :----------------------: |
|  INT0   |    0003H     |      0(highest)      |         PX0H,PX0         |
| Timer 0 |    000BH     |          1           |         PT0H,PT0         |
|  INT1   |    0013H     |          2           |         PX1H,PX1         |
| Timer 1 |    001BH     |          3           |         PT1H,PT1         |
|  UART   |    0023H     |          4           |          PSH,PS          |
| Timer2  |    002BH     |          5           |         PT2H,PT2         |
|  INT2   |    0033H     |          6           |         PX2H,PX2         |
|  INT3   |    003BH     |      7(lowest)       |         PX3H,PX3         |

中断优先级最低为 0，最高为 3，IPH 与 IP 两个位组成优先级 0~3。

单片机的中断优先级实现比较简单，下面分析一下在 RISC-V 下的中断优先级配置。

## RISC-V CPU 中断优先级

### CPU 中断优先级

以下内容引自 [Volume II, Privileged Architecture. 20211203][005]。

> The machine-level interrupt registers handle a few root interrupt sources which are assigned a fixed service priority for simplicity, while separate external interrupt controllers can implement a more complex prioritization scheme over a much larger set of interrupts that are then muxed into the machine-level interrupt sources.

这些机器级的中断寄存器处理了一些根中断源，为了简单起见，这些中断被分配了固定的中断复位优先级。外部中断控制器可以基于中断组，实现复杂的中断优先级方案，混合这些中断源之后输入到 CPU 中。

多个中断在 M 模式下同时产生时，会按照以下顺序递减优先级：MEI, MSI, MTI, SEI, SSI, STI。

下图是 6 种中断的中断标志寄存器 mip 和中断使能寄存器 mie。

![image-20220726220846925](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220726220846925.png)

各个位代表的中断如下表所示：

| 寄存器位 | 含义                 |
| -------- | -------------------- |
| MEI      | 机器模式外部中断     |
| SEI      | 监管者模式外部中断   |
| MTI      | 机器模式定时器中断   |
| STI      | 监管者模式定时器中断 |
| MSI      | 机器模式软中断       |
| SSI      | 监管者模式软中断     |

以下引自 [Volume II, Privileged Architecture. 20211203][005] 第 34 页。

> **高级别的特权模式中断** 一定比 **低级别特权模式中断** 优先级高。
>
> mip 和 mie 寄存器 15:0 是标准的寄存器中断，在 16 位及以上的平台特定的机器级中断源具有平台特定的优先级，但是通常选择最高的服务优先级来支持非常快的本地中断向量。
>
> 外部中断在内部（定时器/软件）中断之前处理，因为产生的外部中断的设备，通常需要较少的中断服务次数。
>
> 软件中断在内部定时器中断之前处理，因为内部定时器中断通常用于时间片，其中时间精度不太重要，而软件中断用于处理器间消息传递。当需要高精度定时器时，可以避免软中断，或者将高精度定时器的中断路由到其他路径上，来保证高精度定时器的准确。软件中断位于 mip 的最低四位，因为这些位经常被软件写入，并且该位置允许使用单个五位立即数的 CSR 指令进行读写。

以上是在寄存器级别的分析。

## 小结

本文分析了 51 单片机和 RISC-V CPU 核的中断优先级，两者在中断优先级方面有相同之处，都是固定优先级的，但是 RISC-V 在片上还会有中断控制器，进一步的拓展对外部中断优先级的控制，能够进行一些中断优先级的自定义。本次关于中断的部分先分析到这里，RISC-V 还有很多坑待填，后续再根据工作内容继续分析中断相关的实现。

## 参考资料

* [articles/20220519-riscv-irq-analysis.md · 泰晓科技/RISCV-Linux - Gitee.com][002]
* [如何分析 Linux 内核 RISC-V 架构相关代码][008]
* [Volume I, Unprivileged Spec v. 20191213][006]
* [RISC-V-Reader-Chinese-v2p1][007]
* [Volume II, Privileged Architecture. 20211203][005]
* [STC89C51RC-RD.pdf (stcmcudata.com)][009]

[001]: https://baike.baidu.com/item/中断优先级/8474282
[002]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220519-riscv-irq-analysis.md
[003]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220626-riscv-irq-analysis-part2-Interrupt-handling-plic.md
[004]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220712-riscv-irq-analysis-part3-Interrupt-handling-cpu.md
[005]: https://github.com/riscv/riscv-isa-manual/releases/download/Priv-v1.12/riscv-privileged-20211203.pdf
[006]: https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf
[007]: https://max.book118.com/html/2022/0412/7105025163004111.shtm
[008]: https://tinylab.org/riscv-linux-quickstart/
[009]: http://www.stcmcudata.com/datasheet/stc/STC-AD-PDF/STC89C51RC-RD.pdf
