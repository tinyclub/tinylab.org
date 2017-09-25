---
layout: post
author: 'Keven'
title: "嵌入式Linux系统发行版制作神器 Buildroot"
# tagline: "  "
# album: " "
# group: "original"
permalink: /using-buildroot-to-make-embedded-linux-system-release/
category:
  - Linux 系统
  - Buildroot
tags:
  - Buildroot 
  - Embedded Linux
  - Cross GCC
---

> By Keven of [TinyLab.org][1]
> 2017-09-25 21:19:55

Linux 作为目前最主流的操作系统，其已经广泛的影响到我们生活。嵌入式Linux 作为Linux 在嵌入式终端中应用，也随着Linux 的壮大而不断发展。

## 前言
随着万物互联(IOT)以及人工智能的发展，嵌入式Linux 被应用在各个领域，如日常生活中所使用的手机，智能终端等。那么作为Linux 在嵌入式领域的一个应用。我们可能更加关心的是我的硬件怎样以更加低成本的硬件去跑我们的业务。那么更加低成本的硬件就限制了我们传统桌面Linux 系统的使用。所以我们不得不对Linux 进行了二次的移植和裁剪，精简到最小。以达到可以低廉的硬件上运行的效果。 
说到这里，我们发现了嵌入式Linux 的特性，叫基于Linux的移植和裁剪。嵌入式终端一般都是功能单一，不需要像PC那样复杂，所以我们的的移植和裁剪就变得非常有趣。我们将只保留我们想要的那部分内容。介于此。我们下面介绍一位新朋友，它叫 buildroot。

## Buildroot 

官网的开头是这么描述的 - Buildroot is a simple, efficient and easy-to-use tool to generate embedded Linux systems through cross-compilation；
意思是Buildroot 是一个简单的，高效且易用的，通过交叉编译工具定制嵌入式Linux 系统的工具。
其三大特点是：
- 1、Can handle everything - 包含了一切嵌入式系统的组件(交叉工具，根文件系统，内核，bootloader)
- 2、Is very easy - 非常简单，类似于kernel 的编译，支持menuconfig ,xconfig 等组建菜单
- 3、Supports hundreds of packages - 支持100多种主流包(完全满足嵌入式系统的一切要求)

这简直就是嵌入式开发者的福音，在也不需要一个个去移植相关软件包(组建非常吃力还不讨好)，统一了交叉环境，大大的促进了行业发展，最重要的一点是Buildroot 当然是开源的啦，文档丰富，社区很活跃。

社区赞助厂商：[目前社区的赞助有[Google](https://www.google.com), [Mind](),[Free Electrons](http://free-electrons.com/) ]等等，

上面的描述已经明确的告诉我们，Buildroot 其实就一个嵌入式Linux 系统的发行工具。那么下面我们继续看看怎么利用buildroot 做这个事情。

##  使用buildroot 生成最小系统用户态镜像

### 获取buildroot源码包
这里我使用的buildroot 是官网的2016.08-rc1版本(刚才我去看的时候已经变成2017-08了)，足以见得buildroot的活跃程度非常高)。
获取buildroot 源码

	#/home/hole/Linux_hole# wget https://buildroot.org/downloads/buildroot-2016.08-rc1.tar.gz
	#/home/hole/Linux_hole# tar xvf buildroot-2016.08-rc1.tar.gz

### [拷贝上一节生成的交叉工具链到buildroot 目录
	#/home/hole/Linux_hole# cd buildroot-2016.08-rc1
	#/home/hole/Linux_hole/buildroot-2016.08-rc1# cp ../crosstool-ng-soucrce/x86_64-cross/x86_64-bin/  .

### 获取配置文件并且修改
上面我们介绍了buildroot 的目录，明确知道了buildroot 相关目录的说明，由于这里我是跑在x86_64 平台上，所以我使用下面这个config文件
	
	#/home/hole/Linux_hole/buildroot-2016.08-rc1# cp configs/qemu_x86_64_defconfig  .config
这里要稍作修改，因为buildroot 其实已经集成了crosstool-ng，其本身也支持生成工具链，但是由于我们已经生成，所以此处就不需要了，另外buildroot 还集成了内核，但是这个地方我们暂时不编译内核(比较简单)，所以也去掉。既然如此，我们的修改就很明确了：
修改工具链配置选项以及去掉内核部分即可，这里为了不贴的满屏都是，我直接将我改过的config 放出来(链接见附录)，大家可以compare 一下我改过的和qemu_x86_64_defconfig的差异，配置文件里面包含了root用户名的默认密码，我设置为了1;
`BR2_TARGET_GENERIC_ROOT_PASSWD="1"`
	
如果要用我的配置文件：

	#/home/hole/Linux_hole/buildroot-2016.08-rc1# cp ../buildroot_src/config_x86-hole  .config 

### 获取程序源码包
为了方便和节省时间，我已经将上述.config 要用到的源码包都放在了云盘(链接见附录)，当然如果你的网速够快(一定是翻越长城快)，那么你有两个选择：
第一个：直接make  边下载边编译
第二个：make souece 将所用包全部下载
另外一种选择就使用我给你的包：

	#/home/hole/Linux_hole/buildroot-2016.08-rc1# cp -rf ../buildroot_src/dl/* dl/ 

### 得到最终生成的镜像文件
编译生成最终镜像

	#/home/hole/Linux_hole/buildroot-2016.08-rc1# make -j 48
这里的镜像其实就是一个压缩文件

	#/home/hole/Linux_hole/buildroot-2016.08-rc1# ls output/images/
	rootfs.cpio  rootfs.cpio.gz

### 编译一个内核镜像
#### 编译内核镜像
内核的编译不在细述，具体细节请戳[全面解析Linux 内核 3.10.x 系列文章](http://blog.csdn.net/ongoingcre/article/category/5931425)
这里我直接写步骤

	#/home/hole/Linux_hole# wget https://www.kernel.org/pub/linux/kernel/v3.x/linux-3.10.28.tar.gz
	#/home/hole/Linux_hole# tar xvf linux-3.10.28.tar.gz
	#/home/hole/Linux_hole# cd linux-3.10.28
	#/home/hole/Linux_hole/linux-3.10.28# cp arch/x86/configs/x86_64_defconfig .config
	#/home/hole/Linux_hole/linux-3.10.28# make menuconfig
	#/home/hole/Linux_hole/linux-3.10.28# make -j 48
	#/home/hole/Linux_hole/linux-3.10.28# ls arch/x86_64/boot/ -l
	total 0
	lrwxrwxrwx 1 root root 22 Aug 19 07:23 bzImage -> ../../x86/boot/bzImage

到这里，x86_64 的内核镜像已经生成;

### 制作img or vmdk 虚拟机镜像文件
#### 下载专用制作工具 - hole-builds
	
	#/home/hole/Linux_hole/build_img/hole_tools# git clone https://github.com/bjwrkj/hole-tools

此工具包已经被我开源，其核心打包功能摘录于openwrt; 
####[4.2、安装一些依赖软件]()

	#/home/hole/Linux_hole/build_img/hole_tools# apt-get install qemu-img 

如果不想安装，我这里当然也准备好了，链接见附录
然后将其拷贝出来，导入环境变量即可。
	#/home/hole/Linux_hole/build_img/hole_tools# cp -arf hole-tools-bin  /usr/local/  
	#/home/hole/Linux_hole/build_img/hole_tools# export PATH=/usr/local/hole-tools-bin/bin:$PATH
#### 开始制作
将上述步骤生成的rootfs.cpio 以及 bzImage 分别拷贝到具体目录

	#/home/hole/Linux_hole/build_img/hole_tools# cp ../../linux-3.10.28/arch/x86/boot/bzImage  targets/img/x86_64/
	#/home/hole/Linux_hole/build_img/hole_tools# cp ../../buildroot-2016.08-rc1/output/images/rootfs.cpio  targets/rootfs/

然后执行

	#/home/hole/Linux_hole/build_img/hole_tools# make
	#/home/hole/Linux_hole/build_img/hole_tools# ls *.img 
	hole-dist.img

好了，上面看的hole-dist.img 就是我们的虚拟机硬盘文件啦。
如果想要vdi 或者 vmdk 文件，只需要在执行
	#/home/hole/Linux_hole/build_img/hole_tools# make vdi
或者
	#/home/hole/Linux_hole/build_img/hole_tools# make vmdk
	
### 使用virtulbox or qmenu 启动最小系统镜像文件
#### 使用virtualbox 启动虚拟硬盘
- a.新建一个虚拟机
- b.将现有虚拟硬盘添加
- c.启动虚拟机
- d.用户名 root 密码 1

效果图：
![buildroot-show1](/wp-content/uploads/2017/09/buildroot-to-make-embeded-linux-release-show1.png)
![buildroot-show2](/wp-content/uploads/2017/09/buildroot-to-make-embeded-linux-release-show2.png)


## 后记
虽然目前大家都在追逐云服务器，云计算等等，很少会有人去主动的搭建这种环境。但是，对于新手而言，通过此文章你可以了解一个嵌入式系统的组成部分，以及相关内容。对于老手而言，哪怕你上了云， 你上了docker 业务环境也是要记得搭建的； 当前世界上大概有50,60亿嵌入式设备在跑，不管你是IOT，还是VR,AR，机器人等等； 支撑业务的是始终是那千千万万的库。比较讽刺的是，核心库百分之八十是社区出的。
正如我开头标语说的一样，其原文为：
假如你只用一种方式去理解某件事情，那么你并不能真正的理解这件事。这是因为假如有一个步骤发生错误，你将会被自己的思维束缚。一件事对于我们的意义取决于你如何把这件事同其他的事情关联起来 - 出自奇点临近。

----------

> 附录 - 上述安装所用安装包
> 源码包地址：[戳这儿](http://pan.baidu.com/s/1o8Cke74)
密码: **b37a**

如果觉得文章有帮助，也欢迎扫描如下二维码鼓励和支持我们。

[1]: http://tinylab.org
