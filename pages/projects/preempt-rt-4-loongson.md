---
title: '龙芯/MIPS 实时抢占 Linux'
tagline: 为龙芯加入实时抢占，龙芯 2F 最大延迟小到 80us
author: Wu Zhangjin
layout: page
permalink: /preempt-rt-4-loongson/
description: 为龙芯/MIPS 版 Linux 添加实时抢占支持。
update: 2015-10-1
categories:
  - 开源项目
  - MIPS
  - 实时抢占
tags:
  - 实时性
  - 龙芯
  - Linux
---

因该项目的原主页已无法访问，这里将作为龙芯/MIPS 版实时抢占 Linux 的临时主页。

## 仓库

  * <https://github.com/tinyclub/preempt-rt-linux>

## 文章

  * [嵌入式系统采用 Linux 系统，怎样保证实时性？][3]

## Wiki
    
  * [Linux Real Time Wiki][4]
  * [eLinux.org Real Time Wiki][5]

### 测试结果演示

![Loongson 2F Real Time Latency][7]

**原图地址**：[Latency plot of Loongson Real Time Linux system in OSADL][8]


 [1]: http://lwn.net/images/conf/rtlws11/papers/proc/p14.pdf
 [2]: /wp-content/uploads/2015/11/linux-preempt-rt-research-and-practice.pdf
 [3]: /how-to-make-a-linux-system-real-time/
 [4]: http://rt.wiki.kernel.org/index.php/Main_Page
 [5]: http://www.elinux.org/Real_Time
 [6]: http://www.osadl.org/Downloads.downloads.0.html
 [7]: /wp-content/uploads/2015/07/loongson-2f-preempt-rt-latency.gif
 [8]: https://www.osadl.org/Latency-plot-of-system-in-rack-2-slot.qa-latencyplot-r2s4.0.html?latencies=&showno=&slider=159
