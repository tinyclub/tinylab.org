---
layout: post
author: 'Zhang Fan'
title: "LWN 203924: V4L2接口介绍"
album: 'LWN 中文翻译'
group: translation
license: "cc-by-sa-4.0"
permalink: /lwn-203924-The-Video4Linux2-API-an-introduction/
description: "LWN 文章翻译，V4L2接口介绍"
category:
  - 设备驱动
  - LWN
tags:
  - Linux
  - V4L2
---

> 原文：[The Video4Linux2 API: an introduction](https://lwn.net/Articles/203924/)
> 原创：By Corbet @ October 11, 2006
> 翻译：By Zhang Fan of [TinyLab.org][1] @ Jan 01, 2018
> 校对：By NULL of [TinyLab.org][1]

> Your editor has recently had the opportunity to write a Linux driver for a camera device - the camera which will be packaged with the One Laptop Per Child system, in particular. This driver works with the internal kernel API designed for such purposes: the Video4Linux2 API. In the process of writing this code, your editor made the shocking discovery that, in fact, this API is not particularly well documented - though the user-space side is, instead, quite well documented indeed. In an attempt to remedy the situation somewhat, LWN will, over the coming months, publish a series of articles describing how to write drivers for the V4L2 interface.

笔者最近有幸有机会为一款儿童便携式电脑的camera模块编写驱动，这个驱动模块将会与Linux的V4L2内核接口进行协同工作。虽然V4L2用户空间的文档相对齐全，但是笔者在编写代码的时候，V4L2内核API文档并不十分齐全这种情况仍然让笔者感到震惊。 为了改变这种状况，LWN将会在后续的几个月内，陆续发表一系列的文档来描述如何基于V4L2内核API编译一个驱动

> V4L2 has a long history - the first gleam came into Bill Dirks's eye back around August of 1998. Development proceeded for years, and the V4L2 API was finally merged into the mainline in November, 2002, when 2.5.46 was released. To this day, however, quite a few Linux drivers do not support the newer API; the conversion process is an ongoing task. Meanwhile, the V4L2 API continues to evolve, with some major changes being made in 2.6.18. Applications which work with V4L2 remain relatively scarce.

V4L2的发展有相当长的一段历史了，大约在1998年八月份，首次由Bill Dirks提出。经过数年的发展,于2002年11月份最终提交到内核2.5.46 release主线代码中。时至今日，仍有少部分的驱动不支持较这个新的API。这种新旧接口的转换是一个不断进行中的过程。而与此同时，V4L2 API继续在演变。最近一些主要的变化是在Linux 2.6.18中。基于V4L2接口的应用依旧比较匮乏.

> V4L2 is designed to support a wide variety of devices, only some of which are truly "video" in nature:

	* The video capture interface grabs video data from a tuner or camera device. For many, video capture will be the primary application for V4L2. Since your editor's experience is strongest in this area, this series will tend to emphasize the capture API, but there is more to V4L2 than that.
	* The video output interface allows applications to drive peripherals which can provide video images - perhaps in the form of a television signal - outside of the computer.
	* A variant of the capture interface can be found in the video overlay interface, whose job is to facilitate the direct display of video data from a capture device. Video data moves directly from the capture device to the display, without passing through the system's CPU.
	* The VBI interfaces provide access to data transmitted during the video blanking interval. There are two of them, the "raw" and "sliced" interfaces, which differ in the amount of processing of the VBI data performed in hardware.
	* The radio interface provides access to audio streams from AM and FM tuner devices.
	* 

V4L2被设计于支持尽可能多的设备，它们当中只有一部分是真正意义上的“video"设备：

	* 视频捕捉接口，这种接口从tuner或者camera中抓取视频数据.大部分情况下，视频捕捉仍然是V4L2的首要应用场景。笔者在这方面经验丰富，因此在本系列文章中会着重描述capture相关的API，但是V4L2的强大远不止于此.
	* 视频输出接口，这种接口允许应用程序输出视频图像-这种应用场景不仅限于计算机-也有可能是电视信号的输出
	* 视频覆盖接口，这种接口是视频捕捉接口的一种变种。这种接口允许直接显示捕捉到的视频数据，视频数据从捕捉设备直接投射到显示设备上，而不需要CPU参与其中
	* VBI接口( Vertical Blanking Interval,场消隐期)，这种接口允许在场消隐期继续传输视频.这种接口又分为"raw"和"sliced"接口，两者的差异在于硬件处理的VBI数据的数量上.
	* 无线电波接口，这种接口允许对访问AM和FM调谐器的音频流进行访问


> Other types of devices are possible. The V4L2 API has some stubs for "codec" and "effect" devices, both of which perform transformations on video data streams. Those areas have not yet been completely specified, however, much less implemented. There are also the "teletext" and "radio data system" interfaces currently implemented in the older V4L1 API; those have not been moved to V4L2 and there do not appear to be any immediate plans to do so.

除了上述的类型，V4L2也可能应用在其他类型的设备上.例如V4L2就为那种在视频流上执行转换的设备预留了“codec”&“effect”接口.当然，这些接口还未完全开发完成，也鲜有实际应用。除此之外，V4L1中的"teletext" 和 "radio data system"接口还没有移植到V4L2框架中，而这项工作目前看来并不显得那么紧急。

> Video devices differ from many others in the vast number of ways in which they can be configured. As a result, much of a V4L2 driver implements code which enables applications to discover a given device's capabilities and to configure that device to operate in the desired manner. The V4L2 API defines several dozen callbacks for the configuration of parameters like tuner frequencies, windowing and cropping, frame rates, video compression, image parameters (brightness, contrast, ...), video standards, video formats, etc. Much of this series will be devoted to looking at how this configuration process happens.

与其他类型设备不同，视频设备可以通过很多种途径对其进行配置。很多V4L2的驱动代码实现使得应用层能够以一种相对理想的方式去获取视频设备的能力或者进行配置。V4L2定义了一些列回调函数用于配置参数例如tunrer频率，帧率，视频格式，视频标准等等.本系列的文章将会着重解析这些配置过程是如何运作的.

> Then, there is the small task of actually performing I/O at video rates in an efficient manner. The V4L2 API defines three different ways of moving video data between user space and the peripheral, some of which can be on the complex side. Separate articles will look at video I/O and the video-buf layer which has been provided to handle common tasks.

除此之外，还会稍微介绍一下如何在视频频率上进行高效的I/O操作.V4L2定义了三种不同的方式用以用户程序与外围设备之间的视频数据传输，他们当中的一份部分在某些方面可能比较复杂. 将会有单独的文章对视频I/O 与视频缓冲层模块中一些共有的通用功能进行描述.

> Subsequent articles will appear every few weeks, and will be added to the list below:

	* Part 2: registration and open()
	* Part 3: Basic ioctl() handling
	* Part 4: Inputs and Outputs
	* Part 5a: Colors and formats
	* Part 5b: Format negotiation
	* Part 6a: Basic frame I/O
	* Part 6b: Streaming I/O
	* Part 7: Controls

随后将会逐步发布剩余的文章，并添加到下面的列表中：

	* Part 2: registration and open()
	* Part 3: Basic ioctl() handling
	* Part 4: Inputs and Outputs
	* Part 5a: Colors and formats
	* Part 5b: Format negotiation
	* Part 6a: Basic frame I/O
	* Part 6b: Streaming I/O
	* Part 7: Controls

