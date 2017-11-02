---
title: 投稿
tagline: 欢迎投递原创稿件、工作机会、求职简历等
layout: page
group: navigation
highlight: true
permalink: /post/
order: 30
---

泰晓科技 作为一个 Android / Linux 原创交流平台，热烈欢迎大家参与。

而参与的最好方式莫过于创作并分享。我们欢迎各类 Android / Linux 原创、翻译文章，也欢迎发布工作机会，递送求职简历。

为了提高稿件、工作机会和简历的质量，我们也会安排严格的评审。

下面是一般的稿件投递过程。

## 撰写稿件

首先下载文章仓库：

    $ git clone https://github.com/tinyclub/tinylab.org
    $ cd tinylab.org

然后生成文章模板, slug 为链接，title 为标题。

    $ tools/post slug=the-first-post-slug title="第一篇原创文章。。。"

接着，参照模板编辑文章。

    $ vim _posts/*the-first-post-slug*

Markdown 基本用法请参考 [Markdown 语法说明][2] 以及上面创建的文章模板中的说明。

如果希望使用更多样式，可参照 `_posts/` 目录下的其他文章。

如果有附件或者图片资料，请创建目录 `wp-content/uploads/年/月/`，并添加资料进去，然后在文章中通过 Markdown 语法引用。引用图片的方式：

    ![图片简介](/wp-content/uploads/2017/09/xxx.png)

## 本地预览

如果时间允许，请务必提前在本地预览一下效果，确保文档显示优雅美观。这一步可通过 Cloud Lab 完成，大体用法如下。

### 安装 Docker

已经为本站的编辑环境创建了一个 Docker 镜像，使用之前需要先安装 Docker，可参考：

* Linux 和 Mac OSX: [Docker CE](https://store.docker.com/search?type=edition&offering=community)
* Windows: [Docker Toolbox](https://www.docker.com/docker-toolbox)

注意事项：

安装完 docker 后如果想免 `sudo` 使用 linux lab，请务必把用户加入到 docker 用户组并重启系统。

    $ sudo usermod -aG docker $USER

由于 docker 镜像文件比较大，有 1G 左右，下载时请耐心等待。另外，为了提高下载速度，建议通过配置 docker 更换镜像库为本地区的，更换完记得重启 docker 服务。

    $ grep registry-mirror /etc/default/docker
    DOCKER_OPTS="$DOCKER_OPTS --registry-mirror=https://docker.mirrors.ustc.edu.cn"
    $ service docker restart

如果 docker 默认的网络环境跟本地的局域网环境地址冲突，请通过如下方式更新 docker 网络环境，并重启 docker 服务。

    $ grep bip /etc/default/docker
    DOCKER_OPTS="$DOCKER_OPTS --bip=10.66.0.10/16"
    $ service docker restart

如果上述改法不生效，请在类似 `/lib/systemd/system/docker.service` 这样的文件中修改后再重启 docker 服务。

    $ grep dockerd /lib/systemd/system/docker.service
    ExecStart=/usr/bin/dockerd -H fd:// --bip=10.66.0.10/16 --registry-mirror=https://docker.mirrors.ustc.edu.cn
    $ service docker restart

### 使用 tinylab.org 编辑环境

安装完 Docker 后，即可下载编辑环境，选择之前先选定一个工作目录。如果使用的是 Docker Toolbox 安装的 `default` 系统，该系统默认的工作目录为 `/root`，它仅仅挂载在内存中，因此在关闭系统后所有数据会丢失，所以需要换一处上面提到的 `/mnt/sda1`，它是外挂的一个磁盘镜像，关闭系统后数据会持续保存。

   $ cd /mnt/sda1

在 Linux 或者 Mac 系统，可以随便在 `~/Downloads` 或者 `~/Documents` 下找一处工作目录，然后进入，比如：

   $ cd ~/Documents

之后即可下载并运行：

    $ git clone https://github.com/tinyclub/cloud-lab.git
    $ cd cloud-lab/ && tools/docker/choose tinylab.org
    $ tools/docker/run tinylab.org

运行完以后会通过浏览器自动登陆一个桌面，点击里头的 `Local Page` 即可查看预览效果。

随后把新撰写的文章内容拷贝到 `labs/tinylab.org/_posts` 后，稍等几分钟即可在在预览页面查看，如果发现有问题，请提前进行调整，确保文章质量。

## 递送稿件

撰写完后即可通过 Github 发送 Pull Request 进行投稿。也可直接把稿件和相关图片发送到 wuzhangjin [AT] gmail [DOT] com。

这一步要求事先做如下准备：

  * 在 Github [Fork][3] 上述 [文章仓库][1]
  * 您在本地修改后先提交到刚 Fork 的仓库
  * 然后再进入自己仓库，选择合并到 [文章仓库][1] 的 master 分支

提交 Pull Request 后，我们会尽快安排人员评审，评审通过后即可发布到网站。

## 文章模板说明

通过 `rake post` 或者 `tools/post` 可以创建一份文章模板，这里对该模板做稍许说明，更多内容请阅读模板本身。

该模板包括两大部分，第一部分是用两个 `---` 括起来的文件头，剩下的部分为文章正文。

* 文件头包含文章的基本信息，`jekyll` 模板系统用它来构建文章页面
* 文件正文即普通的 Markdown 文件主体，基本遵循 Markdown 规范

模板基本样式如下：

    ---
    layout: post
    author: "Your Name"
    title: "new post"
    permalink: /new-post-slug/
    description: "summary"
    category:
      - category1
      - category2
    tags:
      - tag1
      - tag2
    ---


    > By YOUR NICK NAME of TinyLab.org
    > 2015-09-21



    文章正文




模板文件头中的关键字大部分为 `jekyll` 默认支持，我们加入了少许关键字，这里一并说明：

| 关键字 | 说明              |  备注     |
|:------:|-------------------|---------------|
|layout  | 文章均为 post     | **必须**
|author  | 作者名，同 `_data/people.yml` | **必须**
|title   | 标题名，支持中、英文      | **必须**
|permalink| 英文短链接，不能包含中文 | **必须**
|tagline  | 子标题/副标题            | 可选
|description| 文章摘要              | 可选
|album      | 所属文章系列/专题     | 可选
|group      | 默认 original，可选 translation, news, resume or jobs, 详见 `_data/groups.yml` | 可默认
|category   | 分类，每行1个，至少1个，必须在`_data/categories.yml` | **必须**
|tags       | 标签，每行1个，至少1个，至多5个 | **必须**

## 完善作者信息

为了方便读者和潜在合作伙伴联系到您，请参考如下表格在 `_data/people.yml` 中编辑作者信息并发送 Pull Request 入库。

更多信息说明如下，以网站帐号 `admin` 为例，即 `_data/people.yml` 中左侧的 `admin:`：

|属性    |   属性值      |  说明                    |
|:------:|:-------------:|--------------------------|
|name    | 泰晓科技      | 对应中文名或者全名
|nickname| tinylab       | 网络昵称或者英文名
|archive | true          | 展示作者所有文章
|article | true          | 生成当前文章二维码，手机可扫码阅读
|site    | tinylab.org   | 作者个人站点地址，请不要写 `http://` 头
|email   | xxx@gmail.com | 作者邮箱
|github  | tinyclub             | 作者 github 帐号
|weibo   | tinylaborg           | 新浪微博帐号，务必事先配好短域名，否则须用 `u/xxx`
|weibo-qrcode  | false          | 新浪微博二维码，本站可自动生成，请保留为false
|wechat        | tinylab-org    | 微信或者公众号
|wechat-qrcode | true           | 暂时无法自动生成，需要显示二维码必须先生成一份传到 `images/wechat`，并以 `wechat` 帐号命名，该项为 true
|ali-pay       | ali-pay-admin-9.68 | 如希望获得支付宝打赏，请命名二维码图片为：ali-pay-*author*-*money*
|wechat-pay    | wechat-pay-admin-9.68 | 如希望获得微信打赏，请命名二维码图片为：wechat-pay-*author*-*money*
|sponsor       | wechat-pay            | 选择一种打赏方式（仅用于作者信息栏）
|sponsor-qrcode| true                  | 图片请存到 `images/sponsor` 并设该项为 true
|info          | ...                   | 建议介绍专业、兴趣、特长等，如较多，请用 `;` 分割，以便自动分段展示
|--------------|-----------------------|----------------|

 [1]: https://github.com/tinyclub/tinylab.org.git
 [2]: http://wowubuntu.com/markdown/
 [3]: https://github.com/tinyclub/tinylab.org#fork-destination-box
