---
layout: post
author: '孔家东苑'
title: "Tinyget 开发杂记"
draft: true
# tagline: " 子标题，如果存在的话 "
album: "Tinyget 开发记录"
# group: " 默认为 original，也可选 translation, news, resume or jobs, 详见_data/groups.yml"
license: "cc-by-nc-nd-4.0"
permalink: /tinyget-development-chronicles/
description: " 对 Tinyget 开发过程中碰到的技术问题与解决方案进行记录 "
category:
  - Linux
tags:
  - 包管理器
---

## 开发路线变更

在 Tinyget 的开发之初，选定的技术路线是利用各种包管理器的 sdk 实现 Tinyget 的功能：

1. 对于 apt 管理器，可以选择 libapt 的 python binding - python3-apt（https://github.com/Jolicloud/python-apt）。
2. 对于 dnf 管理器，它本身就自带 python 的 sdk - dnf api（https://dnf.readthedocs.io/en/latest/api.html）。

使用这类 SDK 的好处在于，功能更加灵活、全面、强大——毕竟这些包管理器本身就是由 SDK 实现的。同时也不乏基于这些 SDK 的优秀项目，例如：

* nala (https://github.com/volitank/nala)

但是使用 SDK 开发了一段时间后，发现存在如下困难：

1. API 会随着 SDK 的版本变化而剧烈变化——这是一件反直觉的事情，虽然各类包管理器都声称自己的 CLI 接口并不稳定，但是实际上 API 接口更加不稳定。
2. SDK 的文档并不充足，在开发时往往要进行大量的猜测和测试，也没有相关的例程参考。
3. 当调研到 pacman 包管理器时，我发现 python3-pacman 本身就是基于命令行接口实现的。

既然很多人都在直接使用命令行接口和文字解析的方式进行包管理器的二次开发，那我们显然也可以选择这条技术线路，降低开发难度，何乐而不为呢？

因此在后期的开发过程中，所有的包管理器的 wrapper 都被重构为了对命令行接口的封装，开发的难点落到了对包管理器的返回的解析。

在这种情况下，对于包管理器命令的执行相当容易，例如：安装、删除、更新等，但是对于包管理器输出的捕获则相对困难。这也是为什么本次开发周期仅实现了 list 这一个交互式功能。

## 权限配置问题

TinyGet 是一个包管理器的封装，本身是基于 Python 的项目。包管理器的诸多操作都需要 root 权限运行，因此往往用户也会以 root 权限（或 sudo）启动 TinyGet。但是当我为 TinyGet 添加了配置文件支持后，配置文件的权限就成为了一个问题——如果用户以 root 权限启动 TinyGet 并生成了配置文件，那么在普通用户状态下就无法再对该配置文件进行修改，这是与我们的预期不符的。

针对 sudo 场景，我需要实现一个功能，使得创建文件时 python 程序虽然处于高权限状态，但是本身属性仍是普通用户（发起 sudo 的用户）。

```python
@contextmanager
def impersonate(username=os.environ.get("SUDO_USER")):
    """
    Args:
        username (str, optional): The username to impersonate. Defaults to the value of the "SUDO_USER" environment variable.

    Yields:
        str: The path to the configuration file.

    Raises:
        OSError: If the specified user does not exist.
    """

    if username is None:
        need_impersonate = False
    else:
        original_uid = os.geteuid()
        original_gid = os.getegid()
        user_info = pwd.getpwnam(username)

        need_impersonate = (
            original_uid != user_info.pw_uid or original_gid != user_info.pw_gid
        )

    if need_impersonate:
        home_dir = user_info.pw_dir
    else:
        home_dir = os.environ["HOME"]
    config_path = os.path.join(home_dir, ".config", "tinyget", "config.json")
    try:
        yield config_path
    finally:
        if need_impersonate:
            if os.path.exists(config_path):
                os.chown(config_path, user_info.pw_uid, user_info.pw_gid)
```

这段代码使用 `contextlib` 库的 `contextmanager` 装饰器，定义了一个上下文管理器函数 `impersonate()`。这个函数用于模仿或代替系统中指定的用户操作。

1. `impersonate` 函数接受一个可选的参数 `username`，默认值是从环境变量"SUDO_USER"中获取。此参数是要模仿的用户名。
2. `if` 语句检查 `username` 是不是 `None`。如果是，则 `need_impersonate`（即需要模仿的意思）被设为 `False`；否则，它获取原始的用户和组 ID，然后使用 `pwd.getpwnam` 函数用 `username` 查找对应的用户信息。
3. `need_impersonate` 变量检查原始的用户和组 ID 是否与指定用户的不同，如果不同，则需要进行模仿操作。
4. 如果需要模仿，那么`home_dir` 变量被设置为指定用户的主目录，否则，它被设置为当前用户主目录。
5. `config_path` 变量被定义为主目录下的"~/.config/tinyget/config.json"配置文件的路径。
6. `yield` 关键字允许函数返回 `config_path`，同时暂停函数的执行。当生成器继续执行时（在 `with impersonate(username)` 代码块结束后），代码将从`yield` 语句之后的地方开始执行。
7. `finally` 子句确保某些清理操作总是会被执行。在此代码中，如果需要模仿，并且配置文件存在，那么会使用 `os.chown` 将配置文件的所有者改为指定的用户。

这个上下文管理器尝试模仿指定用户，提供其主目录下的".config/tinyget/config.json"文件路径，并确保在上下文退出时文件的所有者是正确的。如果 `username` 未指定或与原始用户相同，那么上下文管理器将直接提供原始用户的".config/tinyget/config.json"文件路径。

## Setup.py 脚本的编写

我常使用 python 项目形成的工具，但是并不太了解一个 python 脚本是怎样被安装到 PATH 中，并可以像 ls 这样的基本命令被调用的，这一次折腾了一下 setuptools，终于答疑解惑了。

```python
setup(
    name="tinyget",
    version="0.0.1",
    install_requires=required_packages,
    packages=find_packages(),
    author="kongjiadongyuan",
    author_email="zhaggbl@outlook.com",
    description="A tiny package manager for Linux",
    license="MIT",
    entry_points={"console_scripts": ["tinyget=tinyget.main:cli"]},
)
```

- name: 包的名称是 "tinyget"
- version: 包的版本号是 "0.0.1"
- install_requires: 安装这个包需要的其他包
- packages: 包含的 Python 包，由 `find_packages` 函数自动找出
- author 和 author_email: 作者的名字和邮箱地址
- description: 包的描述
- license: 包的许可证是 MIT
- entry_points: 定义了程序的入口点，当调用 `tinyget` 命令时，会执行`tinyget.main` 模块中的 `cli` 函数。这通常用于创建命令行工具。

## Click 库和 trogon 库

形成命令行工具的 Click 库相当容易形成一个命令行工具，项目文档如下：

[欢迎查阅 Click 中文文档 — click (click-docs-zh-cn.readthedocs.io)][001]

同时 trogon 可以轻易地将基于 click 开发的程序转变为 TUI 程序，神奇的是竟然还可以进行点击、滚动等鼠标操作。

[Textualize/trogon: Easily turn your Click CLI into a powerful terminal application (github.com)][002]

唯一比较遗憾的是，trogon 必须要求 python3.7 以上版本。不过由于它强大的功能，忍痛舍弃一部分兼容性。

## 参考资料

- [zh/latest][001]
- [Textualize/trogon][002]

[001]: https://click-docs-zh-cn.readthedocs.io/zh/latest/
[002]: https://github.com/Textualize/trogon
