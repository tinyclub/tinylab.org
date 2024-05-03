---
layout: post
author: 'Groot'
title: 'OpenSBI 固件代码分析（四）：coldboot'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /sbi-firmware-analyze-4/
description: 'OpenSBI 固件代码分析（四）：coldboot'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - OpenSBI
  - 固件分析
  - coldboot
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [spaces toc refs pangu autocorrect]
> Author:    groot <gr00t@foxmail.com>
> Date:      2023/09/14
> Revisor:   Falcon [falcon@tinylab.org](https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:falcon@tinylab.org)
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V Linux 内核 SBI 调用技术分析](https://gitee.com/tinylab/riscv-linux/issues/I64YC4)
> Sponsor:   PLCT Lab, ISCAS


## 前言

之前的文章去给大家已经将 OpenSBI 的内容介绍的差不多了，只剩下一些 `init_coldboot()` 中的一些内容没有介绍，这篇文章就带领大家阅读该部分的内容。

如果将每一个函数的代码都在文章中展开，将会占用太多篇幅，这里就只展示函数调用，不展示函数内部代码。不过读者想要看里面的代码并不困难，在 VIM 中使用 ctags 或者使用各种 IDE 环境都可以很方便的查看源码之前的跳转关系，并且在 GitHub 中也可以进行代码的跳转。

## init_coldboot

之前的文章中讲过，这里的 coldboot 并不是传统意义上的冷启动，而是完全初始化的意思。

在这个过程中，系统会初始化 OpenSBI 的一些基础要素，为 OpenSBI 的运行提供基础。

进入该函数之后，下面几个步骤会依次进行：

### sbi scratch 的初始化

```c
// lib/sbi/sbi_init.c: 271

/* Note: This has to be first thing in coldboot init sequence */
rc = sbi_scratch_init(scratch);
if (rc)
	sbi_hart_hang();
```

该部分是初始化每一个核心的 scratch 空间，形成一个数组，该数组中的每一个元素都是一个 `sbi_scratch` 的数据结构，它的结构如下：

```c
// include/sbi/sbi_scartch.h: 57

struct sbi_scratch {
	/** Start (or base) address of firmware linked to OpenSBI library */
	unsigned long fw_start;
	/** Size (in bytes) of firmware linked to OpenSBI library */
	unsigned long fw_size;
	/** Offset (in bytes) of the R/W section */
	unsigned long fw_rw_offset;
	/** Offset (in bytes) of the heap area */
	unsigned long fw_heap_offset;
	/** Size (in bytes) of the heap area */
	unsigned long fw_heap_size;
	/** Arg1 (or 'a1' register) of next booting stage for this HART */
	unsigned long next_arg1;
	/** Address of next booting stage for this HART */
	unsigned long next_addr;
	/** Privilege mode of next booting stage for this HART */
	unsigned long next_mode;
	/** Warm boot entry point address for this HART */
	unsigned long warmboot_addr;
	/** Address of sbi_platform */
	unsigned long platform_addr;
	/** Address of HART ID to sbi_scratch conversion function */
	unsigned long hartid_to_scratch;
	/** Address of trap exit function */
	unsigned long trap_exit;
	/** Temporary storage */
	unsigned long tmp0;
	/** Options for OpenSBI library */
	unsigned long options;
};
```

这个数据结构是维护每个 hart 必要的，里面包含每个 hart 的基础信息。`sbi_scratch_init` 函数中做了如下操作：在总的 sbi_scratch 空间中找到每个 hart 的 scratch 的空间，并且把这些地址写在一个数组中，方便后面使用。

### sbi heap 的初始化

```c
// lib/sbi/sbi_init.c: 276

/* Note: This has to be second thing in coldboot init sequence */
rc = sbi_heap_init(scratch);
if (rc)
	sbi_hart_hang();
```

在函数中首先会初始化用于堆管理的结构体，之后组织起三个链表，分别是：`free_node_list`、`free_space_list` 和 `used_space_list`，用于维护系统中的堆。

```c
// opensbi/lib/sbi/sbi_heap.c: 185

SBI_INIT_LIST_HEAD(&hpctrl.free_node_list);
SBI_INIT_LIST_HEAD(&hpctrl.free_space_list);
SBI_INIT_LIST_HEAD(&hpctrl.used_space_list);
/* Prepare free node list */
for (i = 0; i < (hpctrl.hksize / sizeof(*n)); i++) {
	n = (struct heap_node *)(hpctrl.hkbase + (sizeof(*n) * i));
	SBI_INIT_LIST_HEAD(&n->head);
	n->addr = n->size = 0;
	sbi_list_add_tail(&n->head, &hpctrl.free_node_list);
}
/* Prepare free space list */
n = sbi_list_first_entry(&hpctrl.free_node_list,
			 struct heap_node, head);
sbi_list_del(&n->head);
n->addr = hpctrl.hkbase + hpctrl.hksize;
n->size = hpctrl.size - hpctrl.hksize;
sbi_list_add_tail(&n->head, &hpctrl.free_space_list);
```

### sbi domain 的初始化

上一篇文章我们已经讲过 sbi domain 的含义以及其中的内容了，那么在 `sbi domain` 的初始化时做了什么操作呢？

```c
// lib/sbi/sbi_init.c: 281

/* Note: This has to be the third thing in coldboot init sequence */
rc = sbi_domain_init(scratch, hartid);
if (rc)
	sbi_hart_hang();
```

该函数实现了初始化 SBI 的根域（root domain）。它首先验证根域的内存区域设置，确保其对齐和大小的合法性。然后分配内存和初始化根域的内存区域，包括可执行、可读写以及超级用户权限的区域。接着，它设置根域的启动信息，将根域的可能处理器标记为有效，并最终注册根域。如果任何步骤失败，该函数都会进行相应的内存释放和错误处理。

### sbi hsm 的初始化

```c
// lib/sbi/sbi_init.c: 297

rc = sbi_hsm_init(scratch, hartid, true);
if (rc)
	sbi_hart_hang();
```

之前讲过，OpenSBI 还支持从 OpenSBI v0.7 开始的 Hart State Management (Hart 状态管理 HSM) SBI 扩展。HSM 扩展允许 S 模式软件按照定义的顺序启动所有的 harts，而不是传统的随机启动 harts 的方法。因此，在 S-mode 下可以轻松支持许多所需的功能，例如 CPU 热插拔、kexec/kdump 等。OpenSBI 中的 HSM 扩展以一种非向后兼容的方式实现，以减轻维护负担并避免混淆。这就是为什么如果 S-mode 中不支持 HSM 扩展，使用 OpenSBI 的任何 S-mode 软件将无法启动多于 1 个 hart。

而 hsm 的初始化就是在这里此处完成的，该过程主要做了两件事情：
1. 如果是启动核，将该核的状态标记为 `SBI_HSM_STATE_START_PENDINM`，否则，标记为 `SBI_HSM_STATE_STOPPE`。
2. 将所有核 `hata->start_ticket` 标记为 0

### sbi platform 早期初始化

```c
// lib/sbi/sbi_init.c: 301

rc = sbi_platform_early_init(plat, true);
if (rc)
	sbi_hart_hang();
```

该过程是对当前 platform 的早期初始化，整个过程比较简单。首先是检查该 platform 是否定义了 early_init 这个函数，如果没有定义，直接返回 0，表示早期初始化成功。如果定义了这个函数，系统将进入这个函数，做一些早期的 platform 初始化工作，不过这部分工作是厂商的工作，具体的代码由厂商编写，这里不再对其进行解释。

### sbi hart 初始化

```c
// lib/sbi/sbi_init.c: 305

rc = sbi_hart_init(scratch, true);
if (rc)
	sbi_hart_hang();
```

该函数首先清空特权寄存器的 `mip` 寄存器，防止在 S-mode 产生的某些中断/异常指令扰乱系统行为。如果系统的启动方式是 coldboot，就从堆中取一块内存空间分配给 `hart_features_offset`，用来存放的 hart feature。

之后调用函数 `hart_detect_features()` 进行 hart feature 的探测。这个探测函数这里先不展开说明，不过我们可以知道的是，在这个探测函数执行完之后，hart 的特性都被加载到了 `sbi_scratch` 的对应空间中去了。

之后再执行 `sbi_hart_reinit()` 函数，期间进行了：
1. 初始化 RISC-V 处理器的控制寄存器，配置其工作模式和性能监控，以确保正确的初始状态。
2. 初始化 RISC-V 处理器的浮点单元，包括双精度（'D'）和单精度（'F'）浮点指令集。如果处理器不支持这些浮点指令集或未启用浮点状态（MSTATUS_FS），则直接返回成功。如果浮点指令集可用，它会初始化浮点寄存器和清除浮点控制和状态寄存器（CSR_FCSR）的值。
3. 配置处理器的中断和异常的委托，以便将它们从 M-mode 委托到 S-mode，从而由 S 模式处理中断和异常，提高机器处理效率。

### sbi console 初始化

```c
// lib/sbi/sbi_init.c: 309

rc = sbi_console_init(scratch);
if (rc)
	sbi_hart_hang();
```

这里就是简单的 console 的初始化，同 platform 早期初始化一样，该初始化的主要工作是由厂商完成，这里不做过多介绍。不过需要注意的一点是，console 的初始化并不是必须的。

### sbi pmu 初始化

```c
// lib/sbi/sbi_init.c: 313

	rc = sbi_pmu_init(scratch, true);
	if (rc) {
		sbi_printf("%s: pmu init failed (error %d)\n",
			   __func__, rc);
		sbi_hart_hang();
	}
```

因为 pmu 是现代处理器的一个重要部分，所以在一个成熟的 RISC-V 处理器中必须要有 pmu，OpenSBI 的这部分代码就是对 pmu 的初始化。

如果是 coldboot，该程序会做如下操作：
1. 给 hardware event 分配一块记录空间
2. 在 sbi scratch 空间中获取一块空间分配给 pmu hart state 用以存储一个 hart 的 pmu 状态
3. 进入 `sbi_platform_pmu_init(plat)` 函数将平台的 pmu 进行初始化，该部分有厂商实现
4. 确定可用的硬件计数器数量（num_hw_ctrs）。这些计数器用于测量不同类型的事件，比如 CPU 周期数和指令数。

之后系统获取到 sbi scratch 空间中的 pmu state，然后调用函数 `pmu_reset_event_map(phs)` 将一部分 pmu 的事件初始化为默认未开启，将所有的 firmware 的计数器值设置为 0。

系统默认启用前三个计数器，计数器 0 和计数器 2 并配置为测量 CPU 周期数（`SBI_PMU_HW_CPU_CYCLES`）和指令数（`SBI_PMU_HW_INSTRUCTIONS`）。计数器 1 暂且被置位无效，日后使用。

## 补充

在分析源码的时候可能会经常遇见一个函数 `sbi_scratch_alloc_offset()`，如果不理解该函数的行为，很可能在分析过程中遇见不晓得困难，这里特此做一个补充。

### sbi_scratch_alloc_offset

```c
// lib/sbi/sbi_scratch.c: 43
// 根据 size 在堆中分配一块内存，返回分配内存的首地址
unsigned long sbi_scratch_alloc_offset(unsigned long size)
{
        u32 i;
        void *ptr;
        unsigned long ret = 0;
        struct sbi_scratch *rscratch;

        /*
         * We have a simple brain-dead allocator which never expects
         * anything to be free-ed hence it keeps incrementing the
         * next allocation offset until it runs-out of space.
         *
         * In future, we will have more sophisticated allocator which
         * will allow us to re-claim free-ed space.
         */

        if (!size)
                return 0;

        // groot: 两步操作，将 size 对齐到比 size 的地址大并且最接近 size 的内存中
        size += __SIZEOF_POINTER__ - 1;
        size &= ~((unsigned long)__SIZEOF_POINTER__ - 1);

        // groot: 访问共享内存，加锁
        spin_lock(&extra_lock);

        // groot: 如果内存不能够给 size 分配，跳出
        if (SBI_SCRATCH_SIZE < (extra_offset + size))
                goto done;

        // groot: 将内存分配给 ret，并且记录内存分配的变量 extra_offset 增加 size
        ret = extra_offset;
        extra_offset += size;

done:
        spin_unlock(&extra_lock);

        // groot: 如果内存分配成功
        //        遍历所有的 hart，将每个有效的 hart 的对应内存都清零
        if (ret) {
                for (i = 0; i <= sbi_scratch_last_hartid(); i++) {
                        rscratch = sbi_hartid_to_scratch(i);
                        if (!rscratch)
                                continue;
                        ptr = sbi_scratch_offset_ptr(rscratch, ret);
                        sbi_memset(ptr, 0, size);
                }
        }

        // groot: 返回新开辟的地址
        return ret;
}

```

## 小结

这篇文章紧跟上一篇文章的脚本，分析了 OpenSBI coldboot 的行为，不过因为篇幅原因没有给出全部代码，读者可以根据文中代码的注释自行找出，然后对照该文章进行理解。

不过到这里 coldboot 的启动过程还没有结束，后面还有一系列行为，包括
- sbi_irqchip_init
- sbi_ipi_init
- sbi_tlb_init
- sbi_timer_init
- sbi_domain_finalize
- sbi_hart_pmp_configure
- sbi_platform_final_init
- sbi_ecall_init

如果在本篇文章中一次性全部分析完读者很可能就晕头转向了，所有笔者决定该篇文章暂时先分析到 `sbi_boot_print_banner(scratch)` 之前，也就是 `sbi_pmu_init()` 函数，等完全理解该篇文章的内容后，读者再进入下一环节吧！

## 参考资料

https://github.com/riscv-software-src/opensbi/tree/master
