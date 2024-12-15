---
layout: post
author: 'Petalzu'
title: 'TinyBPT 和面向 buildroot 的二进制包管理服务（3）：服务端说明'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /tinybpt-server-usage/
description: 'TinyBPT 和面向 buildroot 的二进制包管理服务（3）：服务端说明'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - TinyBPT
  - buildroot
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [tounix spaces header]
> Author:    柴子轩 <petalzu@outlook.com>
> Date:      2024/09/27
> Revisor:   falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

TinyBPT (Tiny Buildroot Packaging Tool) 是一个 buildroot 的包管理工具，主要处理 buildroot 的包依赖关系，提供包的安装、卸载等功能。

本文档主要介绍为了向 TinyBPT 提供服务，服务端的配置和使用。

## 在服务器端配置 buildroot 源码

### 使用工具 tsumugu 来更新源

```shell
wget https://github.com/taoky/tsumugu
```

配置运行脚本：

```shell
RUST_LOG=Error /usr/local/bin/tsumugu sync --parser lighttpd http://sources.buildroot.net /mnt/tank2/buildroot
```

在网页设置中添加定时任务，每天更新一次，并将其路径展示在网页上，以 nginx 为例：

```shell
server {
···

  location ~* ^/(bmclapi|ubuntu|centos|debian-security|debian|archlinux|archlinuxcn|debian-nonfree|gentoo|manjaro|opensuse|ubuntukylin|wepe|cygwin|debian-cd|debian-multimedia|deepin-cd|openeuler|rpmfusion|ubuntukylin-cdimage|almalinux|buildroot|buildroot-pkgs|epel|rocky|radxa-apt|debian-ports) {
    include /etc/nginx/config.d/backend.conf;
    include /etc/nginx/config.d/cache.conf;
  }
···
```

## 二进制包

### 二进制包源

目前，二进制包在 `https://mirrors.lzu.edu.cn/buildroot-pkgs` 已经开始提供。

### 目录结构

```shell
buildroot/ -- 源码镜像，直接镜像 buildroot 官方所有包的源码库

buildroot-pkgs/  -- 二进制包发布目录
  riscv64/       -- 处理器架构，独立的话方便第三方镜像
    main/2024.02.6/   -- main 用于存放所有 buildroot lts 版本的二进制包（动态编译）
    tools/v6.10/     -- tools 用于存放 Linux lts 内核版本下的 tools 二进制包（以静态编译）
    rootfs/<version>/   -- rootfs 用于存放 rootfs 包，以及相应的编译配置文件
                - rootfs-xxx.tar.gz
                - rootfs-xxx.config
    tinybpt/
      tinybpt-v0.1.0.tar.gz    -- tinybpt 二进制包
  aarch64/
    main/2024.02.6/
    tools/v6.10/
  x86_64/
    main/2024.02.6/
    tools/v6.10/
```

### 编译选项

如果要自行编译，编译配置在 TinyBPT 仓库的 `/web/settings/.config` 中（后续计划连同 rootfs 一起发布），使用编译配置替换原有配置，或使用 `make menuconfig` 自行勾选需要编译的包。

```shell
cd buildroot
make -j$(nproc)
```

### 二进制包的发布

完成后，进入 `output/build` 目录，运行 `web/script/install.sh` 脚本，将编译好的二进制包打包到 `/mnt/tinybpt` 目录下。

将打包目录下的所有文件名列出到 `deploy-pkgs-version.txt` 文件中，确保已有依赖文件 `packages.json` 也在运行目录下，运行 `web/script/compare.py` 脚本和 `web/script/del.py` 脚本，对比和删除不必要的包，更新依赖文件。

注意：二进制包的编译和发布方式会导致某些包无法编译，原因在于目录结构不同等。

### 提醒事项

为了解决编译中的问题，我们需要在编译前进行一些配置，例如目前已发现的：

1. Buildroot 无法编译 host-heimdal ，问题是 heimdal 的配置脚本使用了已被删除的变量，需要手动修改，在 `buildroot-2024.02.6/package/heimdal/heimdal.mk` 文件中，将 `ac_cv_sys_large_files=1 ac_cv_sys_file_offset_bits=64` 添加到 `HOST_HEIMDAL_CONF_ENV` 变量中。

软件源码包大小约为 468 GB。

编译后的 RISC-V 二进制包大小约为 12 GB。

## 参考资料

- [TinyBPT](https://gitee.com/tinylab/tinybpt)
