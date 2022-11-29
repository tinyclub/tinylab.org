---
layout: post
author: 'yjmstr'
title: 'QEMU 启动方式分析（4）: OpenSBI 固件分析与 SBI 规范的 HSM 扩展'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /opensbi-firmware-and-sbi-hsm/
description: 'QEMU 启动方式分析（4）: OpenSBI 固件分析与 SBI 规范的 HSM 扩展'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector:   [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [pangu epw]
> Author:      YJMSTR <pyjmstr@gmail.com>
> Date:        2022/10/05
> Revisor:     Bin Meng, Falcon
> Project:     [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Environment: Ubuntu22.04 LTS
> Sponsor:     PLCT Lab, ISCAS


## 前言

在 [上一篇文章][1] 中，我们结合 QEMU 代码分析了 QEMU RISC-V 'virt' 机器是如何从 ZSBL 阶段跳转到下一阶段，其中有 OpenSBI firmware 的加载和传递。本文将进一步分析 OpenSBI 各类固件的不同，以及 SBI 规范的 HSM 扩展。

本文使用的软件版本如下：

- QEMU: v7.0.0
- OpenSBI: v1.1

## RISC-V 特权架构简介

RISC-V 定义了三种特权模式：

- Machine Mode：机器模式，简称 M 模式，对应特权等级 3。这是 RISC-V 中 hart（hardware thread，硬件线程）可以执行的最高权限模式。
- Supervisor Mode：监管者模式，简称 S 模式，对应特权等级 1。这是一种可选的权限模式，它的权限比 U 模式更高，但是比 M 模式低。S 模式下运行的软件不能使用 M 模式的 CSR（Control and State Register，控制和状态寄存器） 和 M 模式下的指令，并且受到 PMP（Physical Memory Protection，物理内存保护）的限制，只能访问 M 模式指定该模式可访问的内存地址。
- User Mode：用户模式，简称 U 模式，对应特权等级 0。与 S 模式一样，该模式下的程序不能执行更高特权等级的指令和访问 CSR，并且同样受到 PMP 的限制。

此外还定义了保留的特权等级 2，在 H 扩展中会将 S 模式扩展为 HS 模式（Hypervisor-Extended Supervisor mode）。

RISC-V 启动路径上的各个部分运行在不同的模式下：ROM，Loader 和 Runtime 运行在 M 模式，Bootloader 和通用 OS（例如 Linux）运行在 S 模式，而启动通用 OS 后运行的软件位于 U 模式，硬件可以根据需求实现不同的特权模式组合。如下表所示：

| 实现的特权等级数 | 支持的模式 | 预期用途                   |
| ---------------- | ---------- | -------------------------- |
| 1                | M          | 简单嵌入式系统             |
| 2                | M,U        | 安全嵌入式系统             |
| 3                | M,S,U      | 运行类 Unix 操作系统的系统 |

## SBI 与 OpenSBI

SBI 指 Supervisor Binary Interface，监管者二进制接口，它由一个小核心模块和一组可选的扩展模块构成：

1. 平台特定的运行在 M 模式的固件和 S 或 HS 模式下的引导加载器、管理程序或通用操作系统之间的接口。
2. 运行在 HS 模式的监管者程序和运行在 VS 模式下的引导加载器、通用操作系统之间的接口。

SBI 提供了一系列接口，以支持在 S 模式下通过 `ecall` 指令执行一些需要更高权限的操作。有关 SBI 的更详细介绍可以参考 [官方文档][4]。

OpenSBI 是由西数公司开发的 SBI 实现，旨在为上述情况 1 提供 RISC-V SBI 的一个可参考的开源实现，其可以被扩展以适应特定的硬件配置。OpenSBI 运行在 M 模式，因为其固件需要直接访问硬件。

有关 OpenSBI 的更具体介绍可以参考其 [官方文档][2]。而 OpenSBI 的上手流程可以参考泰晓科技社区 [之前的文章][5]。

## OpenSBI 固件

OpenSBI 为不同的平台提供了不同的固件，用于处理不同平台间早期引导阶段的差异。所有的固件都会执行相同的平台硬件初始化过程，而它们之间的区别在于早期引导阶段传递参数的方式，以及如何执行下一引导阶段。

上一引导阶段将会通过 RISC-V CPU 的如下寄存器传递信息：

- 通过 a0 寄存器传递硬件线程 id (mhartid)
- 通过 a1 寄存器传递设备树文件（device tree blob）在内存中的地址，该地址必须按 8 字节对齐。

OpenSBI 目前支持三种类型的固件，分别是：

- FW_PAYLOAD
- FW_JUMP
- FW_DYNAMIC

以上类型的固件全都可以在编译时可以在 `make` 命令行或平台的 config.mk 配置文件来配置如下选项：

- FW_TEXT_ADDR：必选参数，用于指定 OpenSBI 固件的执行地址。
- FW_FDT_PATH：要嵌入到固件的 `.rodata` 字段的外部扁平设备树的地址。如果没有提供这一选项，固件会认为 FDT 地址将由上一引导阶段通过参数传递进来。
- FW_FDT_PADDING：可选参数，对 FW_FDT_PATH 选项指定的 FDT 二进制文件进行零字节填充。
- FW_PIC：当 FW_PIC=y 时，将生成位置无关的固件映像。此时 OpenSBI 将在其被加载的地址上直接运行。这一选项要求支持 PIE 的工具链，且该选项是默认开启的。

其中，FW_PIC 选项的默认开启导致了 QEMU 'virt' 平台下使用 U-Boot SPL 与 OpenSBI 无法正确加载 Linux Kernel，目前 Bin Meng 老师已向官方社区提交 [patch][14]。

### FW_PAYLOAD

![fw_payload](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/fw_payload.png)

该类型的固件直接包含了下一引导阶段的二进制代码，被包含的代码称为 "payload"。payload 通常是 bootloader 或操作系统内核。这种固件允许用户重写设备树文件（DTB）。当上一引导阶段没有传递扁平设备树文件（FDT 文件）时，它可以在最终固件的 `.rodata` 字段中嵌入 FDT。

FW_PAYLOAD 类型的固件在编译时可以通过 make 命令或 config.mk 配置如下参数：

- FW_PAYLOAD_OFFSET：payload 在最终的 FW_PAYLOAD 二进制映像文件中的地址与 FW_TEXT_BASE 的偏移值。当 FW_PAYLOAD_ALIGN 参数未定义时，该参数是必须的。
- FW_PAYLOAD_ALIGN：地址对齐约束。payload 会在最终的 FW_PAYLOAD 二进制映像文件中，被链接到固件二进制代码的末尾。如果同时指定了 FW_PAYLOAD_ALIGN 参数和 FW_PAYLOAD_OFFSET 参数，FW_PAYLOAD_ALIGN 参数将被忽略。
- FW_PAYLOAD_PATH：下一阶段二进制映像文件的路径。如果没有指定这一参数，OpenSBI 将自动提供一个用于测试的简单 payload，该 payload 将在平台终端中打印一条信息后执行 `while(1)` 死循环。
- FW_PAYLOAD_FDT_ADDR：可以是上一引导阶段传递过来的扁平设备树（FDT）的地址，也可以由 FW_FDT_PATH 参数指定并要嵌入到 `.rodata` 字段的扁平设备树（FDT）在下一引导阶段之前的地址。

在 QEMU RISC-V 'virt' 平台上使用时，若要引导除 OpenSBI 提供的测试用 payload 之外的其它 payload，需要在编译 OpenSBI 时通过 `make` 命令行的 `FW_PAYLOAD_PATH` 选项指定 payload 的路径，以 U-Boot 为例：

```shell
$ export CROSS_COMPILE=riscv64-linux-gnu-
$ make PLATFORM=generic FW_PAYLOAD_PATH=<uboot_build_directory>/u-boot.bin
```

随后通过 QEMU 的 `-bios` 选项指定编译出的 `fw_payload.elf` 或 `fw_payload.bin` 文件路径即可。

### FW_JUMP

![fw_jump](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/fw_jump.png)

该类型的固件会跳转到给定的地址。与 fw_payload 不同的是，其不包含下一引导阶段的二进制代码。该类型固件曾经是 QEMU RISC-V 'virt' 平台的默认固件。

FW_JUMP 类型的固件在编译时可以通过 make 命令或 config.mk 文件配置如下特有的选项：

- FW_JUMP_ADDR：在 OpenSBI 固件之后执行的下一引导阶段的入口地址。这一地址一般与下一引导阶段被加载到的地址一致。这是一个必选的参数。
- FW_JUMP_FDT_ADDR：上一引导阶段传递过来的扁平设备树（FDT）在执行下一引导阶段前要被放在内存中的位置。如果没有提供这个参数，OpenSBI 固件将会直接把 FDT 当前的地址传递给下一引导阶段。

在 QEMU RISC-V 'virt' 平台上使用时，需要先在 QEMU 启动命令中通过 `-bios` 选项指定 FW_JUMP 类型的固件，并通过 `-kernel` 选项指定要加载的 bootloader 或操作系统内核。以 U-Boot 为例，使用如下命令启动 QEMU：

```shell
$ qemu-system-riscv64 -M virt -nographic \
	-bios <opensbi_build_directory>/build/platform/generic/firmware/fw_jump.bin \
	-kernel <uboot_build_directory>/u-boot.bin
```

此外，还需要确保 FW_JUMP_FDT_ADDR 设定的地址足够高，以免覆盖了内核在内存中的位置。

### FW_DYNAMIC

![fw_dynamic](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/fw_dynamic.png)

该类型的固件会在 Runtime 阶段从上一引导阶段获得下一引导阶段的入口，下一阶段通常是 Bootloader 或操作系统内核。目前，此类固件是 QEMU 的默认固件。

在 [上一篇文章][1] 中我们已经知道，RISC-V 'virt' 平台在上一引导阶段创建 `struct fw_dynamic_info` 这一结构体，并将其在内存中的地址通过 RISC-V CPU 的 a2 寄存器传递给 FW_DYNAMIC。由于该类型固件所需的信息能够通过这一结构体传递，其并没有特有的编译时配置选项。`struct fw_dynamic_info` 如下所示：

```C
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

可以看到，其中显式指定了下一引导阶段的地址与模式，以及 OpenSBI 选项等信息。并且该结构体含有版本信息，以便于向后兼容。

在 QEMU RISC-V 'virt' 平台上，若用户没有指定 QEMU 的 `-bios` 参数，QEMU 将会自动加载其自带的 FW_DYNAMIC 类型固件。32 位平台和 64 位平台下的 QEMU 默认固件分别是 `opensbi-riscv32-generic-fw_dynamic.bin` 与 `opensbi-riscv64-generic-fw_dynamic.bin`。

此外，在 QEMU RISC-V 'virt' 上运行 U-Boot SPL 时，U-Boot 本体和 OpenSBI 的 FW_DYNAMIC 固件会被绑定为 FIT 映像（Flattened Image Tree，扁平映像树）以供 U-Boot SPL 使用，需要在编译时指定 `OPENSBI` 环境变量为编译出的 FW_DYNAMIC 固件的路径，或是将该固件复制到 U-Boot 目录下。

### 比较与分析

- FW_PAYLOAD 类型的固件将下一阶段的二进制文件和固件进行打包，适用于上一引导阶段无法同时加载 OpenSBI 和 Runtime 的下一引导阶段的情况。

- FW_JUMP 类型的固件能够跳转到下一阶段的入口，但是需要在编译 FW_JUMP 类型的固件时知晓下一引导阶段（U-Boot，内核和 FDT）要加载到什么地址，其适用于上一引导阶段能够同时加载 Runtime 的下一引导阶段和 OpenSBI 固件的情况。

- FW_DYNAMIC 类型的固件能够从上一引导阶段获得 Runtime 的下一引导阶段的入口。其与 FW_JUMP 类型固件一样，适用于上一引导阶段能够加载 OpenSBI 固件和 Runtime 的下一引导阶段的情况，但不需要在编译固件时指定下一引导阶段的入口地址。与此同时，其通过 `struct fw_dynamic_info` 结构体向 fw_base 提供信息。

QEMU RISC-V 'virt' 平台先前使用 OpenSBI 的 FW_JUMP 固件作为默认固件，其在编译时需要指定后续阶段（FDT 和内核映像）的地址，这使得内核映像的大小受到 FDT 地址和内存大小的限制。

现在上述平台已将默认的 OpenSBI 固件更换为了 FW_DYNAMIC。相比于 FW_JUMP，FW_DYNAMIC 类型的固件允许由 loader 指定下一引导阶段的地址，并且可以向后续引导阶段传递信息。对于 U-Boot 来说，是 SPL 通过 FIT 里的信息填好下一阶段的信息。

引入对 FW_DYNAMIC 类型固件的支持还不会打破对另外两种固件的支持，因为另外两种固件并不通过 a2 寄存器传递信息。

## SBI 的 HSM 扩展

HSM 是指 Hart State Management Extension，硬件线程（hart）状态管理扩展。它引入了一组 hart 状态和一组 S 模式软件用于获取和改变 hart 状态的函数。

OpenSBI 曾经强制选择 hart0 进行重定位和早期的初始化工作。在 v0.6 版本中引入了彩票机制（lottery mechanism）。彩票机制会随机选择一个 hart 作为冷启动 hart （coldboot hart），这个 hart 也被称为 boot/main hart。它负责进行每个 hart 的暂存空间 （scratch space） 的初始化并将 OpenSBI 重定位到其链接地址，其它的 hart 被称为热启动 hart（warmboot hart）。

在 U-Boot SPL 中，有一个 main hart 负责让所有其它 harts （secondary harts）先跳转到 OpenSBI，它自己最后跳转。这使得彩票机制总是会选择 secondary harts 中的一个。若 U-Boot SPL 和 OpenSBI 的链接地址范围有重叠，彩票机制可能会在其它 hart 仍运行在上一引导阶段时进行重定位，覆盖其它 hart 的数据，从而导致启动时崩溃（boot-time crash）。

SBI 的 HSM 扩展允许 S 模式软件按照定义好的顺序启动 harts，而不像之前一样只能按随机顺序启动 harts，这使得 S 模式能够支持更多的 CPU 功能。譬如现在在 `struct fw_dynamic_info` 结构体中可以指定选择哪一个 hart 作为 boot hart （即上文提到的 main hart），并让 boot hart 最后一个跳转到下一引导阶段，从而避免启动时崩溃。

这里与其它体系架构的多核引导流程做个简单对比：以 ARM 为例，Bootloader 会判断当前是否为 CPU0，如果不是，则会执行 `wfe` 指令进行等待，否则继续进行初始化操作。ARM 的多核启动一般有自旋表（spin-table）和电源状态协作接口（power state coordination interface，PSCI） 两种实现方式。自旋表仅能实现 CPU0 之外的处理器的启动，而 PSCI 与 RISC-V 中的 SBI HSM 类似， 能够实现处理器核的热拔插，挂起等功能。

接着分析 HSM 扩展，所有可能的 hart 状态如下表所示：

| 状态 ID |     状态名      |                                                        描述                                                         |
|:-------:|:---------------:|:-----------------------------------------------------------------------------------------------------------------:|
|    0    |     STARTED     |                                              hart 被物理启动且正常运行                                              |
|    1    |     STOPPED     |    hart 没有在 S 模式或任何更低的特权模式下执行。如果平台有能够关闭 hart 的机制，这可能是因为它被 SBI 的实例关闭了    |
|    2    |  START_PENDING  |        其它 hart 要求从 **STOPPED** 状态继续或启动这个 hart，SBI 实例正在尝试让该 hart 进入 **STARTED** 状态         |
|    3    |  STOP_PENDING   |           该 hart 要求将自己从 **STARTED** 状态停止或关闭，SBI 实例正在尝试让该 hart 进入 **STOPPED** 状态           |
|    4    |    SUSPENDED    |                                      该 hart 处于平台特定的挂起（或低功耗）状态                                       |
|    5    | SUSPEND_PENDING | 该 hart 要求让自己从 **STARTED** 状态进入平台特定的低功耗状态，SBI 实例正在尝试让其进入平台特定的 **SUSPENDED** 状态 |
|    6    | RESUME_PENDING  | 中断或平台特定的硬件事件导致 hart 从 **SUSPENDED** 状态转为正常执行，SBI 实例正在尝试将该 hart 转为 **STARTED** 状态 |

任何时刻 hart 的状态只可能是上表中的某一种。SBI 实现的 hart 状态转移需要遵循以下的状态机：

![hsm_state_machine](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/hsm_state_machine.png)

### SBI HSM 函数

SBI 规范中给出了如下四个函数用于获取和改变 hart 的状态：

#### HART start

```c
struct sbiret sbi_hart_start(unsigned long hartid,
  unsigned long start_addr,
  unsigned long opaque)
```

在 `start_addr` 处以 S 模式执行 `hartid` 所指定的 hart，并在开始执行时将 `opaque` 存入 a1 寄存器。其中 `opaque` 是一个 XLEN 位的值，XLEN 指机器位数。

#### HART stop

```c
struct sbiret sbi_hart_stop(void)
```

停止执行 S 模式下调用该函数的 hart，并将其所有权交还给 SBI 实现。

#### HART get status

```c
struct sbiret sbi_hart_get_status(unsigned long hartid)
```

返回 hartid 指定的 hart 的状态。

#### HART suspend

```c
struct sbiret sbi_hart_suspend(uint32_t suspend_type,
  unsigned long resume_addr,
  unsigned long opaque)
```

要求 SBI 实现将调用该函数的 hart 置于 `suspend_type` 所指定的平台特定挂起（或低功耗）状态，`resume_addr` 是 hart 在挂起结束之后回到 S 模式继续执行的地址，`opaque` 是一个 XLEN 位的值，其会在 hart 结束挂起状态时被放入 a1 寄存器。

### OpenSBI HSM 实现

在 OpenSBI 的 README.md 中，有如下介绍：

> Currently, OpenSBI fully supports SBI specification *v0.2*. OpenSBI also supports Hart State Management (HSM) SBI extension starting from OpenSBI v0.7. HSM extension allows S-mode software to boot all the harts a defined order rather than legacy method of random booting of harts. As a result, many required features such as CPU hotplug, kexec/kdump can also be supported easily in S-mode. HSM extension in OpenSBI is implemented in a non-backward compatible manner to reduce the maintenance burden and avoid confusion. That's why, any S-mode software using OpenSBI will not be able to boot more than 1 hart if HSM extension is not supported in S-mode.
>
> Linux kernel already supports SBI v0.2 and HSM SBI extension starting from **v5.7-rc1**. If you are using an Linux kernel older than **5.7-rc1** or any other S-mode software without HSM SBI extension, you should stick to OpenSBI v0.6 to boot all the harts. For a UP systems, it doesn't matter.
>
> N.B. Any S-mode boot loader (i.e. U-Boot) doesn't need to support HSM extension, as it doesn't need to boot all the harts. The operating system should be capable enough to bring up all other non-booting harts using HSM extension.

大意是：

> 从 v0.7 版本开始，OpenSBI 能够提供 HSM 扩展的支持。而为了减少维护负担和避免混淆，OpenSBI 中的 HSM 扩展是以非向后兼容的方式实现的，因此当 S 模式下不支持 HSM 扩展时，所有使用 OpenSBI 的 S 模式软件不能启动超过 1 个 hart。
>
> Linux 内核也从 v5.7-rc1 版本开始为 SBI 规范 v0.2 版本和 HSM 扩展提供支持。如果你在使用更老版本的 Linux 内核或是其它不支持 SBI 扩展的 S 模式软件，你应该继续使用 v0.6 版本的 OpenSBI 来启动所有的 harts。而对于单逻辑处理器系统来说，这无关紧要。
>
> 注：S 模式下的 Bootloader（例如 U-Boot）不需要为 HSM 扩展提供支持，因为它们不需要启动所有的 harts。操作系统需要有能力使用 HSM 扩展启动所有其它的未启动 harts。


并且，OpenSBI 自 v1.0 版本起开始支持在 RISC-V SBI 规范 v0.3 版本中引入的 HART 挂起（suspend）功能。

在 OpenSBI 的 GitHub 仓库中寻找 v0.7 版本 [新增的 commit][8]，这些 commit 为 OpenSBI 引入了 HSM 扩展，以支持 hart 的热拔插（hotplug），并提供了在 S 模式下以指定顺序启动 hart 的能力。

#### sbi_hsm_init()

![sbi_hsm_init](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/sbi_hsm_init.png)

首先在 `lib/sbi/sbi_hsm.c` 中，OpenSBI 通过 `sbi_hsm_init` 函数进行 HSM 的初始化，该函数的流程图如上所示。若当前为冷启动，该函数会为每个 hart 分配一个 `sbi_hsm_data` 类型的结构体，并设置 hart 的初始状态，当前冷启动所使用的 hart 初始状态会被设为 START_PENDING，其它 hart 的初始状态为 STOPPED；否则调用 `sbi_hsm_hart_wait` 函数，通过 mie 寄存器的 MSIP 和 MEIP 位来设置中断，并通过内联汇编使用 `wfi` 指令进入低功耗等待状态，直到该 hart 的状态变为 `START_PENDING` 时恢复 mie。该部分实现如下：

```c
	if (cold_boot) {
		hart_data_offset = sbi_scratch_alloc_offset(sizeof(*hdata));
		if (!hart_data_offset)
			return SBI_ENOMEM;

		/* Initialize hart state data for every hart */
		for (i = 0; i <= sbi_scratch_last_hartid(); i++) {
			rscratch = sbi_hartid_to_scratch(i);
			if (!rscratch)
				continue;

			hdata = sbi_scratch_offset_ptr(rscratch,
						       hart_data_offset);
			ATOMIC_INIT(&hdata->state,
				    (i == hartid) ?
				    SBI_HSM_STATE_START_PENDING :
				    SBI_HSM_STATE_STOPPED);
		}
	} else {
		sbi_hsm_hart_wait(scratch, hartid);
	}
```

#### sbi_ecall_hsm_handler()

在 `lib/sbi/sbi_ecall_hsm.c` 中实现了 `sbi_ecall_hsm_handler` 这一函数，并且 `sbi_ecall_extension` 类型结构体 `ecall_hsm` 的 `handle` 函数被设为该函数。该函数根据参数传入的 funcid 来调用对应的 SBI HSM 处理函数。

在调用 `ecall` 指令后，`lib/sbi/sbi_ecall.c` 中的 `sbi_ecall_handler` 函数会根据 a7 寄存器的值判断要进行的操作是否属于某个 SBI 扩展，若是，则会调用该扩展对应的 `sbi_ecall_extension` 的 `handle` 函数进行处理。

`sbi_ecall_hsm_handler` 函数的实现如下：

```c
static int sbi_ecall_hsm_handler(unsigned long extid, unsigned long funcid,
				 const struct sbi_trap_regs *regs,
				 unsigned long *out_val,
				 struct sbi_trap_info *out_trap)
{
	int ret = 0;
	struct sbi_scratch *scratch = sbi_scratch_thishart_ptr();
	ulong smode = (csr_read(CSR_MSTATUS) & MSTATUS_MPP) >>
			MSTATUS_MPP_SHIFT;

	switch (funcid) {
	case SBI_EXT_HSM_HART_START:
		ret = sbi_hsm_hart_start(scratch, sbi_domain_thishart_ptr(),
					 regs->a0, regs->a1, smode, regs->a2);
		break;
	case SBI_EXT_HSM_HART_STOP:
		ret = sbi_hsm_hart_stop(scratch, TRUE);
		break;
	case SBI_EXT_HSM_HART_GET_STATUS:
		ret = sbi_hsm_hart_get_state(sbi_domain_thishart_ptr(),
					     regs->a0);
		break;
	case SBI_EXT_HSM_HART_SUSPEND:
		ret = sbi_hsm_hart_suspend(scratch, regs->a0, regs->a1,
					   smode, regs->a2);
		break;
	default:
		ret = SBI_ENOTSUPP;
	};
	if (ret >= 0) {
		*out_val = ret;
		ret = 0;
	}

	return ret;
}
```

#### sbi_hsm_hart_start()

![sbi_hsm_hart_start](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/sbi_hsm_hart_start.png)

接着来看对应 HSM 函数调用的具体实现，流程图如上所示。在 `lib/sbi/sbi_hsm.c` 中，以 HART start 对应的函数 `sbi_hsm_hart_start` 为例，该函数中首先判断要启动的特权模式是否为 S 模式或 U 模式：

```c
	/* For now, we only allow start mode to be S-mode or U-mode. */
	if (smode != PRV_S && smode != PRV_U)
		return SBI_EINVAL;
```

随后通过如下代码进行 hdata 中 hart 状态的设置：

```c
    hdata = sbi_scratch_offset_ptr(rscratch, hart_data_offset);
    hstate = atomic_cmpxchg(&hdata->state, SBI_HSM_STATE_STOPPED,
                    SBI_HSM_STATE_START_PENDING);
```

其中 `atomic_cmpxchg` 函数最终调用了宏 `__cmpxchg`，进行 hdata 结构体中 state 的切换。`cmpxchg` 实现的功能是比较和交换，`atomic` 前缀表示其为原子操作的一种。`atomic_cmpxchg(ptr, o, n)` 会在 ptr 指向位置上的值与 o 参数值相同时将 n 写入 ptr 指向的位置，并返回 o 的值，值不同时返回 ptr 指向的位置上的值。因此若 hart 已处于 STOPPED 状态，hstate 的值将会变为 SBI_HSM_STATE_STOPPED，否则 HSTATE 的值为 hdata->state 的值。

OpenSBI 会根据 hsate 的值对该 hart 调用 HART start 之前的状态进行判断。若在调用 HART start 时该 hart 不处于 STOPPED 态，OpenSBI 会认为此时的 HART start 为非法请求。根据先前 hart 所处状态的不同，会返回不同的错误类型。

```c
	if (hstate == SBI_HSM_STATE_STARTED)
		return SBI_EALREADY;

	/**
	 * if a hart is already transition to start or stop, another start call
	 * is considered as invalid request.
	 */
	if (hstate != SBI_HSM_STATE_STOPPED)
		return SBI_EINVAL;
```

随后通过 `sbi_init_count` 判断 hartid 对应 hart 的初始化次数，结果存入 init_count 中：

```c
	init_count = sbi_init_count(hartid);
```

从 [这个 commit][11] 开始，OpenSBI 将 HSM 扩展相关的操作实现为一种设备，简化了 HSM 的实现，原先对于平台的 HSM 相关操作改为了对 HSM 设备进行操作。我们可以在 `sbi_hsm_hart_start` 函数中看见如下代码，其中的判断函数都是基于 hsm_dev 这一设备进行判断：

```c
	if (hsm_device_has_hart_hotplug() ||
	   (hsm_device_has_hart_secondary_boot() && !init_count)) {
		return hsm_device_hart_start(hartid, scratch->warmboot_addr);
	} else {
		int rc = sbi_ipi_raw_send(hartid);
		if (rc)
		    return rc;
	}
```

首先判断设备是否支持 hart 的热拔插，或支持 hart 二级启动且没有初始化过；若是，则会通过 `hsm_device_hart_start` 函数来调用设备的 `hart_start` 函数实现状态切换，否则发送 IPI 中断。`hsm_device_hart_start` 的实现如下：

```c
static int hsm_device_hart_start(u32 hartid, ulong saddr)
{
	if (hsm_dev && hsm_dev->hart_start)
		return hsm_dev->hart_start(hartid, saddr);
	return SBI_ENOTSUPP;
}
```

与之类似的函数还有 `hsm_device_hart_suspend` 等，OpenSBI 通过这些函数判断设备是否实现了上述的 HSM 函数，并进行调用。

## 总结

本文简要介绍了 RISC-V 中的特权架构，OpenSBI v1.1 中三种固件的参数、功能和优缺点，并以 HSM 扩展中的 HART start 函数为例介绍了 SBI 规范的 HSM 扩展在 OpenSBI 中的实现。

FW_DYNAMIC 类型的固件相比 FW_JUMP 局限性更少，且引入该类型固件不会影响 FW_JUMP 与 FW_PAYLOAD 的正常使用，目前已经取代了 FW_JUMP 成为了 QEMU RISC-V 'virt' 平台的默认选择。

SBI HSM 扩展的引入使得 S 模式能够对 hart 的状态进行管理，能够以指定的顺序启动多个 harts，而不是以随机顺序启动。

OpenSBI 在对 HSM 函数进行调用时提供了一些判断来过滤非法调用，并能够根据情况返回对应的错误类型。

## 参考资料

- [QEMU 启动方式分析（3）: QEMU 代码与 RISCV 'virt' 平台 ZSBL 分析][1]
- [OpenSBI 仓库][2]
- [RISC-V OpenSBI Deep Dive][3]
- [RISC-V SBI 文档][4]
- [OpenSBI 快速上手][5]
- [RISC-V 特权模式][6]
- [QEMU commit message: riscv: Add opensbi firmware dynamic support][7]
- [OpenSBI v0.6 与 v0.7 差异][8]
- [OpenSBI commit message: lib: Implement hart hotplug][9]
- [riscv asm cmpxchg 实现解析][10]
- [OpenSBI commit message: lib: sbi: Simplify HSM platform operations][11]
- [U-Boot commit message: spl: opensbi: specify main hart as preferred boot hart][12]
- [一文玩转ARM64 SMP多核启动（二）-　PSCI（超级详细~） - 知乎 (zhihu.com)][13]
- [[PATCH\] riscv: qemu: spl: Fix booting Linux kernel with OpenSBI 1.0+ (mail-archive.com)][14]

[1]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220911-qemu-riscv-zsbl.md
[2]: https://github.com/riscv-software-src/opensbi/
[3]: https://riscv.org/wp-content/uploads/2019/06/13.30-RISCV_OpenSBI_Deep_Dive_v5.pdf
[4]: https://github.com/riscv-non-isa/riscv-sbi-doc
[5]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220505-riscv-opensbi-quickstart.md
[6]: https://ithelp.ithome.com.tw/articles/10289289
[7]: https://gitlab.com/qemu-project/qemu/-/commit/dc144fe13d336caac2f03b57f1df738e84f984ec
[8]: https://github.com/riscv-software-src/opensbi/compare/v0.6...v0.7
[9]: https://github.com/riscv-software-src/opensbi/commit/b677a9b8d641f1c16a4f8f52e00019a9bc747893
[10]: https://zhuanlan.zhihu.com/p/404761561
[11]: https://github.com/riscv-software-src/opensbi/commit/a84a1ddbbabb2389b5af91473250d0aff90e40d7

[12]: https://source.denx.de/u-boot/u-boot/-/commit/b86f6d1e649f237849297b5ec6b5566b7a92b2b4
[13]: https://zhuanlan.zhihu.com/p/501397835
[14]: https://www.mail-archive.com/u-boot@lists.denx.de/msg453580.html