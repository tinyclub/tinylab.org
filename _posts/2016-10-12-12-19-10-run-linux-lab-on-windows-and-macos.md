---
layout: post
author: 'XieQirong'
title: "在 Windows 和 macOS上利用 Linux Lab 完成嵌入式系统软件开发"
permalink: /run-linux-lab-on-windows-and-macos/
description: " 本文介绍了如何在 Windows 和 macOS 平台上完成 Linux Lab 环境的搭建 "
category:
  - Linux Lab
tags:
  - 嵌入式
  - Docker
  - macOS
  - Windows
---

> By [Cheer](mailto:archxr@163.com) of [DSLab of Lanzhou University](http://dslab.lzu.edu.cn)
> 2016-10-12 12:19:10

## 简介

今年年中，[TinyLab](http://tinylab.org) 开源了一套基于 Qemu 的完整的嵌入式 Linux 系统开发环境。其在嵌入式系统开发中具有很多的优势，不仅适合开发者也非常适合广大学生用户，因为除了已有的优势外，对于学生群体来说还能极大的降低学习成本。但是其官方文档只提供了在 Ubuntu 平台的运行教程，本文就针对 Windows 平台和 macOS 平台来介绍此环境的搭建方法。

## 安装 Docker Engine

由于平台限制，Windows 和 macOS 用户均需要提前自行安装 Docker Engine。对于 Windows 和 macOS 平台都存在两种方式安装 Docker Engine，一种是安装 Docker for Windows 或者 Docker for Mac，另一种是安装 Docker Toolbox。两种安装方式对于系统和硬件都有不同的要求，具体来说有以下要求：

- Docker for Windows 要求系统为 64 位的 Windows 10  Pro、Enterprise 或 Education 版（Build 10568 及以上版本并安装 1511 November 更新）同时 Hyper-V 包必须被启用，如果不满足以上条件则只能使用 Docker Toolbox。

- Docker for Mac 要求系统为 OS X 10.10.3 Yosemite 及更新的版本，同时要求 2010 年及往后的 Mac，检测你的 Mac 是否满足以上条件可使用 `sysctl kern.hv_support` 命令，如果结果为 `kern.hv_support: 1` 则满足，否则不满足则只能使用 Docker Toolbox。

- Docker Toolbox 要求系统为 64 位且 CPU 支持虚拟化并已启用。

详细的安装方法参考 [Docker 官方文档](https://docs.docker.com/engine/installation)，本文的教程中 Windows 平台上的 Docker Engine 使用 Docker Toolbox 安装，macOS 平台上的使用 Docker for Mac 安装。

## 修改安装脚本

### Windows 平台

安装好 Docker Engine 后打开 Docker Quickstart Terminal ，首先克隆 Linux Lab 仓库：

    git config --global core.autocrlf input #保持文本文件行结束符为 unix 风格，避免由于文件格式引起的问题
    git clone https://github.com/tinyclub/linux-lab.git
    cd linux-lab

接下来修改部分安装脚本，修改之处及内容如下：

1. 将 tools/install-docker-lab.sh 修改为如下：

        #!/bin/bash
        #
        # install-docker-lab.sh -- Build the docker image for the lab
        #
        TOP_DIR=$(dirname $0)
        IMAGE=$(< $TOP_DIR/lab-name)
        docker build -t $IMAGE $TOP_DIR/

2. 将 tools/run-docker-lab.sh 中以下内容注释:

	第10、69行，即 `LAB_HOST_TOOL=$TOP_DIR/run-local-host.sh` 和 `[ -f $LAB_HOST_TOOL ] && $LAB_HOST_TOOL`

3. 将 tools/open-docker-lab.sh 修改为如下：

        #!/bin/bash
        #
        # open-docker-lab.sh -- open the docker lab via a browser
        #
        TOP_DIR=$(dirname `readlink -f $0`)
        IMAGE=$(< $TOP_DIR/lab-name)
        LAB_HOST_NAME=$TOP_DIR/.lab_host_name
        lab_host="localhost"
        [ -f $LAB_HOST_NAME ] && lab_host=$(< $LAB_HOST_NAME)
        lab_name=`basename $IMAGE`
        LAB_LOCAL_PORT=$TOP_DIR/.lab_local_port
        LAB_VNC_PWD=$TOP_DIR/.lab_login_pwd

        # Get login port
        local_port=6080
        [ -f $LAB_LOCAL_PORT ] && local_port=$(< $LAB_LOCAL_PORT)

        # Get vnc page
        url=http://$(docker-machine ip default):$local_port/vnc.html

	      # Get login password
	      pwd=ubuntu
        [ -f $LAB_VNC_PWD ] && pwd=$(< $LAB_VNC_PWD)

        openwith $url
        echo "Please login $url with password: $pwd"

4. 修改虚拟机的核数，VirtualBox 创建的虚拟机默认分配的核心数为 1 ，可以修改 VirtualBox 中给当前虚拟机分配的核心数（当前虚拟机名字一般是 default ），也可以修改 tools/lab-limits 中 `--cpuset-cpus` 的值，二者可以配合修改，如：将 VirtualBox 中虚拟机的核心数修改为 2 ，同时将 `--cpuset-cpus` 的值修改为 0-1 。

脚本修改完成。

### macOS 平台

安装好 Docker Engine 后首先打开 Terminal ，克隆 Linux Lab 仓库：

    git config --global core.autocrlf input #保持文本文件行结束符为 unix 风格，避免由于文件格式引起的问题
    git clone https://github.com/tinyclub/linux-lab.git
    cd linux-lab

接下来修改部分安装脚本，修改之处及内容如下：

1. 将 tools/install-docker-lab.sh 修改为如下：

        #!/bin/bash
        #
        # install-docker-lab.sh -- Build the docker image for the lab
        #
        TOP_DIR=$(pwd -P)/$(dirname $0)
        IMAGE=$(< $TOP_DIR/lab-name)
        docker build -t $IMAGE $TOP_DIR/

2. 将 tools/run-docker-lab.sh 中以下内容注释:

	第 10、69 行，即 `LAB_HOST_TOOL=$TOP_DIR/run-local-host.sh` 和 `[ -f $LAB_HOST_TOOL ] && $LAB_HOST_TOOL`

3. 将 tools/open-docker-lab.sh 修改为如下：

        #!/bin/bash
        #
        # open-docker-lab.sh -- open the docker lab via a browser
        #
        TOP_DIR=$(pwd -P)/$(dirname $0)
        IMAGE=$(< $TOP_DIR/lab-name)
        LAB_HOST_NAME=$TOP_DIR/.lab_host_name
        lab_host="localhost"
        [ -f $LAB_HOST_NAME ] && lab_host=$(< $LAB_HOST_NAME)
        lab_name=`basename $IMAGE`
        LAB_LOCAL_PORT=$TOP_DIR/.lab_local_port
        LAB_VNC_PWD=$TOP_DIR/.lab_login_pwd
        # Get login port
        local_port=6080
        [ -f $LAB_LOCAL_PORT ] && local_port=$(< $LAB_LOCAL_PORT)

        # Get vnc page
        url=http://$lab_host:$local_port/vnc.html

        # Get login password
        pwd=ubuntu
        [ -f $LAB_VNC_PWD ] && pwd=$(< $LAB_VNC_PWD)

        open $url
        echo "Please login $url with password: $pwd"

4. 将 tools/update-lab-uid.sh, tools/update-lab-identify.sh, tools/start-docker-lab.sh, tools/kill-docker-lab.sh, tools/monitor-docker-lab.sh 中的 ``TOP_DIR=$(dirname `readlink -f $0`)`` 修改为 `TOP_DIR=$(pwd -P)/$(dirname $0)`

脚本修改完成。

## 搭建环境

搭建环境的内容可以参考 [Linux Lab 文档](http://tinylab.org/using-linux-lab-to-do-embedded-linux-development/#section-1)中的相应部分，在此列举一些搭建过程中可能会遇到的问题及其解决办法。

1. 在执行 `tools/install-docker-lab.sh` 的过程中反复出现“ Hash Sum mismatch ”的错误，出现此错误可能是因为网络不好造成 `apt-get update` 时同步的包出错，也可能是第三方源的包本身已经损坏，解决办法：首先尝试编辑 Dockerfile 将 `cn.archive.ubuntu.com` 修改成其他的源，如果再出现问题则直接将 `RUN sed -i -e "s%/archive.ubuntu.com%/cn.archive.ubuntu.com%g" /etc/apt/sources.list` 注释掉。

2. 运行 `tools/run-docker-lab.sh` 后长时间停留在“ LOG: Wait for lab launching... ”，说明在执行 `tools/install-docker-lab.sh` 构建 image 时出错。解决办法：可以使用 DockerHub 上已构建好的 image ，执行以下命令，等待执行完成后再接着 `tools/start-docker-lab.sh` 运行：

        tools/kill-docker-lab.sh
        docker rmi tinylab/linux-lab
        docker pull tinylab/linux

环境搭建完成后的使用教程同 [Linux Lab 文档](http://tinylab.org/using-linux-lab-to-do-embedded-linux-development/#uboot-linux-buildroot-)。
