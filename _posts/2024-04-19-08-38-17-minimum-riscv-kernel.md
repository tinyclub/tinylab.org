---
layout: post
author: 'Reset816'
title: '最小配置的 RISC-V Linux 内核'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /minimum-riscv-kernel/
description: '最小配置的 RISC-V Linux 内核'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [codeinline refs pangu]
> Author:    Yuan Tan <tanyuan@tinylab.org>
> Date:      2023/08/14
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

在开发和测试的环节中，需要经常编译内核。如果使用 defconfig，由于默认开启的配置过多，使用 16 线程编译需要 150 秒，极大的影响了开发效率，打断思路。而如果使用 tinyconfig 只需要 16 秒，编译时间降低为原来的十分之一。

然而 tinyconfig 无法满足调试与验证需求。本文将探索在 tinyconfig 的基础上，创建一个尽可能小的 RISC-V Linux 内核，并让其能够正常运行并打印字符。

## 环境配置

### 下载工具链

Ubuntu 22.04 的包管理器中有 RISC-V 的交叉编译工具链，不需要手动编译：

```bash
sudo apt install gcc-riscv64-linux-gnu
```

### 下载 QEMU

```bash
sudo apt install qemu-system-riscv64
```

### 下载 Linux Kernel 源码

在 [此处][002] 下载 Linux Kernel 源码。本篇文章中使用 6.5.5 版本的内核。其他版本应该类似。

```bash
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.5.5.tar.xz
tar xvf linux-6.5.5.tar.xz
cd linux-6.5.5
```

## initramfs

initramfs（initial RAM file system）是一种在 Linux 操作系统中用于引导时临时加载的文件系统。它主要用于在实际根文件系统（root file system）被挂载之前，提供必要的工具、模块和文件，以便启动过程中执行一些必要的初始化和设置操作。

我们使用一个简单的程序，打印 `test` 后并退出系统，不进行后续的任务。

```c
// init.c

#include <stdio.h>
#include <sys/reboot.h>

int main(int argc, char **argv, char **envp)
{
    printf("test\n");

    reboot(RB_POWER_OFF);

    return 0;
}
```

编译并创建 `Initramfs source files`。

```bash
mkdir ~/initrd/
riscv64-linux-gnu-gcc -static init.c -o ~/initrd/init
chmod +x ~/initrd/init
```

我们还需要创建一个 console 设备：

```
mkdir ~/initrd/dev
sudo mknod ~/initrd/dev/console c 5 1
```

后续内核编译时，会将 `Initramfs source files` 即 `~/initrd/` 放入内核映像中。

## 内核配置

Linux 内核是高度可配置的，要完成我们的目标，我们需要在内核中开启以下选项：

- ELF 支持
- 串口与驱动
- initramfs 支持
- FPU 支持

创建最小的配置文件：

```bash
ARCH=riscv CROSS_COMPILE=/opt/riscv-gcc/bin/riscv64-linux-gnu- make tinyconfig
```

打开 `menuconfig`：

```bash
ARCH=riscv CROSS_COMPILE=/opt/riscv-gcc/bin/riscv64-linux-gnu- make menuconfig
```

### ELF 支持

使用 `/` 搜索 `BINFMT_ELF`：

![image-20230814163138757](/wp-content/uploads/2022/03/riscv-linux/images/20230814-minimum-riscv-kernel/image-20230814163138757.png)

输入 `1` 后点击空格选择 `Kernel support for ELF binaries`：

![image-20230814163203908](/wp-content/uploads/2022/03/riscv-linux/images/20230814-minimum-riscv-kernel/image-20230814163203908.png)

### 串口与驱动

进入 `Device Drivers` -> `Character devices`，选中 `Enable TTY`。

选中 `Enable TTY` 会自动启用一些选项，由于不需要这些功能，可以取消他们的选中。

![image-20230814163640967](/wp-content/uploads/2022/03/riscv-linux/images/20230814-minimum-riscv-kernel/image-20230814163640967.png)

进入 `Device Drivers` -> `Character devices` -> `Serial drivers`，启用 `8250/16550 and compatible serial support` 后，启用 `Console on 8250/16550 and compatible serial port` 和 `Devicetree based probing for 8250 ports`，如下图：

![image-20230814163625020](/wp-content/uploads/2022/03/riscv-linux/images/20230814-minimum-riscv-kernel/image-20230814163625020.png)

### initramfs 支持

进入 `General setup`，选中 `Initial RAM filesystem and RAM disk (initramfs/initrd) support`，并在 `Initramfs source file(s)` 中输入刚刚的 `Initramfs source files` 位置。

![image-20230814185453874](/wp-content/uploads/2022/03/riscv-linux/images/20230814-minimum-riscv-kernel/image-20230814185453874.png)

### FPU 支持

由于 Debian 和 Ubuntu 的 riscv64-linux-gnu-gcc[只支持][003] `lp64d` ABI，所以需要开启内核中的 FPU 支持。关于 RISC-V 数据模型和浮点参数传递的详细信息，可以查阅后文的参考资料。

进入 `Platform type`，选中 `FPU support`

![image-20230814185616855](/wp-content/uploads/2022/03/riscv-linux/images/20230814-minimum-riscv-kernel/image-20230814185616855.png)

如果手动编译一个 ABI 为 `lp64` 的 riscv64-linux-gnu-gcc，那么不需要开启 `FPU support`。

## 运行

编译内核：

```
ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- make -j
```

在 QEMU 中运行内核：

```
qemu-system-riscv64 -nographic -machine virt -kernel arch/riscv/boot/Image -append "console=ttyS0"
```

成功打印 `test`：

![image-20230814185842557](/wp-content/uploads/2022/03/riscv-linux/images/20230814-minimum-riscv-kernel/image-20230814185842557.png)

## 总结

RISC-V Linux Kernel 只需要这些配置，就能运行并打印串口，为开发调试带来了很大的便利。

## 参考资料

- [RISC-V 数据模型，-mabi=ilp32, ilp32f, ilp32d, lp64, lp64f, lp64d_ilp32f][001]
- [All Aboard, Part 1: The -march, -mabi, and -mtune arguments to RISC-V Compilers][004]

[001]: https://blog.csdn.net/zoomdy/article/details/79353313
[002]: https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.45.tar.xz
[003]: https://www.mail-archive.com/debian-glibc@lists.debian.org/msg58228.html
[004]: https://www.sifive.com/blog/all-aboard-part-1-compiler-args
