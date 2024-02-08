---
layout: post
author: 'Groot'
title: 'OpenSBI 固件代码分析（五）：最终章'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /sbi-firmware-analyze-5/
description: 'OpenSBI 固件代码分析（五）：最终章'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [urls refs]
> Author:    groot <gr00t@foxmail.com>
> Date:      2023/09/18
> Revisor:   Falcon [falcon@tinylab.org](https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:falcon@tinylab.org)
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V Linux 内核 SBI 调用技术分析](https://gitee.com/tinylab/riscv-linux/issues/I64YC4)
> Sponsor:   PLCT Lab, ISCAS


## 前言

因为怕读者一次性读完可能较难消化，所以前一篇文章并没有完全的分析完 coldboot 的全部流程。在这篇文章中我们将继续之前的探索，将 coldboot 的全部流程讲解完毕，结束对 OpenSBI 固件代码的分析。

这篇文章同上一篇文章一样，暂不将全部代码放在文章中，读者需要自行使用编辑器/IDE 查看代码。

## init_coldboot

### sbi irq 初始化

```c
// lib/sbi/sbi_init.c: 324

	rc = sbi_irqchip_init(scratch, true);
	if (rc) {
		sbi_printf("%s: irqchip init failed (error %d)\n",
			   __func__, rc);
		sbi_hart_hang();
	}
```

该函数是对中断控制器（irqchip）的初始化代码，其中的主要初始化部分是由厂商完成的，这里不进行说明。

如果厂商部分代码未完成初始化，立刻返回错误。如果完成初始化，检查 `ext_irqfn` 和 `default_irqfn` 这两个变量是否相同，如果不同，将特权寄存器 MIE 的 MEIP 位设置为 1，表明 M-mode 的 external interrupts 设置为 interrupt-pending 状态。

### sbi ipi 初始化

```c
// lib/sbi/sbi_init.c: 331

	rc = sbi_ipi_init(scratch, true);
	if (rc) {
		sbi_printf("%s: ipi init failed (error %d)\n", __func__, rc);
		sbi_hart_hang();
	}
```

该函数完成了 RISC-V 处理器的 inter-processor interrupts（核间中断 IPI）初始化工作，这里需要注意的是，单核处理器并不支持该功能。

同之前的一些初始化函数一样，该函数也是先检测是否是 coldboot，给变量 `ipi_data` 分配空间是否成功，如果没有多余的空间分配给 `ipi_data`，则返回一个错误代码。

然后两次调用 `sbi_ipi_envent_create()` 函数，这个函数将会找到数组 `ipi_ops_array[]` 的第一个空闲的位置将对应的中断函数写入进数组的对应位置，并且将函数的返回值也就是中断函数在数组中的下表赋值给 `ipi_smode_ops` 和 `ipi_halt_ops`。

下面的两行代码在给定的 scratch 数据结构中，通过偏移来获取一个指向 ipi_data 结构体的指针，并设置了该结构体的 ipi_type 成员的值为 0x00。后初始化 `ipi_data->ipi_type` 为 0。

和一些与平台相关的初始化相同，调用厂商编写的平台相关的 ipi 初始化函数，完成 ipi 初始化。

最后将特权寄存器 MIE 的 MSIP 位设置为 1，开启软中断。

### sbi tlb 初始化

```c
// lib/sbi/sbi_init.c: 337

	rc = sbi_tlb_init(scratch, true);
	if (rc) {
		sbi_printf("%s: tlb init failed (error %d)\n", __func__, rc);
		sbi_hart_hang();
	}
```

该函数主要是用于初始化 TLB（Translation Lookaside Buffer）管理相关的数据结构和配置。它的主要逻辑如下：

1. 如果是冷启动（cold_boot 为 true），则进行初始化操作，否则执行后续的热启动操作。
2. 冷启动时，函数分配了一些内存空间来存储 TLB 管理相关的数据结构，包括 `tlb_sync`、`tlb_q` 和 `tlb_mem`。
3. `tlb_sync_off`、`tlb_fifo_off` 和 `tlb_fifo_mem_off` 是在 `Scratch Memory` 中的偏移量，用于保存这些据结构的地址。如果内存分配失败，则释放之前已分配的内存并返回错误码 `SBI_ENOMEM`。
4. 函数还创建了一个 IPI 事件（`Interrupt Processing Interface`）并保存其句柄到 `tlb_event`，这个事用于处理 TLB 刷新。
5. 函数从平台获取 TLB 刷新的限制值，并保存到 `tlb_range_flush_limit` 中。
6. 对于热启动，函数会检查之前分配的内存和事件是否存在，如果不存在，则返回错误码 `SBI_ENOMEM` 或 `SBI_ENOSPC`。
7. 最后，函数对初始化后的数据结构进行了一些设置和初始化操作，确保 TLB 管理模块正常运行。

### sbi timer 初始化

```c
// lib/sbi/sbi_init.c: 343

	rc = sbi_tlb_init(scratch, true);
	if (rc) {
		sbi_printf("%s: tlb init failed (error %d)\n", __func__, rc);
		sbi_hart_hang();
	}
```

这段代码用于在 SBI 层面初始化 RISC-V 处理器上的计时器。计时器是一个关键的系统组件，用于跟踪时间和事件，对于操作系统和应用程序的时间管理非常重要。函数根据是否是冷启动来执行不同的初始化步骤，并确保计时器在系统中正常工作。

该段代码和之前的许多函数一样，首先初始化一些变量，这里是指针 `time_delta`，并且获取到平台指针 `plat`。之后就是检查是否为冷启动，如果冷启动就执行下面的操作：

1. 分配一段内存来存储时间差值（time_delta）。
2. 检查处理器是否支持 SBI_HART_EXT_ZICNTR 扩展。这个扩展通常与计时器相关，如果支持，将计时器回调函数（get_time_val）设置为 get_ticks。

非冷启动返回错误代码 `SBI_ENOMEM`。

之后在堆中给 `time_delta` 获取一段空间，并且初始化该值为 0。

无论是冷启动还是非冷启动，最后都会调用 sbi_platform_timer_init 函数来初始化底层硬件平台上的计时器。该函数调用 `timer_init()` 函数，它由厂商提供，这里不再分析。

### sbi domain 完成

```c
// lib/sbi/sbi_init.c: 349
	/*
	 * Note: Finalize domains after HSM initialization so that we
	 * can startup non-root domains.
	 * Note: Finalize domains before HART PMP configuration so
	 * that we use correct domain for configuring PMP.
	 */
	rc = sbi_domain_finalize(scratch, hartid);
	if (rc) {
		sbi_printf("%s: domain finalize failed (error %d)\n",
			   __func__, rc);
		sbi_hart_hang();
	}
```

`sbi_domain_finalize` 用于初始化和启动多个域，每个域都有其自己的配置和启动 HART。这有助于在系统中实现不同的执行上下文隔离和管理。

首先，它调用 `sbi_platform_domains_init` 函数来初始化并为平台配置域。这个函数负责创建和初始化域的数据结构，以及配置域的属性。如果初始化失败，将返回错误代码。

然后，它使用 sbi_domain_for_each 宏迭代所有的域。这个宏会遍历所有已配置的域，并对每个域执行以下操作：

1. 获取域的启动 HART（处理器核心）的索引（dom->boot_hartid）。
2. 检查启动 HART 的索引是否有效（sbi_hartindex_valid）。
3. 检查启动 HART 是否在域的可能 HART 集合中（dom->possible_harts）。
4. 检查启动 HART 是否被分配给当前域（dom->assigned_harts）。

如果启动 HART 符合上述条件，就会启动该 HART，该 HART 是该域的启动核心。启动时会检查是否是当前冷启动的 HART（cold_hartid），如果是，会将 scratch 结构中的下一个启动地址、启动模式和启动参数设置为当前域的值。否则，会使用 rc = sbi_hsm_hart_start 函数来启动域的 HART。如果启动失败，将返回错误代码。

### sbi hart pmp 配置

```c
// lib/sbi/sbi_init.c: 359

	rc = sbi_hart_pmp_configure(scratch);
	if (rc) {
		sbi_printf("%s: PMP configure failed (error %d)\n",
			   __func__, rc);
		sbi_hart_hang();
	}
```

这段代码是用于配置特权模式（Privilege Mode）中的物理内存保护（Physical Memory Protection，PMP）的设置，这些设置通常用于限制 HART（硬件线程）对物理内存的访问权限。以确保对物理内存的访问权限受到正确的限制。这对于实现特权模式的内存隔离和安全性非常重要

这里面有几个变量需要说明；
1. pmp_gran_log2：pmp 的粒度
2. pmp_bits：pmp 的地址位数
3. pmp_addr_max：pmp 可寻址的最大地址

在完成这三个变量的初始化之后，遍历 `domain` 中的每一个 `memregion`，并根据内存区域的属性（`reg->flags`）设置相应的 PMP 权限标志（`pmp_flags`）。

然后，代码计算 PMP 的起始地址（`pmp_addr`），将内存区域的基地址右移 PMP_SHIFT 位以获得。如果内存区域的粒度不超过 PMP 的粒度（`pmp_gran_log2 <= reg->order`）并且 PMP 地址小于可寻址的最大地址（`pmp_addr_max`），则调用 `pmp_set` 函数来配置 PMP。配置包括 PMP 的索引（`pmp_idx++`）、权限标志（`pmp_flags`）、基地址（`reg->base`）和粒度（`reg->order`）。

### sbi platform 最终初始化

```c
// lib/sbi/sbi_init.c: 366

	/*
	 * Note: Platform final initialization should be after finalizing
	 * domains so that it sees correct domain assignment and PMP
	 * configuration for FDT fixups.
	 */
	rc = sbi_platform_final_init(plat, true);
	if (rc) {
		sbi_printf("%s: platform final init failed (error %d)\n",
			   __func__, rc);
		sbi_hart_hang();
	}
```

该函数调用厂商提供的初始化函数完成平台的最终初始化，这里不再赘述。

### sbi ecall 初始化

```c
// lib/sbi/sbi_init.c: 378
	/*
	 * Note: Ecall initialization should be after platform final
	 * initialization so that all available platform devices are
	 * already registered.
	 */
	rc = sbi_ecall_init();
	if (rc) {
		sbi_printf("%s: ecall init failed (error %d)\n", __func__, rc);
		sbi_hart_hang();
	}
```

该部分是 sbi coldboot 所有初始化中的最后一次初始化，完成该动作后所有的基本设置已经完成，继续完成一些输出之后跳入 S-mode 的软件。

ecall 扩展可以为 SBI 添加额外的功能，例如硬件配置、性能计数、中断处理等。通过注册 ecall 扩展，SBI 可以在特权级别的软件中调用这些扩展功能。

该函数用于初始化 SBI 中的 ecall 部分。ecall 是 SBI 的一部分，它允许特权级别的软件通过 ecall 指令执行特定功能的陷阱处理程序（trap handler）。

函数的主体部分是一个循环，循环次数为 sbi 扩展的个数。在每一个循环中首先获得对应的 sbi 扩展的结构体，并且初始化一个变量 ret，用于标志该 sbi 扩展是否启用成功。之后调用该结构体中的回调函数，完成对应 sbi 扩展的初始化，并且返回 0。

### 最后工作

#### wake_coldboot_harts

该函数用于协调多个 HART 之间的冷启动过程。一旦当前 HART 完成冷启动，它将设置 coldboot_done 标志，并通过 IPI 唤醒其他等待冷启动的 HART，以使它们继续执行后续的初始化和操作。这有助于确保多个 HART 在启动过程中协同工作。

#### sbi_hsm_hart_start_finish

1. 获取下一个执行上下文的参数：代码从 scratch 结构中获取下一个执行上下文的参数，包括参数1、下一条指令的地址和下一个执行的特权模式。

2. 更改 HART 状态：它通过管理 `sbi_hsm_data` 结构来尝试将 HART 的状态从 `SBI_HSM_STATE_START_PENDING` 更改为 `SBI_HSM_STATE_STARTED`。如果无法更改状态，将调用 `sbi_hart_hang()` 函数来处理错误情况。

3. 释放启动令牌：一旦成功更改了 HART 的状态，代码通过调用 `hsm_start_ticket_release` 函数来释放 HART 的启动令牌，表示该 HART 已经启动完成。

4. 执行上下文切换：最后，代码调用 `sbi_hart_switch_mode` 函数，将 HART 的执行上下文切换到下一个指定的特权模式，并传递了相应的参数。

这段代码用于完成 HART 的启动操作，包括状态管理、参数传递和上下文切换。确保每个处理器在适当的时候切换到正确的执行上下文，以开始执行特定的任务或程序。

并且通常来说，这段代码的下面执行的就是 u-boot 或者是 Linux 了。

## 小结

到这里，OpenSBI 的代码分析就结束了，大家可以将以下文章结合起来阅读，加深对 OpenSBI 的理解。

- [RISC-V SBI 概述][001]
- [RISC-V SBI 翻译][002]
- [OpenSBI 固件代码分析（一）：启动流程][003]
- [OpenSBI 固件代码分析（二）：fw_base.S 源码分析][004]
- [OpenSBI 固件代码分析（三）: sbi_init.c][005]
- [OpenSBI 固件代码分析（四）：coldboot][006]

## 参考资料

- https://github.com/riscv-software-src/opensbi/tree/master

- [tinylab/riscv-linux/blob/master/articles/20230612-introduction-to-riscv-sbi.md][001]
- [tinylab/riscv-linux/blob/master/articles/20230710-sbi-specification-translation.md][002]
- [tinylab/riscv-linux/blob/master/articles/20230728-sbi-firmware-analyze-1.md][003]
- [tinylab/riscv-linux/blob/master/articles/20230728-sbi-firmware-analyze-2.md][004]
- [tinylab/riscv-linux/blob/master/articles/20230825-sbi-firmware-analyze-3.md][005]
- [tinylab/riscv-linux/blob/master/articles/20230914-sbi-firmware-analyze-4.md][006]

[001]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230612-introduction-to-riscv-sbi.md
[002]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230710-sbi-specification-translation.md
[003]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230728-sbi-firmware-analyze-1.md
[004]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230728-sbi-firmware-analyze-2.md
[005]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230825-sbi-firmware-analyze-3.md
[006]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230914-sbi-firmware-analyze-4.md
