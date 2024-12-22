---
layout: post
author: '乖乖是干饭王'
title: 'Stratovirt 的 RISC-V 虚拟化支持（一）：环境配置'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /stratovirt-riscv-part1/
description: 'Stratovirt 的 RISC-V 虚拟化支持（一）：环境配置'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - Stratovirt
  - KVM
  - Rust
  - QEMU
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [spaces]
> Author:    Sunts <stsmail163@163.com>
> Date:      2024/08/30
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

StratoVirt 是一种基于 Linux 内核虚拟化（KVM）的开源轻量级虚拟化技术。Stratovirt 的运行环境必须要有 RISC-V 的 H 扩展以及在其之上运行的 Linux 提供 KVM 支持。本文采用 QEMU + Ubuntu 22.04 的环境。

## 准备 Ubuntu 镜像

打开终端，执行以下命令，下载镜像。

```shell
wget https://cdimage.ubuntu.com/releases/jammy/release/ubuntu-22.04.4-preinstalled-server-riscv64+unmatched.img.xz
```

解压缩系统镜像文件

```shell
xz -d ubuntu-22.04.4-preinstalled-server-riscv64+unmatched.img.xz
```

## 编译 QEMU

考虑到直接使用 apt 命令安装的 QEMU 可能不支持 RISC-V 虚拟化扩展。所以直接下载源码编译。

安装编译前所需工具

```shell
sudo apt install autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev \
                 gawk build-essential bison flex texinfo gperf libtool patchutils bc \
                 zlib1g-dev libexpat-dev git ninja-build \
                 libglib2.0-dev libfdt-dev libpixman-1-dev
```

```shell
# 根据 python 版本调整版本号
sudo apt-get install python3.12-venv
```

QEMU 的 user 用户模式网络配置需要 libslirp 的支持

下载 libslirp 源码和编译所需工具

```shell
git clone https://gitlab.freedesktop.org/slirp/libslirp.git
sudo apt install meson
```

libslirp 编译，安装

```shell
meson build
ninja -C build install
```

下载 QEMU 源码

```shell
git clone https://github.com/qemu/qemu.git
```

编译 RV64 架构下的 QEMU：qemu-system-riscv64

```shell
cd qemu && ./configure --target-list=riscv64-softmmu --enable-slirp  && make
```

## 用 QEMU 引导 Linux

安装 U-boot 和 Opensbi

```shell
sudo apt install u-boot-qemu opensbi
```

启动 Linux

```shell
./qemu/build/qemu-system-riscv64 -machine virt -nographic -m 8192 -smp 6 -bios /usr/lib/riscv64-linux-gnu/opensbi/generic/fw_jump.bin -kernel /usr/lib/u-boot/qemu-riscv64_smode/uboot.elf -device virtio-net-device,netdev=eth0 -netdev user,id=eth0,hostfwd=tcp::6666-:22 -device virtio-rng-pci -drive file=./ubuntu-22.04.4-preinstalled-server-riscv64+unmatched.img,format=raw,if=virtio
```

登录到 Linux，系统会立即要求更改密码

```shell
# 默认用户名和密码
username: ubuntu
password: ubuntu
```

加载 kvm 模块，并验证

```shell
sudo modprobe kvm
ls /dev/
```

/dev 目录下观察到文件 kvm 即可。

## RUST 环境安装

按照官方提供的命令直接安装最新的 RUST 即可。

```shell
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

看到提示信息：`Rust is installed now. Great!` 即安装完成。

## 小结

环境配置过程中的源码下载或 RUST 安装等过程难免要从 github 等外网下载内容，请配置解决。

## 参考资料

- [QEMU 官方文档](https://wiki.qemu.org/Documentation/Platforms/RISCV)
