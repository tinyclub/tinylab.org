---
layout: post
author: 'Wang Liming'
title: '使用 Bitbake 和 OpenEmbedded 构建运行在 D1-H 哪吒开发板的软件'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-bitbake-oe-yocto-2-d1-nezha/
description: '使用 Bitbake 和 OpenEmbedded 构建运行在 D1-H 哪吒开发板的软件'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces header toc autocorrect epw]
> Author:    Wang Liming <walimis@gmail.com>
> Date:      2022/10/15
> Revisor:   Falcon <Falcon@163.com>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [Embedded Linux 系统 for RISC-V](https://gitee.com/tinylab/riscv-linux/issues/I5T3XB)
> Sponsor:   PLCT Lab, ISCAS


## 概述

### 目标

在文章 [RISC-V bitbake][001] 中讲述了如何使用 Bitbake 和 Openembedded 构建运行在 QEMU 上的 RISC-V Linux 系统，接下来我们介绍使用这两个工具，构建运行在真实开发板上的系统。这里我们选用 D1-H 哪吒开发板来进行演示，这个开发板在文章 [哪吒介绍][002] 已经进行了详细的介绍，文章里使用的是基于 openwrt-14.07 的 Tina Linux 系统。

本篇文章将详细讲述使用 Bitbake 和 Openembedded 来构建系统，并介绍如何把生成的镜像文件烧写到 D1-H 哪吒开发板上。

## 哪吒开发板的系统构建

### 哪吒开发板的 meta layer

我们使用的 meta layer 是平头哥专门为哪吒开发板开发的，它也是基于 [meta-riscv][003] 进行开发的，定制了可以运行在哪吒开发板的 Bootloader，Linux 内核和文件系统。我们依然基于 Docker 工具来进行整个工程的编译。

### 基础环境准备

- 如果没有完成文章 [RISC-V bitbake][001] 的编译和运行，需要参照文章，操作到 “下载 meta-riscv” 之前的内容。

- 如果已经完成文章 [RISC-V bitbake][001] 的编译和运行，可以直接启动已经创建好的容器，继续使用。

```shell
# 启动之前的容器，如果没启动的话
docker start ubuntu_2004_riscv_yocto

# 进入容器
docker exec -it ubuntu_2004_riscv_yocto bash

# 切换到 test 用户
su test

# 设置 repo 需要的环境变量
export PATH=~/bin:$PATH

export REPO_URL='https://mirrors.tuna.tsinghua.edu.cn/git/git-repo'
```

### 下载和编译

- 下载哪吒开发板的 meta layer。

```shell
# 在 test 用户目录下创建 d1_yocto 目录，所有下载和编译的文件都放在这个目录下
mkdir ~/d1_yocto
cd ~/d1_yocto

# 使用 repo 下载和初始化 D1 的 meta layer
repo init -u https://gitee.com/yocto-thead/manifests.git -b refs/tags/v7.5.1 -m yocto-thead-gitee-d1.xml

# 默认使用 gopher 协议下载 git 库，不是很友好，这里改用 https 协议
sed -i "s/gopher:\/\/git@gitee.com:yocto-thead/https:\/\/gitee.com\/yocto-thead/g" .repo/manifests/yocto-thead-gitee-d1.xml

# 开始同步，这一步比较慢，需要耐心等待
repo sync
```

- 修改文件，使得编译下载成功。

```shell
# 修改如下文件中的 `SRC_URI` 的链接形式，去掉 git@，把 “protocol=ssh” 改为 “protocol=https”
sed -i "s/git@\(gitee.*\)protocol=ssh/\1protocol=https/g" \
    meta-d1/recipes-bsp/opensbi/opensbi_0.6.bbappend \
    meta-d1/recipes-bsp/u-boot/u-boot_2018.05.bb \
    meta-d1/recipes-kernel/linux/linux-thead_5.4.61.bb \
    meta-openembedded/meta-oe/recipes-devtools/android-tools/android-tools_10.bb
```

- 开始编译。

```shell
# 初始化编译环境
source openembedded-core/oe-init-build-env thead-build/d1-miniapp

# 运行 bitbake 开始系统的编译，时间较长，请耐心等候
bitbake d1-image-miniapp-dev
```

- 编译完成。

编译完成后，在 `tmp-glibc/deploy/images/d1/` 目录存放着编译好的文件。包含 BootLoader，Linux 内核，文件系统等。

- 制作镜像文件。

镜像文件指以 .img 命名的，并且是刷机软件可识别的文件，它是使用 pack ⼯具⽣成的⼀种特殊格式的镜像，由 Linux 内核、U-Boot、dtb 和 rootfs 等文件打包⽽成的。哪吒开发板的镜像文件以 yocto_d1-nezha_uart0.img 命名，下面演示在容器中制作该镜像文件的过程：

```shell
# 增加 i386 体系的支持，因为一些工具依赖 i386 的软件
sudo dpkg --add-architecture i386

# 更新
sudo apt update -y

# 安装必要的软件
sudo apt install -y busybox dos2unix libc6:i386 libstdc++6:i386

# 进入 pack 目录
cd pack/

# 使用 pack.sh 脚本制作镜像文件
./pack.sh d1-image-miniapp-dev

# 完成后，当前目录下生成 yocto_d1-nezha_uart0.img 文件
ls yocto_d1-nezha_uart0.img
```

### 烧写镜像文件到哪吒开发板

在文章 [哪吒介绍][002] 已经介绍了如何在 Windows 下使用烧写软件 PhoenixSuit 进行烧写的过程。但是对于如何在 Linux 下使用 LiveSuit 工具进行烧写，并没有详细说明。而 LiveSuit 工具在 GitHub 上的最后更新日期是 2014 年 9 月，适用于 Ubuntu 16.04 和之前的版本，现在已经无法在 Ubuntu 18.04 和之后的版本上运行。我们要使用 LiveSuit 进行烧写的话，需要使用 Docker 运行 Ubuntu 16.04 来运行 LiveSuit。

- 下载 sunxi-livesuite，以下步骤在主机上运行。

```shell
# 下载 sunxi-livesuite
git clone https://github.com/linux-sunxi/sunxi-livesuite.git

# 进入 sunxi-livesuite 目录
cd sunxi-livesuite
```

- LiveSuit 需要 awusb 内核模块才能完成烧写，编译和加载内核模块。

```shell
# 安装编译内核模块需要的头文件
sudo apt install linux-headers-generic

# 进入 awusb 目录
cd awusb

# 替换 SUBDIRS 为 M，保证内核模块编译通过
sed -i "s/SUBDIRS/M/g" Makefile

# 编译内核模块
make

# 加载内核模块
sudo insmod awusb.ko
```

- 拷贝镜像文件到 sunxi-livesuite 目录下。

```shell
# 找到镜像文件 yocto_d1-nezha_uart0.img 所在的目录 path，拷贝 yocto_d1-nezha_uart0.img 文件到 sunxi-livesuite 目录
cp <path>/yocto_d1-nezha_uart0.img sunxi-livesuite/
```

- 运行 xhost 让后面的容器运行 LiveSuit 程序时，可以运行在主机的 Xserver 下。

```shell
xhost +
```

- 启动一个 Ubuntu 16.04 的容器

```shell
# 保证在 sunxi-livesuite 目录下运行 Docker
cd sunxi-livesuite

# 启动 Ubuntu 16.04 的容器，注意，我们把当前目录 sunxi-livesuite 映射到容器里的 /root 目录下
docker run --privileged --rm -it -v /tmp/.X11-unix:/tmp/.X11-unix -v `pwd`/:/root -e DISPLAY=unix$DISPLAY ubuntu:16.04 bash
```

- 在容器里运行 LiveSuit 软件，以下命令在容器里运行。

```shell
# 安装运行 LiveSuit 需要的库文件
apt update && apt install -y libpng12-0 libglib2.0-0 libfreetype6 libsm6 libxrender1 libfontconfig libxext6

# LiveSuit 使用 QT 库，输出 QT 运行需要的环境变量
export QT_X11_NO_MITSHM=1

# 创建 aw_efex0 字符设备文件，开发板进入烧写模式时，LiveSuit 使用这个设备文件和设备进行通讯
mknod /dev/aw_efex0 c 180 0

# 进入 root 目录，即主机上 sunxi-livesuite 的目录
cd /root

# 运行 LiveSuit，此时会弹出 LiveSuit 界面
bash LiveSuit.sh

# 在弹出的界面里，点击 “Image” 按钮，在选择框里选择 /root 目录下的 yocto_d1-nezha_uart0.img 文件。
```

此时界面如下图：

![mtvec](/wp-content/uploads/2022/03/riscv-linux/images/bitbake/livesuit_1.png)

- 插入开发板，LiveSuit 开始烧写镜像文件。

在开发板正面中间位置有一个 fel 按键，按住 fel 按键插入 USB 接口上电。此时 LiveSuit 提示 “Format the partition when upgrade”，点击 “Yes”。

![mtvec](/wp-content/uploads/2022/03/riscv-linux/images/bitbake/livesuit_2.png)

然后 LiveSuit 开始自动烧写镜像文件，当显示 100% 时，表示烧写完成。

![mtvec](/wp-content/uploads/2022/03/riscv-linux/images/bitbake/livesuit_3.png)

### 启动哪吒开发板

烧写完成后，开发板会自动重启，最终会启动到登陆界面：

```shell
THead OS Platform SDK V7.5.1 d1 ttyS0

d1 login:
```

键入 root，登陆到系统。

## 总结

本文演示了如何使用 Bitbake 编译哪吒开发板上运行的镜像文件，并使用 Linux 下的 LiveSuit 软件，烧写镜像文件到开发板的过程。

## 参考资料

- [RISC-V bitbake][001]
- [哪吒介绍][002]
- [meta-riscv][003]

[001]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220930-riscv-bitbake-oe-yocto-1-qemu.md
[002]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220317-nezha-d1.md
[003]: https://github.com/riscv/meta-riscv
