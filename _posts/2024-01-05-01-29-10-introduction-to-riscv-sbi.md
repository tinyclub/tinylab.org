---
layout: post
author: 'Groot'
title: 'RISC-V SBI 概述'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /introduction-to-riscv-sbi/
description: 'RISC-V SBI 概述'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [spaces tables autocorrect]
> Author:    groot <gr00t@foxmail.com>
> Date:      2023/06/12
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V Linux 内核 SBI 调用技术分析](https://gitee.com/tinylab/riscv-linux/issues/I64YC4)
> Sponsor:   PLCT Lab, ISCAS


## 前言

当今计算机体系结构中，RISC-V 架构无疑成为了备受关注的新星，在国内外的学界和工业领域都有着广泛的应用与研究。而其中的 Supervisor Binary Interface (SBI) 作为 RISC-V 执行环境接口（Execute Environment Interface, EEI）之一，为 RISC-V 架构在操作系统内核等方面的应用提供了重要的技术支持。

本文首先介绍了 SBI 的概念、作用和实现方法，重点分析了在 OpenSBI 的事件调用过程和 Linux 下层 SBI Implementation 如果进行交互。旨在帮助读者理解 SBI 在 RISC-V 架构中的重要地位及其中的实现细节，提高 RISC-V 应用开发者的技术水平和实践能力。

## 软件版本信息

| 软件    | 版本     |
|---------|----------|
| Linux   | v6.4-rc5 |
| Opensbi | v1.2     |
| QEMU    | 8.0.2    |

## RISCV-V SBI

### 什么是 SBI？

SBI 全称 Supervisor Binary Interface，是 RISC-V 执行环境接口（Execute Environment Interface, EEI）之一，目的是使处于 Supervisor-mode (S-mode 或者 VS-mode) 的程序能够很方便地移植到实现不同扩展指令集的 RISC-V 架构的处理器上。提供 SBI 接口给监管模式软件的更高特权软件被称为 SBI 实现或监管执行环境（Supervisor Execution Environment, SEE）。

### 为什么要有 SBI

![sbi](/wp-content/uploads/2022/03/riscv-linux/images/introduction-to-riscv-sbi/sbi1.svg)

如果没有 SBI（如上图右侧），针对实现的扩展指令集不同的 RISC-V 微架构，可能要采用不同的方式才能够使操作系统内核触发 M-mode 的动作。而有了 SBI 之后，只要在扩展指令集不同的 RISC-V 微架构中实现统一的向上的 SBI 接口，上层的操作系统就可以不再关注具体的微架构细节，而是专注实现 SBI 接口提供的功能即可，大大提升了处于 Supervisor-mode 的程序的可移植性。
这其实就是计算机中的一个很重要的哲学——抽象。通过将底层的具体实现屏蔽，向上提供统一的接口，使上层应用不需关注过多底层细节，大大简化了程序的开发难度。
通俗地，我们将 SBI 比作手机充电器接口。曾经市场上可能有非常多种类的充电器接口，如果 A 的手机接口和 B 的手机接口不一样，那么他们没办法互相使用对方的充电器，但是如果我们将充电器接口全部统一为 type-c 接口，这种尴尬的场景就不会再发生了，大大的方便了用户。

### SBI 的作用

![sbi2](/wp-content/uploads/2022/03/riscv-linux/images/introduction-to-riscv-sbi/sbi2.svg)

SBI 的第一个作用我们开头已经讲过了（图一左）。
除此之外，如上图所示，SBI 也可能在 Hypervisor-mode（HS-mode）下作为虚拟机管理程序实现。
从更高一级的特权模式来看，SBI Implementation 为 supervisor-mode 软件分配物理执行单元（HARTs）。
因此，从 SBI Implementation 的角度来看，S-mode 的 HART 被称为虚拟 HART（图一）。而如果实现是一个虚拟机管理程序（图二），那么虚拟 HART 则表示 VS-mode 的虚拟 HART。

### SBI Spec

#### 如何获取 SBI Spec

SBI Specification 由 RISC-V 基金会发布，每更新一个版本基金会就会更新 GitHub 仓库，下面附上该仓库链接，进入仓库后开发者即可获取最新的 SBI Specification。

**[riscv-sbi-doc][001]**

目前来看，SBI Specification 的发布周期并不固定，不过基本能够保持一年以内更新一个稳定版本。每次要更新新的版本之前，基金会都会推出 rc (Release Candidate) 版本，开发者可以与基金会联系提出自己的意见和建议，最终形成稳定版本。

#### SBI 版本变更概览

下面对 SBI 的历史版本变更做一个总结：

##### Version 2.0-rc1

- 添加了共享内存物理地址范围参数的通用描述
- 添加了 SBI 调试控制台扩展 (debug console extension)
- 放宽了 SBI PMU 固件计数器的计数位宽要求
- 在 SBI PMU 扩展中添加了 sbi_pmu_counter_fw_read_hi() 函数
- 为 SBI 实现特定的 firmware events 保留了空间
- 添加了 SBI 系统暂停扩展 (system suspend extension)
- 添加了 SBI CPPC 扩展 (CPPC extension)
- 明确了只有定义发现已实现的 SBI 函数机制的 SBI 扩展才能部分实现的规定
- 添加了错误代码 SBI_ERR_NO_SHMEM
- 添加了 SBI 嵌套加速扩展 (nested acceleration extension)
- 添加了虚拟 HART 的通用描述
- 添加了 SBI 偷取时间核算扩展 (steal-time accounting extension)
- 添加了 SBI PMU 快照扩展 (PMU snapshot extension)

##### Version 1.0

- 改进了 SBI 文档 Introduction 部分
- 删除了所有对 RV32 的引用
- 更新了调用规约
- 添加了一个缩写词表

##### Version 0.3

- 改进文档样式和命名规范
- 增加了 SBI 系统重置扩展 (system reset extension)
- 改进了 SBI 文档 Introduction 部分
- 改进了 SBI hart 状态管理扩展（hart state management extension）的文档说明
- 添加了 SBI hart 状态管理扩展（hart state management extension）的暂停（suspend）功能
- 添加了性能监控单元扩展 (performance monitoring unit extension)
- 定义了 SBI 扩展不能部分实现的规定

##### Version 0.2

- 完整的 SBI v0.1 已经被移至遗留扩展，现在成为可选扩展。从技术上讲，这是一项向后不兼容的更改，因为遗留扩展变为了可选选项

注：总结日期截至到 2023/06/15，Version 2.0 还未正式发布。

#### SBI 版本对应扩展

| 扩展、版本             | 0.2 | 0.3 | 1.0 | 2.0-rc1 |
|-----------------------|-----|-----|-----|---------|
| Legacy                | √   | √   | √   | √       |
| Base                  |     | √   | √   | √       |
| Timer                 |     | √   | √   | √       |
| IPI                   |     | √   | √   | √       |
| RFENCE                |     | √   | √   | √       |
| HSM                   |     | √   | √   | √       |
| System Reset          |     | √   | √   | √       |
| PMU                   |     | √   | √   | √       |
| Debug Console         |     |     |     | √       |
| System Suspend        |     |     |     | √       |
| CPPC                  |     |     |     | √       |
| Steal-time Accounting |     |     |     | √       |
| Nested Acceleration   |     |     |     | √       |
| Experimental          |     | √   | √   | √       |
| Vendor-Specific       |     | √   | √   | √       |
| Firmware Specific     |     | √   | √   | √       |

### SBI Implementations

理论上说，因为 SBI Spec 是开源的，只要能够按照 Spec 说明实现其功能就可以称为 SBI Implementation。
不过当前经过 RISC-V 官方认证的 Implementation 有如下几个：

| Implementation ID | Name                       |    Update    |
|-------------------|----------------------------|:------------:|
| 0                 | Berkeley Boot Loader (BBL) | Nov 1, 2020  |
| 1                 | OpenSBI                    | Jun 14, 2023 |
| 2                 | Xvisor                     | Dec 23, 2022 |
| 3                 | KVM                        | Apr 21, 2023 |
| 4                 | RustSBI                    | May 23, 2023 |
| 5                 | Diosix                     | May 8, 2021  |
| 6                 | Coffer                     | Mar 3, 2022  |
| 7                 | Xen Project                |              |

注：Xen Project 仅在 SBI Impelementation 中申请了占位，目前并没有实际支持

## OpenSBI 固件代码分析

### 什么是 OpenSBI

OpenSBI 是 RISC-V SBI Spec 的一个 C 语言参考实现。它由 Western Digital 公司发起，并且在 2019 年开放了源代码。

### 编译 OpenSBI

> 这里已经默认用户安装好 QEMU 和 U-Boot，如果遇到困难，请参考泰晓社区的相关文档：[https://tinylab.org/riscv-linux](https://tinylab.org/riscv-linux)

1. 下载 OpenSBI 源码

```sh
git clone https://github.com/riscv-software-src/opensbi.git
```

2. 进入 OpenSBI 文件夹

```sh
cd opensbi
```

3. 新建文件夹并进入

```sh
mkdir build
cd build
```

3. 编译

```sh
make -C $(pwd)/.. PLATFORM=generic CROSS_COMPILE=riscv64-Linux-gnu- FW_PAYLOAD_PATH=path/to/u-boot.bin
```

### 启动 OpenSBI

1. 在 `qemu-opensbi` 文件夹中执行下面的命令

```sh
qemu-system-riscv64 -M virt -m 256 -nographic -bios build/platform/generic/firmware/fw_payload.elf
```

2. 显示输出

![alt img](/wp-content/uploads/2022/03/riscv-linux/images/introduction-to-riscv-sbi/img.png)

此时，OpenSBI 成功启动，并且引导进了 U-Boot。

### OpenSBI 源码分析

我们以一个 Base Extension 中获取硬件厂商 ID 信息的函数 `sbi_get_mvendorid()` 为例，分析它被调用的过程。

#### OpenSBI 异常处理程序

首先是异常处理程序的入口定义，也就是 `mtvec` 的设置，下面的代码将 `mtvec` 设置为 `_trap_handler`：

```
// opensbi/firmware/fw_base.S: 493

/* Setup trap handler */
lla	a4, _trap_handler
csrw	CSR_MTVEC, a4
```

这样就设置好了异常处理程序入口，如果在系统的执行过程中遇见了异常、中断或系统调用，硬件会自动找到 `_trap_handler` 所在的地址：

```
// opensbi/firmware/fw_base.S: 765

_trap_handler:
	TRAP_SAVE_AND_SETUP_SP_T0

	TRAP_SAVE_MEPC_MSTATUS 0

	TRAP_SAVE_GENERAL_REGS_EXCEPT_SP_T0

	TRAP_CALL_C_ROUTINE

_trap_exit:
	TRAP_RESTORE_GENERAL_REGS_EXCEPT_A0_T0

	TRAP_RESTORE_MEPC_MSTATUS 0

	TRAP_RESTORE_A0_T0

	mret
```

`TRAP_CALL_C_ROUTINE` 之前和之后的宏是状态保存与恢复，`TRAP_CALL_C_ROUTINE` 是真正的异常处理程序。

```
// opensbi/firmware/fw_base.S: 702

.macro	TRAP_CALL_C_ROUTINE
	/* Call C routine */
	add	a0, sp, zero
	call	sbi_trap_handler
.endm
```

然后我们发现最终调用了 `sbi_trap_handler` 函数处理异常。

#### OpenSBI ecall 过程分析

书接上段，进入 `sbi_trap_handler()` 之后，找到里面关于处理 `ecall` 指令的部分：

```c
// opensbi/lib/sbi/sbi_trap.c: 303

case CAUSE_SUPERVISOR_ECALL:
case CAUSE_MACHINE_ECALL:
	rc  = sbi_ecall_handler(regs);
	msg = "ecall handler failed";
	break;
```

然后进入 `sbi_trap_handler()`，其中的 `sbi_ecall_find_extension()` 会检查该扩展是否被支持，如果被支持就调用之前注册好的回调函数进行处理，如果不被支持返回 `SBI_ENOTSUPP` (SBI_ERR_NOT_SUPPORTED)。

```c
// opensbi/lib/sbi/sbi_ecall.c: 108

	ext = sbi_ecall_find_extension(extension_id);
	if (ext && ext->handle) {
		ret = ext->handle(extension_id, func_id,
				  regs, &out_val, &trap);
		if (extension_id >= SBI_EXT_0_1_SET_TIMER &&
		    extension_id <= SBI_EXT_0_1_SHUTDOWN)
			is_0_1_spec = 1;
	} else {
		ret = SBI_ENOTSUPP;
	}
```

#### OpenSBI 扩展初始化简要分析

在 fw_xxx.S 中，会调用 `sbi_init` 进行 OpenSBI 的初始化：

```
// opensbi/firmware/fw_base.S: 519

    /* Initialize SBI runtime */
    call  sbi_init
```

之后进入 `lib/sbi/sbi_init.c` 的 `sbi_init` () 函数进行一系列检查后开始初始化各个扩展：

```c
// opensbi/lib/sbi/sbi_init.c: 264

    rc = sbi_xxx_init(scratch, true);
	if (rc) {
		sbi_printf("%s: xxx init failed (error %d)\n",
			   __func__, rc);
		sbi_hart_hang();
	}
```

最后向 `sbi_ecall_exts` 列表中注册各个扩展，完成初始化。

通过该函数的一系列操作，成功初始化 OpenSBI 之后，我们就可以调用 OpenSBI 提供的函数了。

#### OpenSBI 事件调用过程

现在我们假设 Linux Kernel 向 OpenSBI 发送了一个 `ecall` 指令，该指令的 `ext` 为 `sbi_get_mvendorid()` 所在扩展的 id，也就是 `0x10`。这时 OpenSBI 自动跳入异常处理程序，之后的处理过程前面已经讲解过了，这里不再赘述。

我们这里来讲讲之后的事情，在 `ret = ext->handle(extension_id, func_id,regs, &out_val, &trap);` 的过程中，会调用对应 ext 和 fid 的函数，我们这里是 `lib/sbi/sbi_ecall_base.c` 中的 `sbi_ecall_base_handler`：

```c
// opensbi/lib/sbi/sbi_ecall_base.c: 56

case SBI_EXT_BASE_GET_MVENDORID:
	*out_val = csr_read(CSR_MVENDORID);
	break;
```

直接读取 Machine Information Registers 中的值，得到 `mvendorid`。

整个处理流程结束，逐级向上返回结果，然后由 `a1` 寄存器带回 `mvendorid`。

### OpenSBI 如何兼容不同 SBI 版本

SBI Spec 的设计中贯彻了 RISC-V 的设计哲学——模块化扩展：

1. SBI Implementation 向 S-mode 提供的事件以 SBI 扩展为基本单位，如果想在 SBI Implementation 中实现某个事件，就必须实现该服务所在扩展的所有事件。
2. 与 RISC-V Spec 一样，如果一个新的 SBI Spec 正式版本发布，那么该版本中定义的新扩展将会固定下来，不可以再进行更改。

因为每一版 OpenSBI 都会实现 SBI Spec 中所规定的所有扩展，也就是说新版的 OpenSBI 一定会兼容之前版本的 OpenSBI。

同时 OpenSBI 会在 include 文件中定义支持的扩展与事件：

```c
// opensbi/include/sbi/sbi_ecall_interface.h: 15

/* SBI Extension IDs */
#define SBI_EXT_0_1_SET_TIMER			0x0
#define SBI_EXT_0_1_CONSOLE_PUTCHAR		0x1
#define SBI_EXT_0_1_CONSOLE_GETCHAR		0x2
#define SBI_EXT_0_1_CLEAR_IPI			0x3
#define SBI_EXT_0_1_SEND_IPI			0x4
#define SBI_EXT_0_1_REMOTE_FENCE_I		0x5
#define SBI_EXT_0_1_REMOTE_SFENCE_VMA		0x6
#define SBI_EXT_0_1_REMOTE_SFENCE_VMA_ASID	0x7
#define SBI_EXT_0_1_SHUTDOWN			0x8
#define SBI_EXT_BASE				0x10
#define SBI_EXT_TIME				0x54494D45
#define SBI_EXT_IPI				0x735049
#define SBI_EXT_RFENCE				0x52464E43
#define SBI_EXT_HSM				0x48534D
#define SBI_EXT_SRST				0x53525354
#define SBI_EXT_PMU				0x504D55
#define SBI_EXT_DBCN				0x4442434E
#define SBI_EXT_SUSP				0x53555350
#define SBI_EXT_CPPC				0x43505043

/* SBI function IDs for BASE extension */
#define SBI_EXT_BASE_GET_SPEC_VERSION		0x0
#define SBI_EXT_BASE_GET_IMP_ID			0x1
#define SBI_EXT_BASE_GET_IMP_VERSION		0x2
#define SBI_EXT_BASE_PROBE_EXT			0x3
#define SBI_EXT_BASE_GET_MVENDORID		0x4
#define SBI_EXT_BASE_GET_MARCHID		0x5
#define SBI_EXT_BASE_GET_MIMPID			0x6

/* SBI function IDs for TIME extension */
#define SBI_EXT_TIME_SET_TIMER			0x0

/* SBI function IDs for IPI extension */
#define SBI_EXT_IPI_SEND_IPI			0x0

/* SBI function IDs for RFENCE extension */
#define SBI_EXT_RFENCE_REMOTE_FENCE_I		0x0
#define SBI_EXT_RFENCE_REMOTE_SFENCE_VMA	0x1
#define SBI_EXT_RFENCE_REMOTE_SFENCE_VMA_ASID	0x2
#define SBI_EXT_RFENCE_REMOTE_HFENCE_GVMA_VMID	0x3
#define SBI_EXT_RFENCE_REMOTE_HFENCE_GVMA	0x4
#define SBI_EXT_RFENCE_REMOTE_HFENCE_VVMA_ASID	0x5
#define SBI_EXT_RFENCE_REMOTE_HFENCE_VVMA	0x6

/* SBI function IDs for HSM extension */
#define SBI_EXT_HSM_HART_START			0x0
#define SBI_EXT_HSM_HART_STOP			0x1
#define SBI_EXT_HSM_HART_GET_STATUS		0x2
#define SBI_EXT_HSM_HART_SUSPEND		0x3

#define SBI_HSM_STATE_STARTED			0x0
#define SBI_HSM_STATE_STOPPED			0x1
#define SBI_HSM_STATE_START_PENDING		0x2
#define SBI_HSM_STATE_STOP_PENDING		0x3
#define SBI_HSM_STATE_SUSPENDED			0x4
#define SBI_HSM_STATE_SUSPEND_PENDING		0x5
#define SBI_HSM_STATE_RESUME_PENDING		0x6

#define SBI_HSM_SUSP_BASE_MASK			0x7fffffff
#define SBI_HSM_SUSP_NON_RET_BIT		0x80000000
#define SBI_HSM_SUSP_PLAT_BASE			0x10000000

#define SBI_HSM_SUSPEND_RET_DEFAULT		0x00000000
#define SBI_HSM_SUSPEND_RET_PLATFORM		SBI_HSM_SUSP_PLAT_BASE
#define SBI_HSM_SUSPEND_RET_LAST		SBI_HSM_SUSP_BASE_MASK
#define SBI_HSM_SUSPEND_NON_RET_DEFAULT		SBI_HSM_SUSP_NON_RET_BIT
#define SBI_HSM_SUSPEND_NON_RET_PLATFORM	(SBI_HSM_SUSP_NON_RET_BIT | \
						 SBI_HSM_SUSP_PLAT_BASE)
#define SBI_HSM_SUSPEND_NON_RET_LAST		(SBI_HSM_SUSP_NON_RET_BIT | \
						 SBI_HSM_SUSP_BASE_MASK)

/* SBI function IDs for SRST extension */
#define SBI_EXT_SRST_RESET			0x0

#define SBI_SRST_RESET_TYPE_SHUTDOWN		0x0
#define SBI_SRST_RESET_TYPE_COLD_REBOOT	0x1
#define SBI_SRST_RESET_TYPE_WARM_REBOOT	0x2
#define SBI_SRST_RESET_TYPE_LAST	SBI_SRST_RESET_TYPE_WARM_REBOOT

#define SBI_SRST_RESET_REASON_NONE	0x0
#define SBI_SRST_RESET_REASON_SYSFAIL	0x1

/* SBI function IDs for PMU extension */
#define SBI_EXT_PMU_NUM_COUNTERS	0x0
#define SBI_EXT_PMU_COUNTER_GET_INFO	0x1
#define SBI_EXT_PMU_COUNTER_CFG_MATCH	0x2
#define SBI_EXT_PMU_COUNTER_START	0x3
#define SBI_EXT_PMU_COUNTER_STOP	0x4
#define SBI_EXT_PMU_COUNTER_FW_READ	0x5
#define SBI_EXT_PMU_COUNTER_FW_READ_HI	0x6
```

如果不被支持，OpenSBI 会返回该扩展不被支持的错误代码，告诉上层该扩展不被支持。

## Linux Kernel SBI 代码分析

下面分析 Linux (v6.4-rc5) 源码中的 SBI 代码：

### ecall 指令

`ecall` 指令用于向执行环境发出请求，在不同的特权等级中执行 `ecall` 指令有不同的效果：在 User-mode 中会引发 environment-call-from-U-mode 异常，在 Supervisor-mode 中会引发 environment-call-from-S-mode 异常，而在 Machine-mode 中会引发 environment-call-from-M-mode 异常。

### Linux 内核 SBI 代码

`ecall` 指令在 Linux 内核中用于 SBI 调用，如下为 `arch/riscv/kernel/sbi.c` 中的部分代码。
`sbi_ecall` 指令接受 8 个参数，分别是

- `ext`: SBI extension ID (EID)
- `fid`: SBI function ID (FID)
- `arg0-arg5`: SBI 函数调用参数

```c
// linux/arch/riscv/kernel/sbi.c: 25

struct sbiret sbi_ecall(int ext, int fid, unsigned long arg0,
			unsigned long arg1, unsigned long arg2,
			unsigned long arg3, unsigned long arg4,
			unsigned long arg5)
{
	struct sbiret ret;

	register uintptr_t a0 asm ("a0") = (uintptr_t)(arg0);
	register uintptr_t a1 asm ("a1") = (uintptr_t)(arg1);
	register uintptr_t a2 asm ("a2") = (uintptr_t)(arg2);
	register uintptr_t a3 asm ("a3") = (uintptr_t)(arg3);
	register uintptr_t a4 asm ("a4") = (uintptr_t)(arg4);
	register uintptr_t a5 asm ("a5") = (uintptr_t)(arg5);
	register uintptr_t a6 asm ("a6") = (uintptr_t)(fid);
	register uintptr_t a7 asm ("a7") = (uintptr_t)(ext);
	asm volatile ("ecall"
		      : "+r" (a0), "+r" (a1)
		      : "r" (a2), "r" (a3), "r" (a4), "r" (a5), "r" (a6), "r" (a7)
		      : "memory");
	ret.error = a0;
	ret.value = a1;

	return ret;
}
```

下面对上述代码做简单分析：

- 使用 `ecall` 指令时，将异常类型写在 a7 寄存器，参数写在 a0-a5 寄存器，后面会根据异常类型的不同调用不同的异常处理函数
- `register` 关键字表明后面的变量直接存储在寄存器中
- `asm ("ax")` 表明将后面的变量与 `ax` 寄存器进行绑定
- `asm volatile` 表明嵌入汇编代码进入 C 代码中，并且将 `a0` 和 `a1` 寄存器既作为输入寄存器又作为输出寄存器传给 `ecall` 指令，而 `a2` - `a6` 寄存器作为输入寄存器传递给 `ecall`
- `ecall` 函数返回两个值 `a0` 和 `a1`，`sbi_ecall` 函数将这两个值作为错误和返回值传递给调用它的函数

比如实现一个 putchar 函数用于打印一个字符到系统控制台上，就通过如下 `sbi_ecall` 调用来实现：

```c
// linux/arch/riscv/kernel/sbi.c: 101

void sbi_console_putchar(int ch)
{
	sbi_ecall(SBI_EXT_0_1_CONSOLE_PUTCHAR, 0, ch, 0, 0, 0, 0, 0);
}
```

然后我们进入 `arch/riscv/include/sbi.h`，观察宏定义：

```c
// linux/arch/riscv/include/asm/sbi.h: 14

enum sbi_ext_id {
#ifdef CONFIG_RISCV_SBI_V01
	SBI_EXT_0_1_SET_TIMER = 0x0,
	SBI_EXT_0_1_CONSOLE_PUTCHAR = 0x1,
	SBI_EXT_0_1_CONSOLE_GETCHAR = 0x2,
	SBI_EXT_0_1_CLEAR_IPI = 0x3,
	SBI_EXT_0_1_SEND_IPI = 0x4,
	SBI_EXT_0_1_REMOTE_FENCE_I = 0x5,
	SBI_EXT_0_1_REMOTE_SFENCE_VMA = 0x6,
	SBI_EXT_0_1_REMOTE_SFENCE_VMA_ASID = 0x7,
	SBI_EXT_0_1_SHUTDOWN = 0x8,
#endif
	SBI_EXT_BASE = 0x10,
	SBI_EXT_TIME = 0x54494D45,
	SBI_EXT_IPI = 0x735049,
	SBI_EXT_RFENCE = 0x52464E43,
	SBI_EXT_HSM = 0x48534D,
	SBI_EXT_SRST = 0x53525354,
	SBI_EXT_PMU = 0x504D55,

	/* Experimentals extensions must lie within this range */
	SBI_EXT_EXPERIMENTAL_START = 0x08000000,
	SBI_EXT_EXPERIMENTAL_END = 0x08FFFFFF,

	/* Vendor extensions must lie within this range */
	SBI_EXT_VENDOR_START = 0x09000000,
	SBI_EXT_VENDOR_END = 0x09FFFFFF,
};

```

观察到 `SBI_EXT_0_1_CONSOLE_PUTCHAR` 定义为 `0x1`。

### Linux 如何兼容不同的 SBI 版本

Linux 系统目前的默认 SBI 版本为 0.1，如果当前的 SBI 版本为 0.1，将执行 `arch/riscv/kernel/sbi.c` 中的

```c
// linux/arch/riscv/kernel/sbi.c: 101

#ifdef CONFIG_RISCV_SBI_V01

// 如果支持 SBI 0.1，下面的函数可以被调用
...
void sbi_console_putchar(int ch)
{
	sbi_ecall(SBI_EXT_0_1_CONSOLE_PUTCHAR, 0, ch, 0, 0, 0, 0, 0);
}
...
...
#else

// 如果 SBI 0.1 不被支持，返回 remote fence extension is not available in SBI x.x
...
static void __sbi_set_timer_v01(uint64_t stime_value)
{
	pr_warn("Timer extension is not available in SBI v%lu.%lu\n",
		sbi_major_version(), sbi_minor_version());
}
...
...
#endif /* CONFIG_RISCV_SBI_V01 */
```

如果支持更新版本的 SBI，`#endif` 下面的代码将可以被执行，比如：

```c
// linux/arch/riscv/kernel/sbi.c: 222

static void __sbi_set_timer_v02(uint64_t stime_value)
{
#if __riscv_xlen == 32
	sbi_ecall(SBI_EXT_TIME, SBI_EXT_TIME_SET_TIMER, stime_value,
		  stime_value >> 32, 0, 0, 0, 0);
#else
	sbi_ecall(SBI_EXT_TIME, SBI_EXT_TIME_SET_TIMER, stime_value, 0,
		  0, 0, 0, 0);
#endif
}
```

借这个 `#ifdef` 和 `#endif` 两个宏，Linux 实现了对 0.1 和 0.2 两个版本的 SBI 支持。

## Linux 与 OpenSBI 互动流程

我们将以 `sbi_console_putchar` 为例，简要描述 Linux 与 OpenSBI 的互动流程，方便读者对 SBI 形成更直观的理解。

![sbi3](/wp-content/uploads/2022/03/riscv-linux/images/introduction-to-riscv-sbi/sbi3.svg)

假设我们现在使用 C 语言 `printf()` 函数为例，给读者讲解一下 Linux 系统与 OpenSBI 的交互过程：

首先，我们调用了 `printf()` 函数 (**①**)，自然而然我们陷入了内核态，然后 Linux Kernel 去调用 OpenSBI 提供的 `sbi_ecall()` 函数 (**②**)，并且在调用过程中将 eid, fid 以及之前提到的 5 个参数传递给 OpenSBI (**③**)，之后由 OpenSBI 去真正的操作硬件。

最后操作完成之后，一级一级地向上返回执行结果 (**④ ⑤**)，完成整个向 console 进行输出的过程。

## 小结

这篇文章介绍了 RISC-V 架构下的 SBI（Supervisor Binary Interface）概念、作用和实现方法，并提供了开源实现 OpenSBI 的编译和启动方法。SBI 的作用是使处于 supervisor-mode 的程序能够方便地移植到不同的 RISC-V 微架构处理器上，实现了底层统一接口的抽象，使开发者不需关注底层细节，大大简化了程序的开发难度。此外，文章还分析了在 Linux Kernel 中，SBI 的调用方法，这些对于理解 SBI 与 Linux Kernel 的交互过程非常有帮助。

本文简洁明了地讲述了 SBI 的概念，提高了读者对于 SBI 的理解，为 SBI 的学习提供了指导。

## 参考资料

- [Volume 1, Unprivileged Specification version 20191213][004]
- [Volume 2, Privileged Specification version 20211203][003]
- [RISC-V Supervisor Binary Interface Specification Version -v2.0-rc1, 2023-06-01: Draft][002]

[001]: https://github.com/riscv-non-isa/riscv-sbi-doc
[002]: https://github.com/riscv-non-isa/riscv-sbi-doc/releases/download/v2.0-rc1/riscv-sbi.pdf
[003]: https://github.com/riscv/riscv-isa-manual/releases/download/Priv-v1.12/riscv-privileged-20211203.pdf
[004]: https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf
