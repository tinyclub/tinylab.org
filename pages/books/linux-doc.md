---
title: Linux Doc 中文化
tagline: Linux Documentation/ 文档中文翻译计划
author: Wu Zhangjin
layout: page
album: 'Linux Doc 中文版'
group: translation
permalink: /linux-doc/
description: Linux Documentation 中文翻译计划，该计划包括三阶段目标：第一阶段把原有的中文文档转成 Markdown 并导入；第二阶段翻译余下的部分；第三阶段，持续维护和更新
update: 2015-10-1
categories:
  - 开源书籍
  - Linux 综合知识
tags:
  - Linux
  - Documentation
  - 中文翻译
---

**注意**：该项目不再更新和维护。

## 简介

该项目致力于翻译 [Linux Documentation][1] 为中文版。

* 在线阅读
  * <https://tinylab-1.gitbook.io/linux-doc>
* 代码仓库
  * [https://github.com/tinyclub/linux-doc.git][2]
* 项目首页
  [Linux-Doc](/linux-doc/)

## 报名参与

### 参与步骤

  * 关注[@泰晓科技][3] 微博。
  * 私信一份简介，要求有 Linux、Git、Github、Markdown 和英文相关背景，择优录取。
  * 通过后，会统一加入翻译协作微信群。
  * 提前注册 github.com 和 gitbook.com 帐号，注册完以后把帐号名发到微信群。
  * 提前学习 [markdown][4] 用法。
  * 提前搭建 [gitbook][5] 环境。
  * 查看 [任务分工][6] 认领并更新该文件，然后在微信协作群通知其他同学。
  * 开展后续翻译过程，看下面。

### 开展翻译

具体翻译过程请参考[译者手册][7]。

## 相关项目

  * [Embedded Linux Wiki （嵌入式 Linux 知识库）中文翻译计划][8]
  * [开源书籍：C 语言编程透视][9]
  * [开源书籍：Shell 编程范例][10]

<section id="home">
  {% assign articles = site.posts %}
  {% assign condition = 'album' %}
  {% assign value = page.album %}
  {% include widgets/articles %}
</section>

 [1]: http://www.kernel.org/doc/Documentation
 [2]: https://github.com/tinyclub/linux-doc
 [3]: http://weibo.com/tinylaborg
 [4]: http://help.gitbook.com/format/markdown.html
 [5]: /docker-quick-start-docker-gitbook-writing-a-book/
 [6]: https://tinylab-1.gitbook.io/linux-doc/content/zh-cn/doc/PLAN.html
 [7]: https://tinylab-1.gitbook.io/linux-doc/content/zh-cn/doc/index.html
 [8]: https://tinylab-1.gitbook.io/elinux/
 [9]: https://tinylab-1.gitbook.io/cbook/
 [10]: https://tinylab-1.gitbook.io/shellbook/
