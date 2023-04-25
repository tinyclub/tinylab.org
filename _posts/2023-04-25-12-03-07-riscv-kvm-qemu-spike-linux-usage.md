---
layout: post
author: 'Liming Wang'
title: '用 QEMU/Spike+KVM 运行 Host/Guest Linux'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-kvm-qemu-spike-linux-usage/
description: '用 QEMU/Spike+KVM 运行 Host/Guest Linux'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [header]
> Author:    潘夏凯 <13212017962@163.com>
> Date:      2022/07/09
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V 虚拟化技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I5E4VB)
> Sponsor:   PLCT Lab, ISCAS


## 前言：如何运行一个操作系统

本文基于 QEMU 和 Spike 模拟器，借助 RISC-V KVM 成功实现了引导 Host Linux 操作系统，并在已经引导起来的 Linux 上实现了虚拟化以运行 Guest Linux。

### 概览

启动并运行一个操作系统的过程可以简单地看作这样一个过程，即硬件（CPU，内存等）加电，从特定的位置加载行为固定的程序（Boot loader）完成对于硬件的状态的设置并载入操作系统（OS）最终使之运行。所谓虚拟化则可以形象地解释为将硬件资源包装起来（虚拟化）从而使之支持被多个程序（如多个 Guest OS）调用。

### 组件简介

#### 基于模拟器的硬件（Hardware in Simulator）

Spike，QEMU 通过软件来模拟硬件，由此提供了一个可供用于调试系统级软件及外设的相对低成本的解决方案。

#### 固件与引导（Boot loader）

一般而言，烧录在 ROM 上的一些具备特定功能的程序被称为 `boot loader`，当硬件加电启动后，该段程序默认开始执行其初始化与加载 OS 等其他程序的任务。RISC-V 开发中较为常用的有 BBL（Berkeley Boot Loader），OpenSBI（from Western Digital），U-boot（多用于嵌入式开发），还有 RustSBI（SBI 标准的 Rust 实现）等。

#### 操作系统（OS）

- 内核（Kernel）
- 文件系统（FileSystem）

#### 虚拟化工具（Hypervisor）

在硬件支持虚拟化的基础之上（HS-mode in RISC-V），需要软件协助管理整个虚拟化的过程，一种可行的实现就是实现一个 Hypervisor 作为 Host 与 Guest 的中间层，用于管理诸多虚拟化的实例和虚拟机，KVM 则是其中之一。

### KVM 简介

[KVM][003]（Kernel-based Virtual Machine）是一个开源的基于内核的虚拟层实现（Hypervisor）。KVM 的实现包含 **内核模块（kernel module** 和 **用户工具（userspace kvmtool）** 两个部分：

- 内核模块（KVM kernel Module）
  - 一个可供载入到 Linux 内核的模块，能够提供 CPU、内存、中断的虚拟化。即将一个 Linux kernel 修饰为一个 Hypervisor。
- 用户工具（KVM user-space tool）
  - 帮助用户创建与管理客户端实例（Guest Instances）如虚拟机。类似于提供给每个 Guest 的包装器，保证 Guest 一定程度上能够无视上述修饰而像 Host 一样运行。

KVM 虚拟化图示（基于 RISC-V）如下：

![kvm](/wp-content/uploads/2022/03/riscv-linux/images/20220708-kvm-linux/kvm-hypervisor.png)

## 实验环境

### 软件版本说明

用到的软件以及版本信息汇总如下：

| Software                 | commit ID or version No.                 |
|--------------------------|------------------------------------------|
| Docker Desktop           | 4.10.1 (82475)                           |
| container image          | Ubuntu:20.04                             |
| QEMU                     | a74c66b1b933b37248dd4a3f70a14f779f8825ba |
| Spike                    | ac466a21df442c59962589ba296c702631e041b5 |
| OpenSBI                  | 4489876e933d8ba0d8bc6c64bae71e295d45faac |
| Kernel                   | 5.19-rc5                                 |
| Busybox(to build RootFS) | 1.33.1                                   |

### 组件构建结果速览

基于本文演示，所有软件构建结果如下表所示：

所有指令均已在 docker 环境下基于 Ubuntu:20.04 镜像（image）创建的容器（container）中运行通过。

| Item                             | Products                                                                     | Comments                                                                    |
|----------------------------------|------------------------------------------------------------------------------|-----------------------------------------------------------------------------|
| QEMU(Simulator)                  | `./qemu/build/qemu-system-riscv64`                                           | QEMU system emulator                                                        |
| Spike(Simulator)                 | ./riscv-isa-sim/spike                                                        | spike simulator                                                             |
| **Firmware**(OpenSBI)            | `./opensbi/build/platform/generic/firmware/fw_jump.bin` (`fw_jump.elf`)      | M-mode runtime firmware (`-bios .../*.bin` for QEMU; `.../*.elf` for Spike) |
| **Kernel Image**                 | `build-riscv64/arch/riscv/boot/Image`; `build-riscv64/arch/riscv/kvm/kvm.ko` | `--kernel`; `Image` as OS kernel, `kvm.ko` KVM kernel module;               |
| userspace **kvmtool**            | `./kvmtool/lkvm-static`                                                      | userspace kvmtool                                                           |
| **RootFS**(use Busybox to build) | `./rootfs_kvm_riscv64.img`                                                   | `--initrd`                                                                  |

### 基础环境准备

在开工之前，我们需要先准备好基于 Docker container 的基础实验环境：

```docker
# download image if it doesnot exist, create container kvm based on this image and start it interactively
docker run -it --name kvm ubuntu:20.04 /bin/bash
# install necessary toolchain and dependency (if the below is not enough, feel free to install what you want)
root@0152fed4b28d:~# apt install gcc g++ gcc-riscv64-linux-gnu wget flex bison bc cpio make pkg-config
```

## 组件下载与编译

### QEMU 模拟器

首先，在前述 docker container 的基础上安装编译所需的软件：

```shell
apt install git libglib2.0-dev libfdt-dev libpixman-1-dev zlib1g-dev libncurses-dev libssl-dev ninja-build
```

QEMU 可以从官网直接下载：

```shell
wget https://download.qemu.org/qemu-7.0.0.tar.xz
tar xvJf qemu-7.0.0.tar.xz
cd qemu-7.0.0
```

也可以从 GitLab 下载：

```shell
git clone https://gitlab.com/qemu-project/qemu.git
cd qemu
git submodule init
git submodule update --recursive
```

然后编译，可参考 [官方文档 1][009] 和 [官方文档 2][008]。

指定支持的 ISA 并编译：

```shell
./configure --target-list="riscv32-softmmu riscv64-softmmu" && make -j`nproc`
```

编译后生成的文件在：`./qemu/build/qemu-system-riscv64`。

### Spike 模拟器

```shell
apt install device-tree-compiler
git clone https://github.com/riscv-software-src/riscv-isa-sim && cd riscv-isa-sim
./configure
make
# ./riscv-isa-sim/spike will be the built Spike simulator in later use
```

### OpenSBI 固件

```shell
git clone https://github.com/riscv/opensbi.git
cd opensbi
export CROSS_COMPILE=riscv64-linux-gnu-
make PLATFORM=generic  -j`nproc`
# ./opensbi/build/platform/generic/firmware/fw_jump.bin as M-mode runtime firmware
```

### Linux 内核

首先，修改内核代码使之支持在 Host Linux 中以 `rmmod kvm` 的指令**卸载 kvm module**：

```C
root@0152fed4b28d:~/linux# git diff
diff --git a/arch/riscv/kvm/main.c b/arch/riscv/kvm/main.c
index 1549205fe5fe..d8e91a7b1a72 100644
--- a/arch/riscv/kvm/main.c
+++ b/arch/riscv/kvm/main.c
@@ -122,6 +122,12 @@ void kvm_arch_exit(void)
 {
 }

+static void riscv_kvm_exit(void)
+{
+       kvm_exit();
+}
+module_exit(riscv_kvm_exit);
+
 static int riscv_kvm_init(void)
 {
        return kvm_init(NULL, sizeof(struct kvm_vcpu), 0, THIS_MODULE);
```

接着下载内核源码：

```
git clone https://github.com/kvm-riscv/linux.git # the mirror of the newest kernel version in kvm-riscv howto
```

**友情提示**：

- 版本：Linux 内核下载可以通过 [内核官网][010] 选择对应版本下载，截至 2022 年 7 月 6 日最新版内核为 `2022-07-03 5.19-rc5`，此版本与 `howto` 中的 [内核镜像仓库][006] 版本一致
- 用时：镜像较大，下载耗时可能会很长甚至中断（尤其是使用 git clone 时）

接着，创建编译目录并配置处理器架构和交叉编译器等环境变量：

```shell
export ARCH=riscv
export CROSS_COMPILE=riscv64-linux-gnu-
mkdir build-riscv64
```

接着，通过 menuconfig 配置内核选项。在配置之前，需要注意最新版 Linux 内核默认关闭 RISC-V SBI 相关选项，需要通过以下命令手动配置开启，相关讨论参见该 issue，具体细节参见 [此文][012]。

```shell
make -C linux O=`pwd`/build-riscv64 menuconfig # change options of kernel compiling to generate build-riscv64/.config (output dir)
```

最后一个环节就是编译了：

```shell
make -C linux O=`pwd`/build-riscv64  -j`nproc`
```

编译完，咱们获得了两个重要的二进制文件：

- 内核映像：`build-riscv64/arch/riscv/boot/Image`
- KVM 内核模块：`build-riscv64/arch/riscv/kvm/kvm.ko`

### kvmtools 工具

首先，需要准备好 libfdt 库，将其添加到工具链所在位置的 sysroot 文件夹中：

```cmake
git clone git://git.kernel.org/pub/scm/utils/dtc/dtc.git
cd dtc
export ARCH=riscv
export CROSS_COMPILE=riscv64-linux-gnu-
export CC="${CROSS_COMPILE}gcc -mabi=lp64d -march=rv64gc" # riscv toolchain should be configured with --enable-multilib to support the most common -march/-mabi options if you build it from source code
TRIPLET=$($CC -dumpmachine)
SYSROOT=$($CC -print-sysroot)
make libfdt  -j`nproc`
make NO_PYTHON=1 NO_YAML=1 DESTDIR=$SYSROOT PREFIX=/usr LIBDIR=/usr/lib64/lp64d install-lib install-includes  -j`nproc`
cd ..

# install cross-compiled libfdt library at $SYSROOT/usr/lib64/lp64d directory of cross-compile toolchain
```

接着，编译 kvmtools：

```
git clone https://git.kernel.org/pub/scm/linux/kernel/git/will/kvmtool.git
cd kvmtool
export ARCH=riscv
export CROSS_COMPILE=riscv64-linux-gnu-
cd kvmtool
make lkvm-static  -j`nproc`
${CROSS_COMPILE}strip lkvm-static
cd ..
```

### RootFS 文件系统

RootFS 包括 `KVM kernel module`, `userspace kvmtools`, `kernel image` 三部分。

```
export ARCH=riscv
export CROSS_COMPILE=riscv64-linux-gnu-
git clone https://github.com/kvm-riscv/howto.git
wget https://busybox.net/downloads/busybox-1.33.1.tar.bz2
tar -C . -xvf ./busybox-1.33.1.tar.bz2
mv ./busybox-1.33.1 ./busybox-1.33.1-kvm-riscv64
cp -f ./howto/configs/busybox-1.33.1_defconfig busybox-1.33.1-kvm-riscv64/.config
make -C busybox-1.33.1-kvm-riscv64 oldconfig
make -C busybox-1.33.1-kvm-riscv64 install
mkdir -p busybox-1.33.1-kvm-riscv64/_install/etc/init.d
mkdir -p busybox-1.33.1-kvm-riscv64/_install/dev
mkdir -p busybox-1.33.1-kvm-riscv64/_install/proc
mkdir -p busybox-1.33.1-kvm-riscv64/_install/sys
mkdir -p busybox-1.33.1-kvm-riscv64/_install/apps
ln -sf /sbin/init busybox-1.33.1-kvm-riscv64/_install/init
cp -f ./howto/configs/busybox/fstab busybox-1.33.1-kvm-riscv64/_install/etc/fstab
cp -f ./howto/configs/busybox/rcS busybox-1.33.1-kvm-riscv64/_install/etc/init.d/rcS
cp -f ./howto/configs/busybox/motd busybox-1.33.1-kvm-riscv64/_install/etc/motd
cp -f ./kvmtool/lkvm-static busybox-1.33.1-kvm-riscv64/_install/apps
cp -f ./build-riscv64/arch/riscv/boot/Image busybox-1.33.1-kvm-riscv64/_install/apps
cp -f ./build-riscv64/arch/riscv/kvm/kvm.ko busybox-1.33.1-kvm-riscv64/_install/apps
cd busybox-1.33.1-kvm-riscv64/_install; find ./ | cpio -o -H newc > ../../rootfs_kvm_riscv64.img; cd -
```

## 通过 QEMU+KVM 运行 Linux

### 启动 Host Linux

```bash
./qemu/build/riscv64-softmmu/qemu-system-riscv64 -cpu rv64 -M virt -m 512M -nographic \
  -bios opensbi/build/platform/generic/firmware/fw_jump.bin \
  -kernel ./build-riscv64/arch/riscv/boot/Image \
  -initrd ./rootfs_kvm_riscv64.img \
  -append "root=/dev/ram rw console=ttyS0 earlycon=sbi"
```

需要提醒的是，在上一步中，如果 initrd 未使用 RISC-V 工具链编译，可能会出现如下问题：

```
[ 0.629637] ---[ end Kernel panic - not syncing: No working init found. Try passing init= option to kernel. See Linux Documentation/admin-guide/init.rst for guidance. ]---
```

### 启动 Guest Machine

在上一步打开的仿真环境中执行以下步骤

首先加入 KVM 内核模块：

```
insmod apps/kvm.ko
```

接着使用 KVM 用户空间工具 kvmtool 运行 Guest Linux：

```
./apps/lkvm-static run -m 128 -c2 --console serial -p "console=ttyS0 earlycon=uart8250,mmio,0x3f8" -k ./apps/Image --debug
```

### 结果日志

```
root@0152fed4b28d:~# ./qemu/build/qemu-system-riscv64 -cpu rv64 -M virt -m 512M -nographic -bios opensbi/build/platform/generic/firmware/fw_jump.bin -kernel ./build-riscv64/arch/riscv/boot/Image -initrd ./rootfs_kvm_riscv64.img -append "root=/dev/ram rw console=ttyS0 earlycon=sbi"

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
Firmware Size             : 284 KB
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
Boot HART Priv Version    : v1.12
Boot HART Base ISA        : rv64imafdch
Boot HART ISA Extensions  : time
Boot HART PMP Count       : 16
Boot HART PMP Granularity : 4
Boot HART PMP Address Bits: 54
Boot HART MHPM Count      : 16
Boot HART MIDELEG         : 0x0000000000001666
Boot HART MEDELEG         : 0x0000000000f0b509
[    0.000000] Linux version 5.19.0-rc5-dirty (root@0152fed4b28d) (riscv64-linux-gnu-gcc (Ubuntu 9.4.0-1ubuntu1~20.04) 9.4.0, GNU ld (GNU Binutils for Ubuntu) 2.34) #5 SMP Fri Jul 8 14:48:33 CST 2022
[    0.000000] OF: fdt: Ignoring memory range 0x80000000 - 0x80200000
[    0.000000] Machine model: riscv-virtio,qemu
[    0.000000] earlycon: sbi0 at I/O port 0x0 (options '')
[    0.000000] printk: bootconsole [sbi0] enabled
[    0.000000] efi: UEFI not found.
[    0.000000] Zone ranges:
[    0.000000]   DMA32    [mem 0x0000000080200000-0x000000009fffffff]
[    0.000000]   Normal   empty
[    0.000000] Movable zone start for each node
[    0.000000] Early memory node ranges
[    0.000000]   node   0: [mem 0x0000000080200000-0x000000009fffffff]
[    0.000000] Initmem setup node 0 [mem 0x0000000080200000-0x000000009fffffff]
[    0.000000] SBI specification v1.0 detected
[    0.000000] SBI implementation ID=0x1 Version=0x10001
[    0.000000] SBI TIME extension detected
[    0.000000] SBI IPI extension detected
[    0.000000] SBI RFENCE extension detected
[    0.000000] SBI SRST extension detected
[    0.000000] SBI HSM extension detected
[    0.000000] riscv: base ISA extensions acdfhim
[    0.000000] riscv: ELF capabilities acdfim
[    0.000000] percpu: Embedded 18 pages/cpu s34104 r8192 d31432 u73728
[    0.000000] Built 1 zonelists, mobility grouping on.  Total pages: 128775
[    0.000000] Kernel command line: root=/dev/ram rw console=ttyS0 earlycon=sbi
[    0.000000] Dentry cache hash table entries: 65536 (order: 7, 524288 bytes, linear)
[    0.000000] Inode-cache hash table entries: 32768 (order: 6, 262144 bytes, linear)
[    0.000000] mem auto-init: stack:off, heap alloc:off, heap free:off
[    0.000000] Virtual kernel memory layout:
[    0.000000]       fixmap : 0xff1bfffffee00000 - 0xff1bffffff000000   (2048 kB)
[    0.000000]       pci io : 0xff1bffffff000000 - 0xff1c000000000000   (  16 MB)
[    0.000000]      vmemmap : 0xff1c000000000000 - 0xff20000000000000   (1024 TB)
[    0.000000]      vmalloc : 0xff20000000000000 - 0xff60000000000000   (16384 TB)
[    0.000000]       lowmem : 0xff60000000000000 - 0xff6000001fe00000   ( 510 MB)
[    0.000000]       kernel : 0xffffffff80000000 - 0xffffffffffffffff   (2047 MB)
[    0.000000] Memory: 471456K/522240K available (6518K kernel code, 4864K rwdata, 4096K rodata, 2172K init, 397K bss, 50784K reserved, 0K cma-reserved)
[    0.000000] SLUB: HWalign=64, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
[    0.000000] rcu: Hierarchical RCU implementation.
[    0.000000] rcu:     RCU restricting CPUs from NR_CPUS=8 to nr_cpu_ids=1.
[    0.000000] rcu:     RCU debug extended QS entry/exit.
[    0.000000]  Tracing variant of Tasks RCU enabled.
[    0.000000] rcu: RCU calculated value of scheduler-enlistment delay is 25 jiffies.
[    0.000000] rcu: Adjusting geometry for rcu_fanout_leaf=16, nr_cpu_ids=1
[    0.000000] NR_IRQS: 64, nr_irqs: 64, preallocated irqs: 0
[    0.000000] riscv-intc: 64 local interrupts mapped
[    0.000000] plic: plic@c000000: mapped 96 interrupts with 1 handlers for 2 contexts.
[    0.000000] rcu: srcu_init: Setting srcu_struct sizes based on contention.
[    0.000000] riscv_timer_init_dt: Registering clocksource cpuid [0] hartid [0]
[    0.000000] clocksource: riscv_clocksource: mask: 0xffffffffffffffff max_cycles: 0x24e6a1710, max_idle_ns: 440795202120 ns
[    0.000142] sched_clock: 64 bits at 10MHz, resolution 100ns, wraps every 4398046511100ns
[    0.015542] Console: colour dummy device 80x25
[    0.020750] Calibrating delay loop (skipped), value calculated using timer frequency.. 20.00 BogoMIPS (lpj=40000)
[    0.025722] pid_max: default: 32768 minimum: 301
[    0.031495] Mount-cache hash table entries: 1024 (order: 1, 8192 bytes, linear)
[    0.034808] Mountpoint-cache hash table entries: 1024 (order: 1, 8192 bytes, linear)
[    0.074794] cblist_init_generic: Setting adjustable number of callback queues.
[    0.078104] cblist_init_generic: Setting shift to 0 and lim to 1.
[    0.081658] riscv: ELF compat mode supported
[    0.082496] ASID allocator using 16 bits (65536 entries)
[    0.087668] rcu: Hierarchical SRCU implementation.
[    0.095219] EFI services will not be available.
[    0.102311] smp: Bringing up secondary CPUs ...
[    0.104772] smp: Brought up 1 node, 1 CPU
[    0.615904] devtmpfs: initialized
[    0.626513] clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785100000 ns
[    0.630962] futex hash table entries: 256 (order: 2, 16384 bytes, linear)
[    0.640986] NET: Registered PF_NETLINK/PF_ROUTE protocol family
[    0.652546] cpuidle: using governor menu
[    0.689614] HugeTLB registered 2.00 MiB page size, pre-allocated 0 pages
[    0.702174] iommu: Default domain type: Translated
[    0.706376] iommu: DMA domain TLB invalidation policy: strict mode
[    0.711015] SCSI subsystem initialized
[    0.716260] usbcore: registered new interface driver usbfs
[    0.719412] usbcore: registered new interface driver hub
[    0.722271] usbcore: registered new device driver usb
[    0.745275] vgaarb: loaded
[    0.747591] clocksource: Switched to clocksource riscv_clocksource
[    0.771282] NET: Registered PF_INET protocol family
[    0.774681] IP idents hash table entries: 8192 (order: 4, 65536 bytes, linear)
[    0.782381] tcp_listen_portaddr_hash hash table entries: 256 (order: 1, 8192 bytes, linear)
[    0.786971] Table-perturb hash table entries: 65536 (order: 6, 262144 bytes, linear)
[    0.790377] TCP established hash table entries: 4096 (order: 3, 32768 bytes, linear)
[    0.795760] TCP bind hash table entries: 4096 (order: 5, 131072 bytes, linear)
[    0.797898] TCP: Hash tables configured (established 4096 bind 4096)
[    0.803091] UDP hash table entries: 256 (order: 2, 24576 bytes, linear)
[    0.806493] UDP-Lite hash table entries: 256 (order: 2, 24576 bytes, linear)
[    0.811071] NET: Registered PF_UNIX/PF_LOCAL protocol family
[    0.818711] RPC: Registered named UNIX socket transport module.
[    0.821977] RPC: Registered udp transport module.
[    0.824307] RPC: Registered tcp transport module.
[    0.826181] RPC: Registered tcp NFSv4.1 backchannel transport module.
[    0.829536] PCI: CLS 0 bytes, default 64
[    0.845435] Unpacking initramfs...
[    0.868143] workingset: timestamp_bits=62 max_order=17 bucket_order=0
[    0.909149] NFS: Registering the id_resolver key type
[    0.910778] Key type id_resolver registered
[    0.912817] Key type id_legacy registered
[    0.915129] nfs4filelayout_init: NFSv4 File Layout Driver Registering...
[    0.918431] nfs4flexfilelayout_init: NFSv4 Flexfile Layout Driver Registering...
[    0.935866] 9p: Installing v9fs 9p2000 file system support
[    0.941894] NET: Registered PF_ALG protocol family
[    0.945951] Block layer SCSI generic (bsg) driver version 0.4 loaded (major 250)
[    0.950035] io scheduler mq-deadline registered
[    0.952344] io scheduler kyber registered
[    0.989260] pci-host-generic 30000000.pci: host bridge /soc/pci@30000000 ranges:
[    0.993242] pci-host-generic 30000000.pci:       IO 0x0003000000..0x000300ffff -> 0x0000000000
[    0.996812] pci-host-generic 30000000.pci:      MEM 0x0040000000..0x007fffffff -> 0x0040000000
[    1.000530] pci-host-generic 30000000.pci:      MEM 0x0400000000..0x07ffffffff -> 0x0400000000
[    1.004671] pci-host-generic 30000000.pci: Memory resource size exceeds max for 32 bits
[    1.009984] pci-host-generic 30000000.pci: ECAM at [mem 0x30000000-0x3fffffff] for [bus 00-ff]
[    1.016744] pci-host-generic 30000000.pci: PCI host bridge to bus 0000:00
[    1.020444] pci_bus 0000:00: root bus resource [bus 00-ff]
[    1.022890] pci_bus 0000:00: root bus resource [io  0x0000-0xffff]
[    1.026181] pci_bus 0000:00: root bus resource [mem 0x40000000-0x7fffffff]
[    1.029150] pci_bus 0000:00: root bus resource [mem 0x400000000-0x7ffffffff]
[    1.032837] pci 0000:00:00.0: [1b36:0008] type 00 class 0x060000
[    1.112920] Freeing initrd memory: 22232K
[    1.235256] Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
[    1.249547] printk: console [ttyS0] disabled
[    1.253150] 10000000.uart: ttyS0 at MMIO 0x10000000 (irq = 1, base_baud = 230400) is a 16550A
[    1.258759] printk: console [ttyS0] enabled
[    1.258759] printk: console [ttyS0] enabled
[    1.262596] printk: bootconsole [sbi0] disabled
[    1.262596] printk: bootconsole [sbi0] disabled
[    1.291214] loop: module loaded
[    1.297228] e1000e: Intel(R) PRO/1000 Network Driver
[    1.298424] e1000e: Copyright(c) 1999 - 2015 Intel Corporation.
[    1.300433] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[    1.301964] ehci-pci: EHCI PCI platform driver
[    1.303655] ehci-platform: EHCI generic platform driver
[    1.305293] ohci_hcd: USB 1.1 'Open' Host Controller (OHCI) Driver
[    1.306182] ohci-pci: OHCI PCI platform driver
[    1.308204] ohci-platform: OHCI generic platform driver
[    1.311540] usbcore: registered new interface driver uas
[    1.313508] usbcore: registered new interface driver usb-storage
[    1.316431] mousedev: PS/2 mouse device common for all mice
[    1.322220] goldfish_rtc 101000.rtc: registered as rtc0
[    1.324960] goldfish_rtc 101000.rtc: setting system clock to 2022-07-08T06:58:09 UTC (1657263489)
[    1.331663] syscon-poweroff soc:poweroff: pm_power_off already claimed for sbi_srst_power_off
[    1.333780] syscon-poweroff: probe of soc:poweroff failed with error -16
[    1.338818] sdhci: Secure Digital Host Controller Interface driver
[    1.340662] sdhci: Copyright(c) Pierre Ossman
[    1.342121] sdhci-pltfm: SDHCI platform and OF driver helper
[    1.345732] usbcore: registered new interface driver usbhid
[    1.348886] usbhid: USB HID core driver
[    1.351700] riscv-pmu-sbi: SBI PMU extension is available
[    1.353803] riscv-pmu-sbi: 16 firmware and 18 hardware counters
[    1.355525] riscv-pmu-sbi: Perf sampling/filtering is not supported as sscof extension is not available
[    1.365361] NET: Registered PF_INET6 protocol family
[    1.381090] Segment Routing with IPv6
[    1.382406] In-situ OAM (IOAM) with IPv6
[    1.384585] sit: IPv6, IPv4 and MPLS over IPv4 tunneling driver
[    1.391094] NET: Registered PF_PACKET protocol family
[    1.394654] 9pnet: Installing 9P2000 support
[    1.396662] Key type dns_resolver registered
[    1.401846] debug_vm_pgtable: [debug_vm_pgtable         ]: Validating architecture page table helpers
[    1.454064] Freeing unused kernel image (initmem) memory: 2172K
[    1.460808] Run /init as init process
           _  _
          | ||_|
          | | _ ____  _   _  _  _
          | || |  _ \| | | |\ \/ /
          | || | | | | |_| |/    \
          |_||_|_| |_|\____|\_/\_/

               Busybox Rootfs

Please press Enter to activate this console.
/ # insmod apps/kvm.ko
[   13.404010] kvm [48]: hypervisor extension available
[   13.405257] kvm [48]: using Sv57x4 G-stage page table format
[   13.406316] kvm [48]: VMID 14 bits available
/ # ./apps/lkvm-static run -m 128 -c2 --console serial -p "console=ttyS0 earlyco
n=uart8250,mmio,0x3f8" -k ./apps/Image --debug
  # lkvm run -k ./apps/Image -m 128 -c 2 --name guest-49
  Info: (riscv/kvm.c) kvm__arch_load_kernel_image:125: Loaded kernel to 0x80200000 (19789312 bytes)
  Info: (riscv/kvm.c) kvm__arch_load_kernel_image:136: Placing fdt at 0x81c00000 - 0x87ffffff
  # Warning: The maximum recommended amount of VCPUs is 1
  Info: (virtio/mmio.c) virtio_mmio_init:197: virtio-mmio.devices=0x200@0x10000000:5
  Info: (virtio/mmio.c) virtio_mmio_init:197: virtio-mmio.devices=0x200@0x10000200:6
  Info: (virtio/mmio.c) virtio_mmio_init:197: virtio-mmio.devices=0x200@0x10000400:7
[    0.000000] Linux version 5.19.0-rc5-dirty (root@0152fed4b28d) (riscv64-linux-gnu-gcc (Ubuntu 9.4.0-1ubuntu1~20.04) 9.4.0, GNU ld (GNU Binutils for Ubuntu) 2.34) #5 SMP Fri Jul 8 14:48:33 CST 2022
[    0.000000] OF: fdt: Ignoring memory range 0x80000000 - 0x80200000
[    0.000000] Machine model: linux,dummy-virt
[    0.000000] earlycon: uart8250 at MMIO 0x00000000000003f8 (options '')
[    0.000000] printk: bootconsole [uart8250] enabled
[    0.000000] efi: UEFI not found.
[    0.000000] Zone ranges:
[    0.000000]   DMA32    [mem 0x0000000080200000-0x0000000087ffffff]
[    0.000000]   Normal   empty
[    0.000000] Movable zone start for each node
[    0.000000] Early memory node ranges
[    0.000000]   node   0: [mem 0x0000000080200000-0x0000000087ffffff]
[    0.000000] Initmem setup node 0 [mem 0x0000000080200000-0x0000000087ffffff]
[    0.000000] SBI specification v0.3 detected
[    0.000000] SBI implementation ID=0x3 Version=0x51300
[    0.000000] SBI TIME extension detected
[    0.000000] SBI IPI extension detected
[    0.000000] SBI RFENCE extension detected
[    0.000000] SBI SRST extension detected
[    0.000000] SBI HSM extension detected
[    0.000000] riscv: base ISA extensions acdfim
[    0.000000] riscv: ELF capabilities acdfim
[    0.000000] percpu: Embedded 18 pages/cpu s34104 r8192 d31432 u73728
[    0.000000] Built 1 zonelists, mobility grouping on.  Total pages: 31815
[    0.000000] Kernel command line:  console=ttyS0 rw rootflags=trans=virtio,version=9p2000.L,cache=loose rootfstype=9p init=/virt/init  ip=dhcp console=ttyS0 earlycon=uart8250,mmio,0x3f8
[    0.000000] Dentry cache hash table entries: 16384 (order: 5, 131072 bytes, linear)
[    0.000000] Inode-cache hash table entries: 8192 (order: 4, 65536 bytes, linear)
[    0.000000] mem auto-init: stack:off, heap alloc:off, heap free:off
[    0.000000] Virtual kernel memory layout:
[    0.000000]       fixmap : 0xff1bfffffee00000 - 0xff1bffffff000000   (2048 kB)
[    0.000000]       pci io : 0xff1bffffff000000 - 0xff1c000000000000   (  16 MB)
[    0.000000]      vmemmap : 0xff1c000000000000 - 0xff20000000000000   (1024 TB)
[    0.000000]      vmalloc : 0xff20000000000000 - 0xff60000000000000   (16384 TB)
[    0.000000]       lowmem : 0xff60000000000000 - 0xff60000007e00000   ( 126 MB)
[    0.000000]       kernel : 0xffffffff80000000 - 0xffffffffffffffff   (2047 MB)
[    0.000000] Memory: 106368K/129024K available (6518K kernel code, 4864K rwdata, 4096K rodata, 2172K init, 397K bss, 22656K reserved, 0K cma-reserved)
[    0.000000] SLUB: HWalign=64, Order=0-3, MinObjects=0, CPUs=2, Nodes=1
[    0.000000] rcu: Hierarchical RCU implementation.
[    0.000000] rcu:     RCU restricting CPUs from NR_CPUS=8 to nr_cpu_ids=2.
[    0.000000] rcu:     RCU debug extended QS entry/exit.
[    0.000000]  Tracing variant of Tasks RCU enabled.
[    0.000000] rcu: RCU calculated value of scheduler-enlistment delay is 25 jiffies.
[    0.000000] rcu: Adjusting geometry for rcu_fanout_leaf=16, nr_cpu_ids=2
[    0.000000] NR_IRQS: 64, nr_irqs: 64, preallocated irqs: 0
[    0.000000] riscv-intc: 64 local interrupts mapped
[    0.000000] plic: interrupt-controller@0c000000: mapped 1023 interrupts with 2 handlers for 4 contexts.
[    0.000000] rcu: srcu_init: Setting srcu_struct sizes based on contention.
[    0.000000] riscv_timer_init_dt: Registering clocksource cpuid [0] hartid [0]
[    0.000000] clocksource: riscv_clocksource: mask: 0xffffffffffffffff max_cycles: 0x24e6a1710, max_idle_ns: 440795202120 ns
[    0.000132] sched_clock: 64 bits at 10MHz, resolution 100ns, wraps every 4398046511100ns
[    0.058657] Console: colour dummy device 80x25
[    0.095279] Calibrating delay loop (skipped), value calculated using timer frequency.. 20.00 BogoMIPS (lpj=40000)
[    0.164253] pid_max: default: 32768 minimum: 301
[    0.224586] Mount-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[    0.277689] Mountpoint-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[    1.368094] cblist_init_generic: Setting adjustable number of callback queues.
[    1.411153] cblist_init_generic: Setting shift to 1 and lim to 1.
[    1.446243] riscv: ELF compat mode supported
[    1.448377] ASID allocator using 16 bits (65536 entries)
[    1.499701] rcu: Hierarchical SRCU implementation.
[    1.531291] EFI services will not be available.
[    2.491551] smp: Bringing up secondary CPUs ...
[    2.551252] smp: Brought up 1 node, 2 CPUs
[    2.650149] devtmpfs: initialized
[    2.711053] clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785100000 ns
[    2.781423] futex hash table entries: 512 (order: 3, 32768 bytes, linear)
[    3.678845] NET: Registered PF_NETLINK/PF_ROUTE protocol family
[    3.738055] cpuidle: using governor menu
[    3.894209] HugeTLB registered 2.00 MiB page size, pre-allocated 0 pages
[    3.970099] iommu: Default domain type: Translated
[    4.001139] iommu: DMA domain TLB invalidation policy: strict mode
[    4.063992] SCSI subsystem initialized
[    4.121977] usbcore: registered new interface driver usbfs
[    4.179208] usbcore: registered new interface driver hub
[    4.219538] usbcore: registered new device driver usb
[    4.613374] vgaarb: loaded
[    4.653564] clocksource: Switched to clocksource riscv_clocksource
[    4.926025] NET: Registered PF_INET protocol family
[    4.974051] IP idents hash table entries: 2048 (order: 2, 16384 bytes, linear)
[    5.058030] tcp_listen_portaddr_hash hash table entries: 128 (order: 0, 4096 bytes, linear)
[    5.148512] Table-perturb hash table entries: 65536 (order: 6, 262144 bytes, linear)
[    5.209568] TCP established hash table entries: 1024 (order: 1, 8192 bytes, linear)
[    5.276291] TCP bind hash table entries: 1024 (order: 3, 32768 bytes, linear)
[    5.341897] TCP: Hash tables configured (established 1024 bind 1024)
[    5.406785] UDP hash table entries: 256 (order: 2, 24576 bytes, linear)
[    5.466837] UDP-Lite hash table entries: 256 (order: 2, 24576 bytes, linear)
[    5.535911] NET: Registered PF_UNIX/PF_LOCAL protocol family
[    5.624395] RPC: Registered named UNIX socket transport module.
[    5.670725] RPC: Registered udp transport module.
[    5.700296] RPC: Registered tcp transport module.
[    5.728202] RPC: Registered tcp NFSv4.1 backchannel transport module.
[    5.772245] PCI: CLS 0 bytes, default 64
[    5.827469] workingset: timestamp_bits=62 max_order=15 bucket_order=0
[    6.735634] NFS: Registering the id_resolver key type
[    6.774655] Key type id_resolver registered
[    6.802063] Key type id_legacy registered
[    6.831186] nfs4filelayout_init: NFSv4 File Layout Driver Registering...
[    6.875372] nfs4flexfilelayout_init: NFSv4 Flexfile Layout Driver Registering...
[    6.929106] 9p: Installing v9fs 9p2000 file system support
[    6.977877] NET: Registered PF_ALG protocol family
[    7.006556] Block layer SCSI generic (bsg) driver version 0.4 loaded (major 250)
[    7.057411] io scheduler mq-deadline registered
[    7.086547] io scheduler kyber registered
[    7.143818] pci-host-generic 30000000.pci: host bridge /smb/pci ranges:
[    7.196469] pci-host-generic 30000000.pci:       IO 0x0000000000..0x000000ffff -> 0x0000000000
[    7.275220] pci-host-generic 30000000.pci:      MEM 0x0040000000..0x007fffffff -> 0x0040000000
[    7.350731] pci-host-generic 30000000.pci: ECAM at [mem 0x30000000-0x3fffffff] for [bus 00-01]
[    7.414455] pci-host-generic 30000000.pci: PCI host bridge to bus 0000:00
[    7.460026] pci_bus 0000:00: root bus resource [bus 00-01]
[    7.498065] pci_bus 0000:00: root bus resource [io  0x0000-0xffff]
[    7.540312] pci_bus 0000:00: root bus resource [mem 0x40000000-0x7fffffff]
[    8.638643] Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
[    8.709733] printk: console [ttyS0] disabled
[    8.762750] 3f8.U6_16550A: ttyS0 at MMIO 0x3f8 (irq = 1, base_baud = 115200) is a 16550A
[    8.823902] printk: console [ttyS0] enabled
[    8.823902] printk: console [ttyS0] enabled
[    8.886645] printk: bootconsole [uart8250] disabled
[    8.886645] printk: bootconsole [uart8250] disabled
[    8.968186] 2f8.U6_16550A: ttyS1 at MMIO 0x2f8 (irq = 2, base_baud = 115200) is a 16550A
[    9.036636] 3e8.U6_16550A: ttyS2 at MMIO 0x3e8 (irq = 3, base_baud = 115200) is a 16550A
[    9.108624] 2e8.U6_16550A: ttyS3 at MMIO 0x2e8 (irq = 4, base_baud = 115200) is a 16550A
[   11.046849] loop: module loaded
[   11.170238] net eth0: Fail to set guest offload.
[   11.210647] virtio_net virtio2 eth0: set_features() failed (-22); wanted 0x0000000000134829, left 0x0080000000134829
[   11.330906] e1000e: Intel(R) PRO/1000 Network Driver
[   11.389219] e1000e: Copyright(c) 1999 - 2015 Intel Corporation.
[   11.430344] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[   11.486294] ehci-pci: EHCI PCI platform driver
[   11.515628] ehci-platform: EHCI generic platform driver
[   11.551281] ohci_hcd: USB 1.1 'Open' Host Controller (OHCI) Driver
[   11.598433] ohci-pci: OHCI PCI platform driver
[   11.634790] ohci-platform: OHCI generic platform driver
[   11.705856] usbcore: registered new interface driver uas
[   11.742504] usbcore: registered new interface driver usb-storage
[   11.783699] mousedev: PS/2 mouse device common for all mice
[   11.831074] sdhci: Secure Digital Host Controller Interface driver
[   11.870880] sdhci: Copyright(c) Pierre Ossman
[   11.899942] sdhci-pltfm: SDHCI platform and OF driver helper
[   11.940434] usbcore: registered new interface driver usbhid
[   11.991571] usbhid: USB HID core driver
[   12.035816] NET: Registered PF_INET6 protocol family
[   12.148551] Segment Routing with IPv6
[   12.179554] In-situ OAM (IOAM) with IPv6
[   12.211655] sit: IPv6, IPv4 and MPLS over IPv4 tunneling driver
[   12.274482] NET: Registered PF_PACKET protocol family
[   12.314503] 9pnet: Installing 9P2000 support
[   12.379475] Key type dns_resolver registered
[   12.443790] debug_vm_pgtable: [debug_vm_pgtable         ]: Validating architecture page table helpers
[   12.728184] Legacy PMU implementation is available
[   12.853858] Sending DHCP requests ., OK
[   12.930786] IP-Config: Got DHCP answer from 192.168.33.1, my address is 192.168.33.15
[   13.022571] IP-Config: Complete:
[   13.050310]      device=eth0, hwaddr=02:15:15:15:15:15, ipaddr=192.168.33.15, mask=255.255.255.0, gw=192.168.33.1
[   13.158329]      host=192.168.33.15, domain=, nis-domain=(none)
[   13.211725]      bootserver=192.168.33.1, rootserver=0.0.0.0, rootpath=
[   13.211943]      nameserver0=192.168.33.1
[   13.394327] VFS: Mounted root (9p filesystem) on device 0:15.
[   13.451710] devtmpfs: mounted
[   13.579633] Freeing unused kernel image (initmem) memory: 2172K
[   13.642610] Run /virt/init as init process
Mounting...
/ # poweroff -f
[   30.712083] reboot: Power down

  # KVM session ended normally.
/ # rmmod kvm
/ # poweroff -f
[   80.496454] reboot: Power down
root@0152fed4b28d:~#
```

## 通过 Spike+KVM 运行 Linux

### 启动 Host Linux

```shell
# Run Host Linux
./riscv-isa-sim/spike -m512 --isa rv64gch --kernel ./build-riscv64/arch/riscv/boot/Image --initrd ./rootfs_kvm_riscv64.img opensbi/build/platform/generic/firmware/fw_jump.elf
```

### 启动 Guest Machine

```
# insert kvm kernel module
insmod apps/kvm.ko
```

```
# start guest os using lkvm-static
./apps/lkvm-static run -m 128 -c2 --console serial -p "console=ttyS0 earlycon=uart8250,mmio,0x3f8" -k ./apps/Image --debug

```

### 结果日志

```

root@0152fed4b28d:~# ./riscv-isa-sim/spike -m512 --isa rv64gch --kernel ./build-riscv64/arch/riscv/boot/Image --initrd ./rootfs_kvm_riscv64.img opensbi/build/platform/generic/firmware/fw_jump.elf

OpenSBI v1.1

---

/ ** \ / \_\_**| _ \_ _|
| | | |\_ ** \_** \_ ** | (\_** | |_) || |
| | | | '_ \ / _ \ '_ \ \_** \| \_ < | |
| |**| | |_) | **/ | | |\_\_**) | |_) || |\_
\_**\_/| .**/ \_**|_| |_|\_\_\_**/|\_**\_/\_\_\_**|
| |
|\_|

Platform Name : ucbbar,spike-bare
Platform Features : medeleg
Platform HART Count : 1
Platform IPI Device : aclint-mswi
Platform Timer Device : aclint-mtimer @ 10000000Hz
Platform Console Device : htif
Platform HSM Device : ---
Platform Reboot Device : htif
Platform Shutdown Device : htif
Firmware Base : 0x80000000
Firmware Size : 284 KB
Runtime SBI Version : 1.0

Domain0 Name : root
Domain0 Boot HART : 0
Domain0 HARTs : 0\*
Domain0 Region00 : 0x0000000002080000-0x00000000020bffff (I)
Domain0 Region01 : 0x0000000002000000-0x000000000207ffff (I)
Domain0 Region02 : 0x0000000080000000-0x000000008007ffff ()
Domain0 Region03 : 0x0000000000000000-0xffffffffffffffff (R,W,X)
Domain0 Next Address : 0x0000000080200000
Domain0 Next Arg1 : 0x0000000082200000
Domain0 Next Mode : S-mode
Domain0 SysReset : yes

Boot HART ID : 0
Boot HART Domain : root
Boot HART Priv Version : v1.12
Boot HART Base ISA : rv64imafdch
Boot HART ISA Extensions : none
Boot HART PMP Count : 16
Boot HART PMP Granularity : 4
Boot HART PMP Address Bits: 54
Boot HART MHPM Count : 0
Boot HART MIDELEG : 0x0000000000001666
Boot HART MEDELEG : 0x0000000000f0b509
[ 0.000000] Linux version 5.19.0-rc5-dirty (root@0152fed4b28d) (riscv64-linux-gnu-gcc (Ubuntu 9.4.0-1ubuntu1~20.04) 9.4.0, GNU ld (GNU Binutils for Ubuntu) 2.34) #5 SMP Fri Jul 8 14:48:33 CST 2022
[ 0.000000] OF: fdt: Ignoring memory range 0x80000000 - 0x80200000
[ 0.000000] Machine model: ucbbar,spike-bare
[ 0.000000] earlycon: sbi0 at I/O port 0x0 (options '')
[ 0.000000] printk: bootconsole [sbi0] enabled
[ 0.000000] efi: UEFI not found.
[ 0.000000] Zone ranges:
[ 0.000000] DMA32 [mem 0x0000000080200000-0x000000009fffffff]
[ 0.000000] Normal empty
[ 0.000000] Movable zone start for each node
[ 0.000000] Early memory node ranges
[ 0.000000] node 0: [mem 0x0000000080200000-0x000000009fffffff]
[ 0.000000] Initmem setup node 0 [mem 0x0000000080200000-0x000000009fffffff]
[ 0.000000] SBI specification v1.0 detected
[ 0.000000] SBI implementation ID=0x1 Version=0x10001
[ 0.000000] SBI TIME extension detected
[ 0.000000] SBI IPI extension detected
[ 0.000000] SBI RFENCE extension detected
[ 0.000000] SBI SRST extension detected
[ 0.000000] SBI HSM extension detected
[ 0.000000] riscv: base ISA extensions acdfhim
[ 0.000000] riscv: ELF capabilities acdfim
[ 0.000000] percpu: Embedded 18 pages/cpu s34104 r8192 d31432 u73728
[ 0.000000] Built 1 zonelists, mobility grouping on. Total pages: 128775
[ 0.000000] Kernel command line: root=/dev/ram console=hvc0 earlycon=sbi
[ 0.000000] Dentry cache hash table entries: 65536 (order: 7, 524288 bytes, linear)
[ 0.000000] Inode-cache hash table entries: 32768 (order: 6, 262144 bytes, linear)
[ 0.000000] mem auto-init: stack:off, heap alloc:off, heap free:off
[ 0.000000] Virtual kernel memory layout:
[ 0.000000] fixmap : 0xff1bfffffee00000 - 0xff1bffffff000000 (2048 kB)
[ 0.000000] pci io : 0xff1bffffff000000 - 0xff1c000000000000 ( 16 MB)
[ 0.000000] vmemmap : 0xff1c000000000000 - 0xff20000000000000 (1024 TB)
[ 0.000000] vmalloc : 0xff20000000000000 - 0xff60000000000000 (16384 TB)
[ 0.000000] lowmem : 0xff60000000000000 - 0xff6000001fe00000 ( 510 MB)
[ 0.000000] kernel : 0xffffffff80000000 - 0xffffffffffffffff (2047 MB)
[ 0.000000] Memory: 471476K/522240K available (6518K kernel code, 4864K rwdata, 4096K rodata, 2172K init, 397K bss, 50764K reserved, 0K cma-reserved)
[ 0.000000] SLUB: HWalign=64, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
[ 0.000000] rcu: Hierarchical RCU implementation.
[ 0.000000] rcu: RCU restricting CPUs from NR*CPUS=8 to nr_cpu_ids=1.
[ 0.000000] rcu: RCU debug extended QS entry/exit.
[ 0.000000] Tracing variant of Tasks RCU enabled.
[ 0.000000] rcu: RCU calculated value of scheduler-enlistment delay is 25 jiffies.
[ 0.000000] rcu: Adjusting geometry for rcu_fanout_leaf=16, nr_cpu_ids=1
[ 0.000000] NR_IRQS: 64, nr_irqs: 64, preallocated irqs: 0
[ 0.000000] riscv-intc: 64 local interrupts mapped
[ 0.000000] rcu: srcu_init: Setting srcu_struct sizes based on contention.
[ 0.000000] riscv_timer_init_dt: Registering clocksource cpuid [0] hartid [0]
[ 0.000000] clocksource: riscv_clocksource: mask: 0xffffffffffffffff max_cycles: 0x24e6a1710, max_idle_ns: 440795202120 ns
[ 0.000005] sched_clock: 64 bits at 10MHz, resolution 100ns, wraps every 4398046511100ns
[ 0.000655] Console: colour dummy device 80x25
[ 0.000925] printk: console [hvc0] enabled
[ 0.000925] printk: console [hvc0] enabled
[ 0.001415] printk: bootconsole [sbi0] disabled
[ 0.001415] printk: bootconsole [sbi0] disabled
[ 0.001975] Calibrating delay loop (skipped), value calculated using timer frequency.. 20.00 BogoMIPS (lpj=40000)
[ 0.002585] pid_max: default: 32768 minimum: 301
[ 0.002990] Mount-cache hash table entries: 1024 (order: 1, 8192 bytes, linear)
[ 0.003425] Mountpoint-cache hash table entries: 1024 (order: 1, 8192 bytes, linear)
[ 0.005160] cblist_init_generic: Setting adjustable number of callback queues.
[ 0.005590] cblist_init_generic: Setting shift to 0 and lim to 1.
[ 0.006065] riscv: ELF compat mode failed
[ 0.006085] ASID allocator using 16 bits (65536 entries)
[ 0.006760] rcu: Hierarchical SRCU implementation.
[ 0.007290] EFI services will not be available.
[ 0.007820] smp: Bringing up secondary CPUs ...
[ 0.008095] smp: Brought up 1 node, 1 CPU
[ 0.008650] devtmpfs: initialized
[ 0.009465] clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785100000 ns
[ 0.010040] futex hash table entries: 256 (order: 2, 16384 bytes, linear)
[ 0.011760] NET: Registered PF_NETLINK/PF_ROUTE protocol family
[ 0.012380] cpuidle: using governor menu
[ 0.018845] HugeTLB registered 2.00 MiB page size, pre-allocated 0 pages
[ 0.019490] iommu: Default domain type: Translated
[ 0.019785] iommu: DMA domain TLB invalidation policy: strict mode
[ 0.020335] SCSI subsystem initialized
[ 0.020840] usbcore: registered new interface driver usbfs
[ 0.021190] usbcore: registered new interface driver hub
[ 0.021525] usbcore: registered new device driver usb
[ 0.022330] vgaarb: loaded
[ 0.022580] clocksource: Switched to clocksource riscv_clocksource
[ 0.030525] NET: Registered PF_INET protocol family
[ 0.031090] IP idents hash table entries: 8192 (order: 4, 65536 bytes, linear)
[ 0.033000] tcp_listen_portaddr_hash hash table entries: 256 (order: 1, 8192 bytes, linear)
[ 0.033505] Table-perturb hash table entries: 65536 (order: 6, 262144 bytes, linear)
[ 0.033970] TCP established hash table entries: 4096 (order: 3, 32768 bytes, linear)
[ 0.034475] TCP bind hash table entries: 4096 (order: 5, 131072 bytes, linear)
[ 0.035070] TCP: Hash tables configured (established 4096 bind 4096)
[ 0.035475] UDP hash table entries: 256 (order: 2, 24576 bytes, linear)
[ 0.035890] UDP-Lite hash table entries: 256 (order: 2, 24576 bytes, linear)
[ 0.036415] NET: Registered PF_UNIX/PF_LOCAL protocol family
[ 0.037185] RPC: Registered named UNIX socket transport module.
[ 0.037540] RPC: Registered udp transport module.
[ 0.037825] RPC: Registered tcp transport module.
[ 0.038110] RPC: Registered tcp NFSv4.1 backchannel transport module.
[ 0.038495] PCI: CLS 0 bytes, default 64
[ 0.039390] Unpacking initramfs...
[ 0.046680] workingset: timestamp_bits=62 max_order=17 bucket_order=0
[ 0.052835] NFS: Registering the id_resolver key type
[ 0.053175] Key type id_resolver registered
[ 0.053430] Key type id_legacy registered
[ 0.053730] nfs4filelayout_init: NFSv4 File Layout Driver Registering...
[ 0.054130] nfs4flexfilelayout_init: NFSv4 Flexfile Layout Driver Registering...
[ 0.058645] 9p: Installing v9fs 9p2000 file system support
[ 0.059215] NET: Registered PF_ALG protocol family
[ 0.059525] Block layer SCSI generic (bsg) driver version 0.4 loaded (major 250)
[ 0.059965] io scheduler mq-deadline registered
[ 0.060240] io scheduler kyber registered
[ 0.140120] Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
[ 0.151730] loop: module loaded
[ 0.152920] e1000e: Intel(R) PRO/1000 Network Driver
[ 0.153220] e1000e: Copyright(c) 1999 - 2015 Intel Corporation.
[ 0.153620] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[ 0.154010] ehci-pci: EHCI PCI platform driver
[ 0.154300] ehci-platform: EHCI generic platform driver
[ 0.154690] ohci_hcd: USB 1.1 'Open' Host Controller (OHCI) Driver
[ 0.155060] ohci-pci: OHCI PCI platform driver
[ 0.155345] ohci-platform: OHCI generic platform driver
[ 0.155885] usbcore: registered new interface driver uas
[ 0.156230] usbcore: registered new interface driver usb-storage
[ 0.156730] mousedev: PS/2 mouse device common for all mice
[ 0.157300] sdhci: Secure Digital Host Controller Interface driver
[ 0.157670] sdhci: Copyright(c) Pierre Ossman
[ 0.157940] sdhci-pltfm: SDHCI platform and OF driver helper
[ 0.158380] usbcore: registered new interface driver usbhid
[ 0.158765] usbhid: USB HID core driver
[ 0.159060] riscv-pmu-sbi: SBI PMU extension is available
[ 0.159490] riscv-pmu-sbi: 16 firmware and 2 hardware counters
[ 0.159840] riscv-pmu-sbi: Perf sampling/filtering is not supported as sscof extension is not available
[ 0.171790] Freeing initrd memory: 22232K
[ 0.172505] NET: Registered PF_INET6 protocol family
[ 0.173680] Segment Routing with IPv6
[ 0.173980] In-situ OAM (IOAM) with IPv6
[ 0.174255] sit: IPv6, IPv4 and MPLS over IPv4 tunneling driver
[ 0.175035] NET: Registered PF_PACKET protocol family
[ 0.175445] 9pnet: Installing 9P2000 support
[ 0.175750] Key type dns_resolver registered
[ 0.176315] debug_vm_pgtable: [debug_vm_pgtable ]: Validating architecture page table helpers
[ 0.179125] Freeing unused kernel image (initmem) memory: 2172K
[ 0.186640] Run /init as init process
* _
| ||_|
| | _ \_\_\_\_ _ \_ \_ _
| || | _ \| | | |\ \/ /
| || | | | | |_| |/ \
 |_||_|_| |\_|\_\_\_\_|\_/\_/

               Busybox Rootfs

Please press Enter to activate this console.

/ # insmod apps/kvm.ko
insmod apps/kvm.ko
[ 3.104495] kvm [48]: hypervisor extension available
[ 3.104795] kvm [48]: using Sv57x4 G-stage page table format
[ 3.105135] kvm [48]: VMID 14 bits available
/ # ./apps/lkvm-static run -m 128 -c2 --console serial -p "console=ttyS0 earlycon=uart8250,mmio,0x3f8" -k ./apps/Image --debug
./apps/lkvm-static run -m 128 -c2 --console serial -p "console=ttyS0 earlyco
n=uart8250,mmio,0x3f8" -k ./apps/Image --debug

# lkvm run -k ./apps/Image -m 128 -c 2 --name guest-49

Info: (riscv/kvm.c) kvm**arch_load_kernel_image:125: Loaded kernel to 0x80200000 (19789312 bytes)
Info: (riscv/kvm.c) kvm**arch_load_kernel_image:136: Placing fdt at 0x81c00000 - 0x87ffffff

# Warning: The maximum recommended amount of VCPUs is 1

Info: (virtio/mmio.c) virtio_mmio_init:197: virtio-mmio.devices=0x200@0x10000000:5
Info: (virtio/mmio.c) virtio_mmio_init:197: virtio-mmio.devices=0x200@0x10000200:6
Info: (virtio/mmio.c) virtio_mmio_init:197: virtio-mmio.devices=0x200@0x10000400:7
[ 0.000000] Linux version 5.19.0-rc5-dirty (root@0152fed4b28d) (riscv64-linux-gnu-gcc (Ubuntu 9.4.0-1ubuntu1~20.04) 9.4.0, GNU ld (GNU Binutils for Ubuntu) 2.34) #5 SMP Fri Jul 8 14:48:33 CST 2022
[ 0.000000] OF: fdt: Ignoring memory range 0x80000000 - 0x80200000
[ 0.000000] Machine model: linux,dummy-virt
[ 0.000000] earlycon: uart8250 at MMIO 0x00000000000003f8 (options '')
[ 0.000000] printk: bootconsole [uart8250] enabled
[ 0.000000] efi: UEFI not found.
[ 0.000000] Zone ranges:
[ 0.000000] DMA32 [mem 0x0000000080200000-0x0000000087ffffff]
[ 0.000000] Normal empty
[ 0.000000] Movable zone start for each node
[ 0.000000] Early memory node ranges
[ 0.000000] node 0: [mem 0x0000000080200000-0x0000000087ffffff]
[ 0.000000] Initmem setup node 0 [mem 0x0000000080200000-0x0000000087ffffff]
[ 0.000000] SBI specification v0.3 detected
[ 0.000000] SBI implementation ID=0x3 Version=0x51300
[ 0.000000] SBI TIME extension detected
[ 0.000000] SBI IPI extension detected
[ 0.000000] SBI RFENCE extension detected
[ 0.000000] SBI SRST extension detected
[ 0.000000] SBI HSM extension detected
[ 0.000000] riscv: base ISA extensions acdfim
[ 0.000000] riscv: ELF capabilities acdfim
[ 0.000000] percpu: Embedded 18 pages/cpu s34104 r8192 d31432 u73728
[ 0.000000] Built 1 zonelists, mobility grouping on. Total pages: 31815
[ 0.000000] Kernel command line: console=ttyS0 rw rootflags=trans=virtio,version=9p2000.L,cache=loose rootfstype=9p init=/virt/init ip=dhcp console=ttyS0 earlycon=uart8250,mmio,0x3f8
[ 0.000000] Dentry cache hash table entries: 16384 (order: 5, 131072 bytes, linear)
[ 0.000000] Inode-cache hash table entries: 8192 (order: 4, 65536 bytes, linear)
[ 0.000000] mem auto-init: stack:off, heap alloc:off, heap free:off
[ 0.000000] Virtual kernel memory layout:
[ 0.000000] fixmap : 0xff1bfffffee00000 - 0xff1bffffff000000 (2048 kB)
[ 0.000000] pci io : 0xff1bffffff000000 - 0xff1c000000000000 ( 16 MB)
[ 0.000000] vmemmap : 0xff1c000000000000 - 0xff20000000000000 (1024 TB)
[ 0.000000] vmalloc : 0xff20000000000000 - 0xff60000000000000 (16384 TB)
[ 0.000000] lowmem : 0xff60000000000000 - 0xff60000007e00000 ( 126 MB)
[ 0.000000] kernel : 0xffffffff80000000 - 0xffffffffffffffff (2047 MB)
[ 0.000000] Memory: 106368K/129024K available (6518K kernel code, 4864K rwdata, 4096K rodata, 2172K init, 397K bss, 22656K reserved, 0K cma-reserved)
[ 0.000000] SLUB: HWalign=64, Order=0-3, MinObjects=0, CPUs=2, Nodes=1
[ 0.000000] rcu: Hierarchical RCU implementation.
[ 0.000000] rcu: RCU restricting CPUs from NR_CPUS=8 to nr_cpu_ids=2.
[ 0.000000] rcu: RCU debug extended QS entry/exit.
[ 0.000000] Tracing variant of Tasks RCU enabled.
[ 0.000000] rcu: RCU calculated value of scheduler-enlistment delay is 25 jiffies.
[ 0.000000] rcu: Adjusting geometry for rcu_fanout_leaf=16, nr_cpu_ids=2
[ 0.000000] NR_IRQS: 64, nr_irqs: 64, preallocated irqs: 0
[ 0.000000] riscv-intc: 64 local interrupts mapped
[ 0.000000] plic: interrupt-controller@0c000000: mapped 1023 interrupts with 2 handlers for 4 contexts.
[ 0.000000] rcu: srcu_init: Setting srcu_struct sizes based on contention.
[ 0.000000] riscv_timer_init_dt: Registering clocksource cpuid [0] hartid [0]
[ 0.000000] clocksource: riscv_clocksource: mask: 0xffffffffffffffff max_cycles: 0x24e6a1710, max_idle_ns: 440795202120 ns
[ 0.000005] sched_clock: 64 bits at 10MHz, resolution 100ns, wraps every 4398046511100ns
[ 0.004335] Console: colour dummy device 80x25
[ 0.006480] Calibrating delay loop (skipped), value calculated using timer frequency.. 20.00 BogoMIPS (lpj=40000)
[ 0.011385] pid_max: default: 32768 minimum: 301
[ 0.013850] Mount-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[ 0.017275] Mountpoint-cache hash table entries: 512 (order: 0, 4096 bytes, linear)
[ 0.023840] cblist_init_generic: Setting adjustable number of callback queues.
[ 0.027255] cblist_init_generic: Setting shift to 1 and lim to 1.
[ 0.030260] riscv: ELF compat mode failed
[ 0.030340] ASID allocator using 16 bits (65536 entries)
[ 0.034930] rcu: Hierarchical SRCU implementation.
[ 0.037605] EFI services will not be available.
[ 0.040310] smp: Bringing up secondary CPUs ...
[ 0.052190] smp: Brought up 1 node, 2 CPUs
[ 0.072570] devtmpfs: initialized
[ 0.088375] clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785100000 ns
[ 0.092995] futex hash table entries: 512 (order: 3, 32768 bytes, linear)
[ 0.098035] NET: Registered PF_NETLINK/PF_ROUTE protocol family
[ 0.101505] cpuidle: using governor menu
[ 0.140230] HugeTLB registered 2.00 MiB page size, pre-allocated 0 pages
[ 0.148305] iommu: Default domain type: Translated
[ 0.150565] iommu: DMA domain TLB invalidation policy: strict mode
[ 0.153930] SCSI subsystem initialized
[ 0.168475] usbcore: registered new interface driver usbfs
[ 0.171075] usbcore: registered new interface driver hub
[ 0.173665] usbcore: registered new device driver usb
[ 0.177200] vgaarb: loaded
[ 0.196220] clocksource: Switched to clocksource riscv_clocksource
[ 0.215040] NET: Registered PF_INET protocol family
[ 0.217650] IP idents hash table entries: 2048 (order: 2, 16384 bytes, linear)
[ 0.221960] tcp_listen_portaddr_hash hash table entries: 128 (order: 0, 4096 bytes, linear)
[ 0.225880] Table-perturb hash table entries: 65536 (order: 6, 262144 bytes, linear)
[ 0.229695] TCP established hash table entries: 1024 (order: 1, 8192 bytes, linear)
[ 0.233315] TCP bind hash table entries: 1024 (order: 3, 32768 bytes, linear)
[ 0.236955] TCP: Hash tables configured (established 1024 bind 1024)
[ 0.240205] UDP hash table entries: 256 (order: 2, 24576 bytes, linear)
[ 0.243335] UDP-Lite hash table entries: 256 (order: 2, 24576 bytes, linear)
[ 0.247060] NET: Registered PF_UNIX/PF_LOCAL protocol family
[ 0.276940] RPC: Registered named UNIX socket transport module.
[ 0.279680] RPC: Registered udp transport module.
[ 0.282130] RPC: Registered tcp transport module.
[ 0.284350] RPC: Registered tcp NFSv4.1 backchannel transport module.
[ 0.287330] PCI: CLS 0 bytes, default 64
[ 0.308310] workingset: timestamp_bits=62 max_order=15 bucket_order=0
[ 0.328680] NFS: Registering the id_resolver key type
[ 0.331080] Key type id_resolver registered
[ 0.333260] Key type id_legacy registered
[ 0.335215] nfs4filelayout_init: NFSv4 File Layout Driver Registering...
[ 0.338360] nfs4flexfilelayout_init: NFSv4 Flexfile Layout Driver Registering...
[ 0.342220] 9p: Installing v9fs 9p2000 file system support
[ 0.345165] NET: Registered PF_ALG protocol family
[ 0.347420] Block layer SCSI generic (bsg) driver version 0.4 loaded (major 250)
[ 0.351105] io scheduler mq-deadline registered
[ 0.353245] io scheduler kyber registered
[ 0.367710] pci-host-generic 30000000.pci: host bridge /smb/pci ranges:
[ 0.370855] pci-host-generic 30000000.pci: IO 0x0000000000..0x000000ffff -> 0x0000000000
[ 0.375075] pci-host-generic 30000000.pci: MEM 0x0040000000..0x007fffffff -> 0x0040000000
[ 0.379170] pci-host-generic 30000000.pci: ECAM at [mem 0x30000000-0x3fffffff] for [bus 00-01]
[ 0.383465] pci-host-generic 30000000.pci: PCI host bridge to bus 0000:00
[ 0.386645] pci_bus 0000:00: root bus resource [bus 00-01]
[ 0.389405] pci_bus 0000:00: root bus resource [io 0x0000-0xffff]
[ 0.392305] pci_bus 0000:00: root bus resource [mem 0x40000000-0x7fffffff]
[ 0.514900] Serial: 8250/16550 driver, 4 ports, IRQ sharing disabled
[ 0.519605] printk: console [ttyS0] disabled
[ 0.521705] 3f8.U6_16550A: ttyS0 at MMIO 0x3f8 (irq = 1, base_baud = 115200) is a 16550A
[ 0.525850] printk: console [ttyS0] enabled
[ 0.525850] printk: console [ttyS0] enabled
[ 0.529820] printk: bootconsole [uart8250] disabled
[ 0.529820] printk: bootconsole [uart8250] disabled
[ 0.535435] 2f8.U6_16550A: ttyS1 at MMIO 0x2f8 (irq = 2, base_baud = 115200) is a 16550A
[ 0.540065] 3e8.U6_16550A: ttyS2 at MMIO 0x3e8 (irq = 3, base_baud = 115200) is a 16550A
[ 0.544995] 2e8.U6_16550A: ttyS3 at MMIO 0x2e8 (irq = 4, base_baud = 115200) is a 16550A
[ 0.560955] loop: module loaded
[ 0.568400] net eth0: Fail to set guest offload.
[ 0.570600] virtio_net virtio2 eth0: set_features() failed (-22); wanted 0x0000000000134829, left 0x0080000000134829
[ 0.578025] e1000e: Intel(R) PRO/1000 Network Driver
[ 0.580570] e1000e: Copyright(c) 1999 - 2015 Intel Corporation.
[ 0.583430] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[ 0.586660] ehci-pci: EHCI PCI platform driver
[ 0.588985] ehci-platform: EHCI generic platform driver
[ 0.591500] ohci_hcd: USB 1.1 'Open' Host Controller (OHCI) Driver
[ 0.594535] ohci-pci: OHCI PCI platform driver
[ 0.596885] ohci-platform: OHCI generic platform driver
[ 0.612240] usbcore: registered new interface driver uas
[ 0.614790] usbcore: registered new interface driver usb-storage
[ 0.618010] mousedev: PS/2 mouse device common for all mice
[ 0.621095] sdhci: Secure Digital Host Controller Interface driver
[ 0.624020] sdhci: Copyright(c) Pierre Ossman
[ 0.626300] sdhci-pltfm: SDHCI platform and OF driver helper
[ 0.629240] usbcore: registered new interface driver usbhid
[ 0.631880] usbhid: USB HID core driver
[ 0.634485] NET: Registered PF_INET6 protocol family
[ 0.652825] Segment Routing with IPv6
[ 0.654670] In-situ OAM (IOAM) with IPv6
[ 0.656770] sit: IPv6, IPv4 and MPLS over IPv4 tunneling driver
[ 0.660020] NET: Registered PF_PACKET protocol family
[ 0.662705] 9pnet: Installing 9P2000 support
[ 0.667280] Key type dns_resolver registered
[ 0.670095] debug_vm_pgtable: [debug_vm_pgtable ]: Validating architecture page table helpers
[ 0.796380] Legacy PMU implementation is available
[ 0.836255] Sending DHCP requests ., OK
[ 0.838685] IP-Config: Got DHCP answer from 192.168.33.1, my address is 192.168.33.15
[ 0.842520] IP-Config: Complete:
[ 0.844075] device=eth0, hwaddr=02:15:15:15:15:15, ipaddr=192.168.33.15, mask=255.255.255.0, gw=192.168.33.1
[ 0.849185] host=192.168.33.15, domain=, nis-domain=(none)
[ 0.851985] bootserver=192.168.33.1, rootserver=0.0.0.0, rootpath=
[ 0.851995] nameserver0=192.168.33.1
[ 0.859605] VFS: Mounted root (9p filesystem) on device 0:15.
[ 0.868885] devtmpfs: mounted
[ 0.875665] Freeing unused kernel image (initmem) memory: 2172K
[ 0.892250] Run /virt/init as init process
Mounting...
/ # rmmod kvm
rmmod kvm
rmmod: remove 'kvm': No such file or directory
/ # poweroff -f
poweroff -f
[ 7.716205] reboot: Power down

# KVM session ended normally.

/ # rmmod kvm
rmmod kvm
/ #
/ # poweroff -f
poweroff -f
[ 46.367045] reboot: Power down
root@0152fed4b28d:~#

```

## 总结

本文是在 Docker 环境下对 [kvm-riscv howto wiki][003] 中 [KVM RISCV64 on QEMU][004] 和 [KVM RISCV64 on Spike][005] 两篇基于 KVM 运行 Host/Guest Linux 的文章的验证和补充。

## 参考资料

- [Cloud Lab][001]
- [Linux Lab][002]
- [RISC-V Linux][002]
- [RISC-V KVM Howto][003]
- [Spike RISC-V ISA Simulator][003]
- [QEMU][011]
- [kvmtools][007]

[001]: https://gitee.com/tinylab/cloud-lab
[002]: https://gitee.com/tinylab/linux-lab
[003]: https://github.com/kvm-riscv/howto/wiki
[004]: https://github.com/kvm-riscv/howto/wiki/KVM-RISCV64-on-QEMU
[005]: https://github.com/kvm-riscv/howto/wiki/KVM-RISCV64-on-Spike#7-run-risc-v-kvm-on-spike
[006]: https://github.com/kvm-riscv/linux.git
[007]: https://git.kernel.org/pub/scm/linux/kernel/git/will/kvmtool.git
[008]: https://wiki.qemu.org/Documentation/Platforms/RISCV
[009]: https://wiki.qemu.org/Hosts/Linux
[010]: https://www.kernel.org/
[011]: https://www.qemu.org/
[012]: https://zhuanlan.zhihu.com/p/539390400
