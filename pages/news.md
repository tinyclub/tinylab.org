---
title: '资讯'
tagline: '追踪 Linux 业界动态'
author: Wu Zhangjin
layout: page
album: '泰晓资讯'
permalink: /news/
update: 2023-4-25
group: navigation
order: 2
toc: false
description: '汇集国内外 Linux 社区最新最重要的资讯，及时跟踪业界动态和发展趋势，主要关注 RISC-V、QEMU 模拟器、Linux 内核、发行版、应用、行业峰会等最新进展。'
categories:
  - 泰晓资讯
  - 技术动态
  - 行业动向
tags:
  - Linux 内核
  - 行业峰会
  - Linux 发行版
  - RISC-V
  - QEMU
---

亲爱的读者朋友们好！

早在 2015 年，本站编辑 [@cee1](/authors/#chen-jie-ref) 发起并维护了数月的 “泰晓周报”，及时跟踪了行业动态，由于时间关系，该专辑一度中断。

从 2019/05/31 日起，本站编辑 [@unicornx](/authors/#unicornx-ref) 重新启动该专辑，同时更名为 “泰晓资讯”，该专辑致力于及时地把国内外 Linux 社区的一些重要资讯汇总起来，同步给大家。

自 2022 年起，为了更深入细致地挖掘最新技术进展，泰晓社区新增了 3 个资讯栏目：

* 每周汇集 Linux 官方社区的最新开发进展，新增了 “RISC-V Linux 内核及周边技术动态”，内容涉及 RISC-V 架构以及各个内核子系统。
* 每两个月，在 Linux 内核发布大版本后，开展一期线上 Linux 内核观察节目。
* 每四个月，在 QEMU 模拟器发布大版本后，开展一期线上 QEMU 模拟器观察节目。

欢迎大家关注，也欢迎大家投递资讯线索、撰写资讯摘要。

* 泰晓资讯
  * 资讯首页：[tinylab.org/news](/news)
  * 内核观察：[B 站合集](https://space.bilibili.com/687228362/channel/collectiondetail?sid=637712)
  * QEMU观察：[B 站合集](https://space.bilibili.com/687228362/channel/collectiondetail?sid=1003432)

* **投稿地址**
  * [Gitee 投稿页面](https://gitee.com/tinylab/tinylab.org/issues)

<hr>

<section id="home">
  {% assign articles = site.posts %}
  {% assign condition = 'group' %}
  {% assign value = 'news' %}
  {% include widgets/articles %}
</section>
