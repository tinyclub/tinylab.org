---
layout: post
author: 'iOSDevLog'
title: 'The Real Time Linux 官方文档翻译'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-real-time-linux-2/
description: 'The Real Time Linux 官方文档翻译'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - Realtime
  - Preempt
  - 实时抢占
---

> Corrector:  [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [urls]
> Title:      [The Real Time Linux](https://wiki.linuxfoundation.org/realtime/start)
> Author:     lukas.bulwahn, kstewart, bigeasy, anna-maria
> Translator: Jia Xianhua <jiaxianhua@tinylab.org>
> Date:       2023/02/10
> Revisor:    Falcon <falcon@tinylab.org>;Taotieren <admin@taotieren.com>
> Project:    [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:   [【老师提案】RISC-V RealTime 分析、优化与 CPU 设计建议][002]
> Sponsor:    PLCT Lab, ISCAS


> The Real Time Linux collaborative project was established to help coordinate the efforts around mainlining Preempt RT and ensuring that the maintainers have the ability to continue development work, long-term support and future research of RT. In coordination with the broader community, the workgroup aims to encourage broader adoption of RT, improve testing automation and documentation and better prioritize the development roadmap.

实时 Linux 合作项目的建立，是为了帮助协调围绕主线化 Preempt RT 的所有努力，并确保维护者有能力继续开发工作，长期支持和未来研究 RT。在与更广泛的社区协调下，该工作组旨在鼓励更广泛地采用 RT，改善测试自动化和文档，并更好地确定开发计划图的优先次序。

## RTL 合作项目（The RTL Collaborative Project）

> The RTL Collaborative Project was first announced in October 2015.

RTL 合作项目于 2015 年 10 月首次宣布。

> The Real-Time Linux (RTL) Collaborative Project was founded by industry experts to advance technologies for the robotics, telecom, manufacturing, and medical industries. The RTL Collaborative Project will initially focus on pushing critical code upstream to be reviewed and later merged into the mainline Linux kernel with ongoing support. RTL’s Thomas Gleixner, who has been maintaining the RTL branch for more than a decade, will become a Linux Foundation Fellow to dedicate even more time to this project.

实时 Linux（RTL）合作项目是由行业专家创立的，旨在推动机器人、电信、制造和医疗行业的技术。RTL 合作项目最初将专注于向上游推送关键代码，以便进行审查，随后合并到 Linux 内核主线中，并提供持续支持。RTL 合作项目的 Thomas Gleixner 已经维护 RTL 分支十多年了，他将成为 Linux 基金会研究员，为这个项目奉献更多的时间。

### RTL 项目进展（RTL project progress）

> The aim of the RTL collaborative project is mainlining the PREEMPT_RT patch. In order to reach this goal, there is much work to be done. The following page describes the topics that Thomas Gleixner's real-time team is currently working on:
>
> - Current Topics for PREEMPT_RT mainlining

RTL 合作项目的目标是使 PREEMPT_RT 补丁主线化。为了达到这个目标，还有很多工作要做。下面的页面描述了 Thomas Gleixner 的实时团队目前正在进行的主题。

- 当前的 PREEMPT_RT 主线化主题

> For an overview of the tasks to be accomplished to reach the project's goals see:
>
> - Topics Overview for PREEMPT_RT mainlining

关于为实现项目目标所要完成的任务的概述，请参见：

- PREEMPT_RT 主线化的主题概述

> Beside those specialized topics, the already existing PREEMPT_RT patches have to be maintained later on.

除了这些专门的主题外，之后还需要维护已经存在的 PREEMPT_RT 补丁。

## PREEMPT_RT 补丁版本（PREEMPT_RT patch versions）

> The PREEMPT_RT patch is available for every long term stable version of the mainline Linux kernel since kernel version v2.6.11. Most long term stable versions of the Linux kernel have an even subversion number.

PREEMPT_RT 补丁适用于自内核版本 v2.6.11 以来的每个长期稳定版本的 Linux 内核。大多数 Linux 内核的长期稳定版本都有一个偶数的 subversion (子版本) 编号。

### 仓库（Repositories）

> There are two git repositories hosting the source code of the Linux mainline kernel versions with the additional PREEMPT_RT Patch.

有两个 git 仓库存放着带有额外 PREEMPT_RT 补丁的 Linux 主线内核版本的源代码。

- <http://git.kernel.org/cgit/linux/kernel/git/rt/linux-rt-devel.git>
- <http://git.kernel.org/cgit/linux/kernel/git/rt/linux-stable-rt.git>

> The first one hosts the current development PREEMPT_RT patches with the corresponding Linux mainline source. The development of a particular version usually stops when the focus switches to the next mainline version. This happens once a new stable candidate is released. After this, the development versions are moved to the second repository and are maintained by Steven Rostedt. The maintainers of the first git repository are Sebastian Siewior and Thomas Gleixner.

第一个存放了当前开发的 PREEMPT_RT 补丁和相应的 Linux 主线源。当重点转向下一个主线版本时，某个特定版本的开发通常会停止。这发生在一个新的稳定候选版本发布之后。在这之后，开发版本被移到第二个仓库，由 Steven Rostedt 维护。第一个 git 仓库的维护者是 Sebastian Siewior 和 Thomas Gleixner。

> The different versions of the PREEMPT_RT patch are additionally available as tar balls. They are hosted on the kernel.org website.

此外，不同版本的 PREEMPT_RT 补丁也以 tar 包的形式提供。它们被托管在 kernel.org 网站上。

- <https://cdn.kernel.org/pub/linux/kernel/projects/rt/>

### 补丁版本概述（Patch versions overview）

> The versions of the PREEMPT_RT patch can be split into two groups. The first one contains those versions which are actively maintained. The second group includes the kernel versions that are no longer actively maintained. The support for a PREEMPT_RT patch version depends on the projected "End of Life" of the mainline kernel version.

PREEMPT_RT 补丁的版本可以被分成两组。第一组包含那些正在积极维护的版本。第二组包括不再积极维护的内核版本。对 PREEMPT_RT 补丁版本的支持，取决于主线内核版本的计划停止维护时间。

## 参与（Participation）

> The RTL project is looking for people who are interested to work with us in the areas of testing, documentation and development.

RTL 项目正在寻找有兴趣在测试、文档和开发领域与我们合作的人。

### 测试（Testing）

> Testing is one of the most important tasks in any project. We have only access to a limited number of boards and we can only run generic procedures. We would appreciate if you run RT on your hardware with your application specific test cases.

测试是任何项目中最重要的任务之一。我们只能接触到数量有限的开发板，我们只能运行通用程序。如果您在您的硬件上运行 RT，并使用您的特定应用测试案例，我们将非常感激。

> If you run into problems, then you have two options:
>
> - Report the problem. See ["Reporting a bug"][006] for further information
> - Analyze the problem and submit a patch. Don't worry if you think that your patch is not perfect. It's a start and at least you share the analysis of the problem. See ["Submitting a patch"][007] for further information.

如果你遇到问题，那么你有两个选择：

- 报告问题。参见 ["报告一个错误"][006] 以了解更多信息
- 分析问题并提交一个补丁。如果你认为你的补丁不完美，也不要担心。这只是一个开始，至少你分享了对问题的分析。更多信息请参见 ["提交补丁"][007]。

### 文档（Documentation）

> We need help in creating and maintaining content in this [wiki][005]. Part of the effort is to cherry pick pages of the old wiki which contain valuable information, transfer them to the new wiki and bring them up to date. We also look for editors to document areas which are missing completely.

我们需要帮助来创建和维护这个 [维基][005] 的内容。部分工作是挑选旧维基中包含有价值信息的页面，将其转移到新维基中并使其成为最新的内容。我们也在寻找编辑来记录那些完全缺失的领域。

> [Here][010] you can find an incomplete list of topics which need help.

在 [这里][010]，你可以找到一个不完整的需要帮助的主题清单。

> If you pick a topic to work on, please mark it with your name in the list. If you chose to pick a topic which is not in the list, please add it and assign it to yourself.

如果你选择了一个要做的主题，请在列表中标明你的名字。如果你选择了一个不在列表中的主题，请添加它并将其分配给自己。

> Please see the [wiki guideline][009] to get started.

请参阅 [wiki 指南][009] 以开始。

### 开发（Development）

> If you want to help with the development and mainlining effort of RT please contact [us][011].

如果您想帮助 RT 的开发和主线化工作，请与 [我们][011] 联系。

> The topics, that need to be handled to get PREEMPT_RT mainlined are listed [on the RTL Collaborative Project page][2].

为了让 PREEMPT_RT 进入主线，需要处理的主题已经在 [RTL 合作项目页面上列出][2]。

> An overview about features that are disabled by CONFIG_PREEMPT_RT_FULL=y are listed [here][008]. (The support of those features with PREEMPT_RT_FULL is not a main part of the RTL project.)

[这里][008] 列出了被 `CONFIG_PREEMPT_RT_FULL=y` 禁用的功能的梗概（对这些功能的支持不是 RTL 项目的主要部分）。

## 参考资料

1. [The Real-Time Linux][1]
2. [The RTL Collaborative Project][2]
3. [Versions of PREEMPT_RT patches][3]
4. [Participation][4]

[1]: https://wiki.linuxfoundation.org/realtime/start
[2]: https://wiki.linuxfoundation.org/realtime/rtl/start
[3]: https://wiki.linuxfoundation.org/realtime/preempt_rt_versions
[4]: https://wiki.linuxfoundation.org/realtime/rtl/participate
[005]: http://rt.wiki.kernel.org/
[006]: https://wiki.linuxfoundation.org/realtime/communication/bugreport
[007]: https://wiki.linuxfoundation.org/realtime/communication/send_rt_patches
[008]: https://wiki.linuxfoundation.org/realtime/documentation/known_limitations#disabled-config_-options
[009]: https://wiki.linuxfoundation.org/realtime/edit_guideline
[010]: https://wiki.linuxfoundation.org/realtime/rtl/wikilist
[011]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:rt@linutronix.de
