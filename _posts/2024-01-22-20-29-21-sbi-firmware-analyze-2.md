---
layout: post
author: 'Groot'
title: 'OpenSBI 固件代码分析（二）：fw_base.S 源码分析'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /sbi-firmware-analyze-2/
description: 'OpenSBI 固件代码分析（二）：fw_base.S 源码分析'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - OpenSBI
  - 固件分析
  - fw_base.S
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [urls refs]
> Author:    groot <gr00t@foxmail.com>
> Date:      2023/07/28
> Revisor:   Falcon [falcon@tinylab.org](https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:falcon@tinylab.org)
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V Linux 内核 SBI 调用技术分析](https://gitee.com/tinylab/riscv-linux/issues/I64YC4)
> Sponsor:   PLCT Lab, ISCAS


## 前言

在上一篇文章中，我们在逻辑层面讲解了 fw_base.S 这个文件，不过并没有对具体的代码进行分析。在这篇文章中，我们将代码与文章 [sbi-firemware-analyze-1][001] 结合起来，为读者进行更深层次的讲解，加深读者对 OpenSBI 固件代码的理解。

## 代码解析

将代码内容分割成小段进行解析，并在每段前用有序列表将其主要功能进行归纳。

### 初始化

1. 导入头文件：
   * 通过 `#include` 指令导入了一系列的头文件，包括用于 RISC-V 汇编的宏定义和功能。
2. 定义宏和常量：
   * 定义了两个常量 `BOOT_STATUS_RELOCATE_DONE` 和 `BOOT_STATUS_BOOT_HART_DONE`，用于表示引导状态。
   * 定义了一系列宏，例如 `MOV_3R` 和 `MOV_5R`，用于将寄存器值复制到其他寄存器。
   * 定义了宏 `BRANGE`，用于根据一组寄存器值的范围条件进行条件跳转。
3. 进入代码段：
   * 使用 `.section` 指令将代码放置在 `.entry` 段中，指定代码段属性为 "ax"（可执行且分配内存）。
   * 使用 `.align` 指令将代码对齐到 `2^3 = 8` 字节的边界。
   * 使用 `.globl` 指令声明全局可见的 `_start` 和 `_start_warm` 函数。

这段代码主要是一些预处理和准备工作，定义了常量、宏以及入口函数，并为接下来的代码部分做了一些准备。通常，这样的初始化和准备阶段在程序中会出现在代码的开头。在此之后，该文件应该会继续定义和执行更多的代码来实现特定的功能。

```asm
// opensbi/firmware/fw_base.S: 1

/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2019 Western Digital Corporation or its affiliates.
 *
 * Authors:
 *   Anup Patel <anup.patel@wdc.com>
 */

#include <sbi/riscv_asm.h>

#include <sbi/riscv_encoding.h>

#include <sbi/riscv_elf.h>

#include <sbi/sbi_platform.h>

#include <sbi/sbi_scratch.h>

#include <sbi/sbi_trap.h>

#define BOOT_STATUS_RELOCATE_DONE   1

#define BOOT_STATUS_BOOT_HART_DONE  2

.macro  MOV_3R __d0, __s0, __d1, __s1, __d2, __s2
    add \__d0, \__s0, zero
    add \__d1, \__s1, zero
    add \__d2, \__s2, zero
.endm

.macro  MOV_5R __d0, __s0, __d1, __s1, __d2, __s2, __d3, __s3, __d4, __s4
    add \__d0, \__s0, zero
    add \__d1, \__s1, zero
    add \__d2, \__s2, zero
    add \__d3, \__s3, zero
    add \__d4, \__s4, zero

.endm

/*
 * If __start_reg <= __check_reg and __check_reg < __end_reg then
 *   jump to __pass
 */

.macro BRANGE __start_reg, __end_reg, __check_reg, __jump_lable
    blt \__check_reg, \__start_reg, 999f
    bge \__check_reg, \__end_reg, 999f
    j   \__jump_lable

999:

.endm
    .section .entry, "ax", %progbits
    .align 3
    .globl _start
    .globl _start_warm
```

### 开始和引导 HART 识别

1. `_start` 函数开始，表示系统启动的入口点。
2. 调用 `fw_boot_hart` 函数，用于确定首选的启动核心（HART），函数的返回值存储在寄存器 `a0` 中。
3. 将函数的返回值存储在寄存器 `a6` 中，这个值代表着首选的启动核心的编号。如果返回值是 `-1`，表示没有特定的首选核心。

   - 判断 `a6` 的值是否等于 `-1`，如果等于 `-1`，表示没有指定特定的启动核心，需要进行随机选择。
   - 如果 `a6` 不等于 `-1`，说明已经指定了启动核心。通过比较 `a0` 和 `a6` 的值，如果不相等，表示当前核心不是指定的启动核心，应该跳转到 `_wait_relocate_copy_done` 函数处。
4. 如果到达 `_try_lottery` 函数，表示需要进行抽签来选择启动核心。这里使用原子操作（`amoadd.w`）在地址 `_relocate_lottery` 所指向的位置执行原子加 1 操作，得到的结果存储在 `a6` 中。
5. 根据 `_relocate_lottery` 的值，判断是否是第一个核心执行到抽签操作的，如果不是（`a6` 不等于 0），则直接跳转到 `_wait_relocate_copy_done`。
6. 如果到达这里，说明是第一个核心执行抽签操作，即抽中了签，将会进入下一阶段的代码。

这段代码的主要目的是确定首选的启动核心，并在多核情况下确保只有一个核心执行到 `_try_lottery` 部分，并将启动核心的信息保存到特定地址。对于其他核心，如果不是启动核心，则会跳转到 `_wait_relocate_copy_done` 处等待。

```
// opensbi/firmware/fw_base.S: 49

// 开始
_start:

    /* Find preferred boot HART id */

# 伪代码，见第 26 行
    MOV_3R  s0, a0, s1, a1, s2, a2

# 调用 fw_boot_hart 函数
# fw_payload 和 fw_jump 返回 -1
# fw_danymic 返回指定数字，设置为指定核心启动
    call    fw_boot_hart
    add a6, a0, zero

# 伪代码，见第 20 行
    MOV_3R  a0, s0, a1, s1, a2, s2

# 下面的 66 - 70 行代码以多核的角度看
# 每个核都要执行这些所有代码，没有符合条件的核心进入 _wait_relocate_copy_done 等待
# 判断 a6 是否是 -1
# 如果是 -1，调用 _try_lottery 函数随机产生一个启动核心
    li  a7, -1
    beq a6, a7, _try_lottery
    /* Jump to relocation wait loop if we are not boot hart */

# 如果不是 -1 意味着指定了启动核心，
    bne a0, a6, _wait_relocate_copy_done

# ，前面的 _try_lottery 只能有一个核心获得 lottery，其他没有获取的
_try_lottery:
    /* Jump to relocation wait loop if we don't get relocation lottery */
    lla a6, _relocate_lottery
    li  a7, 1

# 原子操作
# a6 指向的地址上的值（_relocate_lottery 的地址）做原子加 1，_relocate_lottery 的老值写入 a6。
    amoadd.w a6, a7, (a6)

# _relocate_lottery 不等于 0，就跳到 boot hart 做完重定位的地方。
# 如果多个核一起启动执行，只有最先执行上面原子加指令的核的 a6（_relocate_lottery 初始值）是 0，
# 所以，后续执行到这里的核都是从核，直接跳到重定位完成的地址。
    bnez    a6, _wait_relocate_copy_done
```

### 重定位和初始化

重定位过程这里暂不展示，不妨碍读者理解代码逻辑，有兴趣可以自行阅读。

这里只展示 BSS 段的设置以及针对不同 HART 的初始化操作。

1. 如果没有启用位置无关代码，计算并更新 `t0` 为相对于加载地址的 `_boot_status` 的地址。
2. 使用 `fence` 指令确保内存访问操作完成。
3. 设置中断处理例程为 `_start_hang`。
4. 设置临时中断栈的位置。

这段代码在完成重定位后进行了一系列初始化和设置操作，包括清零 BSS 段、设置中断处理例程和临时中断栈。这些操作为系统启动后的主固件提供了一个干净的环境和所需的信息。

```
// opensbi/firmware/fw_base.S: 194
    /*
     * Mark relocate copy done
     * Use _boot_status copy relative to the load address
     */

# 加载 _boot_status 的地址到 t0
    lla t0, _boot_status

#ifndef FW_PIC
    lla t1, _link_start
    REG_L   t1, 0(t1)
    lla t2, _load_start
    REG_L   t2, 0(t2)
    sub t0, t0, t1
    add t0, t0, t2

#endif

# 改变 t0 为 BOOT_STATUS_RELOCATE_DONE，这是个宏，被定义为 1
    li  t1, BOOT_STATUS_RELOCATE_DONE
    REG_S   t1, 0(t0)

# 确保以上的访存操作已经做完
    fence   rw, rw
    /* At this point we are running from link address */
    /* Reset all registers for boot HART */
    li  ra, 0

# 将所有寄存器清零
    call    _reset_regs

# 将 _bss_start 和 _bss_end 分别加载到 s4 和 s5
    /* Zero-out BSS */
    lla s4, _bss_start
    lla s5, _bss_end

# 循环将所有 bss 段内的内容清零
_bss_zero:
# 向 s4 寄存器所指的内存中写 0，也就是清零 s4 寄存器所指内存的值
    REG_S   zero, (s4)
# s4 所指的地址 +4，指向下一个地址
    add s4, s4, __SIZEOF_POINTER__

# 如果 s4 的值小于 s5，也就是还没到 _bss_end ，跳至 _bss_zero
    blt s4, s5, _bss_zero

#  设置一些临时使用的中断
    /* Setup temporary trap handler */
    lla s4, _start_hang
    csrw    CSR_MTVEC, s4

# 设置一些临时使用的中断栈
    /* Setup temporary stack */
    lla s4, _fw_end
    li  s5, (SBI_SCRATCH_SIZE * 2)
    add sp, s4, s5
```

### 设备树重定位

```
// opensbi/firmware/fw_base.S: 239

# 如果定义了设备树的地址，将它加载进来
#ifdef FW_FDT_PATH
    /* Override previous arg1 */
    lla a1, fw_fdt_bin

#endif
```

### 针对特定平台进行相关初始化

1. 使用 `MOV_5R` 宏将参数传递给 `fw_platform_init` 函数。
2. 调用 `fw_platform_init` 函数来初始化平台。

```
// opensbi/firmware/fw_base.S: 245
/*
     * Initialize platform
     * Note: The a0 to a4 registers passed to the
     * firmware are parameters to this function.
     */

    MOV_5R  s0, a0, s1, a1, s2, a2, s3, a3, s4, a4
    call    fw_platform_init
    add t0, a0, zero
    MOV_5R  a0, s0, a1, s1, a2, s2, a3, s3, a4, s4
    add a1, t0, zero
    /* Preload HART details
     * s7 -> HART Count
     * s8 -> HART Stack Size
     * s9 -> Heap Size
     * s10 -> Heap Offset
     */

# 将平台相关的数据结构地址加载进 a4 寄存器
    lla a4, platform

# 根据寄存器 a4 将平台相关的数据加载进来
#if __riscv_xlen > 32
    lwu s7, SBI_PLATFORM_HART_COUNT_OFFSET(a4)
    lwu s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(a4)
    lwu s9, SBI_PLATFORM_HEAP_SIZE_OFFSET(a4)

#else
    lw  s7, SBI_PLATFORM_HART_COUNT_OFFSET(a4)
    lw  s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(a4)
    lw  s9, SBI_PLATFORM_HEAP_SIZE_OFFSET(a4)

#endif
```

### 启动核启动

1. 初始化 Scratch Space（临时工作区域）：
2. 初始化 Scratch Space 内容：
   * 初始化 scratch space，包括存储 fw_start、fw_size、R/W section 偏移、fw_heap_offset、fw_heap_size 等信息。
   * 加载下一个阶段的参数、可执行文件地址、特权等级、启动函数地址、平台数据结构地址、hartid-to-scratch 函数地址、trap-exit 函数地址等，并存储到 scratch space。
3. 初始化所有核心的 Scratch Space：
   * 通过循环初始化所有核心的 scratch space，直到所有核心的 scratch space 都被初始化。
4. 重新定位 Flattened Device Tree (FDT)：
   * 如果存在需要重新定位的 FDT，则将先前和下一个阶段的参数传递给 `_fdt_reloc` 函数，将 FDT 从源地址复制到目标地址。
5. 标记启动核心完成：
   * 启动核心将状态标记为已完成，以通知其他核心。
6. 非启动核心等待启动核心完成：
   * 非启动核心等待启动核心标记为已完成，以确保启动核心完成初始化后才继续执行。

这段汇编代码执行了 RISC-V 系统的早期初始化和引导任务，包括初始化 scratch space、存储关键信息和参数、重新定位 FDT，以及核心间的同步。

```
# tp 是 RISC-V 中的一个特殊寄存器，用于指向临时工作区域（scratch space）。

# 将 _fw_end 地址加载进 tp, 在用 s7,s8 计算出 scratch space, 再加上 tp, 调整 scratch space 的位置
    /* Setup scratch space for all the HARTs */
    lla tp, _fw_end
    mul a5, s7, s8
    add tp, tp, a5

# 原理同上

# 调整 heap 基址
    /* Setup heap base address */
    lla s10, _fw_start
    sub s10, tp, s10
    add tp, tp, s9

    /* Keep a copy of tp */

    add t3, tp, zero

    /* Counter */
    li  t2, 1

    /* hartid 0 is mandated by ISA */

    li  t1, 0

_scratch_init:
    /*
     * The following registers hold values that are computed before
     * entering this block, and should remain unchanged.
     *
     * t3 -> the firmware end address
     * s7 -> HART count
     * s8 -> HART stack size
     * s9 -> Heap Size
     * s10 -> Heap Offset
     */

# 找到 scratch space 的基址
    add tp, t3, zero
    sub tp, tp, s9

# t1 首次是 0，计算出来的 a5 也等于 0，
# 这个 t1 是 hart 的编号，s8 是每个核的栈大小
# 所以，a5 是每个 hart 的栈的偏移。
    mul a5, s8, t1
    sub tp, tp, a5
    li  a5, SBI_SCRATCH_SIZE
    sub tp, tp, a5
    /* Initialize scratch space */
    /* Store fw_start and fw_size in scratch space */
    lla a4, _fw_start
    sub a5, t3, a4
    REG_S   a4, SBI_SCRATCH_FW_START_OFFSET(tp)
    REG_S   a5, SBI_SCRATCH_FW_SIZE_OFFSET(tp)
    /* Store R/W section's offset in scratch space */
    lla a4, __fw_rw_offset
    REG_L   a5, 0(a4)
    REG_S   a5, SBI_SCRATCH_FW_RW_OFFSET(tp)
    /* Store fw_heap_offset and fw_heap_size in scratch space */
    REG_S   s10, SBI_SCRATCH_FW_HEAP_OFFSET(tp)
    REG_S   s9, SBI_SCRATCH_FW_HEAP_SIZE_OFFSET(tp)

# 设置函数：加载下一个阶段的参数 1 的地址
    /* Store next arg1 in scratch space */
    MOV_3R  s0, a0, s1, a1, s2, a2
    call    fw_next_arg1
    REG_S   a0, SBI_SCRATCH_NEXT_ARG1_OFFSET(tp)
    MOV_3R  a0, s0, a1, s1, a2, s2

# 设置函数：加载下一个阶段的可执行文件的地址 的地址
    /* Store next address in scratch space */
    MOV_3R  s0, a0, s1, a1, s2, a2
    call    fw_next_addr
    REG_S   a0, SBI_SCRATCH_NEXT_ADDR_OFFSET(tp)
    MOV_3R  a0, s0, a1, s1, a2, s2

# 设置函数：设置下一个阶段的特权等级的地址
    /* Store next mode in scratch space */
    MOV_3R  s0, a0, s1, a1, s2, a2
    call    fw_next_mode
    REG_S   a0, SBI_SCRATCH_NEXT_MODE_OFFSET(tp)
    MOV_3R  a0, s0, a1, s1, a2, s2

# 设置启动函数地址
    /* Store warm_boot address in scratch space */
    lla a4, _start_warm
    REG_S   a4, SBI_SCRATCH_WARMBOOT_ADDR_OFFSET(tp)

# 将特定平台的数据结构加载进来
    /* Store platform address in scratch space */
    lla a4, platform
    REG_S   a4, SBI_SCRATCH_PLATFORM_ADDR_OFFSET(tp)

# 将 hartid-to-scratch 函数的地址存入 scratch space
    /* Store hartid-to-scratch function address in scratch space */
    lla a4, _hartid_to_scratch
    REG_S   a4, SBI_SCRATCH_HARTID_TO_SCRATCH_OFFSET(tp)

# 将 trap-exit 函数的地址存入 scratch space
    /* Store trap-exit function address in scratch space */
    lla a4, _trap_exit
    REG_S   a4, SBI_SCRATCH_TRAP_EXIT_OFFSET(tp)
    /* Clear tmp0 in scratch space *
    REG_S   zero, SBI_SCRATCH_TMP0_OFFSET(tp)
    /* Store firmware options in scratch space */
    MOV_3R  s0, a0, s1, a1, s2, a2

# FW_OPTIONS 禁用 OpenSBI 启动时打印信息
#ifdef FW_OPTIONS
    li  a0, FW_OPTIONS
#else
    call    fw_options
#endif
    REG_S   a0, SBI_SCRATCH_OPTIONS_OFFSET(tp)
    MOV_3R  a0, s0, a1, s1, a2, s2
    /* Move to next scratch space */

# 再将 t1 + 1，检查 t1 是否小于 s7（HART_COUNT）
# 如果小于，说明还有其他核的 scratch_space 没有初始化完成
# 继续进行其他核心的初始化工作
    add t1, t1, t2
    blt t1, s7, _scratch_init
    /*
     * Relocate Flatened Device Tree (FDT)
     * source FDT address = previous arg1
     * destination FDT address = next arg1
     *
     * Note: We will preserve a0 and a1 passed by
     * previous booting stage.
     */

# a1 = 0，意味着不需要进行 _fdt_reloc
# a1 的值见
# 279: lla  a1, fw_fdt_bin
    beqz    a1, _fdt_reloc_done
    /* Mask values in a4 */
    li  a4, 0xff
    /* t1 = destination FDT start address */
    MOV_3R  s0, a0, s1, a1, s2, a2

# 加载下一个阶段的参数 1
    call    fw_next_arg1
    add t1, a0, zero
    MOV_3R  a0, s0, a1, s1, a2, s2
    beqz    t1, _fdt_reloc_done
    beq t1, a1, _fdt_reloc_done
    /* t0 = source FDT start address */
    add t0, a1, zero
    /* t2 = source FDT size in big-endian */
#if __riscv_xlen == 64
    lwu t2, 4(t0)
#else
    lw  t2, 4(t0)
#endif
    /* t3 = bit[15:8] of FDT size */
    add t3, t2, zero
    srli    t3, t3, 16
    and t3, t3, a4
    slli    t3, t3, 8
    /* t4 = bit[23:16] of FDT size */
    add t4, t2, zero
    srli    t4, t4, 8
    and t4, t4, a4
    slli    t4, t4, 16
    /* t5 = bit[31:24] of FDT size */
    add t5, t2, zero
    and t5, t5, a4
    slli    t5, t5, 24
    /* t2 = bit[7:0] of FDT size */
    srli    t2, t2, 24
    and t2, t2, a4
    /* t2 = FDT size in little-endian */
    or  t2, t2, t3
    or  t2, t2, t4
    or  t2, t2, t5
    /* t2 = destination FDT end address */
    add t2, t1, t2
    /* FDT copy loop */
    ble t2, t1, _fdt_reloc_done

_fdt_reloc_again:
    REG_L   t3, 0(t0)
    REG_S   t3, 0(t1)
    add t0, t0, __SIZEOF_POINTER__
    add t1, t1, __SIZEOF_POINTER__
    blt t1, t2, _fdt_reloc_again

_fdt_reloc_done:
# 启动核表明自己启动完成
    /* mark boot hart done */
    li  t0, BOOT_STATUS_BOOT_HART_DONE
    lla t1, _boot_status
    REG_S   t0, 0(t1)
    fence   rw, rw
    j   _start_warm
```

### 非引导 HART 的热启动

1. 使用 `_reset_regs` 函数重置所有寄存器的值，为非启动核心做准备。
2. 使用 `CSR_MIE` 控制寄存器，将机器中断使能位清零，禁用所有中断。
3. 从平台数据结构中加载 HART 的数量和 HART 栈大小。
4. 从机器模式下的 `CSR_MHARTID` 寄存器中读取当前非启动核心的 HART ID（处理器 ID）到寄存器 `s6`。
5. 如果 HART index 在平台数据结构中可用，将 `s6` 设置为对应的 HART index。
6. 计算非启动核心的 scratch space 的地址范围，并将其存储到 `CSR_MSCRATCH` 寄存器中。这个寄存器是每个 HART 独有的，用于存储核心的临时数据。
7. 设置栈的位置为 scratch space 的地址，即为 `sp` 寄存器赋值。
8. 配置陷阱（trap）处理程序，将 `_trap_handler` 函数的地址加载到 `CSR_MTVEC` 寄存器中，用于处理中断和异常。

这段代码负责为非启动核心进行初始化，设置其运行环境，栈，陷阱处理程序等，以及可能的特定于架构的设置。

```
// opensbi/firmware/fw_base.S: 439

# 热启动
# 在这里进行非启动核心的初始化，等待启动核心完成初始化。非启动核心会等待启动核心在主要初始化工作完成后，再进行自己的初始化。
_start_warm:
    /* Reset all registers for non-boot HARTs */
    li  ra, 0
    call    _reset_regs
    /* Disable all interrupts */
    csrw    CSR_MIE, zero
    /* Find HART count and HART stack size */
    lla a4, platform
#if __riscv_xlen == 64
    lwu s7, SBI_PLATFORM_HART_COUNT_OFFSET(a4)
    lwu s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(a4)
#else
    lw  s7, SBI_PLATFORM_HART_COUNT_OFFSET(a4)
    lw  s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(a4)
#endif
    REG_L   s9, SBI_PLATFORM_HART_INDEX2ID_OFFSET(a4)

# 使用 CSR（Control and Status Register）指令，将机器模式下的 HART ID（处理器 ID）读取到 s6 寄存器中。
# CSR_MHARTID 是一个特定的寄存器控制编码，用于获取当前 HART 的 ID。
    /* Find HART id */
    csrr    s6, CSR_MHARTID
    /* Find HART index */
    beqz    s9, 3f
    li  a4, 0
1:
#if __riscv_xlen == 64
    lwu a5, (s9)
#else
    lw  a5, (s9)
#endif
    beq a5, s6, 2f
    add s9, s9, 4
    add a4, a4, 1
    blt a4, s7, 1b
    li  a4, -1

2:  add s6, a4, zero

3:  bge s6, s7, _start_hang

# 经过下面的操作，可以找到符合上面条件的 HART 的 scratch space 的 end 位置
    /* Find the scratch space based on HART index */
    lla tp, _fw_end
    mul a5, s7, s8
    add tp, tp, a5
    mul a5, s8, s6
    sub tp, tp, a5
    li  a5, SBI_SCRATCH_SIZE
    sub tp, tp, a5

# 将上面的值写入 CSR_MSCRATCH 寄存器
    /* update the mscratch */
    csrw    CSR_MSCRATCH, tp
    /* Setup stack */
    add sp, tp, zero
    /* Setup trap handler */
    lla a4, _trap_handler

# 如果架构是 32 位的，做一些特殊操作
#if __riscv_xlen == 32
    csrr    a5, CSR_MISA
    srli    a5, a5, ('H' - 'A')
    andi    a5, a5, 0x1
    beq a5, zero, _skip_trap_handler_rv32_hyp
    lla a4, _trap_handler_rv32_hyp

_skip_trap_handler_rv32_hyp:
#endif
    csrw    CSR_MTVEC, a4

#if __riscv_xlen == 32
    /* Override trap exit for H-extension */
    csrr    a5, CSR_MISA
    srli    a5, a5, ('H' - 'A')
    andi    a5, a5, 0x1
    beq a5, zero, _skip_trap_exit_rv32_hyp
    lla a4, _trap_exit_rv32_hyp
    csrr    a5, CSR_MSCRATCH
    REG_S   a4, SBI_SCRATCH_TRAP_EXIT_OFFSET(a5)

_skip_trap_exit_rv32_hyp:
#endif
```

### 进入 SBI 运行时

这段代码将非启动核心引导到 SBI 的运行时环境，并进入一个死循环，表示在这个点上程序不应该继续执行。

```
// opensbi/firmware/fw_base.S: 516

# 正式进入 SBI 运行时环境
    /* Initialize SBI runtime */
    csrr    a0, CSR_MSCRATCH
    call    sbi_init
    /* We don't expect to reach here hence just hang */
    j   _start_hang
```

## 小结

本篇文章从上一篇文章的逻辑层面进入到实际的代码层面，为读者梳理好整个汇编文件的内容，并且分割出不同的小模块，将各个模块的主要作用整理成有序列表，并且在模块内部的代码块中尽力做到逐段注释，提高可阅读性。

## 参考资料

- OpenSBI 源代码
- RISC-V 手册
- [OpenSBI 固件代码分析（一）][001]

[001]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230728-sbi-firmware-analyze-1.md
