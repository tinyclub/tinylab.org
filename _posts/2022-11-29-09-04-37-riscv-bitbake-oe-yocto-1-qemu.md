---
layout: post
author: 'Wang Liming'
title: '使用 Bitbake 和 OpenEmbedded 构建运行在 RISC-V 的系统'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-bitbake-oe-yocto-1-qemu/
description: '使用 Bitbake 和 OpenEmbedded 构建运行在 RISC-V 的系统'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - Bitbake
  - OpenEmbedded
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [pangu autocorrect]
> Author:   Wang Liming <walimis@gmail.com>
> Date:     2022/09/30
> Revisor:  Falcon <Falcon@163.com>
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [Embedded Linux 系统 for RISC-V](https://gitee.com/tinylab/riscv-linux/issues/I5T3XB)
> Sponsor:  PLCT Lab, ISCAS


## 概述

### Bitbake 和 Openembedded 的来源

在早期进行嵌入式 Linux 软件开发时，软件栈的制作一直是个繁琐的过程。包括但不限于：

- 交叉编译器的下载，有时甚至需要自己进行交叉编译器的编译。
- Bootloader，Linux Kernel 的下载和编译。
- 应用程序的下载和编译。
- 根文件系统的制作，需要把应用程序、库文件和配置文件制作成 rootfs。

以上过程还要伴随着各种打 patch 和排查错误，极大的加大了开发人员的负担。

Bitbake 是一个使用 Python 开发的 build 工具，类似于 make，通过解析特定的配置文件和元数据文件，可以只用一条命令，就完成上面所有的工作，大大地减少了嵌入式 Linux 的开发工作量。

而 OpenEmbedded 就是一个基于 Bitbake 的配置文件和元数据文件的集合，这些文件类似于 Makefile，Bitbake 解析这些文件，完成预定的工作。

这些文件的集合，常常通过名为 meta layer 的子集来提供，OpenEmbedded 可以认为是包含多个 meta layer 的统称。OpenEmbedded 的核心 meta layer 有两个，分别是：

- openembedded-core：包含 BitBake 和一些核心软件的配置文件，比如 Linux 内核。
- meta-openembedded：包含常见软件的配置文件。

meta-riscv [下载网址][001] 是一个专为 RISC-V Linux 开发的 meta layer，我们只需要下载它，就可以完成 RISC-V Linux 所有软件栈的编译和制作。下面我们就基于这个 meta layer 来演示如何构建 RISC-V Linux 的软件栈。

## meta-riscv 的编译和运行

### 介绍

meta-riscv 包含专门为 RISC-V Linux 定制的编译 Bootloader，Linux 内核和文件系统的配置文件。

下面会一步步介绍如何下载和编译它。

我们基于 Docker 来进行整个工程的编译，这样可以完整复现整个编译过程。请先参考 [安装说明][002]，完成 Docker 的安装。

整个编译需要大概 50GiB 左右的空间。下载和编译的时间，随网络带宽和机器的性能而不同。一般来说，启动编译后，需要大概一天时间，所以请耐心等候编译完成。

### 基础环境准备

首先启动一个 Docker 容器，使用的 Docker image 为 ubuntu:20.04。

```docker
docker run -it -v `pwd`/root:/root -v `pwd`/home:/home --name ubuntu_2004_riscv_yocto ubuntu:20.04 bash
```

### 下载和编译

- 容器里安装必要的软件。

```shell
apt update -y

# 安装必要软件
apt install -y git vim python3 wget python flex bison build-essential zip curl \
    chrpath cpio diffstat gawk zstd liblz4-tool locales python3-distutils iproute2 sudo iptables
```

- 生成 en_US.UTF-8 locale，Bitbake 软件需要这个 locale。

```shell
locale-gen en_US.UTF-8
```

- 创建 test 用户。Bitbake 无法使用 root 用户进行编译，所以需要创建一个测试用户 test。

```shell
# 增加 test 用户
useradd -m test

# 随便输入密码
passwd test

# 把 test 加入到 sudo 组，运行 qemu 需要
adduser test sudo

# 把 test 的默认 shell 设置成 bash
chsh test -s /bin/bash
```

- 切换到 test 用户并设置 git。

```shell
# 切换成 test 用户
su test

# 设置 git email
git config --global user.email "test@example.com"

# 设置 git user name
git config --global user.name "test"
```

- meta-riscv 使用 repo 工具来下载自身和 OpenEmbedded 的两个核心 meta layer，这里需要下载并设置 repo。

```shell
# 设置 repo 路径
mkdir ~/bin
PATH=~/bin:$PATH

# 从 tsinghua 下载 repo
curl https://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o ~/bin/repo
chmod a+x ~/bin/repo

# 设置 repo 的参数
export REPO_URL='https://mirrors.tuna.tsinghua.edu.cn/git/git-repo'
git config --global url.https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/.insteadof https://android.googlesource.com
```

- 下载 meta-riscv

```shell
# 在 test 用户目录下创建 riscv-yocto 目录，所有下载和编译的文件都放在这个目录下
mkdir ~/riscv-yocto
cd ~/riscv-yocto

# 使用 repo 下载和初始化 meta-riscv
repo init -u https://github.com/riscv/meta-riscv  -b master -m tools/manifests/riscv-yocto.xml

# 下载所有相关的 meta layer，这一步比较慢，需要耐心等待
repo sync

# 完成下载后工作
repo start work --all
```

- 开始编译

```shell
# 使用 setup.sh 初始化编译环境
. ./meta-riscv/setup.sh

# 运行 bitbake 开始系统的编译，时间较长，请耐心等候
MACHINE=qemuriscv64 bitbake core-image-full-cmdline
```

- 编译完成

编译完成后，在 `tmp-glibc/deploy/images/qemuriscv64/` 目录存放着编译好的文件。包含 BootLoader，Linux 内核，文件系统等。

### 运行 QEMU

上面编译完成后，得到一个使用 QEMU 运行 RISC-V Linux 的环境，可以很方便地来验证软件栈。

下面启动一个 RISC-V 64 位的 Linux，出现登陆提示符后，键入 root，进入系统：

```shell
MACHINE=qemuriscv64 runqemu nographic
...
OpenEmbedded nodistro.0 qemuriscv64 ttyS0

qemuriscv64 login: root
root@qemuriscv64:~# uname -a
Linux qemuriscv64 5.19.9-yocto-standard #1 SMP PREEMPT Wed Sep 21 20:11:18 UTC 2022 riscv64 GNU/Linux

```

## 总结

本文演示了如何在 Docker 环境下使用 Bitbake 完成 meta-riscv 的下载和编译，最终使用 QEMU 运行编译好的软件栈。为后续使用 Bitbake 开发 RISC-V Linux 的软件奠定了基础。
后面的文章会进一步讲述如何使用 Bitbake 进行定制软件的开发。

## 参考资料

- [meta-riscv][001]
- [安装说明][002]

[001]: https://github.com/riscv/meta-riscv
[002]: https://docs.docker.com/engine/install/
