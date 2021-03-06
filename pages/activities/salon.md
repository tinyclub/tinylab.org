---
title: 沙龙
tagline: 由泰晓举办的各类线上线下交流活动
layout: page
album: 泰晓沙龙
permalink: /tinysalon/
description: 由泰晓科技举办的线上、线下沙龙活动，主要围绕 Linux 技术与产品，探讨产品创意、技术热点、行业观察等。
order: 20
---

『泰晓沙龙』历史上为泰晓科技技术社区组织的一档线下交流活动，目前重启后，以线上直播+录播为主，讨论的技术范围主要围绕 Linux 技术与产品。

**直播课堂**免费向所有同学开放，欢迎提前报名，由于会议和课堂的人数有限制，社区贡献者可优先申请，申请地址：[泰晓沙龙-直播课堂](https://www.cctalk.com/m/group/89433087)。也可扫码报名：

![泰晓科技-直播课堂-报名入口](/wp-content/uploads/2021/03/tinylab-salon-video.png)

以下为泰晓沙龙的历史活动简介：

<hr>

泰晓沙龙 致力于打造一个线下交流平台，主要围绕智能手机生态，探讨产品创意、技术热点、行业观察等。

* 活动时间：每个月定期组织。
* 活动地点：环境优美，气氛轻松的场所。
* 活动内容：通过在线交流讨论出1～2个主题，由相关同学准备材料，然后围绕主题展开讨论。
* 活动经费：初期主要是由报名参会的同学 AA 制。
* <b>报名方式</b>：关注 泰晓科技 微博/微信公众号：@泰晓科技，然后私信留言。

## 历届活动

{% for salon in site.data.salons %}

### [{{ salon.title }}]({{ salon.url }})

  * 主题：{{ salon.topic }}
  * 时间：{{ salon.time }}
  * 地点：{{ salon.addr }}
  * 人员：{{ salon.people }}
  * 小结：{{ salon.desc }}

{% endfor %}
