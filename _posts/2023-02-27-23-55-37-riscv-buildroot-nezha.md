---
layout: post
author: 'Kepontry'
title: '使用 buildroot 构建 QEMU 和哪吒开发板的系统镜像'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-buildroot-nezha/
description: '使用 buildroot 构建 QEMU 和哪吒开发板的系统镜像'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [codeblock pangu]
> Author:    Kepontry <Kepontry@163.com>
> Date:      2022/12/28
> Revisor:   Falcon <Falcon@163.com>，Wang Liming walimis@gmail.com
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [Embedded Linux 系统 for RISC-V](https://gitee.com/tinylab/riscv-linux/issues/I5T3XB)
> Sponsor:   PLCT Lab, ISCAS


## 简介

[buildroot][001] 是一种简单、高效、易用的嵌入式 Linux 系统生成工具。利用交叉编译工具链，它能够完成 rootfs 生成，内核镜像编译和 bootloader 的编译。像内核编译一样，它也支持 menuconfig, gconfig 和 xconfig 等配置方式。buildroot 支持数千个软件包，在理想的情况下，通常花费 15-30 分钟即可完成构建，本文实际使用中花了 1 个小时才编译完。

## 环境搭建

### 使用 Docker 启动 Ubuntu 20.04

Docker 是一种轻量级的容器，能够简化配置，统一环境。执行如下命令可以非常快速地配置好 Ubuntu 20.04 环境。需要注意的是，安装 docker 后，应该给当前用户（非 root 用户）使用 docker 的权限，避免以 root 权限启动 docker。

```shell
# 把当前用户加入 docker 组，设置完成后，需要重新登陆用户
$ sudo usermod -aG docker username
# 设定当前用户的新初始组为 docker
$ newgrp docker
# 拉取 ubuntu20.04 镜像
$ docker pull ubuntu:20.04
# 启动镜像，通过指定-d 参数，使容器在后台运行
$ docker run -itd --name ubuntu-2004 ubuntu:20.04 /bin/bash
# 进入容器
$ docker exec -it ubuntu-2004 /bin/bash
```

### 更换系统镜像源

Ubuntu 自带的镜像源对国内用户不太友好，软件包下载速度慢。我们这里换成阿里云的源，在容器里执行下面的命令，写入新的镜像源。最后执行 apt-get update 命令，获取最新软件包列表。

```shell
$ echo "deb http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-proposed main restricted universe multiverse

deb http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse
deb-src http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse">/etc/apt/sources.list
```

### 必要软件安装

接下来安装一些必要的软件包，例如版本控制软件 git，编译工具库 build-essential。由于 buildroot 的 Makefile 中有依赖检查功能，剩下的软件包只需要根据 make 命令的报错信息补充即可。

```shell
# 软件包安装
$ apt-get install git build-essential tree file wget cpio unzip rsync bc
```

### 获取 buildroot 源码

随后使用 git 命令从 [官方仓库][002] 克隆最新版本的源码，指定 `--depth=1` 可以避免下载历史提交记录，从而减小下载体积。如果开发板型号不是最新的可以下载 buildroot 的稳定版本。

```shell
# 源码获取
$ cd /home
$ git clone git://git.buildroot.net/buildroot --depth=1
$ cd buildroot
```

### buildroot 目录结构介绍

buildroot 的目录结构如下所示，make 命令后面跟着的配置文件就存放在 configs 目录下。此外，编译完成后会多出两个目录：dl 和 output 目录。dl 目录用于存放构建过程中下载的软件源码压缩包，供后续使用。output 目录存放构建出的镜像文件和构建过程中产生的中间文件。

```shell
$ tree -L 1
.
|-- CHANGES
|-- COPYING
|-- Config.in
|-- Config.in.legacy
|-- DEVELOPERS
|-- Makefile # 构建脚本
|-- Makefile.legacy
|-- README
|-- arch # 架构相关的配置脚本，如 arm/mips/x86/riscv
|-- board # 存放各开发板的一些配置补丁
|-- boot # 各类启动软件
|-- configs # 各类开发板的配置文件
|-- docs # 参考文档
|-- fs # 各类文件系统源码
|-- linux # linux kernel 的自动构建脚本
|-- package # 存放各软件包的配置文件和构建脚本
|-- support # 构件中可能用到的支持软件
|-- system # 根目录的配置和构建脚本，skeleton 目录下存放根目录的骨架
|-- toolchain # 存放构建工具链的脚本
|-- utils # 一些工具软件
```

## 构建基于 QEMU 的 RISCV64 虚拟环境

QEMU 是一种高性能仿真器，利用动态代码翻译机制，可以模拟任意一种指令集的硬件，并在上面执行软件程序。接下来我们构建 QEMU-RISCV64 上的系统镜像，并用 QEMU 启动它。

### config 配置文件生成

使用 `make qemu_riscv64_virt_defconfig` 命令，在当前目录下生成 `.config` 文件，文件中包括系统镜像编译的配置参数。这和使用 `make menuconfig` 命令，在图形界面中配置并保存的 `.config` 文件的作用是相同的。系统镜像的构建都是直接使用开发板厂商预先写好的配置选项文件，并不需要手动配置。

```shell
$ make qemu_riscv64_virt_defconfig

mkdir -p /home/buildroot/output/build/buildroot-config/lxdialog
PKG_CONFIG_PATH="" make CC="/usr/bin/gcc" HOSTCC="/usr/bin/gcc" \
    obj=/home/buildroot/output/build/buildroot-config -C support/kconfig -f Makefile.br conf
make[1]: Entering directory '/home/buildroot/support/kconfig'
/usr/bin/gcc -DCURSES_LOC="<curses.h>" -DLOCALE  -I/home/buildroot/output/build/buildroot-config -DCONFIG_=\"\"  -MM *.c > /home/buildroot/output/build/buildroot-config/.depend 2>/dev/null || :
/usr/bin/gcc -DCURSES_LOC="<curses.h>" -DLOCALE  -I/home/buildroot/output/build/buildroot-config -DCONFIG_=\"\"   -c conf.c -o /home/buildroot/output/build/buildroot-config/conf.o
/usr/bin/gcc -DCURSES_LOC="<curses.h>" -DLOCALE  -I/home/buildroot/output/build/buildroot-config -DCONFIG_=\"\"  -I. -c /home/buildroot/output/build/buildroot-config/zconf.tab.c -o /home/buildroot/output/build/buildroot-config/zconf.tab.o
/usr/bin/gcc -DCURSES_LOC="<curses.h>" -DLOCALE  -I/home/buildroot/output/build/buildroot-config -DCONFIG_=\"\"   /home/buildroot/output/build/buildroot-config/conf.o /home/buildroot/output/build/buildroot-config/zconf.tab.o  -o /home/buildroot/output/build/buildroot-config/conf
rm /home/buildroot/output/build/buildroot-config/zconf.tab.c
make[1]: Leaving directory '/home/buildroot/support/kconfig'
#
# configuration written to /home/buildroot/.config
#
```

### 多核镜像编译

执行 `make -j$(nproc)` 命令，使用多核来并行编译。由于是初次编译，需要下载较多的软件包，大概经过一个小时完成。网络条件比较差的，要做好预留更多时间的准备。

```shell
$ make -j$(nproc)
...
>>>   Generating filesystem image rootfs.tar
mkdir -p /home/buildroot/output/images
rm -rf /home/buildroot/output/build/buildroot-fs/tar
mkdir -p /home/buildroot/output/build/buildroot-fs/tar
rsync -auH --exclude=/THIS_IS_NOT_YOUR_ROOT_FILESYSTEM /home/buildroot/output/target/ /home/buildroot/output/build/buildroot-fs/tar/target
echo '#!/bin/sh' > /home/buildroot/output/build/buildroot-fs/tar/fakeroot
... # 省略 fakeroot 文件的写入过程
chmod a+x /home/buildroot/output/build/buildroot-fs/tar/fakeroot
PATH="/home/buildroot/output/host/bin:/home/buildroot/output/host/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" FAKEROOTDONTTRYCHOWN=1 /home/buildroot/output/host/bin/fakeroot -- /home/buildroot/output/build/buildroot-fs/tar/fakeroot
rootdir=/home/buildroot/output/build/buildroot-fs/tar/target
table='/home/buildroot/output/build/buildroot-fs/full_devices_table.txt'
ln -snf /home/buildroot/output/host/riscv64-buildroot-linux-gnu/sysroot /home/buildroot/output/staging
>>>   Executing post-image script board/qemu/post-image.sh

$ ls output/images/
Image  fw_dynamic.bin  fw_dynamic.elf  fw_jump.bin  fw_jump.elf  rootfs.ext2  rootfs.tar  start-qemu.sh
```

### QEMU 启动编译的内核镜像和文件系统

接下来通过执行 `output/images/start-qemu.sh` 脚本文件，使用 QEMU 启动一个 riscv64 的虚拟环境。查看 `start-qemu.sh` 的内容，该脚本使用构建的 fw_jump.elf 文件作为 bios 参数，Image 文件作为内核参数，rootfs.ext2 作为文件系统参数启动 QEMU。

```shell
$ cat output/images/start-qemu.sh
#!/bin/sh
(
BINARIES_DIR="${0%/*}/"
cd ${BINARIES_DIR}

if [ "${1}" = "serial-only" ]; then
    EXTRA_ARGS='-nographic'
else
    EXTRA_ARGS=''
fi

export PATH="/home/buildroot/output/host/bin:${PATH}"
exec qemu-system-riscv64 -M virt -bios fw_jump.elf -kernel Image -append "rootwait root=/dev/vda ro" -drive file=rootfs.ext2,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 -netdev user,id=net0 -device virtio-net-device,netdev=net0 -nographic  ${EXTRA_ARGS}
)

```

QEMU 成功启动内核，使用 `uname -a` 命令查看处理器以及操作系统的相关信息。

```shell
$ ./output/images/start-qemu.sh

OpenSBI v0.9
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|____/_____|
        | |
        |_|

Platform Name             : riscv-virtio,qemu
Platform Features         : timer,mfdeleg
Platform HART Count       : 1
Firmware Base             : 0x80000000
Firmware Size             : 124 KB
Runtime SBI Version       : 0.2

...

Welcome to Buildroot
buildroot login: root
# uname -a
Linux buildroot 5.15.43 #1 SMP Tue Dec 27 15:19:22 UTC 2022 riscv64 GNU/Linux
# ls /
bin         lib         lost+found  opt         run         tmp
dev         lib64       media       proc        sbin        usr
etc         linuxrc     mnt         root        sys         var
#
```

## 构建哪吒开发板的系统镜像

最后我们使用 buildroot 构建哪吒开发板的系统镜像，并上板测试。

### config 配置文件生成及编译

按照与之前一样的流程生成配置文件并编译，将 output/images 目录下的 sdcard.img 镜像拷贝至宿主机中。

```shell
# 切换到 2022.11 release，此版本可以在哪吒开发板上正常启动和运行
$ git checkout -b  2022.11.test 2022.11
# 生成.config 配置文件
$ make nezha_defconfig
#
# configuration written to /home/buildroot/.config
#
# 编译
$ make -j$(nproc)
# 查看生成的文件
$ ls output/images/
Image  fw_dynamic.bin  fw_dynamic.elf  rootfs.ext2  rootfs.ext4  sdcard.img  sun20i-d1-nezha.dtb  u-boot-sunxi-with-spl.bin
```

### 拷贝编译好的 image 到宿主机

编译完成后，我们在宿主机通过 `docker cp` 命令拷贝生成的 sdcard.img 文件到宿主机。

```shell
# 宿主机中执行，将 sdcard.img 拷贝到宿主机中
$ docker cp ubuntu-2004:/home/buildroot/output/images/sdcard.img ./
```

### 镜像烧写及上板测试

以下命令都在宿主机上运行。
1. 把 SD 卡插入读卡器，并将读卡器连接至电脑 USB 口，使用 dd 命令烧写 sdcard.img 文件到 SD 卡

2. 烧写结果如下：

  ```shell
  $ time sudo dd if=sdcard.img of=/dev/sda bs=2M
  39+0 records in
  39+0 records out
  81788928 bytes (82 MB, 78 MiB) copied, 10.4105 s, 7.9 MB/s

  real	0m10.436s
  user	0m0.009s
  sys		0m0.013s
  ```

3. 把烧写好的 SD 卡拔出，插入哪吒开发板的 SD 卡槽，上电启动哪吒开发板
4. buildroot 详细启动信息如下：

```shell
[227]HELLO! BOOT0 is starting!
[230]BOOT0 commit : 40bd4a32aa
[233]set pll start
[235]periph0 has been enabled
[238]set pll end
[239]board init ok
[241]DRAM only have internal ZQ!!
[244]get_pmu_exist() = -1
[247]ddr_efuse_type: 0x0
[250][AUTO DEBUG] two rank and full DQ!
[253]ddr_efuse_type: 0x0
[256][AUTO DEBUG] rank 0 row = 15
[259][AUTO DEBUG] rank 0 bank = 8
[263][AUTO DEBUG] rank 0 page size = 2 KB
[266][AUTO DEBUG] rank 1 row = 15
[269][AUTO DEBUG] rank 1 bank = 8
[273][AUTO DEBUG] rank 1 page size = 2 KB
[276]rank1 config same as rank0
[279]DRAM BOOT DRIVE INFO: V0.24
[282]DRAM CLK = 792 MHz
[285]DRAM Type = 3 (2:DDR2,3:DDR3)
[288]DRAMC ZQ value: 0x7b7bfb
[291]DRAM ODT value: 0x42.
[293]ddr_efuse_type: 0x0
[296]DRAM SIZE =1024 M
[300]DRAM simple test OK.
[302]dram size =1024
[304]card no is 0
[306]sdcard 0 line count 4
[308][mmc]: mmc driver ver 2021-04-2 16:45
[317][mmc]: Wrong media type 0x0
[320][mmc]: ***Try SD card 0***
[329][mmc]: HSSDR52/SDR25 4 bit
[332][mmc]: 50000000 Hz
[334][mmc]: 29818 MB
[336][mmc]: ***SD/MMC 0 init OK!!!***
[387]Loading boot-pkg Succeed(index=0).
[390]Entry_name        = opensbi
[393]Entry_name        = dtb
[396]Entry_name        = u-boot
[400]Adding DRAM info to DTB.
[405]Jump to second Boot.

OpenSBI v1.1
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|____/_____|
        | |
        |_|

Platform Name             : Allwinner D1 Nezha
Platform Features         : medeleg
Platform HART Count       : 1
Platform IPI Device       : ---
Platform Timer Device     : --- @ 0Hz
Platform Console Device   : uart8250
Platform HSM Device       : sun20i-d1-ppu
Platform Reboot Device    : sunxi-wdt-reset
Platform Shutdown Device  : ---
Firmware Base             : 0x40000000
Firmware Size             : 240 KB
Runtime SBI Version       : 1.0

Domain0 Name              : root
Domain0 Boot HART         : 0
Domain0 HARTs             : 0*
Domain0 Region00          : 0x0000000040000000-0x000000004003ffff ()
Domain0 Region01          : 0x0000000000000000-0xffffffffffffffff (R,W,X)
Domain0 Next Address      : 0x000000004a000000
Domain0 Next Arg1         : 0x0000000044000000
Domain0 Next Mode         : S-mode
Domain0 SysReset          : yes

Boot HART ID              : 0
Boot HART Domain          : root
Boot HART Priv Version    : v1.11
Boot HART Base ISA        : rv64imafdcvx
Boot HART ISA Extensions  : time
Boot HART PMP Count       : 8
Boot HART PMP Granularity : 2048
Boot HART PMP Address Bits: 38
Boot HART MHPM Count      : 0
Boot HART MIDELEG         : 0x0000000000000222
Boot HART MEDELEG         : 0x000000000000b109

U-Boot 2022.07-rc3 (Dec 27 2022 - 23:25:44 +0800)

CPU:   rv64imafdc
Model: Allwinner D1 Nezha
DRAM:  1 GiB
sunxi_set_gate: (CLK#24) unhandled
Core:  66 devices, 24 uclasses, devicetree: board
WDT:   Started watchdog@6011000 with servicing (16s timeout)
MMC:   mmc@4020000: 0, mmc@4021000: 1
Loading Environment from nowhere... OK
In:    serial@2500000
Out:   serial@2500000
Err:   serial@2500000
Net:
Warning: ethernet@4500000 (eth0) using random MAC address - 06:58:7d:c3:58:d6
eth0: ethernet@4500000
Hit any key to stop autoboot:  0
switch to partitions #0, OK
mmc0 is current device
Scanning mmc 0:1...
Found /boot/extlinux/extlinux.conf
Retrieving file: /boot/extlinux/extlinux.conf
1:      linux
Retrieving file: /boot/Image
append: console=ttyS0,115200 root=/dev/mmcblk0p1 ro rootwait
Moving Image from 0x40040000 to 0x40200000, end=415e7c98
## Flattened Device Tree blob at 7fb14730
   Booting using the fdt blob at 0x7fb14730
   Loading Device Tree to 0000000042df5000, end 0000000042dff68f ... OK

Starting kernel ...

[    0.000000] Linux version 5.19.0-rc1 (root@603c9b6a45b4) (riscv64-buildroot-linux-gnu-gcc.br_real (Buildroot 2022.11) 11.3.0, GNU ld (GNU Binutils) 2.38) #1 PREEMPT Tue Dec 27 23:26:20 CST 2022
[    0.000000] OF: fdt: Ignoring memory range 0x40000000 - 0x40200000
[    0.000000] Machine model: Allwinner D1 Nezha
[    0.000000] Zone ranges:
[    0.000000]   DMA32    [mem 0x0000000040200000-0x000000007fffffff]
[    0.000000]   Normal   empty
[    0.000000] Movable zone start for each node
[    0.000000] Early memory node ranges
[    0.000000]   node   0: [mem 0x0000000040200000-0x000000007fffffff]
[    0.000000] Initmem setup node 0 [mem 0x0000000040200000-0x000000007fffffff]
[    0.000000] riscv: SBI specification v1.0 detected
[    0.000000] riscv: SBI implementation ID=0x1 Version=0x10001
[    0.000000] riscv: SBI TIME extension detected
[    0.000000] riscv: SBI IPI extension detected
[    0.000000] riscv: SBI RFENCE extension detected
[    0.000000] riscv: SBI SRST extension detected
[    0.000000] riscv: base ISA extensions acdfim
[    0.000000] riscv: ELF capabilities acdfim
[    0.000000] Built 1 zonelists, mobility grouping on.  Total pages: 257544
[    0.000000] Kernel command line: console=ttyS0,115200 root=/dev/mmcblk0p1 ro rootwait
[    0.000000] Dentry cache hash table entries: 131072 (order: 8, 1048576 bytes, linear)
[    0.000000] Inode-cache hash table entries: 65536 (order: 7, 524288 bytes, linear)
[    0.000000] mem auto-init: stack:off, heap alloc:off, heap free:off
[    0.000000] Memory: 1007888K/1046528K available (6885K kernel code, 5580K rwdata, 4096K rodata, 2191K init, 319K bss, 38640K reserved, 0K cma-reserved)
[    0.000000] SLUB: HWalign=64, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
[    0.000000] trace event string verifier disabled
[    0.000000] rcu: Preemptible hierarchical RCU implementation.
[    0.000000]  Trampoline variant of Tasks RCU enabled.
[    0.000000] rcu: RCU calculated value of scheduler-enlistment delay is 25 jiffies.
[    0.000000] NR_IRQS: 64, nr_irqs: 64, preallocated irqs: 0
[    0.000000] OF: of_irq_init: found /cpus/cpu@0/interrupt-controller with parent (null)
[    0.000000] OF: of_irq_init: found /soc/interrupt-controller@6010000 with parent /soc/interrupt-controller@10000000
[    0.000000] OF: of_irq_init: found /soc/interrupt-controller@10000000 with parent /cpus/cpu@0/interrupt-controller
[    0.000000] OF: of_irq_init: init /cpus/cpu@0/interrupt-controller with parent (null)
[    0.000000] riscv-intc: 64 local interrupts mapped
[    0.000000] OF: of_irq_init: init /soc/interrupt-controller@10000000 with parent /cpus/cpu@0/interrupt-controller
[    0.000000] plic: interrupt-controller@10000000: mapped 176 interrupts with 1 handlers for 2 contexts.
[    0.000000] OF: of_irq_init: init /soc/interrupt-controller@6010000 with parent /soc/interrupt-controller@10000000
[    0.000000] rcu: srcu_init: Setting srcu_struct sizes based on contention.
[    0.000000] riscv_timer_init_dt: Registering clocksource cpuid [0] hartid [0]
[    0.000000] clocksource: riscv_clocksource: mask: 0xffffffffffffffff max_cycles: 0x588fe9dc0, max_idle_ns: 440795202592 ns
[    0.000001] sched_clock: 64 bits at 24MHz, resolution 41ns, wraps every 4398046511097ns
[    0.000368] clocksource: timer: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 79635851949 ns
[    0.001017] Console: colour dummy device 80x25
[    0.001106] Calibrating delay loop (skipped), value calculated using timer frequency.. 48.00 BogoMIPS (lpj=96000)
[    0.001130] pid_max: default: 32768 minimum: 301
[    0.001438] Mount-cache hash table entries: 2048 (order: 2, 16384 bytes, linear)
[    0.001466] Mountpoint-cache hash table entries: 2048 (order: 2, 16384 bytes, linear)
[    0.003917] cblist_init_generic: Setting adjustable number of callback queues.
[    0.003932] cblist_init_generic: Setting shift to 0 and lim to 1.
[    0.004095] riscv: ELF compat mode failed
[    0.004145] ASID allocator using 16 bits (65536 entries)
[    0.004351] rcu: Hierarchical SRCU implementation.
[    0.005440] devtmpfs: initialized
[    0.018343] clocksource: jiffies: mask: 0xffffffff max_cycles: 0xffffffff, max_idle_ns: 7645041785100000 ns
[    0.018369] futex hash table entries: 256 (order: 0, 6144 bytes, linear)
[    0.018513] pinctrl core: initialized pinctrl subsystem
[    0.020648] NET: Registered PF_NETLINK/PF_ROUTE protocol family
[    0.021016] DMA: preallocated 128 KiB GFP_KERNEL pool for atomic allocations
[    0.021068] DMA: preallocated 128 KiB GFP_KERNEL|GFP_DMA32 pool for atomic allocations
[    0.021877] thermal_sys: Registered thermal governor 'bang_bang'
[    0.021890] thermal_sys: Registered thermal governor 'step_wise'
[    0.021896] thermal_sys: Registered thermal governor 'user_space'
[    0.022489] cpuidle: using governor menu
[    0.049441] platform 5460000.tcon-top: Fixing up cyclic dependency with 5200000.mixer
[    0.049572] platform 5460000.tcon-top: Fixing up cyclic dependency with 5100000.mixer
[    0.050332] platform 5461000.lcd-controller: Fixing up cyclic dependency with 5460000.tcon-top
[    0.051027] platform 5470000.lcd-controller: Fixing up cyclic dependency with 5460000.tcon-top
[    0.051900] platform 5500000.hdmi: Fixing up cyclic dependency with 5460000.tcon-top
[    0.055442] platform 7090000.rtc: Fixing up cyclic dependency with 7010000.clock-controller
[    0.057826] platform connector: Fixing up cyclic dependency with 5500000.hdmi
[    0.090637] iommu: Default domain type: Translated
[    0.090647] iommu: DMA domain TLB invalidation policy: strict mode
[    0.091084] SCSI subsystem initialized
[    0.091448] usbcore: registered new interface driver usbfs
[    0.091537] usbcore: registered new interface driver hub
[    0.091612] usbcore: registered new device driver usb
[    0.091979] mc: Linux media interface: v0.10
[    0.092084] videodev: Linux video capture interface: v2.00
[    0.092909] Advanced Linux Sound Architecture Driver Initialized.
[    0.094037] clocksource: Switched to clocksource riscv_clocksource
[    0.132085] NET: Registered PF_INET protocol family
[    0.132447] IP idents hash table entries: 16384 (order: 5, 131072 bytes, linear)
[    0.135984] tcp_listen_portaddr_hash hash table entries: 512 (order: 0, 4096 bytes, linear)
[    0.136047] TCP established hash table entries: 8192 (order: 4, 65536 bytes, linear)
[    0.136153] TCP bind bhash tables hash table entries: 8192 (order: 5, 131072 bytes, linear)
[    0.136604] TCP: Hash tables configured (established 8192 bind 8192)
[    0.136747] UDP hash table entries: 512 (order: 2, 16384 bytes, linear)
[    0.136805] UDP-Lite hash table entries: 512 (order: 2, 16384 bytes, linear)
[    0.137070] NET: Registered PF_UNIX/PF_LOCAL protocol family
[    0.142163] workingset: timestamp_bits=46 max_order=18 bucket_order=0
[    0.166131] SGI XFS with ACLs, security attributes, no debug enabled
[    0.174601] NET: Registered PF_ALG protocol family
[    0.174852] Block layer SCSI generic (bsg) driver version 0.4 loaded (major 248)
[    0.241896] Serial: 8250/16550 driver, 6 ports, IRQ sharing disabled
[    0.257537] sun8i-mixer 5100000.mixer: Adding to iommu group 0
[    0.262237] sun8i-mixer 5200000.mixer: Adding to iommu group 0
[    0.271661] zram: Added device: zram0
[    0.275655] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[    0.275665] ehci-platform: EHCI generic platform driver
[    0.276200] ohci_hcd: USB 1.1 'Open' Host Controller (OHCI) Driver
[    0.276261] ohci-platform: OHCI generic platform driver
[    0.282316] usbcore: registered new interface driver uas
[    0.282416] usbcore: registered new interface driver usb-storage
[    0.282574] usbcore: registered new interface driver ch341
[    0.282623] usbserial: USB Serial support registered for ch341-uart
[    0.283353] UDC core: g_ether: couldn't find an available UDC
[    0.286610] sun6i-rtc 7090000.rtc: registered as rtc0
[    0.286714] sun6i-rtc 7090000.rtc: setting system clock to 1970-01-02T00:00:07 UTC (86407)
[    0.286949] sun6i-rtc 7090000.rtc: RTC enabled
[    0.287316] i2c_dev: i2c /dev entries driver
[    0.294410] sunxi-wdt 6011000.watchdog: Watchdog enabled (timeout=16 sec, nowayout=0)
[    0.297354] ledtrig-cpu: registered to indicate activity on CPUs
[    0.297750] sun8i-ce 3040000.crypto: Set mod clock to 300000000 (300 Mhz) from 400000000 (400 Mhz)
[    0.302118] sun8i-ce 3040000.crypto: will run requests pump with realtime priority
[    0.302355] sun8i-ce 3040000.crypto: will run requests pump with realtime priority
[    0.306114] sun8i-ce 3040000.crypto: will run requests pump with realtime priority
[    0.306346] sun8i-ce 3040000.crypto: will run requests pump with realtime priority
[    0.306480] sun8i-ce 3040000.crypto: Register cbc(aes)
[    0.306510] sun8i-ce 3040000.crypto: Register ecb(aes)
[    0.306522] sun8i-ce 3040000.crypto: Register cbc(des3_ede)
[    0.306534] sun8i-ce 3040000.crypto: Register ecb(des3_ede)
[    0.306549] sun8i-ce 3040000.crypto: Register md5
[    0.306563] sun8i-ce 3040000.crypto: Register sha1
[    0.306579] sun8i-ce 3040000.crypto: Register sha224
[    0.306594] sun8i-ce 3040000.crypto: Register sha256
[    0.306617] sun8i-ce 3040000.crypto: Register sha384
[    0.306635] sun8i-ce 3040000.crypto: Register sha512
[    0.306651] sun8i-ce 3040000.crypto: Register stdrng
[    0.310683] sun8i-ce 3040000.crypto: CryptoEngine Die ID 0
[    0.311302] usbcore: registered new interface driver usbhid
[    0.311311] usbhid: USB HID core driver
[    0.311552] cedrus 1c0e000.video-codec: Adding to iommu group 0
[    0.312241] cedrus 1c0e000.video-codec: Device registered as /dev/video0
[    0.313213] random: crng init done
[    0.322269] usbcore: registered new interface driver snd-usb-audio
[    0.330889] sun20i-codec 2030000.audio-codec: ASoC: Adding component 2030000.audio-codec for platform /soc/audio-codec@2030000
[    0.330914] sun20i-codec 2030000.audio-codec: ASoC: Adding component 2030000.audio-codec for platform /soc/audio-codec@2030000
[    0.347968] NET: Registered PF_INET6 protocol family
[    0.354639] Segment Routing with IPv6
[    0.354687] In-situ OAM (IOAM) with IPv6
[    0.354792] NET: Registered PF_PACKET protocol family
[    0.457383] sun20i-d1-pinctrl 2000000.pinctrl: initialized sunXi PIO driver
[    0.466253] printk: console [ttyS0] disabled
[    0.510089] 2500000.serial: ttyS0 at MMIO 0x2500000 (irq = 207, base_baud = 1500000) is a 16550A
[    0.514152] printk: console [ttyS0] enabled
[    0.536244] printk: console [ttyS0] printing thread started
[    0.582086] 2500400.serial: ttyS1 at MMIO 0x2500400 (irq = 208, base_baud = 1500000) is a 16550A
[    0.583291] sun4i-drm display-engine: Adding to iommu group 0
[    0.696996] sun4i-drm display-engine: bound 5100000.mixer (ops 0xffffffff80c62638)
[    0.708330] sun4i-drm display-engine: bound 5200000.mixer (ops 0xffffffff80c62638)
[    0.708959] sun4i-drm display-engine: bound 5460000.tcon-top (ops 0xffffffff80c66cd8)
[    0.709719] sun4i-drm display-engine: No panel or bridge found... RGB output disabled
[    0.709742] sun4i-drm display-engine: bound 5461000.lcd-controller (ops 0xffffffff80c5f668)
[    0.720010] sun4i-drm display-engine: bound 5470000.lcd-controller (ops 0xffffffff80c5f668)
[    0.720662] sun8i-dw-hdmi 5500000.hdmi: Detected HDMI TX controller v2.12a with HDCP (sun8i_dw_hdmi_phy)
[    0.726624] sun8i-dw-hdmi 5500000.hdmi: registered DesignWare HDMI I2C bus driver
[    0.727177] sun4i-drm display-engine: bound 5500000.hdmi (ops 0xffffffff80c61708)
[    0.732796] [drm] Initialized sun4i-drm 1.0.0 20150629 for display-engine on minor 0
[    0.732948] sun4i-drm display-engine: [drm] Cannot find any crtc or sizes
[    0.735713] spi-nand spi0.0: Macronix SPI NAND was found.
[    0.735726] spi-nand spi0.0: 256 MiB, block size: 128 KiB, page size: 2048, OOB size: 64
[    0.742469] 4 fixed-partitions partitions found on MTD device spi0.0
[    0.742489] Creating 4 MTD partitions on "spi0.0":
[    0.742501] 0x000000000000-0x000000100000 : "boot0"
[    0.751498] 0x000000100000-0x000000400000 : "uboot"
[    0.772891] 0x000000400000-0x000000500000 : "secure_storage"
[    0.781553] 0x000000500000-0x000010000000 : "sys"
[    2.349527] dwmac-sun8i 4500000.ethernet: IRQ eth_wake_irq not found
[    2.349542] dwmac-sun8i 4500000.ethernet: IRQ eth_lpi not found
[    2.349977] dwmac-sun8i 4500000.ethernet: PTP uses main clock
[    2.350029] dwmac-sun8i 4500000.ethernet: Current syscon value is not the default 50006 (expect 0)
[    2.356780] dwmac-sun8i 4500000.ethernet: No HW DMA feature register supported
[    2.356795] dwmac-sun8i 4500000.ethernet: RX Checksum Offload Engine supported
[    2.356800] dwmac-sun8i 4500000.ethernet: COE Type 2
[    2.356809] dwmac-sun8i 4500000.ethernet: TX Checksum insertion supported
[    2.356817] dwmac-sun8i 4500000.ethernet: Normal descriptors
[    2.356824] dwmac-sun8i 4500000.ethernet: Chain mode enabled
[    2.424329] input: 2009800.keys as /devices/platform/soc/2009800.keys/input/input0
[    2.436951] pcf857x 2-0038: probed
[    2.449370] sun50i-r329-ledc 2008000.led-controller: Registered 1 LEDs
[    2.456891] sunxi-mmc 4021000.mmc: allocated mmc-pwrseq
[    2.457435] sunxi-mmc 4020000.mmc: Got CD GPIO
[    2.467761] phy phy-4100400.phy.0: Changing dr_mode to 1
[    2.467777] phy phy-4100400.phy.0: External vbus detected, not enabling our own vbus
[    2.467785] ehci-platform 4101000.usb: EHCI Host Controller
[    2.467826] ehci-platform 4101000.usb: new USB bus registered, assigned bus number 1
[    2.468024] ehci-platform 4101000.usb: irq 222, io mem 0x04101000
[    2.470013] musb-sunxi 4100000.usb: Invalid or missing 'dr_mode' property
[    2.470026] musb-sunxi: probe of 4100000.usb failed with error -22
[    2.471554] ehci-platform 4200000.usb: EHCI Host Controller
[    2.471594] ehci-platform 4200000.usb: new USB bus registered, assigned bus number 2
[    2.471805] ehci-platform 4200000.usb: irq 223, io mem 0x04200000
[    2.473654] ALSA device list:
[    2.473665]   #0: sun20i-codec
[    2.474897] ohci-platform 4200400.usb: Generic Platform OHCI controller
[    2.474935] ohci-platform 4200400.usb: new USB bus registered, assigned bus number 3
[    2.475099] ohci-platform 4200400.usb: irq 224, io mem 0x04200400
[    2.475611] ohci-platform 4101400.usb: Generic Platform OHCI controller
[    2.475648] ohci-platform 4101400.usb: new USB bus registered, assigned bus number 4
[    2.475830] ohci-platform 4101400.usb: irq 225, io mem 0x04101400
[    2.480706] sunxi-mmc 4021000.mmc: initialized, max. request size: 2047 KB, uses new timings mode
[    2.486792] ehci-platform 4101000.usb: USB 2.0 started, EHCI 1.00
[    2.487243] usb usb1: New USB device found, idVendor=1d6b, idProduct=0002, bcdDevice= 5.19
[    2.487260] usb usb1: New USB device strings: Mfr=3, Product=2, SerialNumber=1
[    2.487269] usb usb1: Product: EHCI Host Controller
[    2.487276] usb usb1: Manufacturer: Linux 5.19.0-rc1 ehci_hcd
[    2.487282] usb usb1: SerialNumber: 4101000.usb
[    2.488341] hub 1-0:1.0: USB hub found
[    2.488420] hub 1-0:1.0: 1 port detected
[    2.498796] sunxi-mmc 4020000.mmc: initialized, max. request size: 2047 KB, uses new timings mode
[    2.505114] ehci-platform 4200000.usb: USB 2.0 started, EHCI 1.00
[    2.505417] usb usb2: New USB device found, idVendor=1d6b, idProduct=0002, bcdDevice= 5.19
[    2.505434] usb usb2: New USB device strings: Mfr=3, Product=2, SerialNumber=1
[    2.505442] usb usb2: Product: EHCI Host Controller
[    2.505449] usb usb2: Manufacturer: Linux 5.19.0-rc1 ehci_hcd
[    2.505456] usb usb2: SerialNumber: 4200000.usb
[    2.506501] hub 2-0:1.0: USB hub found
[    2.506607] hub 2-0:1.0: 1 port detected
[    2.543847] usb usb4: New USB device found, idVendor=1d6b, idProduct=0001, bcdDevice= 5.19
[    2.543865] usb usb4: New USB device strings: Mfr=3, Product=2, SerialNumber=1
[    2.543874] usb usb4: Product: Generic Platform OHCI controller
[    2.543881] usb usb4: Manufacturer: Linux 5.19.0-rc1 ohci_hcd
[    2.543888] usb usb4: SerialNumber: 4101400.usb
[    2.550683] hub 4-0:1.0: USB hub found
[    2.550750] hub 4-0:1.0: 1 port detected
[    2.552957] usb usb3: New USB device found, idVendor=1d6b, idProduct=0001, bcdDevice= 5.19
[    2.552975] usb usb3: New USB device strings: Mfr=3, Product=2, SerialNumber=1
[    2.552984] usb usb3: Product: Generic Platform OHCI controller
[    2.552990] usb usb3: Manufacturer: Linux 5.19.0-rc1 ohci_hcd
[    2.552997] usb usb3: SerialNumber: 4200400.usb
[    2.554194] hub 3-0:1.0: USB hub found
[    2.554259] hub 3-0:1.0: 1 port detected
[    2.557300] Waiting for root device /dev/mmcblk0p1...
[    2.579394] mmc1: new high speed SDIO card at address 0001
[    2.636561] mmc0: new high speed SDHC card at address b368
[    2.645982] mmcblk0: mmc0:b368 NCard 29.1 GiB
[    2.654639]  mmcblk0: p1
[    2.724440] EXT4-fs (mmcblk0p1): mounted filesystem with ordered data mode. Quota mode: disabled.
[    2.724512] VFS: Mounted root (ext4 filesystem) readonly on device 179:1.
[    2.729489] devtmpfs: mounted
[    2.730994] Freeing unused kernel image (initmem) memory: 2188K
[    2.731043] Run /sbin/init as init process
[    3.091293] EXT4-fs (mmcblk0p1): re-mounted. Quota mode: disabled.
Starting syslogd: OK
Starting klogd: OK
Running sysctl: OK
Saving random seed: OK
Starting network: [    3.686081] dwmac-sun8i 4500000.ethernet eth0: PHY [stmmac-0:01] driver [RTL8211F Gigabit Ethernet] (irq=POLL)
[    3.686499] dwmac-sun8i 4500000.ethernet eth0: Register MEM_TYPE_PAGE_POOL RxQ-0
[    3.687401] dwmac-sun8i 4500000.ethernet eth0: No Safety Features support found
[    3.687419] dwmac-sun8i 4500000.ethernet eth0: No MAC Management Counters available
[    3.687429] dwmac-sun8i 4500000.ethernet eth0: PTP not supported by HW
[    3.687867] dwmac-sun8i 4500000.ethernet eth0: configuring for phy/rgmii-id link mode
udhcpc: started, v1.35.0
udhcpc: broadcasting discover

udhcpc: no lease, forking to background
OK

Welcome to Buildroot
buildroot login:
```

## 总结

本次实验中，我们使用 buildroot 构建了基于 QEMU 的 RISCV64 虚拟环境，编译了哪吒开发板的系统镜像，并通过了上板测试，体会到了使用 buildroot 构建系统镜像的方便、快捷。

## 参考资料

* [buildroot 官网][001]

[001]: https://buildroot.org/
[002]: https://git.buildroot.net/buildroot/
