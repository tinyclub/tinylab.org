---
layout: post
author: 'falcon'
title: 'RISC-V Non-MMU Linux (1): 从内核到应用跑通一遍'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-non-mmu-linux-part1/
description: 'RISC-V Non-MMU Linux (1): 从内核到应用跑通一遍'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - MMU
  - Non-MMU
  - nolibc
  - elf2flt
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [urls autocorrect]
> Author:    Falcon <falcon@tinylab.org>
> Date:      2023/03/09
> Revisor:   Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 简介

MMU 是现代处理器中一个非常重要的硬件特性，主要用于虚拟地址与物理地址之间的转换。RISC-V 下可以通过设置 SATP 寄存器为 0 来彻底关闭 MMU。

关掉 MMU 以后，所有的程序将共享同一片物理地址，而不再是“独占”一大片连续的虚拟地址空间，因此内核和应用的行为方式都将受到很大的影响。

这个系列旨在系统地分析 RISC-V Non-MMU Linux 的工作机理，以便后面的同学可以更好地对比 Non-MMU 与 MMU 下，内核与应用的行为差异，从而更彻底地理解内存管理的奥妙。

另外，在 RISC-V Linux 下，关闭 MMU 以后，内核和应用都将工作在纯 Machine Mode 模式，原有的 Machine Mode 的 Firmware 也不再需要，所以，这里也涉及到整个软件架构的变化，从原有的 M/S/U 三层权限变成更为扁平的 M/U 两层权限。

这篇文章我们先来构建实验环境，把 Non-MMU 下的 RISC-V Linux 内核与应用一起跑通。

如果没有特别说明，本文以 v6.2 作为演示内核版本，以 [Linux Lab][001] 或 [Linux Lab Disk][005] 为实验环境。

**注意**：Linux v6.3 版本修改了 Nolibc，已经无法通过 elf2flt 编译出可以直接运行的 Non-MMU 应用，需要临时 revert 掉 `041fa97c` 和 `758f3337` 两笔改动，即 export environ 和 _auxv 变量的修改。

## 准备好 Linux Lab 和 riscv64/virt 开发板

在开展工作之前，我们先准备好 Linux Lab 的实验环境：

```
$ git clone https://gitee.com/tinylab/cloud-lab
$ cd cloud-lab/
$ tools/docker/run linux-lab
```

接着准备好 `riscv64/virt` 的虚拟开发板：

```
$ make BOARD=riscv64/virt
```

为了提升开发效率，我们启用 Nolibc 模式：

```
$ export nolibc=1
```

这样会启用更小的内核配置文件，以便更快速地编译。

## RISC-V Non-MMU Linux 内核

### 配置内核以便禁用 MMU

在 RISC-V Linux 下，可以通过关闭该选项来禁用 MMU 以及关联的所有功能：

```
$ make kernel-menuconfig
[ ] MMU-based Paged Memory Management Support
```

### MMU 关闭后将影响哪些功能

受 MMU 影响的配置选项简单检索后如下：

```
$ cd /labs/linux-lab/src/linux-stable
$ egrep "if MMU|\!MMU" -ur arch/riscv/Kconfig
	select ARCH_HAS_DEBUG_VIRTUAL if MMU
	select ARCH_HAS_SET_DIRECT_MAP if MMU
	select ARCH_HAS_SET_MEMORY if MMU
	select ARCH_HAS_STRICT_KERNEL_RWX if MMU && !XIP_KERNEL
	select ARCH_HAS_STRICT_MODULE_RWX if MMU && !XIP_KERNEL
	select ARCH_SUPPORTS_DEBUG_PAGEALLOC if MMU
	select ARCH_SUPPORTS_HUGETLBFS if MMU
	select ARCH_SUPPORTS_PAGE_TABLE_CHECK if MMU
	select ARCH_WANT_DEFAULT_TOPDOWN_MMAP_LAYOUT if MMU
	select BINFMT_FLAT_NO_DATA_START_OFFSET if !MMU          --> binfmt flat
	select BUILDTIME_TABLE_SORT if MMU
	select CLINT_TIMER if !MMU                               --> clint timer
	select GENERIC_IOREMAP if MMU
	select GENERIC_PTDUMP if MMU
	select GENERIC_TIME_VSYSCALL if MMU && 64BIT && VDSO
	select HAVE_ARCH_HUGE_VMAP if MMU && 64BIT && !XIP_KERNEL
	select HAVE_ARCH_KASAN if MMU && 64BIT
	select HAVE_ARCH_KASAN_VMALLOC if MMU && 64BIT
	select HAVE_ARCH_KFENCE if MMU && 64BIT
	select HAVE_ARCH_MMAP_RND_BITS if MMU
	select HAVE_ARCH_VMAP_STACK if MMU && 64BIT
	select HAVE_DMA_CONTIGUOUS if MMU
	select HAVE_EBPF_JIT if MMU
	select HAVE_GENERIC_VDSO if MMU && 64BIT
	select UACCESS_MEMCPY if !MMU                            --> uaccess memcpy
	default !MMU                                             --> 见下文分析
	default 0x80000000 if 64BIT && !MMU                      --> 见下文分析
	select SWIOTLB if MMU
```

其他受影响的配置：

```
# set if we run in machine mode, cleared if we run in supervisor mode
config RISCV_M_MODE                                              --> 内核直接工作在 Machine Mode
        bool
        default !MMU

# set if we are running in S-mode and can use SBI calls
config RISCV_SBI
        bool
        depends on !RISCV_M_MODE                                 --> 禁用 SBI
        default y

config PAGE_OFFSET
        hex
        default 0xC0000000 if 32BIT
        default 0x80000000 if 64BIT && !MMU                      --> PAGE_OFFSET 0x80000000
        default 0xff60000000000000 if 64BIT
```

更多受影响的文件：

```
$ find ./ -name "Kconfig*" -exec egrep -l ' MMU|!MMU' {} \; | egrep -v 'arch/[^r]|drivers/'
./arch/riscv/kvm/Kconfig
./arch/riscv/Kconfig.erratas
./arch/riscv/Kconfig.socs
./arch/riscv/Kconfig
./fs/minix/Kconfig
./fs/proc/Kconfig
./fs/Kconfig
./fs/Kconfig.binfmt
./init/Kconfig
./kernel/trace/Kconfig
./kernel/dma/Kconfig
./lib/Kconfig.debug
./mm/damon/Kconfig
./mm/Kconfig
./mm/Kconfig.debug

$ find ./ -name "Makefile" -exec grep -l "(CONFIG_MMU)" {} \; | egrep -v 'arch/[^r]'
./arch/riscv/lib/Makefile
./arch/riscv/mm/Makefile
./arch/riscv/Makefile
./fs/proc/Makefile
./fs/ramfs/Makefile
./fs/romfs/Makefile
./kernel/dma/Makefile
./mm/Makefile
./security/Makefile
```

这里并不计划做展开，但是这些内容是后续分析的关键材料。

从上面，我们大体可以总结出来几点本文会用到的内容：

- PAGE_OFFSET = 0x80000000
- 不再需要 SBI Firmware
- binfmt 的格式仅支持 binfmt flat，而不再支持 ELF，详见 `fs/Kconfig.binfmt`

### 内核编译

暂时先不考虑应用部分的话，关闭 MMU 以后就可以直接编译内核了：

```
$ make kernel
```

### 内核引导

编译完，如果要引导 Non-MMU 内核，有两点需要调整：

- 首先是禁用 bios：`-bios none`
- 接着是内核必须加载在 0x80000000
    - 位于 0x00001000 的 Boot ROM 执行完会直接跳转到这个地址，详见 [virt.c][003] 中的 `virt_memmap`

因此，Linux Lab 专门为此增加了一个 `nommu` 的配置选项，以便正确地选择 QEMU 的选项，当设置为 `1` 后将禁用 MMU，并启用 `-bios none`。

```
$ export nommu=1
$ make boot
```

## RISC-V Non-MMU 应用程序

### 可执行文件格式：FLAT

由于 ELF 格式依赖 MMU，所以禁用 MMU 以后的内核需要专门启用另外一种名为 FLAT 的程序格式，否则将无法正确地执行应用程序。

```
$ make kenrel-menuconfig

Executable file formats  --->
  [*] Kernel support for flat binaries
  [ ] Enable support for very old legacy flat binaries
  [ ] Enable ZFLAT support

$ make kernel
```

从帮助菜单可以看到这种格式来自 uClibc —— 一种专门为嵌入式 Linux 系统设计的 C 库。

> Support uClinux FLAT format binaries

从上面的菜单还可以看到 FLAT 格式还支持压缩，可以在内核中进行解压，这里选择不开启。

### ELF2FLT 工具

uClibc 支持 FLAT 的方式比较特殊，它并没有试图开发一系列完整的工具来支持 FLAT 格式，而是开发了一个转换工具 [elf2flt][004]。

这个工具一般不独立使用，而是安装进其他工具链的目录结构中，以某种巧妙的方式去调整链接器的工作过程，进而最终产生 FLAT 格式的可执行文件。这个过程设计得非常巧妙，后续可以考虑以一篇独立的文章来介绍。

elf2flt 的官方仓库还未正式合并 RISC-V 的支持，虽然 RISC-V 的支持补丁已经发了 [PR][002] 并且也已经早早就进入了 Buildroot，所以，我们目前最好的使用 elf2flt 的方式是，直接用 Buildroot 构建一个完整的已经自动编译并安装好了 elf2flt 的 uClibc 工具链。

要获得该工具链，仅需要在编译 Buildroot 时，同样禁用 MMU 即可：

```
$ make root-menuconfig

Target options  --->
  [ ] MMU support
```

它会自动启用 uClibc 和 FLAT 格式，这样编译出来的文件系统就是可以在 Non-MMU Linux 内核中运行的：

```
$ make root
```

需要注意的是，Nolibc 模式默认启用内核内置的 Rootfs，不接受 `ROOTDEV` 参数的设定，如果要引导 Buildroot 编译出来的文件系统，请关闭 Nolibc 模式，然后正常配置内核，禁用 MMU 后再编译，接着引导即可，这里不做专门的演示。

### 为 Nolibc 添加 FLAT 格式支持

从 Buildroot 专门构建工具链和完整的 Rootfs 是一个相对比较低效的工作，尤其是当我们重点是做内核开发的时候。

所以，一开始，我们就尝试直接为 Nolibc 添加 FLAT 格式支持，也就是基于 Nolibc 编译出来 FLAT 格式的程序。

很显然，由于 Nolibc 仅包含一个头文件，所以，我们无需关注和转换诸如 Glibc 提供的那些额外的 C Runtime 库，直接在链接阶段借鉴 elf2flt 的设计和使用思路来把目标程序做相应的转换和处理即可。

遗憾的是，从 Buildroot 里头构建出来的 elf2flt 一开始并不能愉快地工作，因为 elf2flt 并不是为 Nolibc 这么小型的 C 库设计的，所以我们需要尝试单独修改并构建 elf2flt。

如果想单独构建 elf2flt，不仅需要安装 binutils-dev 和 libiberty-dev，以便获得必要的库和头文件，而且需要 binutils 源码中的头文件，所以它本身并不能够直接单独构建出来，所以我们做了适当的修改，并编译出了能够支持 Nolibc 的 elf2flt。

这里并不打算展开介绍这个修改和单独构建的过程，留作后续的作业吧。

接下来，我们介绍如何在 Linux Lab 下，直接构建基于 Nolibc 的 FLAT 程序。

首先，要确保这两条都执行：

```
$ export nolibc=1
$ export nommu=1
```

接着如往常一样编译基于 nolibc 的应用即可，例如 hello.c：

```
$ make nolibc-clean
$ make nolibc-initramfs nolibc_src=$PWD/src/examples/nolibc/hello.c
```

又比如 riscv64-hello.s：

```
$ make nolibc-clean
$ make nolibc-initramfs nolibc_src=$PWD/src/examples/assembly/riscv64/riscv64-hello.s
```

## 完整的 RISC-V Non-MMU Linux 内核与应用

上一节的最后会编译出来基于 nolibc 的 initramfs，这里直接把 initramfs 打包进内核：

```
$ make nolibc-clean
$ make kernel nolibc_src=$PWD/src/examples/assembly/riscv64/riscv64-hello.s
```

这样我们就获得了完整的 RISC-V Non-MMU 内核和应用，接下来就可以引导了：

```
$ make boot
Linux version 6.2.0-00047-gf9a88b15cf5a (ubuntu@linux-lab) (riscv64-linux-gnu-gcc (Ubuntu 9.3.0-17ubuntu1~20.04) 9.3.0, GNU ld (GNU Binutils for Ubuntu) 2.34) #353 Thu Mar  2 22:20:24 CST 2023
Machine model: riscv-virtio,qemu
Zone ranges:
  DMA32    [mem 0x0000000080000000-0x000000008fffffff]
  Normal   empty
Movable zone start for each node
Early memory node ranges
  node   0: [mem 0x0000000080000000-0x000000008fffffff]
Initmem setup node 0 [mem 0x0000000080000000-0x000000008fffffff]
riscv: base ISA extensions acdfhim
riscv: ELF capabilities acdfim
Built 1 zonelists, mobility grouping on.  Total pages: 64640
...
printk: console [ttyS0] disabled
10000000.uart: ttyS0 at MMIO 0x10000000 (irq = 1, base_baud = 230400) is a 16550A
printk: console [ttyS0] enabled
Freeing unused kernel image (initmem) memory: 72K
This architecture does not have kernel memory protection.
Run /init as init process
Hello, RISC-V 64!
reboot: Power down
```

## 总结

本文初步探索了 RISC-V Non-MMU Linux 的支持与用法，并介绍了如何通过 Linux Lab 来快速配置、编译并运行 RISC-V Non-MMU 的 Linux 内核与应用。

接下来，我们将继续分析 Non-MMU 下 Linux 内核与应用背后的更多细节。

## 参考资料

* [elf2flt][004]
* [elf2flt for RISC-V][002]
* [virt.c][003]
* [Linux Lab][001]

[001]: https://gitee.com/tinylab/linux-lab
[002]: https://github.com/floatious/elf2flt
[003]: https://github.com/qemu/qemu/blob/master/hw/riscv/virt.c
[004]: https://github.com/uclinux-dev/elf2flt
[005]: https://tinylab.org/linux-lab-disk
