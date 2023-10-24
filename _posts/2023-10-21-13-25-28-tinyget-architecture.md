---
layout: post
author: '孔家东苑'
title: "Tinyget 架构简介"
draft: false
album: "Tinyget 开发记录"
license: "cc-by-nc-nd-4.0"
permalink: /tinyget-architecture/
description: "介绍了 Tinyget 的设计思路和系统架构"
category:
  - Linux
tags:
  - 包管理器
---

## 总体结构

TinyGet 目录结构如下：

```bash
.
├── README.md
├── setup.py
└── tinyget
    ├── common_utils.py
    ├── globals.py
    ├── __init__.py
    ├── interact
    │   ├── ai_helper.py
    │   ├── buffer.py
    │   ├── __init__.py
    │   └── process.py
    ├── main.py
    ├── package.py
    └── wrappers
        ├── _apt.py
        ├── deprecated
        │   ├── _apt.py
        │   └── _dnf.py
        ├── _dnf.py
        ├── __init__.py
        ├── _pacman.py
        └── pkg_manager.py
```

Tinyget 的整体结构如下：

![Tinyget 整体架构](/wp-content/uploads/2023/10/Tinyget/images/architecture.png)

## interact 包

interact 包主要用于处理交互，`process.py` 用于处理与底层的交互，`ai_helper.py` 用于处理与 OpenAI 服务器的交互。`ai_helper` 在本系列其他文章中已经有介绍，在此不再赘述，重点介绍一下 `process.py`。

```python
def spawn(args: Union[List[str], str], envp: dict = {}):
    """
    Spawns a new process with the given arguments and environment variables.

    Args:
        args (Union[List[str], str]): If args is a string, assume it is a shell command.
                                      If args is a list, assume it is a list of arguments.
        envp (dict, optional): A dictionary containing additional environment variables
                               to be passed to the spawned process. Defaults to {}.

    Returns:
        subprocess.Popen: A subprocess.Popen object representing the spawned process.

    """
    # If args is a string, assume it is a shell command
    # If args is a list, assume it is a list of arguments
    orig_envp = dict(os.environ)
    for k, v in envp.items():
        orig_envp[k] = v
    return subprocess.Popen(
        args=args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        stdin=subprocess.PIPE,
        close_fds=True,
        env=orig_envp,
        bufsize=0,
        shell=isinstance(args, str),
    )

def execute_command(args: Union[List[str], str], envp: dict = {}, timeout: int = None):
    """
    Execute a command and capture its stdout and stderr.

    Args:
        args (Union[List[str], str]): The command to be executed. It can be a list of arguments or a single string.
        envp (dict, optional): The environment variables to be passed to the command. Defaults to an empty dictionary.
        timeout (int, optional): The maximum number of seconds to wait for the command to complete. Defaults to None.

    Returns:
        Tuple[str, str]: A tuple containing the stdout and stderr of the executed command.

    Raises:
        CommandExecutionError: If the command execution fails, an exception is raised with details about the command, environment variables, stdout, and stderr.
    """
    p = spawn(args, envp)
    stdout, stderr = p.communicate(input=None, timeout=timeout)
    if p.returncode != 0:
        raise CommandExecutionError(
            message=f"Executing command failed {args} with {envp}",
            args=args,
            envp=envp,
            stdout=stdout.decode(),
            stderr=stderr.decode(),
        )
    return stdout.decode(), stderr.decode()
```

本项目希望能够像调用函数一样执行命令，因此专门为 subprocess 制作了一层封装，最终达到 execute_command 并返回 stdout、stderr 的结果。

为了保证稳定捕获异常，execute_command 专门检查了命令行的返回值，如果返回值不为 0（根据 Linux 中的一般性约定，非零返回值即为错误发生），则抛出异常：

```python
class CommandExecutionError(Exception):
    def __init__(self, message: str, args: list, envp: dict, stdout: str, stderr: str):
        """
        Initializes a new instance of the class.

        Parameters:
            message (str): The error message.
            args (list): The arguments passed to the function.
            envp (dict): The environment variables.
            stdout (str): The standard output.
            stderr (str): The standard error.

        Returns:
            None
        """
        super().__init__(message)
        print(message)
        self.args = args
        self.envp = envp
        self.stdout = stdout
        self.stderr = stderr
```

## wrappers 包

此包为 TinyGet 核心包，为三类包管理器的功能进行了适配。

TinyGet 动态地检测当前支持的包管理器：

```python
def get_os_package_manager(possible_package_manager_names: List[str]):
    """
    Returns the first supported package manager found in the system's PATH environment variable.

    Parameters:
        possible_package_manager_names (List[str]): A list of possible package manager names to search for.

    Returns:
        str: The name of the first supported package manager found in the system's PATH environment variable.

    Raises:
        Exception: If no supported package manager is found in the system's PATH environment variable.
    """
    paths = os.environ["PATH"].split(os.pathsep)
    for bin_path in paths:
        for package_manager_name in possible_package_manager_names:
            if package_manager_name in os.listdir(bin_path):
                return package_manager_name
    raise Exception("No supported package manager found in PATH")
```

并依据检测的结果动态绑定包管理器：

```python
from ..common_utils import get_os_package_manager

package_manager_name = get_os_package_manager(["apt", "dnf", "pacman"])

if package_manager_name == "apt":
    from ._apt import APT as PackageManager
elif package_manager_name == "dnf":
    from ._dnf import DNF as PackageManager
elif package_manager_name == "pacman":
    from ._pacman import PACMAN as PackageManager
else:
    raise NotImplementedError(f"Unsupported package manager: {package_manager_name}")
```

其中 `APT`, `DNF`, `PACMAN` 均继承自 `PackageManager` 类：

```python
class PackageManagerBase:
    def list(self) -> List[Package]:
        raise NotImplementedError

    def update(self):
        raise NotImplementedError

    def install(self, package: Package):
        raise NotImplementedError

    def uninstall(self, package: Package):
        raise NotImplementedError

    def upgrade(self):
        raise NotImplementedError

    def search(self, keyword, limit=10) -> List[Package]:
        raise NotImplementedError

    def get_package(self, package_name: str) -> Package:
        raise NotImplementedError
```

## 顶层接口

main.py 中实现了与用户交互的所有功能，以 click.command 的形式暴露给用户，以 tinyget list 为例，实现如下：

```python
@cli.command("list", help="List packages.")
@click.option(
    "--installed",
    "-I",
    is_flag=True,
    default=False,
    help="Show only installed packages.",
)
@click.option(
    "--upgradable",
    "-U",
    is_flag=True,
    default=False,
    help="Show only upgradable packages.",
)
@click.option(
    "--count", "-C", is_flag=True, default=False, help="Show count of packages."
)
def list_packages(installed: bool, upgradable: bool, count: bool):
    package_manager = PackageManager()
    packages = package_manager.list_packages(
        only_installed=installed, only_upgradable=upgradable
    )
    if count:
        click.echo(f"{len(packages)} packages in total.")
    else:
        for package in packages:
            click.echo(package)
```

使用 click 库实现 CLI，为后续 trogon 实现 TUI 提供了便利。
