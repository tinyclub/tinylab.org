---
layout: post
author: 'ysyx_22040406-张炀杰'
title: 'QEMU 启动方式分析（1）：QEMU 及 RISC-V 启动流程简介'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /introduction-to-qemu-and-riscv-upstream-boot-flow/
description: 'QEMU 启动方式分析（1）：QEMU 及 RISC-V 启动流程简介'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [epw]
> Author:  YJMSTR <jay1273062855@outlook.com>
> Date:    2022/08/16
> Revisor: Bin Meng, Falcon
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor: PLCT Lab, ISCAS


使用软件版本如下：

> QEMU: v7.0.0
>
> OpenSBI: v1.1
>
> U-Boot: v2022.04
>
> Linux Kernel: v5.18

## QEMU 简介

### 什么是 QEMU

QEMU (Quick Emulator) 是一个开源的通用机器仿真器与虚拟化工具，主要支持以下使用方式：

- 用户模式仿真（User Mode Emulation）：在该仿真方式下，QEMU 可以在一种架构的 CPU 上运行为另一种架构的 CPU 编译的程序。
- 系统仿真（System Emulation）：在该仿真方式下，QEMU 提供运行客户机所需的完整环境，包括 CPU，内存和外围设备。

当使用 QEMU 模拟 RISC-V 架构时，QEMU 能够提供 `virt` 虚拟开发板，它不对应现实中的任何硬件，但它支持模拟多种硬件设备。在接下来分析 QEMU 的启动方式时，本系列文章均以 QEMU 'virt' 机器作为实验平台。Linux Lab 中也提供了 `riscv32/virt` 与 `riscv64/virt` 这两个虚拟开发板，可以用于 RISC-V 的学习。

### QEMU RISC-V 环境构建

Linux Lab 中集成了 QEMU，支持一键自动编译等功能，具体可以参考 [Linux Lab 官方手册][1]，当前的 Linux Lab 版本是 v1.0。

下载并构建支持 RISC-V 的 QEMU 的流程如下：

```bash
$ wget https://download.qemu.org/qemu-7.0.0.tar.xz
$ tar xvJf qemu-7.0.0.tar.xz
$ cd qemu-7.0.0
$ ./configure --target-list="riscv32-softmmu riscv64-softmmu"
$ make -j $(nproc)
$ make install
```

安装完成后在终端中输入 `qemu-system-riscv64 --version`，如果显示以下文字，则说明安装成功：

```bash
QEMU emulator version 7.0.0
Copyright (c) 2003-2022 Fabrice Bellard and the QEMU Project developers
```

## RISC-V 启动流程简介

如下图所示，RISC-V 引导流程分为多个阶段，我们重点关注 OpenSBI 与 U-Boot。

![RISC-V 引导流程图](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/bootflow.png)

### ZSBL

ZSBL (Zero Stage Boot Loader) 从 ROM 中获取核心代码。

### FSBL:U-Boot SPL

FSBL (First Stage Boot Loader) 由 Soc 指定，可能是 CoreBoot 或 U-Boot SPL。这一阶段将会完成 DDR 的初始化，并载入运行时环境（runtime）与引导加载器（bootloader）。

其中，U-Boot SPL 是一个非常小的 loader 程序，其主要功能是加载真正的 U-Boot 并运行。具体的加载过程可以参考 [RISC-V UEFI 架构支持详解，第 1 部分 - OpenSBI/U-Boot/UEFI 简介 - 泰晓科技（tinylab.org）][2] 中 U-Boot 相关部分。在编译 U-Boot 之前需要先编译 OpenSBI。

### Runtime:OpenSBI

RISC-V 的 Runtime 通常是 OpenSBI，它是运行在 M 模式下的程序，但能够为 S 模式提供一些特定的服务，这些服务由 SBI (Supervisor Binary Interface) 规范定义。

SBI 是指 Supervisor Binary Interface，它是运行在 M 模式下的程序，操作系统通过 SBI 来调用 M 模式的硬件资源。而 OpenSBI 是指西数开发的一种开源 SBI 实现。[RISC-V OpenSBI 快速上手 - 泰晓科技（tinylab.org）][3] 这篇文章给出了在 Linux Lab 中编译运行 OpenSBI 的教程。

OpenSBI 有三种 Firmware：

- FW_PAYLOAD：下一引导阶段被作为 payload 打包进来，通常是 U-Boot 或 Linux。这是兼容 Linux 的 RISC-V 硬件所使用的默认 firmware。
- FW_JUMP：跳转到一个固定地址，该地址上需存有下一个加载器。QEMU 的早期版本曾经使用过它。
- FW_DYNAMIC：根据前一个阶段传入的信息加载下一个阶段。通常是 U-Boot SPL 使用它。现在 QEMU 默认使用 FW_DYNAMIC。

下载并编译 OpenSBI 的流程如下：

```bash
$ git clone https://gitee.com/tinylab/qemu-opensbi.git
$ cd qemu-opensbi/
$ export CROSS_COMPILE=riscv64-linux-gnu-
$ make all PLATFORM=generic PLATFORM_RISCV_XLEN=64
```

其中 PLATFORM 选择 qemu_virt 所需的 generic 平台。

### Bootloader:U-Boot

Bootloader 是嵌入式系统在加电后执行的较为早期的代码，这段程序将会完成硬件的初始化与环境设置等操作，再将操作系统映像或嵌入式应用程序载入内存，然后跳转到操作系统所在空间，启动操作系统。

U-Boot 指 Universal Boot Loader，是一种流行的嵌入式 Linux 系统引导加载程序。它分为 U-Boot SPL 与 U-Boot 两部分，其中 SPL 指第二阶段程序加载器（Secondary Program Loader）。

U-Boot SPL 在之前的 "FSBL/U-Boot SPL" 小节已经介绍过，这里主要谈谈 U-Boot 本身。它被 U-Boot SPL 加载进内存后，将会发挥 Bootloader 的作用。在 [这篇文章][2] 中有对 U-Boot 加载过程以及代码的分析。

下载 U-Boot：

```bash
$ git clone https://gitee.com/mirrors/u-boot.git
$ cd u-boot
$ git checkout v2022.04
```

为了通过 U-Boot 启动 RISC-V 64 架构的 Linux，我们需要在编译时选择交叉编译工具链 riscv64-linux-gnu-gcc。在 U-Boot 目录下执行以下命令：

```bash
$ export CROSS_COMPILE=riscv64-linux-gnu-
$ make qemu-riscv64_smode_defconfig
$ make -j $(nproc)
```

如果想直接引导 S 模式下的 U-Boot 镜像，使用以下命令：

```bash
$ qemu-system-riscv64 -M virt -smp 4 -m 2G \
    -display none -serial stdio \
    -kernel /path/to/u-boot.bin
```

其中 `/path/to/u-boot.bin` 指之前编译出的 `u-boot.bin` 所在路径。

如需启动 U-Boot 或 Linux，需要在 OpenSBI 编译时指定 U-Boot 或 Linux 的 payload 路径。以 U-Boot 为例，切换到 OpenSBI 目录下，编译命令如下：

```bash
$ export CROSS_COMPILE=riscv64-linux-gnu-
$ make PLATFORM=generic FW_PAYLOAD_PATH=<uboot_build_directory>/u-boot.bin
```

运行：

```bash
$ qemu-system-riscv64 -M virt -m 256M -nographic \
	-bios build/platform/generic/firmware/fw_payload.elf
```

或是使用以下命令运行：

```bash
$ qemu-system-riscv64 -M virt -m 256M -nographic \
	-bios build/platform/generic/firmware/fw_jump.bin \
	-kernel <uboot_build_directory>/u-boot.bin
```

如果要使用 U-Boot SPL，使用如下命令：

```bash
$ export CROSS_COMPILE=riscv64-linux-gnu-
$ cd /path/to/u-boot
$ export OPENSBI=/path/to/opensbi/build/platform/generic/firmware/fw_dynamic.bin
$ make qemu-riscv64_spl_defconfig
$ make -j $(nproc)
$ qemu-system-riscv64 -M virt -smp 4 -m 2G \
    -display none -serial stdio \
    -bios /path/to/u-boot-spl \
    -device loader,file=/path/to/u-boot.itb,addr=0x80200000
```

### OS:Linux

编译内核需要使用交叉编译工具链。

在终端中执行以下命令：

```bash
$ mkdir linux-kernel
$ cd linux-kernel
$ git init
$ git fetch git@gitee.com:mirrors/linux_old1.git
// 如果断了，可以多次执行 git fetch，以便实现续传
$ git checkout v5.18
```

随后进行内核的配置与编译：

```bash
$ make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- defconfig
$ make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j $(nproc)
```

编译出的 kernel image 位于 `arch/riscv/boot/Image`.

随后我们用 busybox 构建根文件系统 rootfs，首先下载编译 busybox：

```bash
$ git clone https://gitee.com/mirrors/busyboxsource
$ cd busyboxsource
$ export CROSS_COMPILE=riscv64-linux-gnu-
$ make defconfig
$ make menuconfig
# 这里启用了 Settings-->Build Options 里的 Build static binary (no shared libs) 选项
$ make -j $(nproc)
$ make install
```

制作文件系统并新建一个启动脚本：

```bash
$ cd ~
$ qemu-img create rootfs.img 1g
$ mkfs.ext4 rootfs.img
$ mkdir rootfs
$ sudo mount -o loop rootfs.img rootfs
$ cd rootfs
$ sudo cp -r ../busyboxsource/_install/* .
$ sudo mkdir proc sys dev etc etc/init.d
$ cd etc/init.d/
$ sudo touch rcS
$ sudo vi rcS
```

编辑启动脚本 rcS 中的内容如下：

```shell
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
/sbin/mdev -s
```

并修改文件权限：

```bash
$ sudo chmod +x rcS
$ cd ~
$ sudo umount rootfs
```

随后尝试直接引导内核：

```bash
$ qemu-system-riscv64 -M virt -m 256M -nographic \
	-kernel linux-kernel/arch/riscv/boot/Image \
	-drive file=rootfs.img,format=raw,id=hd0  \
	-device virtio-blk-device,drive=hd0 \
	-append "root=/dev/vda rw console=ttyS0"
```

启动日志如下：

```bash
OpenSBI v1.0
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|____/_____|
        | |
        |_|

Platform Name             : riscv-virtio,qemu
Platform Features         : medeleg
Platform HART Count       : 1
Platform IPI Device       : aclint-mswi
Platform Timer Device     : aclint-mtimer @ 10000000Hz
Platform Console Device   : uart8250
Platform HSM Device       : ---
Platform Reboot Device    : sifive_test
Platform Shutdown Device  : sifive_test
Firmware Base             : 0x80000000
Firmware Size             : 252 KB
Runtime SBI Version       : 0.3

Domain0 Name              : root
Domain0 Boot HART         : 0
Domain0 HARTs             : 0*
Domain0 Region00          : 0x0000000002000000-0x000000000200ffff (I)
Domain0 Region01          : 0x0000000080000000-0x000000008003ffff ()
Domain0 Region02          : 0x0000000000000000-0xffffffffffffffff (R,W,X)
Domain0 Next Address      : 0x0000000080200000
Domain0 Next Arg1         : 0x000000008f000000
Domain0 Next Mode         : S-mode
Domain0 SysReset          : yes

Boot HART ID              : 0
Boot HART Domain          : root
Boot HART ISA             : rv64imafdcsuh
Boot HART Features        : scounteren,mcounteren,time
Boot HART PMP Count       : 16
Boot HART PMP Granularity : 4
Boot HART PMP Address Bits: 54
Boot HART MHPM Count      : 0
Boot HART MIDELEG         : 0x0000000000001666
Boot HART MEDELEG         : 0x0000000000f0b509
[    0.000000] Linux version 5.18.0 (yjmstr@yjmstr) (riscv64-linux-gnu-gcc (Ubuntu 11.2.0-16ubuntu1) 11.2.0, GNU ld (GNU Binutils for Ubuntu) 2.38) #2 SMP Sun Aug 14 13:14:26 CST 2022
[    0.000000] OF: fdt: Ignoring memory range 0x80000000 - 0x80200000
[    0.000000] Machine model: riscv-virtio,qemu
[    0.000000] efi: UEFI not found.
[    0.000000] Zone ranges:
[    0.000000]   DMA32    [mem 0x0000000080200000-0x000000008fffffff]
[    0.000000]   Normal   empty
[    0.000000] Movable zone start for each node
[    0.000000] Early memory node ranges
[    0.000000]   node   0: [mem 0x0000000080200000-0x000000008fffffff]
[    0.000000] Initmem setup node 0 [mem 0x0000000080200000-0x000000008fffffff]
[    0.000000] SBI specification v0.3 detected
[    0.000000] SBI implementation ID=0x1 Version=0x10000
[    0.000000] SBI TIME extension detected
[    0.000000] SBI IPI extension detected
[    0.000000] SBI RFENCE extension detected
[    0.000000] SBI SRST extension detected
[    0.000000] SBI HSM extension detected
[    0.000000] riscv: base ISA extensions acdfhim
[    0.000000] riscv: ELF capabilities acdfim
[    0.000000] percpu: Embedded 18 pages/cpu s34040 r8192 d31496 u73728
[    0.000000] Built 1 zonelists, mobility grouping on.  Total pages: 64135
[    0.000000] Kernel command line: root=/dev/vda rw console=ttyS0
[    0.000000] Dentry cache hash table entries: 32768 (order: 6, 262144 bytes, linear)
[    0.000000] Inode-cache hash table entries: 16384 (order: 5, 131072 bytes, linear)
[    0.000000] mem auto-init: stack:off, heap alloc:off, heap free:off
[    0.000000] Virtual kernel memory layout:
[    0.000000]       fixmap : 0xff1bfffffee00000 - 0xff1bffffff000000   (2048 kB)
[    0.000000]       pci io : 0xff1bffffff000000 - 0xff1c000000000000   (  16 MB)
[    0.000000]      vmemmap : 0xff1c000000000000 - 0xff20000000000000   (1073741824 MB)
[    0.000000]      vmalloc : 0xff20000000000000 - 0xff60000000000000   (17179869184 MB)
[    0.000000]       lowmem : 0xff60000000000000 - 0xff6000000fe00000   ( 254 MB)
[    0.000000]       kernel : 0xffffffff80000000 - 0xffffffffffffffff   (2047 MB)
[    0.000000] Memory: 237564K/260096K available (6460K kernel code, 4865K rwdata, 2048K rodata, 2165K init, 334K bss, 22532K reserved, 0K cma-reserved)
[    0.000000] SLUB: HWalign=64, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
[    0.000000] rcu: Hierarchical RCU implementation.
[    0.000000] rcu: 	RCU restricting CPUs from NR_CPUS=8 to nr_cpu_ids=1.
[    0.000000] rcu: 	RCU debug extended QS entry/exit.
[    0.000000] 	Tracing variant of Tasks RCU enabled.
[    0.000000] rcu: RCU calculated value of scheduler-enlistment delay is 25 jiffies.
[    0.000000] rcu: Adjusting geometry for rcu_fanout_leaf=16, nr_cpu_ids=1
[    0.000000] NR_IRQS: 64, nr_irqs: 64, preallocated irqs: 0
[    0.000000] riscv-intc: 64 local interrupts mapped
[    0.000000] plic: plic@c000000: mapped 53 interrupts with 1 handlers for 2 contexts.
[    0.000000] random: get_random_bytes called from start_kernel+0x4be/0x71a with crng_init=0
[    0.000000] riscv_timer_init_dt: Registering clocksource cpuid [0] hartid [0]
[    0.000000] clocksource: riscv_clocksource: mask: 0xffffffffffffffff max_cycles: 0x24e6a1710, max_idle_ns: 440795202120 ns
[    0.000110] sched_clock: 64 bits at 10MHz, resolution 100ns, wraps every 4398046511100ns
[    0.005548] Console: colour dummy device 80x25
[    0.010694] Calibrating delay loop (skipped), value calculated using timer frequency.. 20.00 BogoMIPS (lpj=40000)
[    0.010903] pid_max: default: 32768 minimum: 301
[    0.014081] Mount-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[    0.014137] Mountpoint-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[    0.045919] cblist_init_generic: Setting adjustable number of callback queues.
[    0.046122] cblist_init_generic: Setting shift to 0 and lim to 1.
[    0.046833] ASID allocator using 16 bits (65536 entries)
[    0.048191] rcu: Hierarchical SRCU implementation.
[    0.050214] EFI services will not be available.
[    0.052914] smp: Bringing up secondary CPUs ...
[    0.053035] smp: Brought up 1 node, 1 CPU
[    0.064892] devtmpfs: initialized
[    0.072338] clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785100000 ns
[    0.072854] futex hash table entries: 256 (order: 2, 16384 bytes, linear)
[    0.078634] NET: Registered PF_NETLINK/PF_ROUTE protocol family
[    0.084802] cpuidle: using governor menu
[    0.116094] HugeTLB registered 2.00 MiB page size, pre-allocated 0 pages
[    0.121303] iommu: Default domain type: Translated
[    0.121359] iommu: DMA domain TLB invalidation policy: strict mode
[    0.122808] SCSI subsystem initialized
[    0.124731] usbcore: registered new interface driver usbfs
[    0.125085] usbcore: registered new interface driver hub
[    0.125244] usbcore: registered new device driver usb
[    0.139845] vgaarb: loaded
[    0.141481] clocksource: Switched to clocksource riscv_clocksource
[    0.160052] NET: Registered PF_INET protocol family
[    0.161357] IP idents hash table entries: 4096 (order: 3, 32768 bytes, linear)
[    0.165568] tcp_listen_portaddr_hash hash table entries: 128 (order: 0, 5120 bytes, linear)
[    0.165859] TCP established hash table entries: 2048 (order: 2, 16384 bytes, linear)
[    0.166095] TCP bind hash table entries: 2048 (order: 4, 65536 bytes, linear)
[    0.166331] TCP: Hash tables configured (established 2048 bind 2048)
[    0.168312] UDP hash table entries: 256 (order: 2, 24576 bytes, linear)
[    0.168666] UDP-Lite hash table entries: 256 (order: 2, 24576 bytes, linear)
[    0.170129] NET: Registered PF_UNIX/PF_LOCAL protocol family
[    0.173256] RPC: Registered named UNIX socket transport module.
[    0.173403] RPC: Registered udp transport module.
[    0.173427] RPC: Registered tcp transport module.
[    0.173453] RPC: Registered tcp NFSv4.1 backchannel transport module.
[    0.173613] PCI: CLS 0 bytes, default 64
[    0.180799] workingset: timestamp_bits=62 max_order=16 bucket_order=0
[    0.195702] NFS: Registering the id_resolver key type
[    0.196803] Key type id_resolver registered
[    0.196859] Key type id_legacy registered
[    0.197434] nfs4filelayout_init: NFSv4 File Layout Driver Registering...
[    0.197557] nfs4flexfilelayout_init: NFSv4 Flexfile Layout Driver Registering...
[    0.198259] 9p: Installing v9fs 9p2000 file system support
[    0.199780] NET: Registered PF_ALG protocol family
[    0.200339] Block layer SCSI generic (bsg) driver version 0.4 loaded (major 250)
[    0.200507] io scheduler mq-deadline registered
[    0.200597] io scheduler kyber registered
[    0.210780] pci-host-generic 30000000.pci: host bridge /soc/pci@30000000 ranges:
[    0.211790] pci-host-generic 30000000.pci:       IO 0x0003000000..0x000300ffff -> 0x0000000000
[    0.212339] pci-host-generic 30000000.pci:      MEM 0x0040000000..0x007fffffff -> 0x0040000000
[    0.212418] pci-host-generic 30000000.pci:      MEM 0x0400000000..0x07ffffffff -> 0x0400000000
[    0.213009] pci-host-generic 30000000.pci: Memory resource size exceeds max for 32 bits
[    0.214178] pci-host-generic 30000000.pci: ECAM at [mem 0x30000000-0x3fffffff] for [bus 00-ff]
[    0.215635] pci-host-generic 30000000.pci: PCI host bridge to bus 0000:00
[    0.215922] pci_bus 0000:00: root bus resource [bus 00-ff]
[    0.216027] pci_bus 0000:00: root bus resource [io  0x0000-0xffff]
[    0.216104] pci_bus 0000:00: root bus resource [mem 0x40000000-0x7fffffff]
[    0.216122] pci_bus 0000:00: root bus resource [mem 0x400000000-0x7ffffffff]
[    0.217645] pci 0000:00:00.0: [1b36:0008] type 00 class 0x060000
[    0.293879] Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
[    0.302601] printk: console [ttyS0] disabled
[    0.304582] 10000000.uart: ttyS0 at MMIO 0x10000000 (irq = 2, base_baud = 230400) is a 16550A
[    0.327092] printk: console [ttyS0] enabled
[    0.343852] loop: module loaded
[    0.347926] virtio_blk virtio0: [vda] 2097152 512-byte logical blocks (1.07 GB/1.00 GiB)
[    0.372012] e1000e: Intel(R) PRO/1000 Network Driver
[    0.372155] e1000e: Copyright(c) 1999 - 2015 Intel Corporation.
[    0.372587] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[    0.372811] ehci-pci: EHCI PCI platform driver
[    0.373121] ehci-platform: EHCI generic platform driver
[    0.373489] ohci_hcd: USB 1.1 'Open' Host Controller (OHCI) Driver
[    0.373714] ohci-pci: OHCI PCI platform driver
[    0.374048] ohci-platform: OHCI generic platform driver
[    0.375168] usbcore: registered new interface driver uas
[    0.375509] usbcore: registered new interface driver usb-storage
[    0.376576] mousedev: PS/2 mouse device common for all mice
[    0.380046] goldfish_rtc 101000.rtc: registered as rtc0
[    0.380819] goldfish_rtc 101000.rtc: setting system clock to 2022-08-19T12:22:18 UTC (1660911738)
[    0.383918] syscon-poweroff soc:poweroff: pm_power_off already claimed for sbi_srst_power_off
[    0.384279] syscon-poweroff: probe of soc:poweroff failed with error -16
[    0.385888] sdhci: Secure Digital Host Controller Interface driver
[    0.386097] sdhci: Copyright(c) Pierre Ossman
[    0.386425] sdhci-pltfm: SDHCI platform and OF driver helper
[    0.387522] usbcore: registered new interface driver usbhid
[    0.387713] usbhid: USB HID core driver
[    0.388131] riscv-pmu-sbi: SBI PMU extension is available
[    0.388784] riscv-pmu-sbi: 15 firmware and 2 hardware counters
[    0.389008] riscv-pmu-sbi: Perf sampling/filtering is not supported as sscof extension is not available
[    0.393847] NET: Registered PF_INET6 protocol family
[    0.400899] Segment Routing with IPv6
[    0.401209] In-situ OAM (IOAM) with IPv6
[    0.401878] sit: IPv6, IPv4 and MPLS over IPv4 tunneling driver
[    0.405085] NET: Registered PF_PACKET protocol family
[    0.406670] 9pnet: Installing 9P2000 support
[    0.407129] Key type dns_resolver registered
[    0.409166] debug_vm_pgtable: [debug_vm_pgtable         ]: Validating architecture page table helpers
[    0.473625] EXT4-fs (vda): mounted filesystem with ordered data mode. Quota mode: disabled.
[    0.474143] VFS: Mounted root (ext4 filesystem) on device 254:0.
[    0.477311] devtmpfs: mounted
[    0.507212] Freeing unused kernel image (initmem) memory: 2164K
[    0.508186] Run /sbin/init as init process

Please press Enter to activate this console.

```

可以看见打印出的启动信息中的 OpenSBI 版本是 v1.0，这是 QEMU v7.0.0 自带的 OpenSBI 版本。根据 QEMU 官方文档，当没有 `-bios` 这一启动参数时，QEMU 将会加载自带的 OpenSBI firmware。而当使用 `-bios none` 作为启动参数时，QEMU 就不会自动加载任何 firmware。当使用 `-bios <file>` 指定了特定文件作为 firmware 时，QEMU 就会加载我们指定的那个 firmware。

使用我们自己编译的 OpenSBI 引导内核的命令如下：

```bash
$ qemu-system-riscv64 -M virt -m 256M -nographic \
	-bios qemu-opensbi/build/platform/generic/firmware/fw_jump.bin \
	-kernel linux-kernel/arch/riscv/boot/Image \
	-drive file=rootfs.img,format=raw,id=hd0 \
	-device virtio-blk-device,drive=hd0 \
	-append "root=/dev/vda rw console=ttyS0"
```

此处通过 `-bios` 参数指定了 OpenSBI 编译出的 fw_jump 类型的 firmware。启动日志如下：

```bash
OpenSBI v1.1
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|____/_____|
        | |
        |_|

Platform Name             : riscv-virtio,qemu
Platform Features         : medeleg
Platform HART Count       : 1
Platform IPI Device       : aclint-mswi
Platform Timer Device     : aclint-mtimer @ 10000000Hz
Platform Console Device   : uart8250
Platform HSM Device       : ---
Platform Reboot Device    : sifive_test
Platform Shutdown Device  : sifive_test
Firmware Base             : 0x80000000
Firmware Size             : 288 KB
Runtime SBI Version       : 1.0

Domain0 Name              : root
Domain0 Boot HART         : 0
Domain0 HARTs             : 0*
Domain0 Region00          : 0x0000000002000000-0x000000000200ffff (I)
Domain0 Region01          : 0x0000000080000000-0x000000008007ffff ()
Domain0 Region02          : 0x0000000000000000-0xffffffffffffffff (R,W,X)
Domain0 Next Address      : 0x0000000080200000
Domain0 Next Arg1         : 0x0000000082200000
Domain0 Next Mode         : S-mode
Domain0 SysReset          : yes

Boot HART ID              : 0
Boot HART Domain          : root
Boot HART Priv Version    : v1.10
Boot HART Base ISA        : rv64imafdch
Boot HART ISA Extensions  : time
Boot HART PMP Count       : 16
Boot HART PMP Granularity : 4
Boot HART PMP Address Bits: 54
Boot HART MHPM Count      : 0
Boot HART MIDELEG         : 0x0000000000001666
Boot HART MEDELEG         : 0x0000000000f0b509
[    0.000000] Linux version 5.18.0 (yjmstr@yjmstr) (riscv64-linux-gnu-gcc (Ubuntu 11.2.0-16ubuntu1) 11.2.0, GNU ld (GNU Binutils for Ubuntu) 2.38) #2 SMP Sun Aug 14 13:14:26 CST 2022
[    0.000000] OF: fdt: Ignoring memory range 0x80000000 - 0x80200000
[    0.000000] Machine model: riscv-virtio,qemu
[    0.000000] efi: UEFI not found.
[    0.000000] Zone ranges:
[    0.000000]   DMA32    [mem 0x0000000080200000-0x000000008fffffff]
[    0.000000]   Normal   empty
[    0.000000] Movable zone start for each node
[    0.000000] Early memory node ranges
[    0.000000]   node   0: [mem 0x0000000080200000-0x000000008fffffff]
[    0.000000] Initmem setup node 0 [mem 0x0000000080200000-0x000000008fffffff]
[    0.000000] SBI specification v1.0 detected
[    0.000000] SBI implementation ID=0x1 Version=0x10001
[    0.000000] SBI TIME extension detected
[    0.000000] SBI IPI extension detected
[    0.000000] SBI RFENCE extension detected
[    0.000000] SBI SRST extension detected
[    0.000000] SBI HSM extension detected
[    0.000000] riscv: base ISA extensions acdfhim
[    0.000000] riscv: ELF capabilities acdfim
[    0.000000] percpu: Embedded 18 pages/cpu s34040 r8192 d31496 u73728
[    0.000000] Built 1 zonelists, mobility grouping on.  Total pages: 64135
[    0.000000] Kernel command line: root=/dev/vda rw console=ttyS0
[    0.000000] Dentry cache hash table entries: 32768 (order: 6, 262144 bytes, linear)
[    0.000000] Inode-cache hash table entries: 16384 (order: 5, 131072 bytes, linear)
[    0.000000] mem auto-init: stack:off, heap alloc:off, heap free:off
[    0.000000] Virtual kernel memory layout:
[    0.000000]       fixmap : 0xff1bfffffee00000 - 0xff1bffffff000000   (2048 kB)
[    0.000000]       pci io : 0xff1bffffff000000 - 0xff1c000000000000   (  16 MB)
[    0.000000]      vmemmap : 0xff1c000000000000 - 0xff20000000000000   (1073741824 MB)
[    0.000000]      vmalloc : 0xff20000000000000 - 0xff60000000000000   (17179869184 MB)
[    0.000000]       lowmem : 0xff60000000000000 - 0xff6000000fe00000   ( 254 MB)
[    0.000000]       kernel : 0xffffffff80000000 - 0xffffffffffffffff   (2047 MB)
[    0.000000] Memory: 237564K/260096K available (6460K kernel code, 4865K rwdata, 2048K rodata, 2165K init, 334K bss, 22532K reserved, 0K cma-reserved)
[    0.000000] SLUB: HWalign=64, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
[    0.000000] rcu: Hierarchical RCU implementation.
[    0.000000] rcu: 	RCU restricting CPUs from NR_CPUS=8 to nr_cpu_ids=1.
[    0.000000] rcu: 	RCU debug extended QS entry/exit.
[    0.000000] 	Tracing variant of Tasks RCU enabled.
[    0.000000] rcu: RCU calculated value of scheduler-enlistment delay is 25 jiffies.
[    0.000000] rcu: Adjusting geometry for rcu_fanout_leaf=16, nr_cpu_ids=1
[    0.000000] NR_IRQS: 64, nr_irqs: 64, preallocated irqs: 0
[    0.000000] riscv-intc: 64 local interrupts mapped
[    0.000000] plic: plic@c000000: mapped 53 interrupts with 1 handlers for 2 contexts.
[    0.000000] random: get_random_bytes called from start_kernel+0x4be/0x71a with crng_init=0
[    0.000000] riscv_timer_init_dt: Registering clocksource cpuid [0] hartid [0]
[    0.000000] clocksource: riscv_clocksource: mask: 0xffffffffffffffff max_cycles: 0x24e6a1710, max_idle_ns: 440795202120 ns
[    0.000111] sched_clock: 64 bits at 10MHz, resolution 100ns, wraps every 4398046511100ns
[    0.005518] Console: colour dummy device 80x25
[    0.010392] Calibrating delay loop (skipped), value calculated using timer frequency.. 20.00 BogoMIPS (lpj=40000)
[    0.010596] pid_max: default: 32768 minimum: 301
[    0.013666] Mount-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[    0.013719] Mountpoint-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[    0.045715] cblist_init_generic: Setting adjustable number of callback queues.
[    0.045930] cblist_init_generic: Setting shift to 0 and lim to 1.
[    0.046678] ASID allocator using 16 bits (65536 entries)
[    0.047947] rcu: Hierarchical SRCU implementation.
[    0.050035] EFI services will not be available.
[    0.052640] smp: Bringing up secondary CPUs ...
[    0.052761] smp: Brought up 1 node, 1 CPU
[    0.064569] devtmpfs: initialized
[    0.072062] clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785100000 ns
[    0.072424] futex hash table entries: 256 (order: 2, 16384 bytes, linear)
[    0.078307] NET: Registered PF_NETLINK/PF_ROUTE protocol family
[    0.084426] cpuidle: using governor menu
[    0.114553] HugeTLB registered 2.00 MiB page size, pre-allocated 0 pages
[    0.120275] iommu: Default domain type: Translated
[    0.120336] iommu: DMA domain TLB invalidation policy: strict mode
[    0.121627] SCSI subsystem initialized
[    0.123678] usbcore: registered new interface driver usbfs
[    0.124019] usbcore: registered new interface driver hub
[    0.124451] usbcore: registered new device driver usb
[    0.138626] vgaarb: loaded
[    0.140390] clocksource: Switched to clocksource riscv_clocksource
[    0.159138] NET: Registered PF_INET protocol family
[    0.160529] IP idents hash table entries: 4096 (order: 3, 32768 bytes, linear)
[    0.164755] tcp_listen_portaddr_hash hash table entries: 128 (order: 0, 5120 bytes, linear)
[    0.165042] TCP established hash table entries: 2048 (order: 2, 16384 bytes, linear)
[    0.165279] TCP bind hash table entries: 2048 (order: 4, 65536 bytes, linear)
[    0.165513] TCP: Hash tables configured (established 2048 bind 2048)
[    0.167469] UDP hash table entries: 256 (order: 2, 24576 bytes, linear)
[    0.167823] UDP-Lite hash table entries: 256 (order: 2, 24576 bytes, linear)
[    0.169282] NET: Registered PF_UNIX/PF_LOCAL protocol family
[    0.172534] RPC: Registered named UNIX socket transport module.
[    0.172606] RPC: Registered udp transport module.
[    0.172627] RPC: Registered tcp transport module.
[    0.172642] RPC: Registered tcp NFSv4.1 backchannel transport module.
[    0.172794] PCI: CLS 0 bytes, default 64
[    0.180445] workingset: timestamp_bits=62 max_order=16 bucket_order=0
[    0.194614] NFS: Registering the id_resolver key type
[    0.195717] Key type id_resolver registered
[    0.195772] Key type id_legacy registered
[    0.196382] nfs4filelayout_init: NFSv4 File Layout Driver Registering...
[    0.196504] nfs4flexfilelayout_init: NFSv4 Flexfile Layout Driver Registering...
[    0.197282] 9p: Installing v9fs 9p2000 file system support
[    0.198830] NET: Registered PF_ALG protocol family
[    0.199384] Block layer SCSI generic (bsg) driver version 0.4 loaded (major 250)
[    0.199551] io scheduler mq-deadline registered
[    0.199638] io scheduler kyber registered
[    0.211458] pci-host-generic 30000000.pci: host bridge /soc/pci@30000000 ranges:
[    0.212538] pci-host-generic 30000000.pci:       IO 0x0003000000..0x000300ffff -> 0x0000000000
[    0.213088] pci-host-generic 30000000.pci:      MEM 0x0040000000..0x007fffffff -> 0x0040000000
[    0.213169] pci-host-generic 30000000.pci:      MEM 0x0400000000..0x07ffffffff -> 0x0400000000
[    0.213761] pci-host-generic 30000000.pci: Memory resource size exceeds max for 32 bits
[    0.214890] pci-host-generic 30000000.pci: ECAM at [mem 0x30000000-0x3fffffff] for [bus 00-ff]
[    0.216401] pci-host-generic 30000000.pci: PCI host bridge to bus 0000:00
[    0.216695] pci_bus 0000:00: root bus resource [bus 00-ff]
[    0.216802] pci_bus 0000:00: root bus resource [io  0x0000-0xffff]
[    0.216882] pci_bus 0000:00: root bus resource [mem 0x40000000-0x7fffffff]
[    0.216900] pci_bus 0000:00: root bus resource [mem 0x400000000-0x7ffffffff]
[    0.218331] pci 0000:00:00.0: [1b36:0008] type 00 class 0x060000
[    0.294377] Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
[    0.303136] printk: console [ttyS0] disabled
[    0.305194] 10000000.uart: ttyS0 at MMIO 0x10000000 (irq = 2, base_baud = 230400) is a 16550A
[    0.331363] printk: console [ttyS0] enabled
[    0.348432] loop: module loaded
[    0.352537] virtio_blk virtio0: [vda] 2097152 512-byte logical blocks (1.07 GB/1.00 GiB)
[    0.376684] e1000e: Intel(R) PRO/1000 Network Driver
[    0.376828] e1000e: Copyright(c) 1999 - 2015 Intel Corporation.
[    0.377400] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[    0.377758] ehci-pci: EHCI PCI platform driver
[    0.378200] ehci-platform: EHCI generic platform driver
[    0.378530] ohci_hcd: USB 1.1 'Open' Host Controller (OHCI) Driver
[    0.378801] ohci-pci: OHCI PCI platform driver
[    0.379167] ohci-platform: OHCI generic platform driver
[    0.380468] usbcore: registered new interface driver uas
[    0.380919] usbcore: registered new interface driver usb-storage
[    0.382100] mousedev: PS/2 mouse device common for all mice
[    0.385879] goldfish_rtc 101000.rtc: registered as rtc0
[    0.386647] goldfish_rtc 101000.rtc: setting system clock to 2022-08-19T12:20:44 UTC (1660911644)
[    0.389614] syscon-poweroff soc:poweroff: pm_power_off already claimed for sbi_srst_power_off
[    0.389962] syscon-poweroff: probe of soc:poweroff failed with error -16
[    0.391492] sdhci: Secure Digital Host Controller Interface driver
[    0.391720] sdhci: Copyright(c) Pierre Ossman
[    0.392087] sdhci-pltfm: SDHCI platform and OF driver helper
[    0.393373] usbcore: registered new interface driver usbhid
[    0.393604] usbhid: USB HID core driver
[    0.394074] riscv-pmu-sbi: SBI PMU extension is available
[    0.394764] riscv-pmu-sbi: 16 firmware and 2 hardware counters
[    0.395033] riscv-pmu-sbi: Perf sampling/filtering is not supported as sscof extension is not available
[    0.399865] NET: Registered PF_INET6 protocol family
[    0.407267] Segment Routing with IPv6
[    0.407649] In-situ OAM (IOAM) with IPv6
[    0.408329] sit: IPv6, IPv4 and MPLS over IPv4 tunneling driver
[    0.411565] NET: Registered PF_PACKET protocol family
[    0.413200] 9pnet: Installing 9P2000 support
[    0.413775] Key type dns_resolver registered
[    0.415916] debug_vm_pgtable: [debug_vm_pgtable         ]: Validating architecture page table helpers
[    0.504662] EXT4-fs (vda): mounted filesystem with ordered data mode. Quota mode: disabled.
[    0.505310] VFS: Mounted root (ext4 filesystem) on device 254:0.
[    0.529887] devtmpfs: mounted
[    0.559745] Freeing unused kernel image (initmem) memory: 2164K
[    0.560852] Run /sbin/init as init process

Please press Enter to activate this console.

```

可以看见打印出的启动信息中 OpenSBI 版本是 v1.1，这是我们自行编译的 OpenSBI 版本。

## 总结

本文简要介绍了 RISC-V 的启动流程，QEMU 'virt' 平台下 OpenSBI 和 U-Boot 的简单使用，根文件系统的制作和 Linux 内核的引导，并分析了 QEMU 启动参数有无 `-bios` 时的不同行为。接下来的文章我们将探索如何通过 U-Boot 来引导和加载 Linux 内核，并结合 QEMU 'virt' 分析 ZSBL 阶段的行为。

## 参考资料

1. [Linux Lab 官方手册][1]
2. [RISC-V UEFI 架构支持详解，第 1 部分 - OpenSBI/U-Boot/UEFI 简介][2]
3. [RISC-V OpenSBI 快速上手][3]
4. [QEMU 官方文档][4]
5. [在泰晓 Linux 实验盘中构建 QEMU 并引导 openEuler for RISC-V][5]
6. [在 QEMU 上运行 RISC-V 64 位版本的 Linux][6]
7. [RISC-V 启动流程][7]
8. [RISC-V SBI 官方文档][8]
9. [OpenSBI Gitee 镜像][9]
10. [用 U-boot 来引导 riscv-linux kernel][10]
11. [QEMU 6.1.0 运行 RISCV64 OpenSBI + U-Boot + Linux][11]
12. [Booting RISC-V on QEMU][12]
13. [构建 RISC-V 上运行的 Linux 系统][13]

[1]: https://tinylab.org/pdfs/linux-lab-v1.0-manual-zh.pdf
[2]: https://tinylab.org/riscv-uefi-part1/
[3]: https://tinylab.org/riscv-opensbi-quickstart/
[4]: https://www.qemu.org/docs/master/
[5]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220718-build-qemu-and-boot-openeuler-for-risc-v-in-tinylab-linux-lab-disk.md
[6]: https://zhuanlan.zhihu.com/p/258394849
[7]: https://riscv.org/wp-content/uploads/2019/12/Summit_bootflow.pdf
[8]: https://github.com/riscv-non-isa/riscv-sbi-doc
[9]: https://gitee.com/mirrors/OpenSBI
[10]: https://blog.csdn.net/wangyijieonline/article/details/104843769
[11]: https://blog.csdn.net/qq_41957544/article/details/120667695
[12]: https://jborza.com/emulation/2021/04/03/running-riscv-qemu.html
[13]: https://segmentfault.com/a/1190000038317909
