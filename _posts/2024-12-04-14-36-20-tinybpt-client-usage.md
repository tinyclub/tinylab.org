---
layout: post
author: 'Petalzu'
title: 'TinyBPT 和面向 buildroot 的二进制包管理服务（2）：客户端说明'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /tinybpt-client-usage/
description: 'TinyBPT 和面向 buildroot 的二进制包管理服务（2）：客户端说明'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - Buildroot
  - TinyBPT
  - OpenSSL
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [tounix spaces]
> Author:  柴子轩 <petalzu@outlook.com>
> Date:    2024/09/27
> Revisor: falcon <falcon@tinylab.org>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor: PLCT Lab, ISCAS


## 前言

TinyBPT (Tiny Buildroot Packaging Tool) 是一个 buildroot 的包管理工具，主要处理 buildroot 的包依赖关系，提供包的安装、卸载等功能。

本文档主要介绍 TinyBPT 客户端的使用。

## 安装方法

如果要在 `buildroot` 构建的子系统中直接安装，则需要在主机下载后通过构建本地 `HTTP` 服务的方式提供给子系统下载。（如果在构建系统时已经配置了 `HTTPS` 相关服务，则可以直接使用 `HTTPS` 服务下载。）

默认下载为 RISC-V 64 位的版本，下载后解压到 `/` 目录下即可。

本地编译则需要先编译 `OpenSSL`，下载源码后执行如下命令：

```shell
./Configure linux64-riscv64 no-zlib no-rc2 no-idea no-des no-bf no-cast no-md2 no-mdc2 no-dh no-err no-rc5 no-camellia no-seed no-tests  -static  --prefix=/usr/local/openssl/riscv64 --cross-compile-prefix=riscv64-linux-gnu- -flto

make -j$(nproc)
make install_sw
```

使用 `no-*` 的配置选项目的是禁用多个加密算法和功能，以减少库的体积和依赖，并使用 `-flto` 启用链接时优化（Link Time Optimization），以提高生成代码的性能。

如果这些流程均在主机（非 `riscv` 机器）中完成，则需要将编译好的二进制文件，依赖文件和 `CA` 证书移动到嵌入式设备（`riscv` 机器）中。

如果是以调试为目的，可以使用 `ARCH=x86_64` 选项进行编译，或者使用 `CMake`。编译完成后，只需要将依赖文件移动到相应位置，或者在环境变量中设置 `TINYBPT_DB_PATH`。

### 直接安装

```shell
wget https://mirrors.lzu.edu.cn/buildroot-pkgs/riscv64/tinybpt/tinybpt-v0.1-rc1.tar.gz
mkdir -p /etc/tinybpt && mkdir -p /etc/ssl/certs
tar -xvf tinybpt-v0.1-rc1.tar.gz -C /
```

### 本地 Makefile 编译安装

移动到 `tinybpt` 目录下，执行如下命令：

```shell
make ARCH=riscv64 -j$(nproc)
```

```shell
git clone https://gitee.com/tinylab/tinybpt.git
cd tinybpt
wget https://curl.se/ca/cacert.pem
make
make install
```

### 本地 CMake 编译安装

同上，先编译 `OpenSSL`，然后执行如下命令：

```shell
git clone https://gitee.com/tinylab/tinybpt.git tinybpt
cmake -S tinybpt
    -B build \
    -G Ninja
ninja -C build
ninja -C tinybpt/build install
```

### 使用环境变量指定依赖和下载路径（可选）

默认情况下，TinyBPT 会将依赖和下载的文件存储在 `/etc/tinybpt` 和 `/var/cache/tinybpt` 目录下，如果需要指定其他路径，可以使用环境变量 `TINYBPT_DB_PATH` 和 `TINYBPT_DOWNLOAD_PATH`。

```shell
export TINYBPT_DB_PATH=<your_path_to>/tinybpt_db.json
export TINYBPT_DOWNLOAD_PATH=<your_path_to_download>
```

## 使用方法

```shell
# tinybpt
Tiny buildroot packaging tool

Usage: tinybpt <command> [options]

Commands:
    install <package_name>          Install package
    uninstall <package_name> [-f]   Uninstall package (use -f to force uninstall)
    list -all/-installed            List all/installed packages
    find <package_name>             Find package

Options:
    -h, -help
           Show help information
    -V, -version
           Show version information
    -set-mirror <url>               Set mirror URL
    -get-mirror                     Show mirror URL
```

## 基本操作

使用 `tinybpt install/uninstall/list/find <package_name>` 进行包的安装、卸载、查找、列出操作。

```shell
# 安装包
tinybpt install <package_name>

# 卸载包
tinybpt uninstall <package_name>

# 列出所有包
tinybpt list -all

# 列出已安装的包
tinybpt list -installed

# 查找包
tinybpt find <package_name>

# 设置镜像 URL
tinybpt -set-mirror <url>

# 获取镜像 URL
tinybpt -get-mirror

# 显示帮助信息
tinybpt -h

# 显示版本信息
tinybpt -V
```

## 其他说明

- 本工具仅支持 riscv64 buildroot 用户使用，其他架构的支持也将陆续开展，敬请期待！
- 本工具使用 CA 证书为 CA certificates extracted from Mozilla。
- 本项目使用了基于 MIT 协议的第三方库 [nlohmann/json][001] 和 [cpp-httplib][002]。

## 参考资料

- [TinyBPT](https://gitee.com/tinylab/tinybpt)

[001]: https://github.com/nlohmann/json
[002]: https://github.com/yhirose/cpp-httplib
