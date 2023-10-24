---
layout: post
author: '孔家东苑'
title: "Tinyget 软件包管理器演进与现状"
draft: true

album: "Tinyget 开发记录"

license: "cc-by-nc-nd-4.0"
permalink: /tinyget-package-manager/
description: "  这篇文章是 Tinyget 系列的第一篇文章，调研了各种包管理器的发展历史 "
category:
  - Linux
tags:
  - 包管理器
---

## 软件包管理器的诞生背景

在计算机科技的早期阶段，软件的分发主要通过文件传输协议（FTP）或邮件列表进行。这些软件通常需要使用 `configure`、`make` 等工具链操作 `gcc` 等编译器进行构建，依赖`Makefile` 进行所谓的“黑盒”安装。然而，这种方式存在一些显著的问题。首先，它无法获取当前系统已经安装的软件及其版本信息，这使得版本控制变得困难。其次，二进制分发在这种模式下相对困难，因为它需要在本地进行编译，这可能会导致一些兼容性问题。最后，这种方式需要手动维护软件的依赖关系，这无疑增加了用户的负担。

为了解决这些问题，开发者开始寻求新的解决方案，这就是“包”的概念应运而生。在这里，“包”是指包含元信息的“软件”，这些元信息包括但不限于软件的版本、依赖关系等。这种方式使得软件的管理和分发变得更加简单和高效。为了进一步提高效率，开发者还创建了“包管理器”，这是一种可以统一管理“包”的工具。包管理器能够维护当前系统已有的软件列表，对当前系统中的软件进行安装、更新和删除。这大大简化了软件的管理和维护过程，提高了用户的使用体验。

## “初级”软件包管理器

### dpkg

`dpkg`，全称 Debian Package，是一款诞生于 1994 年的包管理器，专为 Debian Linux 系统设计。它是 Debian 操作系统的核心组件，负责处理和管理 Debian 软件包的安装、升级、降级、查询和删除等操作。

`dpkg` 的工作原理是通过读取软件包的元数据，如包的名称、版本、依赖关系等信息，来执行相应的操作。这些元数据通常包含在 `.deb` 文件中，这是 Debian 软件包的标准格式。

`dpkg` 的基本使用方法非常丰富，包括但不限于以下几种：

1. **安装软件包**：使用 `dpkg -i` 或`dpkg --install` 命令可以安装 `.deb` 文件。例如，`dpkg -i package.deb` 会安装名为 `package.deb` 的软件包。

2. **删除软件包**：使用 `dpkg -r` 或`dpkg --remove` 命令可以删除已安装的软件包。例如，`dpkg -r package` 会删除名为 `package` 的软件包。

3. **检查软件包的状态和信息**：`dpkg -s` 或`dpkg --status` 命令可以查看软件包的状态和详细信息。例如，`dpkg -s package` 会显示名为 `package` 的软件包的状态和信息。

4. **列出已经安装的软件包**：`dpkg -l` 或`dpkg --list` 命令可以列出系统中已经安装的所有软件包。

5. **查询文件属于哪个软件包**：`dpkg -S` 或`dpkg --search` 命令可以查询某个文件属于哪个软件包。例如，`dpkg -S /usr/bin/ls` 会显示 `/usr/bin/ls` 文件属于哪个软件包。

6. **重新配置已安装的软件包**：`dpkg-reconfigure` 命令可以重新配置已安装的软件包。例如，`dpkg-reconfigure package` 会重新配置名为 `package` 的软件包。

值得注意的是，`dpkg` 并不处理软件包之间的依赖关系。如果需要处理依赖关系，可以使用 `apt` 或`apt-get` 等高级包管理工具，这些工具在 `dpkg` 的基础上提供了处理依赖关系的功能。

### rpm

RPM，全称 Red Hat Package Manager，是一种强大且灵活的包管理系统，于 1997 年首次亮相，作为 Red Hat Linux 的核心组成部分。RPM 不仅被广泛应用于 Red Hat 及其衍生版本，如 Fedora、CentOS 等，还被其他许多 Linux 发行版如 SUSE、Mandriva 等采用。

RPM 的主要功能是管理 Linux 系统中的软件包，包括安装、卸载、升级、查询和验证等操作。它使用。rpm 文件格式，这种文件格式包含了软件的所有文件和目录，以及如何安装和卸载软件的指令。

RPM 的基本使用方法如下：

1. **安装软件包**：使用 `rpm -i` 或`rpm --install` 命令可以安装。rpm 文件。例如，`rpm -i package.rpm` 会安装名为 package 的软件包。
2. **删除软件包**：使用 `rpm -e` 或`rpm --erase` 命令可以删除已安装的软件包。例如，`rpm -e package` 会删除名为 package 的软件包。
3. **检查软件包的状态和信息**：使用 `rpm -q` 或`rpm --query` 命令可以查询软件包的信息。例如，`rpm -q package` 会显示名为 package 的软件包的信息。
4. **列出已经安装的软件包**：使用 `rpm -qa` 或`rpm --query --all` 命令可以列出系统中所有已安装的软件包。
5. **查询文件属于哪个软件包**：使用 `rpm -qf` 或`rpm --query --file` 命令可以查询某个文件属于哪个软件包。例如，`rpm -qf /path/to/file` 会显示包含该文件的软件包。
6. **检查软件包的完整性**：使用 `rpm -V` 或`rpm --verify` 命令可以检查软件包的完整性。这个命令会比较系统中的文件和。rpm 文件中的文件，检查是否有差异。
7. **升级软件包**：使用 `rpm -U` 或`rpm --upgrade` 命令可以升级软件包。例如，`rpm -U package.rpm` 会升级名为 package 的软件包。

## “高级”包管理器概览

高级包管理器是软件开发和维护中的关键工具，它们主要解决了软件供应链的接入问题，包括软件仓库（源）的管理、依赖关系的自动解决、软件包的版本管理、软件包的升级管理以及软件包的签名管理等问题。这些功能都是为了确保软件的稳定性和安全性，同时也提高了开发和维护的效率。

软件仓库（源）的管理是包管理器的基础功能之一，它允许开发者从指定的源获取和安装软件包。这些源通常包含了大量的预编译软件包，可以方便地进行搜索和安装。

依赖关系的自动解决是包管理器的另一个重要功能。当安装一个软件包时，包管理器会自动检查并安装所有必要的依赖，这极大地简化了软件安装过程。

软件包的版本管理和升级管理则是为了确保软件的稳定性和安全性。包管理器可以跟踪软件包的版本，自动下载和安装更新，以保持软件的最新状态。

软件包的签名管理是为了确保软件的安全性。包管理器会验证软件包的签名，以确保它们来自可信的源，并且没有被篡改。

不同的 Linux 发行版通常会使用不同的包管理器。例如，Debian 系的发行版通常使用 apt，它提供了强大的依赖关系处理和软件包搜索功能。Red Hat 系的发行版则常用 yum 或 dnf，它们提供了丰富的插件系统和自动解决依赖关系的功能。Arch 系的发行版使用 pacman，它以其简洁的设计和高效的性能而闻名。SUSE 系的发行版使用 zypper，它提供了强大的依赖关系处理和软件包管理功能。Gentoo 系的发行版使用 emerge，它允许用户从源代码编译软件包，提供了极高的自定义性。Slackware 系的发行版使用 slackpkg，它是一个简单但功能强大的包管理工具。

每种包管理器都有其独特的特性和优势：

* Debian 系的 apt 包管理器支持多种二进制包格式，包括。deb 和。udeb，它还支持多种源格式，包括镜像源、CD-ROM 源和 FTP 源等。此外，apt 还提供了一种强大的脚本语言，允许开发者编写复杂的安装和卸载脚本。

* Red Hat 系的 yum/dnf 包管理器则以其丰富的插件系统和自动解决依赖关系的功能而闻名。它支持。rpm 包格式，可以自动处理软件包的依赖关系，还可以自动下载和安装软件包的更新。此外，yum/dnf 还提供了一种强大的插件系统，允许开发者扩展其功能。

* Arch 系的 pacman 包管理器以其简洁的设计和高效的性能而闻名。它支持。pkg.tar.zst 包格式，可以自动处理软件包的依赖关系，还可以自动下载和安装软件包的更新。此外，pacman 还提供了一种强大的钩子系统，允许开发者在软件包的安装、升级和卸载过程中执行自定义的操作。

* SUSE 系的 zypper 包管理器提供了强大的依赖关系处理和软件包管理功能。它支持。rpm 包格式，可以自动处理软件包的依赖关系，还可以自动下载和安装软件包的更新。此外，zypper 还提供了一种强大的查询和搜索系统，允许用户快速找到所需的软件包。

* Gentoo 系的 emerge 包管理器允许用户从源代码编译软件包，提供了极高的自定义性。它支持。ebuild 脚本格式，可以自动处理软件包的依赖关系，还可以自动下载和安装软件包的更新。此外，emerge 还提供了一种强大的 USE 标志系统，允许用户自定义软件包的编译选项。

* Slackware 系的 slackpkg 包管理器是一个简单但功能强大的工具。它支持。tgz 和。txz 包格式，可以自动处理软件包的依赖关系，还可以自动下载和安装软件包的更新。此外，slackpkg 还提供了一种强大的模板系统，允许用户自定义软件包的安装过程。

高级包管理器是软件开发和维护中的重要工具，它们提供了一种方便、高效和安全的方式来管理软件包。不同的包管理器有各自的特性和优势，开发者可以根据自己的需求选择合适的工具。

## “SOTA”包管理器

SOTA 包管理器，即最先进的包管理器。这并不是一个既定的概念，而是笔者为了方便讲述而约定的概念。这些包管理器主要解决了一系列软件开发和部署中的关键问题，包括跨发行版、包隔离、环境隔离、安全隔离以及简单部署等。这些问题的解决，使得软件的开发、部署和维护变得更加简单和高效。

* 跨发行版的问题主要涉及到不同的 Linux 发行版之间的差异，这些差异包括但不限于 lib 版本、lib 路径、abi 兼容性（系统调用是否有差异）等。例如，不同的 Linux 发行版可能会使用不同版本的库文件，或者将库文件存放在不同的路径下。这些差异可能会导致在一个发行版上正常运行的软件在另一个发行版上无法运行。SOTA 包管理器通过提供统一的包格式和运行环境，解决了这个问题。

* 包隔离和环境隔离是指将每个软件包及其依赖项隔离在自己的环境中，以防止不同软件包之间的冲突。例如，两个软件包可能依赖于同一个库的不同版本，如果没有隔离，这可能会导致其中一个或两个软件包无法正常运行。SOTA 包管理器通过创建独立的运行环境来解决这个问题。

* 安全隔离是指将软件包的运行环境与主机系统隔离，以防止潜在的安全威胁。例如，一个恶意的软件包可能会试图修改主机系统的文件或设置，如果没有隔离，这可能会导致系统的安全性受到威胁。SOTA 包管理器通过限制软件包的权限和访问范围来实现安全隔离。

* 简单部署是指使软件包的安装和更新变得简单和直观。SOTA 包管理器通常提供了一种简单的命令行接口，使得用户可以轻松地安装、更新和卸载软件包。

常见的 SOTA 包管理器包括 Snap（Ubuntu 的官方包管理器）、Flatpak、AppImage、Nix（衍生出 NixOS 发行版）以及玲珑（Deepin 的官方包管理器）等。这些包管理器各有特点，但都致力于解决上述的问题，以提供更好的软件开发和部署体验。

1. **Snap**：Snap 是 Ubuntu 的官方包管理器，由 Canonical 公司开发。Snap 包含了应用程序需要的所有依赖项，使得应用程序可以在所有主要的 Linux 发行版上运行。Snap 还提供了自动更新和回滚功能，以及严格的安全控制。
2. **Flatpak**：Flatpak 是一个为 Linux 桌面应用程序设计的软件部署和包管理系统。Flatpak 提供了沙箱环境，使得应用程序可以在其自己的隔离环境中运行，从而提高了安全性。Flatpak 还支持运行在不同的 Linux 发行版上。
3. **AppImage**：AppImage 是一种为 Linux 创建便携式应用程序的格式。AppImage 包含了应用程序以及其运行所需的所有依赖项，无需安装即可运行。AppImage 文件可以在所有主要的 Linux 发行版上运行。
4. **Nix**：Nix 是一个强大的包管理系统，它允许系统配置和软件包的版本管理。Nix 的一个重要特性是它的纯粹性：它确保相同的构建过程总是产生相同的结果。Nix 还提供了原子性升级和回滚功能。
5. **玲珑**：这是 Deepin 的官方包管理器，它提供了一个简单易用的界面，使得用户可以轻松地安装、更新和卸载软件包。此外，它还提供了一些高级功能，如依赖项解析和冲突检测。

## 结论

![软件包管理器演进示意图](/wp-content/uploads/2023/10/Tinyget/images/package_manager.png)

从`dpkg` 和`rpm` 的基础功能，到 `apt`、`dnf` 和`pacman` 的依赖关系管理，再到 `玲珑` 和`snap` 的跨平台和沙箱化特性，包管理器的发展反映了开源社区对于易用性、稳定性和安全性的不断追求。这些工具不仅极大地简化了软件的安装和维护过程，也推动了 Linux 和其他开源操作系统的普及。未来，我们期待看到更多创新的包管理器出现，以满足日益复杂和多样化的需求。