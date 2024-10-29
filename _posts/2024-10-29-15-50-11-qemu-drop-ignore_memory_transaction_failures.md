---
layout: post
author: 'Chao Liu'
title: '废弃 QEMU xilinx_zynq 板卡的 ignore_memory_transaction_failures'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /qemu-drop-ignore_memory_transaction_failures/
description: '废弃 QEMU xilinx_zynq 板卡的 ignore_memory_transaction_failures'
category:
  - 开源项目
  - Qemu
tags:
  - Linux
  - QEMU
  - xilinx
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [toc comments codeblock refs]
> Author:    刘超 <chao.liu@yeah.net>
> Date:      2024/09/22
> Revisor:   Bin Meng, falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

早期某些嵌入式系统或者硬件平台，对内存管理不够严苛，当 CPU 访问一个未分配或未映射的内存地址时：

* 进行读操作，则返回零值，这个行为被称为 Read Address Zero（RAZ）；

* 进行写操作，则忽略，这个行为被称为 Write Ignore（WI）。

在实际应用中，RAZ/WI 行为通常用于：

* 调试目的：在开发过程中，访问未映射地址，可能会被忽略或返回零值，以避免系统崩溃；

* 硬件兼容性：在某些硬件平台上，这种行为被视为一种标准，以确保软件在不同硬件配置下的兼容性。

在 QEMU 的使用场景中，这种行为通常是为了兼容某些硬件平台的传统行为。在这些平台上，访问未映射的内存区域，可能会被简单地忽略或返回零值，而不是抛出一个错误或异常。

## ignore_memory_transaction_failures

随着 QEMU 的发展，更现代的方法是使用 `unimplemented-device` 来模拟那些 QEMU 中尚未实现的硬件设备。这种方法更符合现代操作系统的期望，即当访问未实现的设备时，应该明确地报告错误或异常，而不是简单地返回零或忽略写入。

另外通过 `unimplemented-device` 创建的设备，可以记录所有客户机 CPU 对该设备的访问，并通过 QEMU 的调试日志记录下来。这有助于调试和验证设备模型的行为。

然而，在一些遗留的板卡模型中，可能仍然依赖于 RAZ/WI 行为来处理那些 QEMU 尚未建模的设备。

为了兼容传统的板卡模型（通常是 ARM boards），QEMU 在 v2.10.0-291-ged860129ac 中，为 `MachineClass` 增加了一个新的 `ignore_memory_transaction_failures` 字段，类型为 `bool`。

如果将该字段设置为 `true`，则 vCPU 将忽略那些因访问未分配的物理地址而导致的内存事务失败，通常这些失败会引发异常。

此标志应仅用于 QEMU 中依赖旧的 RAZ/WI 行为的传统板卡访问尚未建模的设备。新板卡模型中未实现的设备应使用 `unimplemented-device`。

### 分析代码实现

这里我们以 QEMU v9.0.2 源代码为例，进行分析。

CPU 模型在 realize 阶段，通过 `cpu_common_realizefn` 函数，从 `MachineClass` 中获取 `ignore_memory_transaction_failures` 的值，然后更新 `cpu->ignore_memory_transaction_failures`，代码如下：

```c
// hw/core/cpu-common.c:195
static void cpu_common_realizefn(DeviceState *dev, Error **errp)
{
    CPUState *cpu = CPU(dev);
    Object *machine = qdev_get_machine();

    /* qdev_get_machine() can return something that's not TYPE_MACHINE
     * if this is one of the user-only emulators; in that case there's
     * no need to check the ignore_memory_transaction_failures board flag.
     */
    if (object_dynamic_cast(machine, TYPE_MACHINE)) {
        MachineClass *mc = MACHINE_GET_CLASS(machine);
        if (mc) {
            cpu->ignore_memory_transaction_failures =
                mc->ignore_memory_transaction_failures;
        }
    }

    ...
}
```

在 CPU 执行访存指令时，如果是全系统模拟，那么 CPU 所有的访存行为，都要先经过 SoftMMU。以 TCG 为例：

1. CPU 首先会查询 Soft TLB，如果 TLB Miss，则进入慢速路径调用 Helper 函数访存，流程如下；

```
                tb binary code
                  ---+---
find tlb    --->     |
                    bne -----------------------------+
direct ld   --->     |                               |
                    -+-                              | TLB Miss
                     |                               |
TB end      --->    -+-                              |
                     |  <--- ldst slow path code <---+
                    ...
```

2. 以读操作为例，Helper 函数最终会调用到 `int_ld_mmio_beN` 函数，代码如下：

```c
// accel/tcg/cputlb.c:1268
static void io_failed(CPUState *cpu, CPUTLBEntryFull *full, vaddr addr,
                      unsigned size, MMUAccessType access_type, int mmu_idx,
                      MemTxResult response, uintptr_t retaddr)
{
    if (!cpu->ignore_memory_transaction_failures // 忽略访存异常
        && cpu->cc->tcg_ops->do_transaction_failed) {
        hwaddr physaddr = full->phys_addr | (addr & ~TARGET_PAGE_MASK);

        cpu->cc->tcg_ops->do_transaction_failed(cpu, physaddr, addr, size,
                                                access_type, mmu_idx,
                                                full->attrs, response, retaddr);
    }
}

// accel/tcg/cputlb.c:1928
static uint64_t int_ld_mmio_beN(CPUState *cpu, CPUTLBEntryFull *full,
                                uint64_t ret_be, vaddr addr, int size,
                                int mmu_idx, MMUAccessType type, uintptr_t ra,
                                MemoryRegion *mr, hwaddr mr_offset)
{
    MemTxResult r;

    ...

    r = memory_region_dispatch_read(mr, mr_offset, &val,
                                    this_mop, full->attrs);
    if (unlikely(r != MEMTX_OK)) {
        io_failed(cpu, full, addr, this_size, type, mmu_idx, r, ra);
    }

    ...

    return ret_be;
}
```

如果在 `memory_region_dispatch_read` 函数中，返回了 `MEMTX_OK`，则表示访问成功，否则会调用 `io_failed` 函数。

在 `io_failed` 函数中会根据 `ignore_memory_transaction_failures` 的值，判断是否需要抛出异常，如果值为 true，则按照 RAZ/WI 行为处理。

## 移除 Xilinx Zynq 的 ignore_memory_transaction_failures

由于笔者环境中正好有一个 Xilinx Zynq 的 Linux 内核二进制镜像，所以决定尝试移除 Xilinx Zynq 板卡中的 `ignore_memory_transaction_failures`。

首先在 `zynq_machine_class_init` 函数中去除这个字段的初始化代码：

```c
// hw/arm/xilinx_zynq.c
@@ -394,7 +437,6 @@ static void zynq_machine_class_init(ObjectClass *oc, void *data)
     mc->init = zynq_init;
     mc->max_cpus = ZYNQ_MAX_CPUS;
     mc->no_sdcard = 1;
-    mc->ignore_memory_transaction_failures = true;
     mc->valid_cpu_types = valid_cpu_types;
     mc->default_ram_id = "zynq.ext_ram";
     prop = object_class_property_add_str(oc, "boot-mode", NULL,
--
```

然后重新编译（细节不在这里赘述），并运行 QEMU :

```bash
$ ./qemu/build/qemu-system-arm -M xilinx-zynq-a9 \
-serial /dev/null \
-serial mon:stdio \
-display none \
-kernel QEMU_CPUFreq_Zynq/Prebuilt_functional/kernel_standard_linux/uImage \
-dtb QEMU_CPUFreq_Zynq/Prebuilt_functional/my_devicetree.dtb \
--initrd QEMU_CPUFreq_Zynq/Prebuilt_functional/umy_ramdisk.image.gz
```

> PS: 获取配套测试的 Linux 内核二进制镜像：`git clone https://github.com/zevorn/QEMU_CPUFreq_Zynq.git`

运行现象是终端没有任何输出。遇到这种情况不要慌张，我们可以通过 QEMU 的 gdb 远程调试功能，查看客户机程序的运行情况。

修改 QEMU 启动命令，尾部加入 `-s -S` 使能 gdb 远程调试功能，然后另起一个终端，进行调试：

```bash
$ gdb-multiarch QEMU_CPUFreq_Zynq/Prebuilt_functional/kernel_standard_linux/uImage
(gdb) target remote localhost:1234
Remote debugging using localhost:1234
...
determining executable automatically.  Try using the "file" command.
0x00000000 in ?? ()
(gdb) c
Continuing.
# 这里多等待一会儿，因为 QEMU 使能 GDB 远程调试以后，性能会下降
# 这里键入 Ctrl + C，暂停客户机程序执行
Program received signal SIGINT, Interrupt.
0xc0770240 in ?? ()
(gdb) display /i $pc
1: x/i $pc
=> 0xc0770240:  subs    r0, r0, #1
(gdb) si
0xc0770244 in ?? ()
1: x/i $pc
=> 0xc0770244:  bhi     0xc0770240
(gdb) si
0xc0770240 in ?? ()
1: x/i $pc
=> 0xc0770240:  subs    r0, r0, #1
(gdb)
0xc0770244 in ?? ()
1: x/i $pc
=> 0xc0770244:  bhi     0xc0770240
```

这里有一个小技巧，借助 `dispay /i $pc` 命令，让每次单步都可以打印当前地址的指令反汇编，有助于我们定位问题。

观察多次指令单步的现象，确定已经陷入死循环（0xc0770240 和 0xc0770244 之间循环跳转），大概率是触发了访存异常后，陷入了异常处理函数的死循环当中。但是我们得到信息还是太少，不能轻易论断。

接着调试，看看是在什么地方触发的访存异常。

常规手段是借助 `bt` 命令，查看调用栈，来剖析 CPU 的执行路径，大致推测运行的程序逻辑，操作如下：

```bash
(gdb) bt
#0  0xc0770244 in ?? ()
#1  0xc011cb10 in ?? ()
Backtrace stopped: previous frame identical to this frame (corrupt stack?)
(gdb) x /i 0xc011cb10
   0xc011cb10:  b       0xc011cafc
(gdb)
```

根据调用栈打印结果来看，缺少调试信息，没有什么有效信息。

现在需要我们转变 debug 策略，进一步地，直接通过调试 QEMU 源代码来分析客户机访存异常的地址。

上文提到访存异常是在 `io_failed` 函数中设置的，那么我们在这函数中增加打印，将客户机访存的 GVA 和 GPA 分别打印出来：

```c
static void io_failed(CPUState *cpu, CPUTLBEntryFull *full, vaddr addr,
                      unsigned size, MMUAccessType access_type, int mmu_idx,
                      MemTxResult response, uintptr_t retaddr)
{
    if (!cpu->ignore_memory_transaction_failures
        && cpu->cc->tcg_ops->do_transaction_failed) {
        hwaddr physaddr = full->phys_addr | (addr & ~TARGET_PAGE_MASK);

        // 增加调试打印信息，输出 GVA、GPA 和 access_type
        printf("vaddr %lx phyaddr %lx access_type %d\n", addr, physaddr, access_type);

        cpu->cc->tcg_ops->do_transaction_failed(cpu, physaddr, addr, size,
                                                access_type, mmu_idx,
                                                full->attrs, response, retaddr);
    }
}
```

重新编译运行 QEMU，输出如下：

```bash
vaddr c884f080 phyaddr f8007080 access_type 0
```

访存的客户机物理地址是 0xf8007080，access_type 为 0，代表是一个读操作。

查阅 Xilinx Zynq 的 dts，我们得知地址 0xf8007080 对应的是 devcfg 设备，这个设备在 QEMU 中被模拟为 `xlnx,zynq-devcfg` 类型，其寄存器地址空间为 0xf8007000~0xf8007fff，所以，这个访存异常应该来自 QEMU 模拟的 devcfg 设备。

```c
// roms/u-boot/arch/arm/dts/zynq-7000.dtsi
devcfg: devcfg@f8007000 {
    compatible = "xlnx,zynq-devcfg-1.0";
    interrupt-parent = <&intc>;
    interrupts = <0 8 4>;
    reg = <0xf8007000 0x100>;
    clocks = <&clkc 12>, <&clkc 15>, <&clkc 16>, <&clkc 17>, <&clkc 18>;
    clock-names = "ref_clk", "fclk0", "fclk1", "fclk2", "fclk3";
    syscon = <&slcr>;
};
```

其中 `reg = <0xf8007000 0x100>;` 对应 devcfg 的地址范围。

但是这个设备被 QEMU 模拟了，按道理不应该产生访存异常，除非存在 “地址空洞”，即在 devcfg 设备的地址空间范围内，某些地址段没有被实现。

为了验证我们的猜想，先尝试在 Xilinx Zynq 板卡初始化阶段，为 devcfg 添加 `unimplemented-device`，代码如下：

```c
// hw/arm/xilinx_zynq.c:34
#include "hw/net/cadence_gem.h"
#include "hw/cpu/a9mpcore.h"
#include "hw/qdev-clock.h"
#include "hw/misc/unimp.h" // 添加头文件

// hw/arm/xilinx_zynq.c:203
static void zynq_init(MachineState *machine)
{
    /* Other */
    create_unimplemented_device("amba.devcfg", 0xf8007000, 0x100);
    ...
}
```

重新编译 QEMU，并运行，此时 QEMU 输出：

```bash
[    0.000000] Booting Linux on physical CPU 0x0
[    0.000000] Linux version 5.6.0-axiom+ (kromes@mcsoc2-Latitude-7480) (gcc version 8.2.1 20180802 (GNU Toolchain for the A-profile Architecture 8.2-2018.11 (arm-rel-8.26))) #10 SMP PREEMPT Fri Jul 3 08:42:52 CEST 2020
[    0.000000] CPU: ARMv7 Processor [413fc090] revision 0 (ARMv7), cr=10c5387d
[    0.000000] CPU: PIPT / VIPT nonaliasing data cache, VIPT nonaliasing instruction cache
[    0.000000] OF: fdt: Machine model: xlnx,zynq-zed
[    0.000000] Memory policy: Data cache writeback
[    0.000000] cma: Failed to reserve 64 MiB
[    0.000000] CPU: All CPU(s) started in SVC mode.
[    0.000000] percpu: Embedded 15 pages/cpu s31948 r8192 d21300 u61440
[    0.000000] Built 1 zonelists, mobility grouping on.  Total pages: 32512
[    0.000000] Kernel command line: console=ttyPS0, 115200 root=/dev/ram rw
[    0.000000] Dentry cache hash table entries: 16384 (order: 4, 65536 bytes, l
...
```

发现可以正常输出了。

但是到这里还没结束，由于我们测试集不够充分，那么 Xilinx Zynq 板卡很可能存在其他没有实现的设备，这里我们进入 QEMU 的命令行界面，查看一下 Xilinx Zynq 板卡已经实现的设备及其地址空间：

```bash
$ ./qemu/build/qemu-system-arm -M xilinx-zynq-a9 -display none -monitor stdio
QEMU 9.1.50 monitor - type 'help' for more information
(qemu) info mtree
address-space: cpu-memory-0
address-space: cpu-secure-memory-0
address-space: dma
address-space: dma
address-space: memory
  0000000000000000-ffffffffffffffff (prio 0, i/o): system
    0000000000000000-0000000007ffffff (prio 0, ram): zynq.ext_ram
    00000000e0000000-00000000e0000fff (prio 0, i/o): uart
    00000000e0001000-00000000e0001fff (prio 0, i/o): uart
    00000000e0002000-00000000e0002fff (prio 0, i/o): ehci
      00000000e0002000-00000000e00020ff (prio 0, i/o): usb-chipidea.misc
      00000000e0002100-00000000e000210f (prio 0, i/o): capabilities
    ...

address-space: I/O
  0000000000000000-000000000000ffff (prio 0, i/o): io

(qemu) vaddr 8000000 phyaddr 8000000 a
```

`info mtree` 从 Xilinx Zynq 板卡的起始地址开始，从低到高，输出板卡包含的所有设备，这里我们以 Uart 地址空间的打印为例进行分析：

```bash
00000000e0000000-00000000e0000fff (prio 0, i/o): uart
```

其中 `0xe0000000-0xe0000fff` 为 Uart 地址空间，`prio` 为这个设备在 `mr` 该段地址范围的优先级。因此，我们可以同样按照从低地址到高地址，梳理一遍 Xilinx Zynq 板卡的 dts，将所有没有实现的设备排查出来。

这里举例 PMU 设备，先查看 dts 里面对于的地址范围：

```
// roms/u-boot/arch/arm/dts/zynq-7000.dtsi
	pmu@f8891000 {
		compatible = "arm,cortex-a9-pmu";
		interrupts = <0 5 4>, <0 6 4>;
		interrupt-parent = <&intc>;
		reg = <0xf8891000 0x1000>,
		      <0xf8893000 0x1000>;
	};
```

这里可以看到 PMU 有两段地址，`0xf8891000-0xf8891fff` 和 `0xf8893000-0xf8893fff`。

接着查看 `info mtree` 的输出，定位到以上两个地址段的附近：

```bash
(qemu) info mtree
address-space: cpu-memory-0
address-space: cpu-secure-memory-0
address-space: dma
address-space: dma
address-space: memory
    ...
 00000000e2000000-00000000e5ffffff (prio 0, romd): zynq.pflash
    00000000f8000000-00000000f8000fff (prio 0, i/o): slcr
    00000000f8001000-00000000f8001fff (prio 0, i/o): timer
    00000000f8002000-00000000f8002fff (prio 0, i/o): timer
    00000000f8003000-00000000f8003fff (prio 0, i/o): dma
      00000000f8007000-00000000f800703f (prio 0, i/o): xlnx.ps7-dev-cfg
    00000000f8007100-00000000f800711f (prio 0, i/o): zynq-xadc
    # 大概在这个位置，但是没有对应的设备
    00000000f8f00000-00000000f8f01fff (prio 0, i/o): a9mp-priv-container
    ...
address-space: I/O
  0000000000000000-000000000000ffff (prio 0, i/o): io
```

接着我们在 QEMU 源代码中，添加 PMU 设备为 unimplemented_device：

```c
// hw/arm/xilinx_zynq.c:203
static void zynq_init(MachineState *machine)
{
    ...

    /* DDR remapped to address zero. */
    memory_region_add_subregion(address_space_mem, 0, machine->ram);

    /* PMU */
    create_unimplemented_device("pmu.region0", 0xf8891000, 0x1000);
    create_unimplemented_device("pmu.region1", 0xf8893000, 0x1000);
    ...
}
```

继续排查，发现确实有很多设备没有实现，由于数量较多，这里直接给出代码实现，不再一一列举：

```c
// hw/arm/xilinx_zynq.c:203
static void zynq_init(MachineState *machine)
{
    ...

    /* DDR remapped to address zero. */
    memory_region_add_subregion(address_space_mem, 0, machine->ram);

    /* CAN */
    create_unimplemented_device("amba.can0", 0xe0008000, 0x1000);
    create_unimplemented_device("amba.can1", 0xe0009000, 0x1000);

    /* GPIO */
    create_unimplemented_device("amba.gpio0", 0xe000a000, 0x1000);

    /* I2C */
    create_unimplemented_device("amba.i2c0", 0xe0004000, 0x1000);
    create_unimplemented_device("amba.i2c1", 0xe0005000, 0x1000);

    /* Interrupt-Controller */
    create_unimplemented_device("amba.intc.region0", 0xf8f00100, 0x100);
    create_unimplemented_device("amba.intc.region1", 0xf8f01000, 0x1000);

    /* Memory-Controller */
    create_unimplemented_device("amba.mc", 0xf8006000, 0x1000);

    /* SMCC */
    create_unimplemented_device("amba.smcc", 0xe000e000, 0x1000);
    create_unimplemented_device("amba.smcc.nand0", 0xe1000000, 0x1000000);

    /* Timer */
    create_unimplemented_device("amba.global_timer", 0xf8f00200, 0x20);
    create_unimplemented_device("amba.scutimer", 0xf8f00600, 0x20);

    /* WatchDog */
    create_unimplemented_device("amba.watchdog0", 0xf8005000, 0x1000);

    /* Other */
    create_unimplemented_device("amba.devcfg", 0xf8007000, 0x100);
    create_unimplemented_device("amba.efuse", 0xf800d000, 0x20);
    create_unimplemented_device("amba.etb", 0xf8801000, 0x1000);
    create_unimplemented_device("amba.tpiu", 0xf8803000, 0x1000);
    create_unimplemented_device("amba.funnel", 0xf8804000, 0x1000);
    create_unimplemented_device("amba.ptm.region0", 0xf889c000, 0x1000);
    create_unimplemented_device("amba.ptm.region1", 0xf889d000, 0x1000);

    ...
}
```

另外在打印 `info mtree` 时，发现 devcfg 的地址范围不对：

```bash
(qemu) info mtree
    ...
      00000000f8007000-00000000f800703f (prio 0, i/o): xlnx.ps7-dev-cfg
    ...
```

按照上文给出的设备树配置，devcfg 的地址范围应当是 `0xf8007000-f80070ff`，打开对应代码，定位问题：

```c
// include/hw/dma/xlnx-zynq-devcfg.h
#define XLNX_ZYNQ_DEVCFG_R_MAX (0x100 / 4)
```

由于 XLNX_ZYNQ_DEVCFG_R_MAX 的值为 0x100 / 4，但实际的大小为 0x100。

这里查阅了当时补丁作者这么修改的原因，Message 如下：

```
dma: xlnx-zynq-devcfg: Fix up XLNX_ZYNQ_DEVCFG_R_MAX

Whilst according to the Zynq TRM this device covers a register region of
0x000 - 0x120. The register region is also shared with XADCIF prefix
registers at 0x100 and above. Due to how the devcfg and the xadc devices
are implemented in QEMU these are separate models with individual mmio
regions. As such the region registered by the devcfg overlaps with the
xadc when initialized in a machine model (e.g. xilinx-zynq-a9).

This patch fixes up the incorrect region size, where
XLNX_ZYNQ_DEVCFG_R_MAX is missing its '/ 4' causing it to be 0x460 in
size. As well as setting the region size to the 0x0 - 0x100 region so
that an xadc device instance can be registered in the correct region to
pair with the devcfg device instance.

Mapping with XLNX_ZYNQ_DEVCFG_R_MAX = 0x118:
dev: xlnx.ps7-dev-cfg, id ""
mmio 00000000f8007000/0000000000000460
dev: xlnx,zynq-xadc, id ""
mmio 00000000f8007100/0000000000000020

Mapping with XLNX_ZYNQ_DEVCFG_R_MAX = 0x100 / 4:
dev: xlnx.ps7-dev-cfg, id ""
mmio 00000000f8007000/0000000000000100
dev: xlnx,zynq-xadc, id ""
mmio 00000000f8007100/0000000000000020

Signed-off-by: Nathan Rossi <nathan@nathanrossi.com>
Reviewed-by: Alistair Francis <alistair.francis@xilinx.com>
Message-id: 20160921180911.32289-1-nathan@nathanrossi.com
Signed-off-by: Peter Maydell <peter.maydell@linaro.org>
```

主要是解决 devcfg 和 xadc 设备地址映射范围重叠的问题，但是在 `xlnx_zynq_devcfg_init` 函数中，`register_init_block32` 时没有将 `XLNX_ZYNQ_DEVCFG_R_MAX` 乘以 4，导致 devcfg 实际创建的地址范围只有 0x40。

代码修改如下：

```c
// hw/dma/xlnx-zynq-devcfg.c:360
static void xlnx_zynq_devcfg_init(Object *obj)
{
    SysBusDevice *sbd = SYS_BUS_DEVICE(obj);
    XlnxZynqDevcfg *s = XLNX_ZYNQ_DEVCFG(obj);
    RegisterInfoArray *reg_array;

    sysbus_init_irq(sbd, &s->irq);

    memory_region_init(&s->iomem, obj, "devcfg", XLNX_ZYNQ_DEVCFG_R_MAX * 4);
    reg_array =
        register_init_block32(DEVICE(obj), xlnx_zynq_devcfg_regs_info,
                              ARRAY_SIZE(xlnx_zynq_devcfg_regs_info),
                              s->regs_info, s->regs,
                              &xlnx_zynq_devcfg_reg_ops,
                              XLNX_ZYNQ_DEVCFG_ERR_DEBUG,
                              XLNX_ZYNQ_DEVCFG_R_MAX); // 这里没有 x 4
}
```

我们修改 `register_init_block32` 函数最后一个参数修改为 `XLNX_ZYNQ_DEVCFG_R_MAX * 4` 即可。

## 总结

本文总结了 `ignore_memory_transaction_failures` 代码实现，以及如何废弃某些传统板卡中这个属性，替换成 `unimplemented_device`。

## 参考资料

- [qemu tcg 访存指令模拟][1]
- [boards.h: Define new flag ignore_memory_transaction_failures][2]

[1]: https://wangzhou.github.io/qemu-tcg%E8%AE%BF%E5%AD%98%E6%8C%87%E4%BB%A4%E6%A8%A1%E6%8B%9F/
[2]: https://lists.nongnu.org/archive/html/qemu-devel/2017-09/msg01643.html
