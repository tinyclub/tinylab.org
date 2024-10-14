---
layout: post
author: '范思棋'
title: 'Epiphany 异常卡死问题分析 - Part2 编译 Mesa'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /epiphany-x11-fixing-part2/
description: 'Epiphany 异常卡死问题分析 - Part2 编译 Mesa'
category:
  - 开源项目
  - OpenGL
tags:
  - Linux
  - epiphany
  - x11
  - OpenGL
  - Mesa
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [codeblock urls refs pangu autocorrect]
> Author:    Siqi Fan <fansq19@lzu.edu.cn>
> Date:      20240925
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS

# epiphany 异常卡死问题分析 - Part2 编译 Mesa

## 概述

Mesa 仓库中有着许多显卡驱动，不同的版本会导致不同的 GUI 程序行为，特别是硬件加速的兼容性。我们需要手动编译来切换版本。

## 编译 Mesa

根据官方文档编译
[Compiling and Installing — The Mesa 3D Graphics Library latest documentation](https://docs.mesa3d.org/install.html)

```
meson setup builddir/

meson compile -C builddir/
sudo meson install -C builddir/
```

## 启用 Mesa

应用程序是通过动态链接来使用 Mesa 的。
动态链接（Dynamic Linking）是一种程序链接的方式，它在程序运行时而不是在编译时将所需的库（通常以 `.so` 结尾）加载到程序的地址空间中。动态链接的目的是为了节省内存、简化软件更新和减少可执行文件的大小。动态链接主要是在程序初始化时或者程序执行的过程中解析变量或者函数的引用。
在 Linux 系统中，动态链接器（`ld.so` 或 `ld-linux.so`）负责在运行时加载和链接共享库（即动态链接库）。它会根据配置文件 `/etc/ld.so.conf` 中的路径顺序，依次查找并加载所需的共享库。
如果我们希望启用刚编译的 Mesa，需要编辑 `/etc/ld.so.conf` 文件：

```
include /usr/local/lib/x86_64-linux-gnu
```

然后更新动态链接器的缓存：

```bash
sudo ldconfig
```

这样，任何新打开的 GUI 程序都会使用新编译的 Mesa。

此外，还可以用另一种方法临时启用新编译的 Mesa。
对于 OpenGL，可以通过使用更改环境变量切换调用 Mesa 的路径：

```
LD_LIBRARY_PATH="$MESA_INSTALLDIR/lib64" glxinfo
```

## 小结

经过编译不同的 Mesa 版本进行测试，最终可以确认 Mesa 24.1.0 版本修复了 epiphany 异常卡死问题。

## 参考资料

[程序链接 - CTF Wiki (ctf-wiki.org)](https://ctf-wiki.org/executable/elf/linking/program-linking/)
