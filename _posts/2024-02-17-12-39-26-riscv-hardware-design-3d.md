---
layout: post
author: '谭源'
title: 'RISV-V 硬件产品开发 - 外壳设计'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-hardware-design-3d/
description: 'RISV-V 硬件产品开发 - 外壳设计'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces toc urls pangu]
> Author:    谭源 <tanyuan98@outlook.com>
> Date:      2022/11/04
> Revisor:   徐宇奇 <xuyuqiabcd@outlook.com>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V 硬件产品开发实录][013]
> Sponsor:   PLCT Lab, ISCAS


## 简介

在泰晓社区 [2022 年的开源之夏][014] 活动中，有一个“[从 0 开始设计和制作一款 RISC-V 开源硬件产品][013]”项目。

在这个项目中，需要零基础的学习 3D 设计，为 PCB 做一个外壳，本文为该过程的详细总结。

本文首先介绍了 3D 外壳设计的软件准备工作，然后详细介绍了 3D 外壳设计的完整过程，之后导出 STL 文件完成 3D 外壳打印，最后也展示了各种设计效果图。

## 3D 外壳设计准备

### 软件准备

本次设计使用 Fusion 360。Fusion 360 功能简单直观，方便入门。此外，Autodesk 为学生提供免费的教育版访问权限，可以在 [此处][003] 申请。

在设计完成之后，使用 [三维猴][010] 来打印出我们的外壳。

### 导入 PCB 3D 模型

在进入外壳设计之前，我们需要确保 PCB 定稿。我们需要在 PCB 的 3D 模型的基础上设计外壳。

咱们这个项目是通过嘉立创 EDA 来设计 PCB 的，需要先通过嘉立创 EDA 中打开 PCB，并点击导出 STEP 类型的 PCB + 元件模型的 3D 文件。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221021160118140.png" alt="嘉立创 EDA 截图 1" style="zoom:33%;" />

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221021160217444.png" alt="嘉立创 EDA 截图 2" style="zoom: 50%;" />

之后导入至 funsion 库中。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022191408462.png" alt="Fusion 360 上传界面" style="zoom: 25%;" />

## 3D 外壳设计过程

接下来是本文主体部分，详细地介绍如何通过 Fusion 设计 3D 外壳。

### 创建草图

草图是 3D 设计中创建新的形状的基础。基于定义好的草图，我们可以拉伸出各种形状。

我们在这里需要依据 PCB 模型的底面大小，创建出外壳的下底面草图。

选中 3D 的 PCB 模型，创建一个草图，以该草图为基准构建外壳。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022192212234.png" alt="Fusion 360 创建草图" style="zoom:33%;" />

进入草图编辑模式后，可以看到工具栏中有许多工具可以画出新的形状来编辑草图。

我们可以在绘制草图时候，可以绘制一些辅助图形来定位。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221102151218211.png" alt="Fusion 360 草图工具" style="zoom: 50%;" />

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022192318903.png" alt="设计 1" style="zoom: 25%;" />

在该基础上画一个矩形，边与 PCB 之间预留 1 - 3 mm，因为 PCB 加工和分板会有误差，3D 结构受温度影响也会有形变。并删除除了用于固定的孔外的所有孔。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022195106000.png" alt="设计 2" style="zoom:25%;" />

得到如下草图：

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022201305778.png" alt="设计 3" style="zoom:33%;" />

### 创建实体

创建完草图后，我们可以从草图拉伸出实体。

拉伸平面，取消选中孔。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022202559949.png" alt="设计 4" style="zoom: 25%;" />

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022202700558.png" alt="设计 5" style="zoom:25%;" />

对上表面进行外侧抽壳，这样可以留下边缘，空出内部的空间。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022202835002.png" alt="设计 6" style="zoom:25%;" />

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022202900576.png" alt="设计 7" style="zoom:25%;" />

然后我们需要三个支柱来支撑 PCB，存放螺丝。这一步骤看起来比较复杂，可以参考 [这个视频][005]。

对草图进行拉伸，这次保留孔。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022203428362.png" alt="设计 8" style="zoom: 25%;" />

再对新拉伸出的立方体进行向内抽壳。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022203801101.png" alt="设计 9" style="zoom:25%;" />

降低四周多余的边，调整支柱的高度。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022204208048.png" alt="设计 10" style="zoom:25%;" />

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022204342578.png" alt="设计 11" style="zoom: 33%;" />

打孔，增加螺纹。

注意：螺纹需要实体化，否则最后由 Fusion 360 导出的模型是没有螺纹的。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022210157418.png" alt="设计 12" style="zoom: 25%;" />

把刚刚创建的两个实体转换为零部件，并合并。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022212029506.png" alt="设计 13" style="zoom: 33%;" />

使用装配中的联接，对齐两个外壳和 PCB 的孔，两个模型会自动连接在一起。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022212831284.png" alt="设计 14" style="zoom:33%;" />

用同样的合并办法，封住盒子上方。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022215349922.png" alt="设计 15" style="zoom: 25%;" />

因为 PCB 有两个突出的面，所以只能从中间切开。

在中心处创建一个面片，使用面片作为切割工具切开上下外壳。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022220159506.png" alt="设计 16" style="zoom: 25%;" />

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022220533521.png" alt="设计 17" style="zoom:25%;" />

### 为接口预留孔

现在只是做了一个方正的盒子，我们还需要为各种接口留出孔来。

可以使用草图的投影功能准确的找到预留孔的位置和大小。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221102152253173.png" alt="设计 18" style="zoom:33%;" />

可以得到如下的结果。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022222958010.png" alt="设计 19" style="zoom:33%;" />

这里同样要留出冗余量。需要注意的是这里的接口无法体现出线材外部包裹的大小，冗余量很难确定，需要和 PCB 设计人员沟通 PCB 的组装要求，或者由 PCB 设计人员自行确定。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022223306977.png" alt="设计 20" style="zoom:25%;" />

我们由此画出了接口大小的草图。草图不仅可以新建形状，也可以通过剪切来调整现有的形状。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221022235110469.png" alt="设计 21" style="zoom:33%;" />

如上图中，我们使用这个圆对现有的上下外壳进行剪切，这样就得到了圆孔。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221023100439256.png" alt="设计 22" style="zoom:33%;" />

### 上下外壳的固定

现在上下外壳都做好了，需要把上下外壳固定起来。

拼接固定的方式有：

1. 螺丝固定，底窄外宽，成倒凹型嵌套
2. 卡扣式，倒凹型，卡扣在底部四周分布，配合超声波焊接组装
3. 滑轨式，凹型
4. 对接处呈 L 型组装，一般使用机械冲模的方式生产。
5. U 型链接，适合对密闭性有要求的

本项目选择使用螺丝固定的方式，设计较为简单。使用螺丝固定可以加上 L 扣辅助定位，避免装配过程中出现偏差，打坏螺丝或者 PCB。

设计过程中还需要考虑到防呆、应力、公差、材料的参数和使用寿命问题。脆弱的地方需要加强力筋，可以使用设计软件中的应力计算功能选择合适的受力点位，调整螺丝位置。

我们计划在边框两边打三个螺丝。

螺丝孔的具体位置就直接选取了中点。中点可以使用辅助线的方式画出草图。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221023100324573.png" alt="辅助线" style="zoom: 50%;" />

螺丝，即紧固件，有很多种类别，可以根据各类别的优缺点进行选择。参考资料有：

1. [不同头型螺丝作用不同-法士威教您如何正确选择 - 知乎（zhihu.com）][012]

2. [螺丝的平头、沉头、盘头，有何区别呢？(luosijie.com)][001]

螺丝孔使用沉头孔或者倒角孔，以免组装完成后螺丝突出。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221102153634720.png" alt="Fusion 360 孔 面板" style="zoom: 33%;" />

需要先 [查询][008] 对应的螺丝是否有货，再打孔。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221102153449776.png" style="zoom:33%;" />

在这次设计中，我们使用了 [这款][009] 螺丝。

### 修订与加固

之前的设计，PCB 仅由三个支柱支撑，不太稳固。

我们可以创建一些同高度的实体来辅助支撑 PCB。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221102154334498.png" style="zoom: 50%;" />

同样也是先画出草图，再拉伸出实体。

画草图的时候需要注意 PCB 背面是否有元器件，并留出间隙方便散热。

## 3D 外壳打印

### 导出 STL 文件

我们使用 [三维猴][010] 来打印出我们的外壳。

参考三维猴的 [技术要求][011]，我们需要导出规定的格式。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/sanweihou-spec.png" alt="三维猴技术要求" style="zoom: 67%;" />

三维猴规定了误差和公差，使用的例子是 SOLIDWORKS 2021。我们可以使用 Fusion 360 完成同样的操作。

选择要导出的零部件，点击另存为网格。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221102155537466.png" alt="Fusion 导出 STL" style="zoom:33%;" />

参考 [资料][002] 得知，曲向偏差对应的是 SOLIDWORKS 2021 中的误差，法向偏差对应的是公差。

由此导出了需要的 STL 文件。

### 3D 打印的材料及选择

3D 打印最常见的两种方法是热熔法和光固化法。

在这次验证性的生产中，我们选用 `LEDO 6060-光敏树脂（进口）` 材料，因为该材料相比同类型材料热变形温度更高，更耐热。不同的材料在参数上会有区别，可以在制造商网站上查询。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221103213132666.png" alt="LEDO 6060-光敏树脂（进口）详细参数" style="zoom: 33%;" />

3D 打印后还可能会进行打磨表面等操作。

量产时如果选用塑料外壳，高温下可能产生形变，需要提前留出冗余量。

到这里，就可以提交并试生产了！

## 3D 外壳设计效果图

### 外壳最终效果图

最后设计出的 3D 外壳效果如图：

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221103211422923.png" alt="最终效果图" style="zoom:50%;" />

### 爆炸图、尺寸图和渲染图

这些额外的步骤可以直观的展示出我们的设计的细节，方便生产和装配。

在 Fusion 360 中，可以通过更改工作空间来完成这些图。

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/image-20221103212702841.png" alt="Fusion 工作空间" style="zoom:33%;" />

- 爆炸图：

![爆炸图](/wp-content/uploads/2022/03/riscv-linux/https://tinylab.org/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/tinylab-d1s-a0-0.jpg)

- 外壳上 尺寸图：

![外壳上 尺寸图](/wp-content/uploads/2022/03/riscv-linux/https://tinylab.org/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/tinylab-d1s-a0-1.jpg)

- 外壳下 尺寸图：

![外壳下 尺寸图](/wp-content/uploads/2022/03/riscv-linux/https://tinylab.org/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/tinylab-d1s-a0-2.jpg)

- 渲染图：

<img src="/wp-content/uploads/2022/03/riscv-linux/images/riscv-hardware-design-3d/tinylab-d1s-rendering.png" alt="渲染图" style="zoom:50%;" />

## 总结

这次实践中，PCB 的设计迟迟未定稿，导致外壳设计被阻塞了很久，于是先自己随便画了一个模型练手，熟悉 Fusion 360 的功能。

3D 设计是我未曾接触的领域，需要投入很多时间来熟悉这一领域的常用方法和开发流程，我最开始连旋转视角都不会，到最后终于能较为熟练的操作。其实和其他领域一样，3D 设计的大部分的需求都有其特定的套路解决办法，用着用着就熟练了。最常用的就是草图、拉伸、抽壳这几种工具，通过他们对不同形状进行组合剪切，就能设计出目标的形状。

在这过程中，也遇到了 Fusion 360 在性能上的一些问题。Fusion 360 是一款基于远程服务的三维建模平台，性能注定比平台原生的软件差。Fuison 360 在 Windows 平台上的高 DPI 支持仍然存在问题。在以后的实践中可以考虑尝试其他设计软件。此外，N 卡用户可以试试把驱动换成专为设计打造的 Studio 版本，理论上会有性能的提升。

## 参考资料

- [Fusion 360 - 从 2D PCB 开始创建外壳_哔哩哔哩_bilibili][004]
- [接近完美的树莓派外壳 - 玩转 3D 打印机之 Fusion 360 - 孤独的二进制出品_哔哩哔哩_bilibili][007]
- [摩擦力——盒子和盖子的合体姿势之一_哔哩哔哩_bilibili][006]

[001]: http://www.luosijie.com/toubuqufen.html
[002]: https://markforged.com/resources/blog/how-to-create-high-quality-stl-files-for-3d-prints
[003]: https://www.autodesk.com.cn/education/edu-software/overview?sorting=featured&filters=individual
[004]: https://www.bilibili.com/video/BV1DE411j7vK/
[005]: https://www.bilibili.com/video/BV1DE411j7vK?t=593.9
[006]: https://www.bilibili.com/video/BV1T54y1x7Du/
[007]: https://www.bilibili.com/video/BV1va411J7me/
[008]: https://www.jlcfa.com/product/E/E02
[009]: https://www.jlcfa.com/product/E/E02/EDLW
[010]: https://www.sanweihou.com/
[011]: https://www.sanweihou.com/technicalColumnsDetails/7ba10b20e3e941689aae4c703b5fd5b5
[012]: https://zhuanlan.zhihu.com/p/73664388
[013]: https://gitee.com/tinylab/cloud-lab/issues/I56CKU
[014]: https://tinylab.org/summer2022
