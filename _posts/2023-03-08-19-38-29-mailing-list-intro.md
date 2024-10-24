---
layout: post
author: 'Bin Meng'
title: '正确使用邮件列表参与开源社区的协作'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /mailing-list-intro/
description: '正确使用邮件列表参与开源社区的协作'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - 邮件列表
  - 社区协作
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [codeblock autocorrect]
> Author:    Bin Meng <bmeng@tinylab.org>
> Date:      2022/11/12
> Revisor:   lzufalcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

国内的小伙伴们在初次接触一些开源社区（如 Linux 内核社区、QEMU 社区等）的时候，会发现他们都使用邮件列表作为主要的沟通方式（提交补丁、报告 bug 等），这对于习惯了使用微信、钉钉、飞书等即时聊天工具的我们来讲，可能会非常不适应，一时不知如何上手从而萌生了“从入门到放弃”的念头。“工欲善其事，必先利其器”，如果我们要参与到开源社区的协作中去，我们一定要好好了解一下邮件列表到底是什么，有什么用，以及正确的打开方式。

## 邮件列表的定义

[维基百科][1] 对邮件列表这个词条的定义是这样的，它包括了两种类型，分别是公告型和讨论型。今天我们见到的大部分邮件列表都是讨论型的邮件列表，其定义如下：

> a 'discussion list' allows subscribing members (sometimes even people outside the list) to post their own items
> which are broadcast to all of the other mailing list members. Recipients may answer in similar fashion, thus,
> actual discussion and information exchanges can occur. Mailing lists of this type are usually topic-oriented
> (for example, politics, scientific discussion, health problems, joke contests), and the topic may range from
> extremely narrow to "whatever you think could interest us". In this they are similar to Usenet newsgroups,
> another form of discussion group that may have an aversion to off-topic messages.

简单翻译一下，即是：

> 一个 “讨论列表” 允许订阅成员（有时甚至是列表之外的人）发送他们自己的消息，这些消息将广播给所有其他邮件列表成员。接收者亦可以用同样的方式做出回应，参与讨论并交流信息。这种类型的邮件列表通常有某个特定的主题（如科学、健康、数码产品等），这点跟早期的 Usenet 新闻组非常类似。

## 邮件列表的特点

邮件列表的历史相当悠久了，从上面的定义中可以看到，其实它的讨论功能跟我们今天使用的微信群有点类似，但为什么这些开源社区仍然坚守邮件列表这一沟通方式呢？

我们来看看邮件列表都有哪些特点：

- 异步的交流方式。开源社区的参与者往往分布在全球各地，通过邮件列表这样的沟通方式可以很好的解决时区问题。这点跟跨国公司一般采用电子邮件进行沟通是基于同样的原因。因为邮件沟通是异步进行的，接收者可以选择他比较方便的时间回复信息。

- 方便存档和检索。参与者可以通过搜索公开的邮件列表存档方便地获取到相关问题的讨论，哪怕这个讨论已经过去许久。开源软件常被人诟病没有设计文档，但新功能的实现一般都会在邮件列表进行深度讨论。后来者要想获悉前人在某个功能特性设计之初的想法和社区的评审意见，如果错过了当时的讨论也没有关系，通过检索互联网上公开的邮件列表存档即可一览全貌。这一点是一众即时聊天工具力不能及的。

- 讨论内容能够保证一定的质量。一般来说邮件列表会对发往列表的信息作出一定程度的质量要求，所有的参与者在制定了规则的情况下，并且有异步沟通带来的充裕时间保障，在编辑和回复邮件时会更加注意措辞和用词的严谨性，对内容的质量有着更高的潜在要求。

## 如何参与邮件列表的讨论

### 订阅邮件列表

大多数开源社区的邮件列表并不要求使用者订阅邮件列表后才能向邮件列表发送消息，但如果你想更加方便地参与到邮件列表的讨论中，你可以选择使用自己的邮箱地址订阅邮件列表。

订阅的方式根据提供邮件列表服务的软件各不相同。最常见的通常有下面两种形式：

- 一种是以 [Linux 内核社区][2] 为代表的基于 majordomo 服务的邮件列表。订阅这种类型的邮件列表，用自己的邮箱向指定的邮件地址发一封纯文本格式的邮件即可。比如想订阅 Linux 内核开发的邮件列表，发送一封这样的邮件：

  ```
  mailto:majordomo@vger.kernel.org?body=subscribe linux-kernel
  ```

- 另一种是基于 mailman 服务的邮件列表，比如 [QEMU 社区][3]、[U-Boot 社区][4] 等。订阅这种类型的邮件列表，需要从网页端注册，比如 QEMU 开发的邮件列表，在这个 [页面][3] 注册，填入自己的邮箱地址和该邮件列表的访问密码（注意不是邮箱本身的密码），然后静等邮件列表服务器给自己的邮箱地址发一封确认邮件，收到后点击确认邮件中的链接即可完成订阅。

国内的邮件服务提供商如腾讯、网易等，对邮件列表发来的邮件的容忍度略低，通常会把这些邮件视为垃圾邮件直接拦截。如果想完整体验邮件列表的讨论乐趣，推荐使用谷歌 gmail 或者微软的 Outlook 邮箱来订阅。考虑到其他非技术因素（如需要搭梯子等），使用国内的邮箱对收发邮件更加友好，但须注意禁止垃圾邮件拦截，或者把邮件列表地址加入白名单等方式。

注意：订阅不是必须的，如果你不想订阅，还是有办法可以参与社区的讨论，不过就是稍微麻烦一些。后面会有章节专门讲述这部分内容。

### 发送和回复邮件

一般来说，开源社区的邮件列表对于邮件格式有一些共同的基本要求：

- 邮件格式须为“纯文本”格式。现在大多数邮件客户端的默认格式都已经是 HTML 了，从客户端撰写邮件的时候需要注意切换。

- 回复别人的邮件进行引用时，一般使用符号 **>** 作为标记，且回复的内容不能在最顶部，即所谓 “Top-Post” 的方式。这一点在使用邮件客户端进行回复的时候尤其要注意，因为大部分邮件客户端在回复邮件的时候都是采用 “Top-Post” 的方式。正确的方式是引用的内容在上面，回复的内容放在引用的内容之后，如下所示：

  ```
  > This is a sample email.
  > It changes a behavior of API x, ...

  blabla ...

  > API y has an issue that ...

  blabla ...
  ```

  发送邮件如果邮件内容是一个补丁文件，推荐使用 `git` 自带的 `send-email` 命令来发送补丁。切忌从邮件客户端里撰写新邮件，严禁直接粘贴补丁的内容到邮件正文中。很多邮件客户端会对邮件内容进行一些“自作主张”的修改，比如删除空行、自动折行等，这会破坏补丁文件的有效性，导致补丁不能被正确地合并。

  有些时候你可能需要回复一封发送到某个邮件列表的邮件（如审阅 / 测试别人的补丁），但是这封邮件因为各种不同的原因并没有在你的邮箱中，比如：

- 你订阅了邮件列表，但是这封邮件是在你订阅邮件列表之前发送到邮件列表的

- 你订阅了邮件列表，因为网络的原因（如你的邮件服务提供商的短时服务中断）邮件并没有成功投递到你的邮箱地址

- 你没有订阅邮件列表

这时候我们可以使用 Linux 内核官方的邮件列表存档服务 [lore][5]，配合 `git send-email` 命令来发送你的邮件。

在 lore 页面上搜索你想要的邮件列表，比如在搜索框键入 `qemu`，点击返回的 [链接][6] 进入，然后搜素自己想回的邮件标题，比如搜索 `Avoid warning about dangerous use of strncpy()` 会返回几个结果，定位到自己想回的某封邮件，如 [这一封][7]，搜索 `raw` 并点击保存得到纯文本格式的原始邮件。

编辑保存的文件：

- 删掉最上面的一大片的邮件头信息

- 保留邮件标题所在的行，并在原标题前面加上 `Re:` 即可
  - 即保留 “Subject” 字样的行，并改为：`Subject: Re: 原标题`

- 用符号标记 **>** 引用原文，自己回复的内容穿插于引用的内容之间
  - 可以批量替换：`sed -i -e 's/^/> /g' /path/to/the-patch-email`
  - 也可以在 vim 中按下 `CTRL+V` 进入可视模式选中需要回复的所有行，然后键入 `s/^/> /` 在行首插入 `>`
  - **注意**：不要替换 `Subject` 所在邮件标题行

完毕后保存到 `/path/to/YOUR_REPLY`。向下滚动 lore 的邮件 [页面][7]，页面底部列出了用 `git send-email` 命令来回复这封邮件的命令：

```
$ git send-email \
    --in-reply-to=20221111124550.35753-1-philmd@linaro.org \
    --to=philmd@linaro.org \
    --cc=armbru@redhat.com \
    --cc=bin.meng@windriver.com \
    --cc=f4bug@amsat.org \
    --cc=kwolf@redhat.com \
    --cc=qemu-devel@nongnu.org \
    --cc=stefanha@redhat.com \
    --cc=xieyongji@bytedance.com \
    /path/to/YOUR_REPLY
```

发送成功后，见到

```
OK. Log says:
Server: smtp.gmail.com
...

Result: 250
```

就表示邮件已经成功地发送出去了。

上面这个方法虽然麻烦一些，但并不要求使用者订阅邮件列表，对于不要求订阅者才能发送邮件的邮件列表，或是因为个人邮箱容量大小的限制不能订阅某些邮件列表的时候，还是非常有用的。

### 手动补发一个补丁系列中的某个补丁

`git send-email` 命令可以自动把整个补丁系列的所有补丁以邮件的形式发送到邮件列表，并且在默认的配置下会把所有的补丁邮件串成一个系列，即除第一封邮件的所有后续邮件都是回复的系列第一封邮件。整个补丁系列在邮件客户端看起来大概是这样：

```
[PATCH 0/7] Here is what I did ...
    [PATCH 1/7] Clean up and tests
    [PATCH 2/7] Implementation
    blabla
    [PATCH 7/7] Enable something
```

有时我们会发现，出于某种原因发往邮件列表的一个补丁系列中的其中一封邮件丢了，并没有被成功发送到邮件列表中。这时候我们可以选择直接重发整个补丁系列，比如常见的最佳实践是在所有的补丁邮件标题上加上一个 `RESEND` 的 tag 表明这是一次重发，补丁的版本号保持不变。除了重发这种简单粗暴的方法之外，有没有什么轻量级的补救办法可以手动补发一封邮件，并且还可以正确地串到之前的系列邮件呢？

答案是有的，需要我们准备好邮件头中两个 metadata，分别是 `In-Reply-To` 和 `Message-Id`。`In-Reply-To` 是补丁系列第一封邮件的 `Message-Id`，这个可以在 [lore][5] 中查看邮件头得到。`Message-Id` 是补发邮件的 `Message-Id`，参考补丁邮件系列中第一封邮件的 `Message-ID` 生成一个即可。确认这两个 metadata 后，将其写入到要重发的补丁文件开头。以下是针对上述邮件系列补发 [PATCH 7/7] 的例子，修改 [PATCH 7/7] 补丁文件在 `Subject` 前面插入这两个 metadata：

```
In-Reply-To: <20230107114100.3184790-1-bmeng@tinylab.org>
Message-Id: <20230107114100.3184790-8-bmeng@tinylab.org>
Subject: [PATCH 7/7] Enable something
```

然后再次通过 `git send-email` 发送更新后的补丁文件即可。

## 常见的 SMTP 服务提供商配置

下面列出了一些常见的邮件服务提供商的 `git` 配置信息，仅供参考。注意 `smtpuser` 和 `smtppass` 分别是邮箱的地址和密码，使用时需替换成自己的账户信息。

**[谷歌 gmail][8]**

```
[sendemail]
        smtpencryption = tls
        smtpserver = smtp.gmail.com
        smtpserverport = 587
        smtpuser = username@gmail.com
        smtppass = ****************
```

**[微软 Outlook][9]**

```
[sendemail]
        smtpencryption = tls
        smtpserver = smtp-mail.outlook.com
        smtpserverport = 587
        smtpuser = username@outlook.com
        smtppass = ****************
```

**[腾讯企业邮][10]**

```
[sendemail]
        smtpencryption = ssl
        smtpserver = smtp.exmail.qq.com
        smtpserverport = 465
        smtpuser = username@tinylab.org
        smtppass = ****************
```

## 总结

本文介绍了邮件列表的定义和特点，并用一个例子详细说明了如何订阅邮件列表，怎样发送信息（补丁文件），以及具体参与其中的讨论。希望有志于投身开源软件的小伙伴们读过此文后，能够掌握邮件列表这一沟通工具，从而顺利地参与到开源社区的全球合作中去。

[1]: https://en.wikipedia.org/wiki/Mailing_list
[2]: http://vger.kernel.org/vger-lists.html
[3]: https://lists.nongnu.org/mailman/listinfo/qemu-devel
[4]: https://lists.denx.de/listinfo/u-boot
[5]: https://lore.kernel.org
[6]: https://lore.kernel.org/qemu-devel
[7]: https://lore.kernel.org/qemu-devel/20221111124550.35753-1-philmd@linaro.org
[8]: https://gmail.google.com
[9]: https://outlook.live.com
[10]: https://exmail.qq.com
