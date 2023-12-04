---
layout: post
author: 'yjmstr'
title: 'Linux RISC-V ISA 扩展支持'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-isa-discovery-5-linux/
description: 'Linux RISC-V ISA 扩展支持'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Author:    YJMSTR [jay1273062855@outlook.com](https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:jay1273062855@outlook.com)
> Date:      2023/09/01
> Revisor:   Bin Meng, Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   ISCAS


## 前言

本文是 RISC-V 扩展软硬件支持系列的第 5 篇文章，将介绍 Linux 内核对 RISC-V 扩展的检测与支持方式。建议在阅读本文之前先阅读本系列第一篇文章：[《RISC-V 当前指令集扩展类别与检测方式》][003] 以对 RISC-V ISA 扩展目前的命名、分类与硬件检测方式有所了解。

RISC-V 之前使用名为 misa 的 CSR 来检测 ISA 扩展，在 misa 中分配了 26 位，每一位用于标识某扩展/特权模式是否启用，但随着扩展数目增加，misa 的位数不够了。RISC-V 后来引入了一个名为 mconfigptr 的 CSR，该 CSR 中存放有一个地址，指向包含硬件信息的数据结构，固件可以利用这个数据结构来生成 SMBIOS/设备树/ACPI。

SMBIOS 中存放的 ISA 信息仅包含 misa 中的那些，还是不够用。设备树通过一个 ISA string 来表示 ISA 扩展组合，ACPI 则是包含有一个 RHCT（RISC-V Hart Capabilities Table），其中同样包含了一个 ISA string 节点。

PLCT 在 2022 年曾经做过相关的[调研工作][008]，当时的 Linux 内核可以通过 cpuinfo/环境变量/HWCAP/SIGILL 等方式在用户空间获取 ISA 扩展信息。

[本系列的上一篇文章][007]中介绍了 OpenSBI 的 RISC-V ISA 扩展检测情况，SBI 位于 M 模式，能够直接读取相关 CSR 来获得相应的扩展信息。

## 获取 Linux 源码

Linux 内核较大，使用 `git fetch` 可以断点续传，以免网络出问题导致 `git clone` 中断。

```sh
$ mkdir linux-kernel
$ cd linux-kernel
$ git init
$ git fetch https://gitee.com/mirrors/linux_old1.git
$ git checkout FETCH_HEAD
$ git remote add origin https://gitee.com/mirrors/linux_old1.git
$ git pull origin
```

`git checkout` 的输出表明：HEAD is now at 2dde18cd1d8f Linux 6.5，本文将基于这一版本进行分析。如果我们想要获取特定版本的 Linux 内核源码，可以从 [kernel.org][001] 上下载，也可以在 `git pull origin` 之后通过 `git checkout` 切换到指定版本。

## 编译内核并启动

编译内核需要用到 RISC-V 交叉编译工具链，本系列之前的文章已经介绍过，此处不再赘述：

```sh
$ make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- defconfig
$ make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j $(nproc)
```

嵌入式领域通常使用 busybox 来构建根文件系统，首先下载编译 busybox：

```sh
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

```sh
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

```sh
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
/sbin/mdev -s
```

并修改文件权限：

```sh
$ sudo chmod +x rcS
$ cd ~
$ sudo umount rootfs
```

随后尝试直接引导内核：

```sh
$ qemu-system-riscv64 -M virt -m 256M -nographic -kernel linux-kernel/arch/riscv/boot/Image -drive file=rootfs.img,format=raw,id=hd0  -device virtio-blk-device,drive=hd0 -append "root=/dev/vda rw console=ttyS0"
```

可以得到 Linux 启动日志如下：

```sh
$ qemu-system-riscv64 -M virt -m 256M -nographic -kernel linux-kernel/arch/riscv/boot/Image -drive file=rootfs.img,format=raw,id=hd0  -device virtio-blk-device,drive=hd0 -append "root=/dev/vda rw console=ttyS0"

OpenSBI v1.3.1
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|___/_____|
        | |
        |_|

Platform Name             : riscv-virtio,qemu
Platform Features         : medeleg
Platform HART Count       : 1
Platform IPI Device       : aclint-mswi
Platform Timer Device     : aclint-mtimer @ 10000000Hz
Platform Console Device   : uart8250
Platform HSM Device       : ---
Platform PMU Device       : ---
Platform Reboot Device    : sifive_test
Platform Shutdown Device  : sifive_test
Platform Suspend Device   : ---
Platform CPPC Device      : ---
Firmware Base             : 0x80000000
Firmware Size             : 194 KB
Firmware RW Offset        : 0x20000
Firmware RW Size          : 66 KB
Firmware Heap Offset      : 0x28000
Firmware Heap Size        : 34 KB (total), 2 KB (reserved), 9 KB (used), 22 KB (free)
Firmware Scratch Size     : 4096 B (total), 760 B (used), 3336 B (free)
Runtime SBI Version       : 1.0

Domain0 Name              : root
Domain0 Boot HART         : 0
Domain0 HARTs             : 0*
Domain0 Region00          : 0x0000000002000000-0x000000000200ffff M: (I,R,W) S/U: ()
Domain0 Region01          : 0x0000000080000000-0x000000008001ffff M: (R,X) S/U: ()
Domain0 Region02          : 0x0000000080020000-0x000000008003ffff M: (R,W) S/U: ()
Domain0 Region03          : 0x0000000000000000-0xffffffffffffffff M: (R,W,X) S/U: (R,W,X)
Domain0 Next Address      : 0x0000000080200000
Domain0 Next Arg1         : 0x000000008fe00000
Domain0 Next Mode         : S-mode
Domain0 SysReset          : yes
Domain0 SysSuspend        : yes

Boot HART ID              : 0
Boot HART Domain          : root
Boot HART Priv Version    : v1.12
Boot HART Base ISA        : rv64imafdch
Boot HART ISA Extensions  : time,sstc
Boot HART PMP Count       : 16
Boot HART PMP Granularity : 4
Boot HART PMP Address Bits: 54
Boot HART MHPM Count      : 16
Boot HART MIDELEG         : 0x0000000000001666
Boot HART MEDELEG         : 0x0000000000f0b509
[    0.000000] Linux version 6.5.0 (mint@linux-lab-host) (riscv64-linux-gnu-gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0, GNU ld (GNU Binutils for Ubuntu) 2.38) #1 SMP Wed Aug 30 17:20:35 CST 2023
[    0.000000] random: crng init done
[    0.000000] Machine model: riscv-virtio,qemu
[    0.000000] SBI specification v1.0 detected
[    0.000000] SBI implementation ID=0x1 Version=0x10003
[    0.000000] SBI TIME extension detected
[    0.000000] SBI IPI extension detected
[    0.000000] SBI RFENCE extension detected
[    0.000000] SBI SRST extension detected
[    0.000000] efi: UEFI not found.
[    0.000000] OF: reserved mem: 0x0000000080000000..0x000000008001ffff (128 KiB) nomap non-reusable mmode_resv0@80000000
[    0.000000] OF: reserved mem: 0x0000000080020000..0x000000008003ffff (128 KiB) nomap non-reusable mmode_resv1@80020000
[    0.000000] Zone ranges:
[    0.000000]   DMA32    [mem 0x0000000080000000-0x000000008fffffff]
[    0.000000]   Normal   empty
[    0.000000] Movable zone start for each node
[    0.000000] Early memory node ranges
[    0.000000]   node   0: [mem 0x0000000080000000-0x000000008003ffff]
[    0.000000]   node   0: [mem 0x0000000080040000-0x000000008fffffff]
[    0.000000] Initmem setup node 0 [mem 0x0000000080000000-0x000000008fffffff]
[    0.000000] SBI HSM extension detected
[    0.000000] riscv: base ISA extensions acdfhim
[    0.000000] riscv: ELF capabilities acdfim
[    0.000000] percpu: Embedded 19 pages/cpu s40888 r8192 d28744 u77824
[    0.000000] Kernel command line: root=/dev/vda rw console=ttyS0
[    0.000000] Dentry cache hash table entries: 32768 (order: 6, 262144 bytes, linear)
[    0.000000] Inode-cache hash table entries: 16384 (order: 5, 131072 bytes, linear)
[    0.000000] Built 1 zonelists, mobility grouping on.  Total pages: 64512
[    0.000000] mem auto-init: stack:off, heap alloc:off, heap free:off
[    0.000000] Virtual kernel memory layout:
[    0.000000]       fixmap : 0xff1bfffffea00000 - 0xff1bffffff000000   (6144 kB)
[    0.000000]       pci io : 0xff1bffffff000000 - 0xff1c000000000000   (  16 MB)
[    0.000000]      vmemmap : 0xff1c000000000000 - 0xff20000000000000   (1024 TB)
[    0.000000]      vmalloc : 0xff20000000000000 - 0xff60000000000000   (16384 TB)
[    0.000000]      modules : 0xffffffff0157b000 - 0xffffffff80000000   (2026 MB)
[    0.000000]       lowmem : 0xff60000000000000 - 0xff60000010000000   ( 256 MB)
[    0.000000]       kernel : 0xffffffff80000000 - 0xffffffffffffffff   (2047 MB)
[    0.000000] Memory: 218332K/262144K available (8728K kernel code, 4974K rwdata, 4096K rodata, 2200K init, 482K bss, 43812K reserved, 0K cma-reserved)
[    0.000000] SLUB: HWalign=64, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
[    0.000000] rcu: Hierarchical RCU implementation.
[    0.000000] rcu: 	RCU restricting CPUs from NR_CPUS=64 to nr_cpu_ids=1.
[    0.000000] rcu: 	RCU debug extended QS entry/exit.
[    0.000000] 	Tracing variant of Tasks RCU enabled.
[    0.000000] rcu: RCU calculated value of scheduler-enlistment delay is 25 jiffies.
[    0.000000] rcu: Adjusting geometry for rcu_fanout_leaf=16, nr_cpu_ids=1
[    0.000000] NR_IRQS: 64, nr_irqs: 64, preallocated irqs: 0
[    0.000000] riscv-intc: 64 local interrupts mapped
[    0.000000] plic: plic@c000000: mapped 95 interrupts with 1 handlers for 2 contexts.
[    0.000000] riscv: providing IPIs using SBI IPI extension
[    0.000000] rcu: srcu_init: Setting srcu_struct sizes based on contention.
[    0.000000] clocksource: riscv_clocksource: mask: 0xffffffffffffffff max_cycles: 0x24e6a1710, max_idle_ns: 440795202120 ns
[    0.000073] sched_clock: 64 bits at 10MHz, resolution 100ns, wraps every 4398046511100ns
[    0.000182] riscv-timer: Timer interrupt in S-mode is available via sstc extension
[    0.008216] Console: colour dummy device 80x25
[    0.009505] Calibrating delay loop (skipped), value calculated using timer frequency.. 20.00 BogoMIPS (lpj=40000)
[    0.009635] pid_max: default: 32768 minimum: 301
[    0.010714] LSM: initializing lsm=capability,integrity
[    0.012870] Mount-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[    0.012948] Mountpoint-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[    0.040252] RCU Tasks Trace: Setting shift to 0 and lim to 1 rcu_task_cb_adjust=1.
[    0.040655] riscv: ELF compat mode supported
[    0.041099] ASID allocator using 16 bits (65536 entries)
[    0.042073] rcu: Hierarchical SRCU implementation.
[    0.042107] rcu: 	Max phase no-delay instances is 1000.
[    0.044384] EFI services will not be available.
[    0.045645] smp: Bringing up secondary CPUs ...
[    0.046625] smp: Brought up 1 node, 1 CPU
[    0.057137] devtmpfs: initialized
[    0.064078] clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785100000 ns
[    0.064309] futex hash table entries: 256 (order: 2, 16384 bytes, linear)
[    0.066112] pinctrl core: initialized pinctrl subsystem
[    0.072724] NET: Registered PF_NETLINK/PF_ROUTE protocol family
[    0.080456] DMA: preallocated 128 KiB GFP_KERNEL pool for atomic allocations
[    0.080750] DMA: preallocated 128 KiB GFP_KERNEL|GFP_DMA32 pool for atomic allocations
[    0.081016] audit: initializing netlink subsys (disabled)
[    0.084218] thermal_sys: Registered thermal governor 'step_wise'
[    0.084758] cpuidle: using governor menu
[    0.085806] audit: type=2000 audit(0.040:1): state=initialized audit_enabled=0 res=1
[    0.099344] HugeTLB: registered 2.00 MiB page size, pre-allocated 0 pages
[    0.099384] HugeTLB: 28 KiB vmemmap can be freed for a 2.00 MiB page
[    0.103034] ACPI: Interpreter disabled.
[    0.104629] iommu: Default domain type: Translated
[    0.104662] iommu: DMA domain TLB invalidation policy: strict mode
[    0.106649] SCSI subsystem initialized
[    0.108322] usbcore: registered new interface driver usbfs
[    0.108532] usbcore: registered new interface driver hub
[    0.108678] usbcore: registered new device driver usb
[    0.119431] vgaarb: loaded
[    0.139122] clocksource: Switched to clocksource riscv_clocksource
[    0.141072] pnp: PnP ACPI: disabled
[    0.158856] NET: Registered PF_INET protocol family
[    0.159756] IP idents hash table entries: 4096 (order: 3, 32768 bytes, linear)
[    0.164351] tcp_listen_portaddr_hash hash table entries: 128 (order: 0, 4096 bytes, linear)
[    0.164450] Table-perturb hash table entries: 65536 (order: 6, 262144 bytes, linear)
[    0.164501] TCP established hash table entries: 2048 (order: 2, 16384 bytes, linear)
[    0.164727] TCP bind hash table entries: 2048 (order: 5, 131072 bytes, linear)
[    0.164988] TCP: Hash tables configured (established 2048 bind 2048)
[    0.165942] UDP hash table entries: 256 (order: 2, 24576 bytes, linear)
[    0.166364] UDP-Lite hash table entries: 256 (order: 2, 24576 bytes, linear)
[    0.167395] NET: Registered PF_UNIX/PF_LOCAL protocol family
[    0.170224] RPC: Registered named UNIX socket transport module.
[    0.170280] RPC: Registered udp transport module.
[    0.170291] RPC: Registered tcp transport module.
[    0.170305] RPC: Registered tcp-with-tls transport module.
[    0.170315] RPC: Registered tcp NFSv4.1 backchannel transport module.
[    0.170463] PCI: CLS 0 bytes, default 64
[    0.177633] workingset: timestamp_bits=46 max_order=16 bucket_order=0
[    0.180895] NFS: Registering the id_resolver key type
[    0.181717] Key type id_resolver registered
[    0.181750] Key type id_legacy registered
[    0.181976] nfs4filelayout_init: NFSv4 File Layout Driver Registering...
[    0.182049] nfs4flexfilelayout_init: NFSv4 Flexfile Layout Driver Registering...
[    0.182691] 9p: Installing v9fs 9p2000 file system support
[    0.184022] NET: Registered PF_ALG protocol family
[    0.184294] Block layer SCSI generic (bsg) driver version 0.4 loaded (major 246)
[    0.184406] io scheduler mq-deadline registered
[    0.184462] io scheduler kyber registered
[    0.184546] io scheduler bfq registered
[    0.187615] pci-host-generic 30000000.pci: host bridge /soc/pci@30000000 ranges:
[    0.188285] pci-host-generic 30000000.pci:       IO 0x0003000000..0x000300ffff -> 0x0000000000
[    0.188845] pci-host-generic 30000000.pci:      MEM 0x0040000000..0x007fffffff -> 0x0040000000
[    0.188906] pci-host-generic 30000000.pci:      MEM 0x0400000000..0x07ffffffff -> 0x0400000000
[    0.189388] pci-host-generic 30000000.pci: Memory resource size exceeds max for 32 bits
[    0.189752] pci-host-generic 30000000.pci: ECAM at [mem 0x30000000-0x3fffffff] for [bus 00-ff]
[    0.191528] pci-host-generic 30000000.pci: PCI host bridge to bus 0000:00
[    0.191752] pci_bus 0000:00: root bus resource [bus 00-ff]
[    0.191831] pci_bus 0000:00: root bus resource [io  0x0000-0xffff]
[    0.191884] pci_bus 0000:00: root bus resource [mem 0x40000000-0x7fffffff]
[    0.191897] pci_bus 0000:00: root bus resource [mem 0x400000000-0x7ffffffff]
[    0.193325] pci 0000:00:00.0: [1b36:0008] type 00 class 0x060000
[    0.287202] Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
[    0.297113] printk: console [ttyS0] disabled
[    0.300265] 10000000.serial: ttyS0 at MMIO 0x10000000 (irq = 12, base_baud = 230400) is a 16550A
[    0.301524] printk: console [ttyS0] enabled
[    0.323403] SuperH (H)SCI(F) driver initialized
[    0.343215] loop: module loaded
[    0.344307] virtio_blk virtio0: 1/0/0 default/read/poll queues
[    0.348817] virtio_blk virtio0: [vda] 2097152 512-byte logical blocks (1.07 GB/1.00 GiB)
[    0.384041] e1000e: Intel(R) PRO/1000 Network Driver
[    0.384260] e1000e: Copyright(c) 1999 - 2015 Intel Corporation.
[    0.387880] usbcore: registered new interface driver uas
[    0.388206] usbcore: registered new interface driver usb-storage
[    0.389412] mousedev: PS/2 mouse device common for all mice
[    0.393353] goldfish_rtc 101000.rtc: registered as rtc0
[    0.394317] goldfish_rtc 101000.rtc: setting system clock to 2023-09-02T07:35:32 UTC (1693640132)
[    0.398165] syscon-poweroff poweroff: pm_power_off already claimed for sbi_srst_power_off
[    0.399069] syscon-poweroff: probe of poweroff failed with error -16
[    0.401754] sdhci: Secure Digital Host Controller Interface driver
[    0.401947] sdhci: Copyright(c) Pierre Ossman
[    0.402639] sdhci-pltfm: SDHCI platform and OF driver helper
[    0.403484] usbcore: registered new interface driver usbhid
[    0.403664] usbhid: USB HID core driver
[    0.404356] riscv-pmu-sbi: SBI PMU extension is available
[    0.405010] riscv-pmu-sbi: 16 firmware and 18 hardware counters
[    0.405216] riscv-pmu-sbi: Perf sampling/filtering is not supported as sscof extension is not available
[    0.410466] NET: Registered PF_INET6 protocol family
[    0.418128] Segment Routing with IPv6
[    0.418632] In-situ OAM (IOAM) with IPv6
[    0.419337] sit: IPv6, IPv4 and MPLS over IPv4 tunneling driver
[    0.422999] NET: Registered PF_PACKET protocol family
[    0.424737] 9pnet: Installing 9P2000 support
[    0.425341] Key type dns_resolver registered
[    0.466679] debug_vm_pgtable: [debug_vm_pgtable         ]: Validating architecture page table helpers
[    0.476006] clk: Disabling unused clocks
[    0.569745] EXT4-fs (vda): recovery complete
[    0.572787] EXT4-fs (vda): mounted filesystem b1c2c62f-2f6d-4da5-af97-58c3648c79f4 r/w with ordered data mode. Quota mode: disabled.
[    0.573412] VFS: Mounted root (ext4 filesystem) on device 254:0.
[    0.576056] devtmpfs: mounted
[    0.618132] Freeing unused kernel image (initmem) memory: 2200K
[    0.618994] Run /sbin/init as init process

Please press Enter to activate this console.

```

## Base ISA extensions & ELF capabilities

Linux Kernel 的启动日志中有两行输出如下：

```sh
[    0.000000] riscv: base ISA extensions acdfhim
[    0.000000] riscv: ELF capabilities acdfim
```

在源码中以 `base ISA extensions` 作为关键字进行搜索，可以发现 ISA 扩展信息相关的函数位于 `arch/riscv/kernel/cpufeature.c` 这一文件中。这部分代码是在 [commit 6bcff51][006] 引入的，其中 riscv_isa 这个 bitmap 用于表示主机上所有 CPU 支持的 ISA 扩展的交集，而 elf_hwcap 仅用于表示与用户空间有关的 ISA 扩展的交集。

相关的函数比较长，下面通过添加中文注释的方式进行分析：

```c
/* arch/riscv/kernel/cpufeature.c:102 */

void __init riscv_fill_hwcap(void)
{
        // hwcap 指 hardware capability
	struct device_node *node;
	const char *isa;
	char print_str[NUM_ALPHA_EXTS + 1];
	int i, j, rc;
	unsigned long isa2hwcap[26] = {0};
	struct acpi_table_header *rhct;
	acpi_status status;
	unsigned int cpu;
	// COMPAT_HWCAP_ISA_? == (1 << （字母 ? 的 ASCII 码 - 'A'）)
	isa2hwcap['i' - 'a'] = COMPAT_HWCAP_ISA_I;
	isa2hwcap['m' - 'a'] = COMPAT_HWCAP_ISA_M;
	isa2hwcap['a' - 'a'] = COMPAT_HWCAP_ISA_A;
	isa2hwcap['f' - 'a'] = COMPAT_HWCAP_ISA_F;
	isa2hwcap['d' - 'a'] = COMPAT_HWCAP_ISA_D;
	isa2hwcap['c' - 'a'] = COMPAT_HWCAP_ISA_C;
	isa2hwcap['v' - 'a'] = COMPAT_HWCAP_ISA_V;

	elf_hwcap = 0;

	// 将 riscv_isa 这个 bitmap 清零
	bitmap_zero(riscv_isa, RISCV_ISA_EXT_MAX);

        // 检测是否启用了 ACPI，如果是，读取 ACPI status
	if (!acpi_disabled) {
		status = acpi_get_table(ACPI_SIG_RHCT, 0, &rhct);
		if (ACPI_FAILURE(status))
			return;
	}

	for_each_possible_cpu(cpu) {
        // struct riscv_isainfo 结构体中包含了一个名为 isa 的长为 64 位的 bitmap
		struct riscv_isainfo *isainfo = &hart_isa[cpu];
        // 当前 cpu 的 hwcap
		unsigned long this_hwcap = 0;

        // 如果没有启用 ACPI，就读取设备树以获取 isa 信息
		if (acpi_disabled) {
                // 获取设备树结点
			node = of_cpu_device_node_get(cpu);
			if (!node) {
				pr_warn("Unable to find cpu node\n");
				continue;
			}
			// 从设备树中读出 isa 字符串
			rc = of_property_read_string(node, "riscv,isa", &isa);
			of_node_put(node);
			if (rc) {
				pr_warn("Unable to find \"riscv,isa\" devicetree entry\n");
				continue;
			}
		} else {
                // 如果启用了 ACPI，通过 ACPI 获取 isa 字符串
			rc = acpi_get_riscv_isa(rhct, cpu, &isa);
			if (rc < 0) {
				pr_warn("Unable to get ISA for the hart - %d\n", cpu);
				continue;
			}
		}

		/*
		 * For all possible cpus, we have already validated in
		 * the boot process that they at least contain "rv" and
		 * whichever of "32"/"64" this kernel supports, and so this
		 * section can be skipped.
		 */
                // isa 字符串必包含 rv+位数共 4 个字符，可以跳过对这四个的检查
		isa += 4;

		while (*isa) {
			const char *ext = isa++;
			const char *ext_end = isa;
                // ext_long 表示是否有多字母扩展
			bool ext_long = false, ext_err = false;

                // 逐字符检查 isa 字符串中的扩展
			switch (*ext) {
			case 's':
				/*
				 * Workaround for invalid single-letter 's' & 'u'(QEMU).
				 * No need to set the bit in riscv_isa as 's' & 'u' are
				 * not valid ISA extensions. It works until multi-letter
				 * extension starting with "Su" appears.
				 */

				if (ext[-1] != '_' && ext[1] == 'u') {
					++isa;
					ext_err = true;
					break;
				}
				fallthrough;
			case 'S':
			case 'x':
			case 'X':
			case 'z':
			case 'Z':
				/*
				 * Before attempting to parse the extension itself, we find its end.
				 * As multi-letter extensions must be split from other multi-letter
				 * extensions with an "_", the end of a multi-letter extension will
				 * either be the null character or the "_" at the start of the next
				 * multi-letter extension.
				 *
				 * Next, as the extensions version is currently ignored, we
				 * eliminate that portion. This is done by parsing backwards from
				 * the end of the extension, removing any numbers. This may be a
				 * major or minor number however, so the process is repeated if a
				 * minor number was found.
				 *
				 * ext_end is intended to represent the first character *after* the
				 * name portion of an extension, but will be decremented to the last
				 * character itself while eliminating the extensions version number.
				 * A simple re-increment solves this problem.
				 */
				ext_long = true;
				for (; *isa && *isa != '_'; ++isa)
					if (unlikely(!isalnum(*isa)))
						ext_err = true;

				ext_end = isa;
				if (unlikely(ext_err))
					break;

				if (!isdigit(ext_end[-1]))
					break;

				while (isdigit(*--ext_end))
					;

				if (tolower(ext_end[0]) != 'p' || !isdigit(ext_end[-1])) {
					++ext_end;
					break;
				}

				while (isdigit(*--ext_end))
					;

				++ext_end;
				break;
			default:
				/*
				 * Things are a little easier for single-letter extensions, as they
				 * are parsed forwards.
				 *
				 * After checking that our starting position is valid, we need to
				 * ensure that, when isa was incremented at the start of the loop,
				 * that it arrived at the start of the next extension.
				 *
				 * If we are already on a non-digit, there is nothing to do. Either
				 * we have a multi-letter extension's _, or the start of an
				 * extension.
				 *
				 * Otherwise we have found the current extension's major version
				 * number. Parse past it, and a subsequent p/minor version number
				 * if present. The `p` extension must not appear immediately after
				 * a number, so there is no fear of missing it.
				 *
				 */
				if (unlikely(!isalpha(*ext))) {
					ext_err = true;
					break;
				}

				if (!isdigit(*isa))
					break;

				while (isdigit(*++isa))
					;

				if (tolower(*isa) != 'p')
					break;

				if (!isdigit(*++isa)) {
					--isa;
					break;
				}

				while (isdigit(*++isa))
					;

				break;
			}

			/*
			 * The parser expects that at the start of an iteration isa points to the
			 * first character of the next extension. As we stop parsing an extension
			 * on meeting a non-alphanumeric character, an extra increment is needed
			 * where the succeeding extension is a multi-letter prefixed with an "_".
			 */
			if (*isa == '_')
				++isa;

#define SET_ISA_EXT_MAP(name, bit)							\
			do {								\
				if ((ext_end - ext == sizeof(name) - 1) &&		\
				     !strncasecmp(ext, name, sizeof(name) - 1) &&	\
				     riscv_isa_extension_check(bit))			\
					set_bit(bit, isainfo->isa);			\
			} while (false)							\

			if (unlikely(ext_err))
				continue;
			if (!ext_long) {
                        	// 如果没有多字母扩展
				int nr = tolower(*ext) - 'a';
				if (riscv_isa_extension_check(nr)) {
                                        // 设置 hwcap
					this_hwcap |= isa2hwcap[nr];
					set_bit(nr, isainfo->isa);
				}
			} else {
 	                	// 判断多字母扩展，检测并设置相应的 bitmap
        	        	// riscv_isa_extension_check 函数会额外检测 Zicbom 与 Zicboz 扩展的一些限制
				/* sorted alphabetically */
				SET_ISA_EXT_MAP("smaia", RISCV_ISA_EXT_SMAIA);
				SET_ISA_EXT_MAP("ssaia", RISCV_ISA_EXT_SSAIA);
				SET_ISA_EXT_MAP("sscofpmf", RISCV_ISA_EXT_SSCOFPMF);
				SET_ISA_EXT_MAP("sstc", RISCV_ISA_EXT_SSTC);
				SET_ISA_EXT_MAP("svinval", RISCV_ISA_EXT_SVINVAL);
				SET_ISA_EXT_MAP("svnapot", RISCV_ISA_EXT_SVNAPOT);
				SET_ISA_EXT_MAP("svpbmt", RISCV_ISA_EXT_SVPBMT);
				SET_ISA_EXT_MAP("zba", RISCV_ISA_EXT_ZBA);
				SET_ISA_EXT_MAP("zbb", RISCV_ISA_EXT_ZBB);
				SET_ISA_EXT_MAP("zbs", RISCV_ISA_EXT_ZBS);
				SET_ISA_EXT_MAP("zicbom", RISCV_ISA_EXT_ZICBOM);
				SET_ISA_EXT_MAP("zicboz", RISCV_ISA_EXT_ZICBOZ);
				SET_ISA_EXT_MAP("zihintpause", RISCV_ISA_EXT_ZIHINTPAUSE);
			}
#undef SET_ISA_EXT_MAP
		}

		/*
		 * These ones were as they were part of the base ISA when the
		 * port & dt-bindings were upstreamed, and so can be set
		 * unconditionally where `i` is in riscv,isa on DT systems.
		 */

       		// 如果未启用 ACPI，直接无条件将以下扩展在 bitmap 中标记为已启用
		if (acpi_disabled) {
			set_bit(RISCV_ISA_EXT_ZICSR, isainfo->isa);
			set_bit(RISCV_ISA_EXT_ZIFENCEI, isainfo->isa);
			set_bit(RISCV_ISA_EXT_ZICNTR, isainfo->isa);
			set_bit(RISCV_ISA_EXT_ZIHPM, isainfo->isa);
		}

		/*
		 * All "okay" hart should have same isa. Set HWCAP based on
		 * common capabilities of every "okay" hart, in case they don't
		 * have.
		 */
        	// 取出各个 CPU hwcap 的交集作为 elf_hwcap
		if (elf_hwcap)
			elf_hwcap &= this_hwcap;
		else
			elf_hwcap = this_hwcap;

        	// 取出各个 CPU ISA 扩展的 bitmap 的交集作为 riscv_isa
		if (bitmap_empty(riscv_isa, RISCV_ISA_EXT_MAX))
			bitmap_copy(riscv_isa, isainfo->isa, RISCV_ISA_EXT_MAX);
		else
			bitmap_and(riscv_isa, riscv_isa, isainfo->isa, RISCV_ISA_EXT_MAX);
	}
	// 如果启用了 ACPI，并且存在 RHCT
    	// RHCT 指 RISC-V Hart Capabilities Table，是 RISC-V CPU 与 OS 之间交流 CPU 的功能特性时使用的表格结构
	if (!acpi_disabled && rhct)
		acpi_put_table((struct acpi_table_header *)rhct);

	/* We don't support systems with F but without D, so mask those out
	 * here. */
    	// Linux 要求若启用了 F 扩展，D 扩展必须同时启用，否则就关闭 F 扩展
	if ((elf_hwcap & COMPAT_HWCAP_ISA_F) && !(elf_hwcap & COMPAT_HWCAP_ISA_D)) {
		pr_info("This kernel does not support systems with F but not D\n");
		elf_hwcap &= ~COMPAT_HWCAP_ISA_F;
	}

	if (elf_hwcap & COMPAT_HWCAP_ISA_V) {
		riscv_v_setup_vsize();
		/*
		 * ISA string in device tree might have 'v' flag, but
		 * CONFIG_RISCV_ISA_V is disabled in kernel.
		 * Clear V flag in elf_hwcap if CONFIG_RISCV_ISA_V is disabled.
		 */
        	// 如果 config 里没有启用 V 扩展，但是设备树的 ISA string 里包含了 V 扩展，则在 elf_hwcap 中将 V 扩展标记为未启用
		if (!IS_ENABLED(CONFIG_RISCV_ISA_V))
			elf_hwcap &= ~COMPAT_HWCAP_ISA_V;
	}

	memset(print_str, 0, sizeof(print_str));
	for (i = 0, j = 0; i < NUM_ALPHA_EXTS; i++)
		if (riscv_isa[0] & BIT_MASK(i))
			print_str[j++] = (char)('a' + i);
    	// 按照字典序输出启用的单字母扩展
	pr_info("riscv: base ISA extensions %s\n", print_str);

	memset(print_str, 0, sizeof(print_str));
	for (i = 0, j = 0; i < NUM_ALPHA_EXTS; i++)
		if (elf_hwcap & BIT_MASK(i))
			print_str[j++] = (char)('a' + i);
    	// 按照字典序输出 ELF 支持的扩展
	pr_info("riscv: ELF capabilities %s\n", print_str);
}
```

将上述代码简单总结一下：

- S-mode 的 Linux 内核会通过 ACPI 或设备树中的 ISA string 得到 RISC-V ISA 扩展信息，但不是直接拿来用，而是会进行一些合法性检测与其它设置，例如：内核中 F 扩展和 D 扩展要么都启用，要么都不启用。
- 内核最终输出的所支持的 ISA，是各个 hart 所支持的 ISA 的交集，并在此基础上应用一些 config 配置文件中有关 ISA 扩展的设置。
- 未启用 ACPI 时，Linux 内核通过设备树中的 ISA string 获得扩展信息，此时 Zicsr，Zifencei，Zicntr，Zihpm 扩展会无条件启用。
- 启用 ACPI 时，Linux 会尝试获取 ACPI 中用于向 OS 传递 CPU 信息的 RHCT（RISC-V Hart Capabilities Table）结构，如果存在 RHCT，就从中读取出 ISA string。

上述代码所检测的这些扩展在 bitmap 中所对应的位号定义在 `arch/riscv/include/asm/hwcap.h` 中，每个扩展对应一个位，其中低 26 位用于单字母扩展，多字母扩展对应的位号从 27 开始分配，bitmap 的最大容量为 64：

```c
/* arch/riscv/include/asm/hwcap.h:16 */

#define RISCV_ISA_EXT_a		('a' - 'a')
#define RISCV_ISA_EXT_c		('c' - 'a')
#define RISCV_ISA_EXT_d		('d' - 'a')
#define RISCV_ISA_EXT_f		('f' - 'a')
#define RISCV_ISA_EXT_h		('h' - 'a')
#define RISCV_ISA_EXT_i		('i' - 'a')
#define RISCV_ISA_EXT_m		('m' - 'a')
#define RISCV_ISA_EXT_s		('s' - 'a')
#define RISCV_ISA_EXT_u		('u' - 'a')
#define RISCV_ISA_EXT_v		('v' - 'a')

/*
 * These macros represent the logical IDs of each multi-letter RISC-V ISA
 * extension and are used in the ISA bitmap. The logical IDs start from
 * RISCV_ISA_EXT_BASE, which allows the 0-25 range to be reserved for single
 * letter extensions. The maximum, RISCV_ISA_EXT_MAX, is defined in order
 * to allocate the bitmap and may be increased when necessary.
 *
 * New extensions should just be added to the bottom, rather than added
 * alphabetically, in order to avoid unnecessary shuffling.
 */
#define RISCV_ISA_EXT_BASE		26

#define RISCV_ISA_EXT_SSCOFPMF		26
#define RISCV_ISA_EXT_SSTC		27
#define RISCV_ISA_EXT_SVINVAL		28
#define RISCV_ISA_EXT_SVPBMT		29
#define RISCV_ISA_EXT_ZBB		30
#define RISCV_ISA_EXT_ZICBOM		31
#define RISCV_ISA_EXT_ZIHINTPAUSE	32
#define RISCV_ISA_EXT_SVNAPOT		33
#define RISCV_ISA_EXT_ZICBOZ		34
#define RISCV_ISA_EXT_SMAIA		35
#define RISCV_ISA_EXT_SSAIA		36
#define RISCV_ISA_EXT_ZBA		37
#define RISCV_ISA_EXT_ZBS		38
#define RISCV_ISA_EXT_ZICNTR		39
#define RISCV_ISA_EXT_ZICSR		40
#define RISCV_ISA_EXT_ZIFENCEI		41
#define RISCV_ISA_EXT_ZIHPM		42

#define RISCV_ISA_EXT_MAX		64
#define RISCV_ISA_EXT_NAME_LEN_MAX	32

#ifdef CONFIG_RISCV_M_MODE
#define RISCV_ISA_EXT_SxAIA		RISCV_ISA_EXT_SMAIA
#else
#define RISCV_ISA_EXT_SxAIA		RISCV_ISA_EXT_SSAIA
#endif
```

但解析 ISA string 面临着诸多问题，从上述代码也可以看出来对 ISA string 的解析比较繁琐且容易出错，相关讨论见 [邮件列表][005]：

> There's been a bunch of off-list discussions about this, including at
> Plumbers. The original plan was to do something involving providing an
> ISA string to userspace, but ISA strings just aren't sufficient for a
> stable ABI any more: in order to parse an ISA string users need the
> version of the specifications that the string is written to, the version
> of each extension (sometimes at a finer granularity than the RISC-V
> releases/versions encode), and the expected use case for the ISA string
> (ie, is it a U-mode or M-mode string). That's a lot of complexity to
> try and keep ABI compatible and it's probably going to continue to grow,
> as even if there's no more complexity in the specifications we'll have
> to deal with the various ISA string parsing oddities that end up all
> over userspace.

于是 Linux Kernel 又在用户空间引入了新的系统调用，详见下一小节。

## RISC-V Hardware Probing Interface

上一小节中提到的 elf_hwcap 仅有 64 位可用，但用户空间需要检测的扩展可能不止 64 个，因此上述机制同样面临位数不够的问题。

为了解决这些问题，Linux 内核在 [commit ea3de9c][004] 中引入了一个用于在用户空间进行硬件检测的系统调用，相关文档见

`Documentation/riscv/hwprobe.rst`。该系统调用的参数包括一个键值对数组，键值对的个数，CPU 个数，CPU set 与一个 flag，目前支持检测 `m{arch,imp,vendor}id` 和少数 ISA 扩展，未来能够基于键值对参数进行更多的检测：

```c
struct riscv_hwprobe {
  __s64 key;
  __u64 value;
};

long sys_riscv_hwprobe(struct riscv_hwprobe *pairs, size_t pair_count, size_t cpu_count, cpu_set_t *cpus, unsigned int flags);
```

其中与扩展检测相关的 C 代码如下：

```c
/* arch/riscv/kernel/sys_riscv.c:125 */

static void hwprobe_isa_ext0(struct riscv_hwprobe *pair,
			     const struct cpumask *cpus)
{
	int cpu;
	u64 missing = 0;

	pair->value = 0;
	if (has_fpu())
		pair->value |= RISCV_HWPROBE_IMA_FD;

	if (riscv_isa_extension_available(NULL, c))
		pair->value |= RISCV_HWPROBE_IMA_C;

	if (has_vector())
		pair->value |= RISCV_HWPROBE_IMA_V;

	/*
	 * Loop through and record extensions that 1) anyone has, and 2) anyone
	 * doesn't have.
	 */
	for_each_cpu(cpu, cpus) {
		struct riscv_isainfo *isainfo = &hart_isa[cpu];

		if (riscv_isa_extension_available(isainfo->isa, ZBA))
			pair->value |= RISCV_HWPROBE_EXT_ZBA;
		else
			missing |= RISCV_HWPROBE_EXT_ZBA;

		if (riscv_isa_extension_available(isainfo->isa, ZBB))
			pair->value |= RISCV_HWPROBE_EXT_ZBB;
		else
			missing |= RISCV_HWPROBE_EXT_ZBB;

		if (riscv_isa_extension_available(isainfo->isa, ZBS))
			pair->value |= RISCV_HWPROBE_EXT_ZBS;
		else
			missing |= RISCV_HWPROBE_EXT_ZBS;
	}

	/* Now turn off reporting features if any CPU is missing it. */
	pair->value &= ~missing;
}
```

上述这段代码检查 `IMAFDCV_Zba_Zbb_Zbs` 这些扩展是否受支持。其中 F 和 D 扩展是绑定的，Linux 内核中这两个扩展要么都启用，要么都关闭。

## 总结

本文通过对 `riscv_fill_hwcap` 函数的分析，介绍了 Linux 利用设备树/ACPI 检测 RISC-V ISA 扩展并生成 HWCAP 的方式，并介绍了 Linux 新引入的硬件检测系统调用 hw_probe。

2022 年，PLCT 曾经做过有关 RISC-V ISA 扩展检测机制的[调研][008]，当时的 Linux 内核通过 M 模式传递来的设备树/SMBIOS/ACPI 中所包含的信息来在检测 ISA 扩展，而用户态可以通过 HWCAP/cpuinfo/环境变量/SIGILL 等方式对 RISC-V ISA 进行检测，但大部分方法本质上都是基于 ISA-string，对 ISA-string 的解析容易出错，且用户态缺少相应的硬件检测系统调用。

如今，用户空间的 RISC-V ISA 检测机制发生了一些变化，在 Linux v6.4 版本中引入了新的系统调用 hw_probe，用于检测硬件。目前这一系统调用支持的功能比较少，但它能够解决 HWCAP 位数不够用，用户空间缺少硬件检测的系统调用等问题。

## 参考资料

- [kernel.org][001]
- [RISC-V Linux 启动流程分析][002]
- [RISC-V 当前指令集扩展类别与检测方式][003]
- [commit ea3de9c: RISC-V: Add a syscall for HW probing][004]
- [引入 RISC-V Hardware Probing User Interface 的邮件讨论][005]
- [commit 6bcff51: RISC-V: Add bitmap reprensenting ISA features common across CPUs][006]
- [OpenSBI RISC-V ISA 扩展检测与支持方式分析][007]
- [PLCT 2022 年对 RISC-V ISA 扩展检测方式的调研][008]

[001]: https://mirrors.edge.kernel.org/pub/linux/kernel/
[002]: https://tinylab.org/riscv-linux-startup/
[003]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230715-riscv-isa-extensions-discovery-1.md
[004]: https://github.com/torvalds/linux/commit/ea3de9ce8aa280c5175c835bd3e94a3a9b814b74#diff-24372ab3ad2d22486b15d8a8f7e9e53a04e16efe0a392cec83786e24cb767bdd
[005]: https://lore.kernel.org/all/20230411-primate-rice-a5c102f90c6c@wendy/https://lore.kernel.org/all/20230411-primate-rice-a5c102f90c6c@wendy/
[006]: https://github.com/torvalds/linux/commit/6bcff51539ccae5431a01f60293419dbae21100f
[007]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230816-riscv-isa-discovery-4-opensbi.md
[008]: https://github.com/plctlab/PLCT-Open-Reports/blob/master/20220706-%E9%83%91%E9%88%9C%E5%A3%AC-discovery.pdf
