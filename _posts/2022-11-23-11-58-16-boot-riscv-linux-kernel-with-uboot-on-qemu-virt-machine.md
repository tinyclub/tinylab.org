---
layout: post
author: 'ysyx_22040406-张炀杰'
title: 'QEMU 启动方式分析（2）: QEMU virt 平台下通过 OpenSBI + U-Boot 引导 RISCV64 Linux Kernel'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /boot-riscv-linux-kernel-with-uboot-on-qemu-virt-machine/
description: 'QEMU 启动方式分析（2）: QEMU virt 平台下通过 OpenSBI + U-Boot 引导 RISCV64 Linux Kernel'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [quotes header codeblock codeinline]
> Author:  YJMSTR <jay1273062855@outlook.com>
> Date:    2022/08/23
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

## 前言

在上一篇文章中，我们简要介绍了 RISC-V 的启动流程，并给出了在 QEMU RISCV 'virt' 平台下直接引导 Linux 内核以及使用 OpenSBI 引导 Linux 内核的步骤。本文将进一步在该平台下通过 U-Boot 与 OpenSBI 引导 Linux 内核，并简要介绍 QEMU 与 U-Boot 的相关命令与参数。

## 前期准备

这部分内容与 [本系列上一篇文章][3] 一致，不同之处在于制作根文件系统时需要将编译出的内核文件复制进来。

按如下命令下载并编译 OpenSBI：

```bash
$ git clone https://gitee.com/tinylab/qemu-opensbi.git
$ cd qemu-opensbi/
$ export CROSS_COMPILE=riscv64-linux-gnu-
$ make all PLATFORM=generic PLATFORM_RISCV_XLEN=64
```

按如下命令下载并编译 U-Boot：

```bash
$ git clone https://gitee.com/mirrors/u-boot.git
$ cd u-boot
$ git checkout v2022.04
$ export CROSS_COMPILE=riscv64-linux-gnu-
$ make qemu-riscv64_smode_defconfig
$ make -j $(nproc)
```

按如下命令编译内核：

```bash
$ make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- defconfig
$ make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j $(nproc)
```

使用 Busybox 制作根文件系统，将编译内核时编译出的 Kernel Image 也复制进来：

```bash
$ git clone https://gitee.com/mirrors/busyboxsource
$ cd busyboxsource
$ export CROSS_COMPILE=riscv64-linux-gnu-
$ make defconfig
$ make menuconfig
# 这里启用了 Settings-->Build Options 里的 Build static binary (no shared libs) 选项
$ make -j $(nproc)
$ make install
$ cd ~
$ qemu-img create rootfs.img 1g
$ mkfs.ext4 rootfs.img
$ mkdir rootfs
$ sudo mount -o loop rootfs.img rootfs
$ cd rootfs
$ sudo cp -r ../busyboxsource/_install/* .
$ sudo cp /path/to/Image .
$ sudo mkdir proc sys dev etc etc/init.d
$ cd etc/init.d/
$ sudo touch rcS
$ sudo vi rcS
```

编辑启动脚本 rcS 中的内容如下：

```
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

## 引导内核

QEMU 启动命令：

```bash
$ qemu-system-riscv64 -M virt -m 256M -nographic \
	-bios qemu-opensbi/build/platform/generic/firmware/fw_jump.bin \
	-kernel u-boot/u-boot-nodtb.bin \
	-drive file=rootfs.img,format=raw,id=hd0 \
	-device virtio-blk-device,drive=hd0 \
	-append "root=/dev/vda rw console=ttyS0"
```

最后在 U-Boot 中输入：

```
=> load virtio 0 0x80200000 \Image
=> booti 0x80200000 - $fdtcontroladdr
```

即可启动内核。

此处 `load` 命令的作用是从文件系统中读取一个二进制文件。在 U-Boot 中键入 `help load`，参考其帮助文档可知：命令 `load virtio 0 0x80200000 \Image` 表示从 `virtio` 类型的第 `0` 号设备的根目录中读取名为 `Image` 的文件到内存的 0x80200000 地址处。若我们在制作文件系统时进行了分区，则需要在设备号后通过 `:` 连接分区编号，以进一步指明从哪个分区中读取文件。由于我们需要加载整个 `\Image` 文件，故此处忽略 `bytes` 和 `pos` 参数。

`booti` 命令用于从内存中读取 `Image` 类型的内核文件。在 U-Boot 中键入 `help booti`，参考其帮助文档可知，命令 `booti 0x80200000 - $fdtcontroladdr` 的含义是引导存放于内存 0x80200000 处的内核文件，并加载位于 `$fdtcontroladdr` 处的设备树二进制文件（device tree blob，缩写为 dtb）。由于我们没有使用 initrd，而是使用了 `/dev/sda`，因此中间的 `initrd[:size]` 参数使用 `-` 忽略。

参数 `fdt` 用于指定 dtb 的地址，此处将其设置为了变量 `fdtcontroladdr` 的值。该变量表示 U-Boot 自身的 dtb 地址。

在 `/path/to/u-boot/doc/usage/environment.rst` 中，对其的描述如下：

> fdtcontroladdr
> if set this is the address of the control flattened
>   	device tree used by U-Boot when CONFIG_OF_CONTROL is
>   	defined.

当启用了 `CONFIG_OF_CONTROL` 选项后，`fdtcontroladdr` 将作为 U-Boot 内置的设备树地址。在编译 U-Boot 时所选择的配置文件 `qemu-riscv64_smode_defconfig` 中，有这么一行代码：

```
CONFIG_PREBOOT="setenv fdt_addr ${fdtcontroladdr}; fdt addr ${fdtcontroladdr};"
```

其将设备树地址设为 `$fdtcontroladdr`，并通过 `fdt addr` 命令将传递给操作系统的设备树地址设为 `$fdtcontroladdr`。[U-Boot 官方文档][4] 中对于 `fdt addr` 的描述如下：

> The working FDT is the one passed to the Operating System when booting. This can be freely modified, so far as U-Boot is concerned, since it does not affect U-Boot’s operation.
>
> ...
>
> If the addr argument is provided, then this sets the address of the working or control FDT to the provided address.

在 U-Boot 中，除 `booti` 外，用于引导内核的命令还有：

- `bootm`: 从内存中加载应用程序镜像。在使用其引导需要扁平设备树的 Linux 内核时，也需要提供 dtb 地址。可以用于引导 uImage 格式的 Linux 镜像。
- `bootz`: 从内存中加载 zImage 格式的 Linux 镜像，参数格式同 `booti`。
- `boot`, `bootd`：按默认方式启动，例如通过 `run 'bootcmd'` 直接运行 `bootcmd` 变量对应的启动命令及参数。

U-Boot 还支持通过设置 `bootargs` 这一变量来向 Linux 内核传递启动参数（kernel command line）。在 QEMU 中通过 `-append` 这一启动参数也能实现这一功能。前文中是通过在 QEMU 启动命令中添加 `-append "root=/dev/vda rw console=ttyS0"` 进行内核启动参数的传递的，但这一参数必须要在有 `-kernel` 参数的情况下才能使用，因此有时我们需要在 U-Boot 中通过设置 `bootargs` 来传递启动命令。

最终的启动日志如下：

```
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

U-Boot 2022.04 (Aug 26 2022 - 11:49:17 +0800)

CPU:   rv64imafdcsuh
Model: riscv-virtio,qemu
DRAM:  256 MiB
Core:  17 devices, 9 uclasses, devicetree: board
Flash: 32 MiB
Loading Environment from nowhere... OK
In:    uart@10000000
Out:   uart@10000000
Err:   uart@10000000
Net:   No ethernet found.
Hit any key to stop autoboot:  0
=> load virtio 0 0x80200000 /Image
17685504 bytes read in 10 ms (1.6 GiB/s)
=> booti 0x80200000 - $fdtcontroladdr
## Flattened Device Tree blob at 8f73bad0
   Booting using the fdt blob at 0x8f73bad0
   Using Device Tree in place at 000000008f73bad0, end 000000008f73fdfd

Starting kernel ...

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
[    0.000110] sched_clock: 64 bits at 10MHz, resolution 100ns, wraps every 4398046511100ns
[    0.005388] Console: colour dummy device 80x25
[    0.010325] Calibrating delay loop (skipped), value calculated using timer frequency.. 20.00 BogoMIPS (lpj=40000)
[    0.010527] pid_max: default: 32768 minimum: 301
[    0.013571] Mount-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[    0.013624] Mountpoint-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[    0.044900] cblist_init_generic: Setting adjustable number of callback queues.
[    0.045100] cblist_init_generic: Setting shift to 0 and lim to 1.
[    0.045804] ASID allocator using 16 bits (65536 entries)
[    0.047123] rcu: Hierarchical SRCU implementation.
[    0.049057] EFI services will not be available.
[    0.051671] smp: Bringing up secondary CPUs ...
[    0.051788] smp: Brought up 1 node, 1 CPU
[    0.063866] devtmpfs: initialized
[    0.072712] clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785100000 ns
[    0.073072] futex hash table entries: 256 (order: 2, 16384 bytes, linear)
[    0.079198] NET: Registered PF_NETLINK/PF_ROUTE protocol family
[    0.085551] cpuidle: using governor menu
[    0.116925] HugeTLB registered 2.00 MiB page size, pre-allocated 0 pages
[    0.122252] iommu: Default domain type: Translated
[    0.122339] iommu: DMA domain TLB invalidation policy: strict mode
[    0.124185] SCSI subsystem initialized
[    0.126213] usbcore: registered new interface driver usbfs
[    0.126546] usbcore: registered new interface driver hub
[    0.126702] usbcore: registered new device driver usb
[    0.141528] vgaarb: loaded
[    0.143138] clocksource: Switched to clocksource riscv_clocksource
[    0.162394] NET: Registered PF_INET protocol family
[    0.164179] IP idents hash table entries: 4096 (order: 3, 32768 bytes, linear)
[    0.168491] tcp_listen_portaddr_hash hash table entries: 128 (order: 0, 5120 bytes, linear)
[    0.168769] TCP established hash table entries: 2048 (order: 2, 16384 bytes, linear)
[    0.169002] TCP bind hash table entries: 2048 (order: 4, 65536 bytes, linear)
[    0.169247] TCP: Hash tables configured (established 2048 bind 2048)
[    0.171587] UDP hash table entries: 256 (order: 2, 24576 bytes, linear)
[    0.171935] UDP-Lite hash table entries: 256 (order: 2, 24576 bytes, linear)
[    0.173301] NET: Registered PF_UNIX/PF_LOCAL protocol family
[    0.176516] RPC: Registered named UNIX socket transport module.
[    0.176585] RPC: Registered udp transport module.
[    0.176606] RPC: Registered tcp transport module.
[    0.176629] RPC: Registered tcp NFSv4.1 backchannel transport module.
[    0.176780] PCI: CLS 0 bytes, default 64
[    0.184118] workingset: timestamp_bits=62 max_order=16 bucket_order=0
[    0.200189] NFS: Registering the id_resolver key type
[    0.201294] Key type id_resolver registered
[    0.201351] Key type id_legacy registered
[    0.201767] nfs4filelayout_init: NFSv4 File Layout Driver Registering...
[    0.201885] nfs4flexfilelayout_init: NFSv4 Flexfile Layout Driver Registering...
[    0.202545] 9p: Installing v9fs 9p2000 file system support
[    0.204311] NET: Registered PF_ALG protocol family
[    0.204862] Block layer SCSI generic (bsg) driver version 0.4 loaded (major 250)
[    0.205046] io scheduler mq-deadline registered
[    0.205135] io scheduler kyber registered
[    0.217852] pci-host-generic 30000000.pci: host bridge /soc/pci@30000000 ranges:
[    0.218831] pci-host-generic 30000000.pci:       IO 0x0003000000..0x000300ffff -> 0x0000000000
[    0.219443] pci-host-generic 30000000.pci:      MEM 0x0040000000..0x007fffffff -> 0x0040000000
[    0.219525] pci-host-generic 30000000.pci:      MEM 0x0400000000..0x07ffffffff -> 0x0400000000
[    0.220115] pci-host-generic 30000000.pci: Memory resource size exceeds max for 32 bits
[    0.221226] pci-host-generic 30000000.pci: ECAM at [mem 0x30000000-0x3fffffff] for [bus 00-ff]
[    0.223271] pci-host-generic 30000000.pci: PCI host bridge to bus 0000:00
[    0.223608] pci_bus 0000:00: root bus resource [bus 00-ff]
[    0.223724] pci_bus 0000:00: root bus resource [io  0x0000-0xffff]
[    0.223807] pci_bus 0000:00: root bus resource [mem 0x40000000-0x7fffffff]
[    0.223825] pci_bus 0000:00: root bus resource [mem 0x400000000-0x7ffffffff]
[    0.225244] pci 0000:00:00.0: [1b36:0008] type 00 class 0x060000
[    0.305403] Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
[    0.313925] printk: console [ttyS0] disabled
[    0.315969] 10000000.uart: ttyS0 at MMIO 0x10000000 (irq = 2, base_baud = 230400) is a 16550A
[    0.337906] printk: console [ttyS0] enabled
[    0.354794] loop: module loaded
[    0.359525] virtio_blk virtio0: [vda] 2097152 512-byte logical blocks (1.07 GB/1.00 GiB)
[    0.384530] e1000e: Intel(R) PRO/1000 Network Driver
[    0.384690] e1000e: Copyright(c) 1999 - 2015 Intel Corporation.
[    0.385178] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[    0.385462] ehci-pci: EHCI PCI platform driver
[    0.385799] ehci-platform: EHCI generic platform driver
[    0.386088] ohci_hcd: USB 1.1 'Open' Host Controller (OHCI) Driver
[    0.386336] ohci-pci: OHCI PCI platform driver
[    0.386641] ohci-platform: OHCI generic platform driver
[    0.387906] usbcore: registered new interface driver uas
[    0.388252] usbcore: registered new interface driver usb-storage
[    0.389615] mousedev: PS/2 mouse device common for all mice
[    0.393187] goldfish_rtc 101000.rtc: registered as rtc0
[    0.393941] goldfish_rtc 101000.rtc: setting system clock to 2022-08-27T05:32:14 UTC (1661578334)
[    0.397014] syscon-poweroff soc:poweroff: pm_power_off already claimed for sbi_srst_power_off
[    0.397375] syscon-poweroff: probe of soc:poweroff failed with error -16
[    0.398866] sdhci: Secure Digital Host Controller Interface driver
[    0.399179] sdhci: Copyright(c) Pierre Ossman
[    0.399513] sdhci-pltfm: SDHCI platform and OF driver helper
[    0.401166] usbcore: registered new interface driver usbhid
[    0.401414] usbhid: USB HID core driver
[    0.401841] riscv-pmu-sbi: SBI PMU extension is available
[    0.402450] riscv-pmu-sbi: 16 firmware and 2 hardware counters
[    0.402646] riscv-pmu-sbi: Perf sampling/filtering is not supported as sscof extension is not available
[    0.407458] NET: Registered PF_INET6 protocol family
[    0.414490] Segment Routing with IPv6
[    0.414785] In-situ OAM (IOAM) with IPv6
[    0.415417] sit: IPv6, IPv4 and MPLS over IPv4 tunneling driver
[    0.418568] NET: Registered PF_PACKET protocol family
[    0.420120] 9pnet: Installing 9P2000 support
[    0.420563] Key type dns_resolver registered
[    0.422637] debug_vm_pgtable: [debug_vm_pgtable         ]: Validating architecture page table helpers
[    0.490329] EXT4-fs (vda): mounted filesystem with ordered data mode. Quota mode: disabled.
[    0.490900] VFS: Mounted root (ext4 filesystem) on device 254:0.
[    0.493945] devtmpfs: mounted
[    0.523717] Freeing unused kernel image (initmem) memory: 2164K
[    0.524690] Run /sbin/init as init process

Please press Enter to activate this console.
```

## 小结

本文介绍了 QEMU RISCV64 'virt' 平台下通过 OpenSBI + U-Boot 引导 Linux Kernel 的流程 以及 U-Boot 和 QEMU 的部分相关命令与参数。后续文章中将结合 QEMU 代码进一步分析 ZSBL 的行为以及 QEMU 的不同启动参数组合。

## 参考资料

1. [QEMU 6.1.0 运行 RISCV64 OpenSBI + U-Boot + Linux][1]
2. [QEMU 运行 RISCV64 Linux][2]
3. [QEMU 启动方式分析（1）：QEMU 及 RISC-V 启动流程简介][3]
4. [U-Boot 官方文档：fdt command][4]

[1]: https://blog.csdn.net/qq_41957544/article/details/120667695
[2]: https://blog.csdn.net/weixin_39871788/article/details/117632731
[3]: https://gitee.com/YJMSTR/riscv-linux/blob/master/articles/20220816-introduction-to-qemu-and-riscv-upstream-boot-flow.md
[4]: https://u-boot.readthedocs.io/en/stable/usage/cmd/fdt.html
