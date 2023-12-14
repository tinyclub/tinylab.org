---
layout: post
author: 'Gege-Wang'
title: 'x86 架构下 UnikernelLinux 构建过程与实践'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /porting-riscv-ukl-x86-build-process/
description: 'x86 架构下 UnikernelLinux 构建过程与实践'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [codeblock codeinline refs pangu autocorrect epw]
> Author:    Gege-Wang <2891067867@qq.com>
> Date:      2023/09/12
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

Unikernel Linux (UKL) 是 Linux 和 glibc 的一个小补丁，它允许您构建许多程序，而无需修改，作为 unikernels。这意味着它们与 Linux 内核链接到一个最终的 vmlinuz 中，并在内核空间中运行。可以在裸机或虚拟机上引导这些内核。Linux 中的几乎所有特性和驱动程序都可供 unikernel 使用。

## 环境准备

- autoconf & automake
- GCC or Clang
- GNU make
- GNU sed
- Docker
- All the prerequisites for building the 6.3 Linux Kernel on your distro
- qemu, if you want to test boot in a virtual machine

## 仓库下载

```bash
$ git clone https://github.com/unikernelLinux/ukl
$ cd ukl
$ git submodule update --init
$ autoreconf -i
$ ./configure --with-program=hello
$ make -j`nproc`
```

以上命令足以成功运行一个 UKL 的 unikernel，下面我们将不使用构建系统手动构建一个 unikernel。

### sample 代码树概览

在 `ukl/linux/samples/ukl/` 下一个是 ukl-base 的 tcp_server 的 demo。
tcp_server.c 是一个基于 epoll 的 TCP echo 服务器，用 C 语言编写，使用端口号默认为为 no.5555。system.S 将 sycall() 函数转换为汇编中的调用指令。通常，C 库提供 sycall() 函数，该函数将转换为系统调用汇编指令。运行 make，它将创建一个 UKL.a 和 tcp_server。然后可以将 UKL.a 复制到 UKL Linux 构建期望它存在的地方。这可以通过 Linux 配置选项进行更改（通过运行 make menuconfig 等）。可以运行生成的 Linux 内核，一旦用户空间出现，就可以通过运行 /UKL 命令启动 echo 服务器。tcp_server 是可以正常运行的同一个 echo server 的用户空间二进制文件。这意味着 UKL 可以运行代码，这些代码也可以作为用户空间二进制文件运行，而无需修改。

```bash
.
├── Makefile
├── README
├── syscall.S
├── tcp_server.c
```

## 构建 UKL

Linux 中的 UKL 代码（由 `#ifdefs` 保护）通过使用特定的 Kconfig 选项来启用。
UKL 要求编译应用程序和所需的用户库代码，并与内核静态链接，因此不能使用可动态加载的系统库。所有代码都必须使用两个特殊标志构建。
1. 禁用红色区域 (`-mno-red-zone`)。这允许红色区域在所有中断等在专用内核堆栈上服务时保持安全。虽然我们可以在 UKL 中采用这种技术，但这需要对代码进行剧烈的修改。
2. 生成内核内存模型的代码 (`-mcmodel=kernel`)。因为应用程序代码必须与内核代码链接，并加载在最高的 2GB 地址空间中，而不是用户代码默认的较低的 2GB 地址空间中。
3. 修改后的内核构建系统将应用程序对象文件、库和内核组合到最终的 vmlinux 二进制文件中，该二进制文件可以裸机启动或虚拟启动。
4. 为了避免名称冲突，在将应用程序和内核链接在一起之前，所有应用程序符号（包括库符号）都以 ukl_ 为前缀。
5. 内核代码通常没有线程本地存储或 c++ 构造函数的概念，因此内核的链接器脚本被修改为与用户空间代码链接，并确保线程本地存储和 c++ 构造函数正常工作。
6. 对内核加载程序进行了适当的更改，以便新的 ELF 部分能够与内核一起加载。

***red zone***
引用 AMD64 ABI 的正式定义：
> The 128-byte area beyond the location pointed to by %rsp is considered to be reserved and shall not be modified by signal or interrupt handlers. Therefore, functions may use this area for temporary data that is not needed across function calls. In particular, leaf functions may use this area for their entire stack frame, rather than adjusting the stack pointer in the prologue and epilogue. This area is known as the red zone.

简单地说，红色区域是一种优化。代码可以假设 rsp 以下的 128 字节不会被信号或中断处理程序异步地破坏，因此可以将其用于临时数据，而无需显式移动堆栈指针。最后一句话是优化所在的位置——递减 rsp 和恢复 rsp 是在使用红色区域存储数据时可以保存的两个指令。

## 通过 Makefile 生成 UKL.a

```bash
# SPDX-License-Identifier: GPL-2.0

CFLAGS += -I usr/include -fno-PIC -mno-red-zone -mcmodel=kernel

UKL.a: tcp_server.o syscall.o userspace
    $(AR) cr UKL.a tcp_server.o syscall.o
    objcopy --prefix-symbols=ukl_ UKL.a

tcp_server.o: tcp_server.c
syscall.o: syscall.S
userspace:
    gcc -o tcp_server tcp_server.c
clean:
    rm -f UKL.a tcp_server.o syscall.o tcp_server
CFLAGS += -I usr/include -fno-PIC -mno-red-zone -mcmodel=kernel
```

指定用于 C 编译器的选项，-I 指定编译头文件（.h）所在的目录是 usr/include。UKL 要求不能使用可动态加载的系统库，因此所有代码必须使用两个特殊标志构建
第一个是 禁用红色区域 (`-mno-red-zone`)
第二个是 生成内核内存模型的代码 (`-mcmodel=kernel`)。
`objcopy --prefix-symbols=ukl_ UKL.a`
--prefix-symbols=string 在输出文件中使用指定的字符串作为符号的前缀。

## 编译内核

1. 将 UKL.a 移动到 Linux 目录下
2. `make menuconfig` 保存生成.config 文件
3. `vim .config`

```bash
CONFIG_RANDOMIZE_BASE=n
CONFIG_PAGE_TABLE_ISOLATION=n
CONFIG_INET=y
```

4. `make menuconfig` 选择 UnikernelLinux 并做如下配置
<div align=center><img src="images/porting-riscv-ukl-2/figure-1.PNG"></div>
保存并退出后在原目录下生成 .config 文件。

5. 编译内核

```bash
make -j`nproc`
```

编译成功后如图所示：
<div align=center><img src="images/porting-riscv-ukl-2/figure-2.PNG"></div>

### 构建 ukl-initrd

```bash
cd init
./create-initrd.sh
```

生成的 initrd 保存在/root/ukl-initrd.cpio.xz

### 启动 unikernel

```bash
cd ukl/linux
qemu-system-x86_64 -cpu host,-smap,-smep -accel kvm -m 4G -kernel arch/x86/boot/bzImage -initrd /path/to/ukl-initrd.cpio.xz -nodefaults -nographic -serial stdio -append " console=ttyS0 net.ifnames=0 biosdevname=0 nowatchdog clearcpuid=smap,smep mitigations=off mds=off ip=192.168.122.128:::255.255.255.0::eth0:none"  -net user
```

启动内核进入 shell 之后，我们执行 UKL 程序触发命令 `/UKL`，成功执行 UKL 程序。
<div align=center><img src="images/porting-riscv-ukl-2/figure-3.PNG"></div>

## 总结

本文主要根据 UKL 构建过程完成了 x86 架构下 unikernel 的实验，更加深刻的理解了 UKL。UKL 的基本模型允许将应用程序链接到内核中，同时保留应用程序和 Linux 的（已知和未知的）不变量和假设。一旦应用程序在 UKL 上运行，我们就可以通过选择（额外的）配置选项和/或修改应用程序来直接调用内核功能，从而采用特定的单内核优化。

## 参考资料
- https://dl.acm.org/doi/10.1145/3317550.3321435
- https://eli.thegreenplace.net/2011/09/06/stack-frame-layout-on-x86-64
- https://github.com/unikernelLinux/ukl-eurosy23-artifacts/
- https://research.redhat.com/blog/research_project/unikernel-linux/

