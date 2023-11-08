---
layout: post
author: '张炀杰'
title: 'RISC-V 当前指令集扩展类别与检测方式'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-isa-extensions-discovery-1/
description: 'RISC-V 当前指令集扩展类别与检测方式'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [epw]
> Author:    YJMSTR [jay1273062855@outlook.com](https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:jay1273062855@outlook.com)<br>
> Date:      2023/07/15
> Revisor:   Bin Meng, Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   ISCAS


## 前言

本文为【调研并总结 RISC-V 处理器扩展的最新软硬件支持方案】系列的第一篇文章，将简要介绍 RISC-V ISA，以及 Spec 中目前描述的对 RISC-V 扩展的检测与硬件支持方式。后续文章中将进一步对 GCC、QEMU、SBI、Linux 内核等软件对 RISC-V 扩展的检测与支持方式进行详细分析。

## RISC-V ISA 概述

RISC-V 指令集架构（ISA, instruction set architecture）及其规范由 RISC-V 国际技术工作组（RISC-V International Technical Working Groups）中的 RISC-V 国际贡献成员（RISC-V International contributing members）进行开发，审核和维护。

计算机体系结构的传统实现方法是增量 ISA，即新处理器不仅必须实现新的 ISA 扩展，还必须实现过去的所有扩展。而 RISC-V 不同，RISC-V 的指令集是模块化的，每个 RISC-V 设备的指令集由必须包含的基础整数 ISA 模块加上其它可选的 ISA 扩展模块构成。

## 扩展类别

基础整数 ISA 通常是 RV32I 或 RV64I，分别对应 32/64 位的通用寄存器位宽与地址空间，但指令长度均为 32 位，并且均包含 32 个通用寄存器。

撰写本文时，ratified 状态的最新 spec 版本是：

- Volume 1, Unprivileged Specification version 20191213
- Volume 2, Privileged Specification version 20211203

Spec 中包含的指令集模块文档可能有 Draft, Frozen 和 Ratified 三种状态。Draft 表示该文档可能还会有较大的更改，Frozen 表示该文档在变为 Ratified 之前应该不会有较大的更改，Ratified 表示该文档已经确定，不再更改。

卷 1 非特权级规范中包括以下指令集模块：

![isa-in-spec-1.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv-isa-extensions/isa-in-spec-1.png)

卷 2 特权级指令规范中包括以下指令集模块：

![isa-in-spec-2.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv-isa-extensions/isa-in-spec-2.png)

RISC-V 的官方网站上给出了目前 ratified 但还未合入最新已发布版本 spec 中的扩展的列表：https://wiki.riscv.org/display/HOME/Recently+Ratified+Extensions

RISC-V 指令集扩展可以分为标准指令集扩展与非标准指令集扩展。其中标准指令集扩展包含非特权级扩展，标准 supervisor-level ISA, 标准 hypervisor-level ISA 与标准 machine-level ISA。

- 标准扩展之间互相不冲突
- 非标准扩展可能与其它的扩展冲突

## 扩展命名约定

在非特权级 ISA Spec 中定义了 RISC-V 扩展的命名约定如下：

- ISA 名称字符串是大小写敏感的
- 支持的 ISA 字符串必须以基础整数指令集对应的字符串（RV32I, RV32E, RV64I, RV128I）作为前缀
- 标准 ISA 扩展用单个字母命名，例如 M 对应整数乘除法指令集扩展
- 任一 RISC-V 指令集扩展组合可以用基础整数指令集对应的字符串作为前缀，按照特定顺序拼接上表示扩展的字符串构成，例如 "RV64IMAFD"，对这一顺序的具体描述见后文
- 此外定义了字母 G 表示 "IMAFDZicsr_Zifencei" 这些基本指令集和扩展的组合
- 一些 ISA 扩展可能依赖于其它扩展，这意味着某些表示扩展组合的字符串是等价的：例如 "D" 双精度浮点扩展依赖于 "F" 单精度浮点扩展，而 "F" 扩展又依赖于 "Zicsr" 扩展，因此 "RV32ID","RV32IFD" 与 "RV32IFDZicsr" 三者所表示的指令集等价
- 指令集可能会不断改变，每个指令集模块可以在名字后面跟上一个表示版本号的字符串，版本号由 major 号和 minor 号两部分组成，用 "p" 字符隔开。如果 minor 号为 0，那么 "p0" 可以从版本号中省略。Major 号改变意味着该版本失去了一部分向后兼容性，而仅有 minor 号不同的版本必须保证向后兼容
- 可以在表示指令集的字符串中加入下划线 "_" 以便阅读
- 标准指令集扩展还可以用 "Z" 开头的字符串加上版本号表示，例如 "Zicsr"。"Z" 后面的第一个字母习惯上用于表示与该扩展最密切相关的字母扩展类别。一个特例是标准 machine-level 指令集扩展同样是用 "Z" 开头字符串表示，但它们以 "Zxm" 三个字母作为前缀
- 当有多个 "Z" 打头的扩展（不包括 "Zxm" 前缀的扩展）同时在指令集字符串中出现时，它们首先按照 "Z" 之后的字符在指令集字符串中的顺序进行排序，随后按照该字符之后子串的字典序进行排序
- 多字母扩展之间必须加上 "_" 进行分隔
- 标准 supervisor-level 的指令集扩展以 "S" 字符作为前缀，后接字母名称和版本号（可选）
- 多个 "S" 打头扩展同时在指令集字符串中出现时，需要按照字典序排序
- 标准 supervisor-level 指令集扩展出现在指令集字符串中表示非特权级 ISA 的字符串之后
- 标准 hypervisor-level 指令集扩展与 supervisor-level 的指令集扩展命名规则类似，区别是开头的字母变为了 "H"，在指令集字符串中应该出现在更低特权等级指令集对应子串之后，多个标准 hypervisor-level 指令集扩展按照字典序排序
- 标准 machine-level 指令集扩展由三个字符 "Zxm" 作为前缀，在指令集字符串中应该出现在更低特权等级指令集对应子串之后，多个标准 machine-level 指令集扩展按照字典序排序
- 非标准扩展用 "X" 开头，后跟字母名称和可选的版本号。非标准扩展在指令集字符串中必须出现在所有标准扩展之后，多个非标准扩展按字典序排序

Spec 中给出了一张图对指令集扩展进行总结：

![isa-naming-convention.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv-isa-extensions/isa-naming-convention.png)

上图还规定了标准指令集模块对应字符串在指令集字符串中的出现顺序，按照从上往下的顺序进行排序，表格中越上方的指令集模块越先出现在指令集字符串中。

## RISC-V 扩展的硬件检测方式

### misa

RISC-V 定义了一个 Machine-Level 的 CSR，名为 `misa`，用于标识当前 hart 所支持的 ISA。该 CSR 是 WARL (Write Any Values, Read Legal Values) 的，在所有 RISC-V 实现中该寄存器必须是可读的，可以通过返回 0 作为读取结果来表示 `misa` 暂未实现，这种情况下需要有其它非标准的机制来确定 CPU 兼容哪些扩展。

`misa` 的字段结构如下图所示：

![misa.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv-isa-extensions/misa.png)

`misa` 的高 2 位是 MXL(Machine XLEN) 字段，用于标识这个设备所实现的基本整数指令集的最大位宽，即 M 模式下的有效地址空间位数与寄存器位宽，MXLEN。当 `misa` 值非 0，MXL 的值与支持的最大 XLEN 的关系如下表所示：

![MXL.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv-isa-extensions/MXL.png)

Extensions 字段用于编码标准扩展，每一位对应字母表中的一个字母所对应的扩展，从第 0 位开始分别对应扩展 "A" 到扩展 "Z"。其中 "I" 留给 RV32I，RV64I，RV128I 基本整数指令集，"E" 留给 RV32E。如果支持 U 模式或 S 模式，`misa` 中对应 "U" 和 "S" 的位会被设置；如果支持任何非标准扩展，那么 "X" 位会被设置。`misa` 中各位与扩展的对应情况如下图所示：

![misa_encoding.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv-isa-extensions/misa_encoding.png)

### 突破 misa 的限制

`misa` 寄存器提供了 M 模式下获得 CPU 所支持指令集扩展的方法，但这样还有两个问题：

- `misa` 的位数有限，无法与现在日益增长的扩展数相匹配，更多的扩展信息需要通过其它手段获得。
- 更低特权模式（如 S/U 模式）无法直接访问 M 模式的 CSR，需要通过执行环境调用 `ecall` 来读取 `misa`。

因此 RISC-V 引入了新的扩展检测机制，PLCT 实验室的郑鈜壬曾就此做过一些[调研工作][007]，总结如下：

- M 模式在 1.12 版本的特权级规范中引入了 mconfigptr 这一 CSR，相关的讨论可以见[基金会邮件列表服务][009]。如果该寄存器非零，那么它的值为配置数据结构（configuration data structure）的地址。这个配置结构的格式由[相应的文档][008]进行规定。目前配置结构使用 ASN.1 JER（ASN.1 值的 JSON 表示）作为人类可读的内容格式编码。配置结构中包含了支持的处理器扩展信息，固件可以使用这个配置结构来生成设备树/SMBIOS/ACPI。

- 对于更低特权级的模式：

  - 嵌入式平台常通过设备树向内核传递信息，这些信息中包括一个 ISA 字符串，启动器或内核需要对字符串进行解析，以获取扩展信息。

  - 服务器或 PC 更常通过 ACPI/SMBIOS 获取设备信息。

关于其它模式软件如何检测并支持 RISC-V 扩展，本系列之后的文章中将会进行更详细的介绍。

## 扩展上下文状态

一些 RISC-V ISA 扩展可能会引入新的 CPU 状态，如新的寄存器等，这使得上下文切换时需要额外保存这些新 CPU 状态，用户模式的程序在进行上下文切换时，需要知晓是否启用了这些扩展，并据此决定是否要保存/恢复对应的上下文。

如果操作系统不知道当前启用了哪些新的用户模式扩展，而用户态线程启用了这些扩展，并向这些扩展引入的新 CPU 状态中存储了信息，操作系统在切换上下文的时候可能就会遗漏这些新 CPU 状态，从而导致出错。

另一个场景是虚拟化，一个 hypervisor 上运行了多个 Guest OSes 的情况。如果 Guest OSes 启用了某些引入新 CPU 状态的扩展，而宿主机意识不到这些新 CPU 状态（如寄存器）时，在 Guest OSes 之间切换时就不会相应地恢复/保存上下文，导致 Guest OSes 之间的隔离性被破坏。

### mstatus：FS，VS 和 XS

RISC-V Spec 中提供了 `mstatus` 这个 CSR，用于标识 M 模式下当前 hart 的状态信息。

`mstatus` CSR 中包括了 FS[1:0] 与 VS[1:0] 这两个 WARL（Write Any, Read Legal）字段，以及 XS[1:0] 这个只读字段。FS 字段用于标识浮点扩展引进的浮点寄存器 f0-f31 以及相关的 CSRs `fcsr`，`frm`，`fflags` 的状态，VS 字段用于标识向量扩展引进的向量寄存器 v0-v31 和 CSRs `vcsr`，`vxrm`，`vxsat`，`vstart`，`vl`，`vtype` 和 `vlenb` 的状态。XS 字段预留给其它用户模式扩展与相关的状态。这些字段的值与对应扩展状态如下图所示：

![fs-vs-xs-encoding.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv-isa-extensions/fs-vs-xs-encoding.png)

这三个字段同样出现在 `sstatus` CSR 中，用于标识 S 模式下 hart 的相应状态。

### Smstateen

同 `misa` CSR 一样，XS 字段也面临着扩展数量日益增长，无法满足需求的问题。为此引入了 [Smstateen 扩展][010]，该扩展为每个特权模式以及 hypervisor extension 各自提供了额外 4 个 CSRs，其中的位用于标识某些扩展是否启用。目前暂时认为为每个特权模式/hypervisor extension 各自分配 CSRs 是足够的。

## 总结

本文简单介绍了 RISC-V ISA，包括命名约定、扩展分类方式、硬件检测机制与额外的支持机制。下一篇文章中我们将介绍 GCC 对 RISC-V 扩展的支持。

## 参考资料

- [RISC-V Spec][001]
- [RISC-V International][002]
- [RISC-V International Technical Working Groups][003]
- [RISC-V Specification Status][004]
- [RISC-V Recently Ratified Extensions][005]
- [RISC-V-Reader-Chinese-v2p1][006]
- [RISC-V 指令集扩展检测机制现状-郑鈜壬][007]
- [RISC-V Configuration Structure][008]
- [ConfigPtr CSR 相关的讨论][009]
- [Smstateen 扩展][010]

[001]: https://riscv.org/technical/specifications/
[002]: https://riscv.org/members/
[003]: https://live-risc-v.pantheonsite.io/technical/technical-forums/
[004]: https://wiki.riscv.org/display/HOME/Specification+Status
[005]: https://wiki.riscv.org/display/HOME/Recently+Ratified+Extensions
[006]: http://www.riscvbook.com/chinese/RISC-V-Reader-Chinese-v2p1.pdf
[007]: https://github.com/plctlab/PLCT-Open-Reports/blob/master/20220706-%E9%83%91%E9%88%9C%E5%A3%AC-discovery.pdf
[008]: https://github.com/riscv/configuration-structure/blob/master/past_work/riscv-configuration-structure-draft.adoc
[009]: https://lists.riscv.org/g/tech-privileged/topic/architecture_extension/83853282?p=,,,20,0,0,0::recentpostdate%2Fsticky,,,20,2,0,83853282
[010]: https://github.com/riscv/riscv-state-enable
