---
layout: post
author: 'wcwfta'
title: '最新 Manjaro 下，rpcbind 和 nfs 服务启动失败问题的解决方案'
draft: false
license: 'cc-by-nc-nd-4.0'
permalink: /solve-rpcbind-nfs/
description: '分析rpcbind和nfs服务启动失败的解决方案'
category:
  - 开源项目
  - manjaro
tags:
  - Linux
  - manjaro
  - rpcbind
  - nfs
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [spaces toc codeblock codeinline refs pangu autocorrect]
> Author:    kevin <1292311636@qq.com>
> Date:      2023/09/30
> Revisor:   walimis
> Project:   [Linux Lab](https://gitee.com/tinylab/linux-lab)
> Proposal:  [在新版 Manjaro 中确保 Linux Lab 正常启动 rpcbind 和 nfs 服务](https://gitee.com/tinylab/cloud-lab/issues/I79Q6V)


## 前言

第一篇讲到了 `rpcbind` 与 `nfs` 启动失败的具体原因，即在新版的 Manjaro 下，进程能打开的最大文件数被设置得过大（是 1073741816），从而导致在 `rpcbind` 启动的过程中申请了一块非常大的内存且申请失败。而本文就希望解决掉这个问题。

## 直接修改进程能打开的最大文件数

既然是因为进程能打开的最大文件数被设置得过大导致的问题，那么不妨直接将这个数设置得小一点，具体为在 Cloud Lab 的 `tools/docker/run` 中做出以下的修改：

```diff

# For /tmp automount
tmpfs="--tmpfs /tmp:rw,exec"

# For lab name
lab_name="-h $LAB_NAME"
+ # 设置 nofile 的值
+ nofile="--ulimit nofile=1024:524288"
+ ulimit="$core_dump $nofile"
+
info_print "Wait for lab launching ..."

- lab_id=$(eval docker run -d $lab_name $privmode $coredump $tmpfs $seccomp $platform $net $audio $container $portmap $caps $dnss $devs $limits $volumemap $vars $EXTRA_ARGS $IMAGE)
+ lab_id=$(eval docker run -d $lab_name $privmode $ulimits $tmpfs $seccomp $platform $net $audio $container $portmap $caps $dnss $devs $limits $volumemap $vars $EXTRA_ARGS $IMAGE)
```

通过这样的修改再次重启并且启动 Linux Lab 后，就发现使用 `ulimit -n` 指令后值不再是 1073741816，而是我们设定好的值，然后我们再次使用 serivec 来启动 `rpcbind` 并且尝试着启动 `nfs`，最终发现两个服务均可以启动起来。
但是显然，这是一个 “治标不治本” 的问题，此时我们并没有对问题函数进行修改，而是试图修改系统的设定值来规避问题函数的处理。那么接下来我们就要尝试着对问题函数进行一定的修改了。

## 尝试修改 _rpc_dtablesize() 函数

在第一篇的时候，曾分析并定位到了问题函数 `_rpc_dtablesize()`，它来自 [libtirpc](https://sourceforge.net/projects/libtirpc/) 库：

```c
int _rpc_dtablesize(void)
{
        static int size;
        struct rlimit rl;
        size = sysconf(_SC_OPEN_MAX);
        return (size);
}
```

且通过查找资料，发现问题主要是出在了 `sysconf(_SC_OPEN_MAX)` 这个上面。那么我们查找上游仓库来看是否有人提出过相同的问题以及他们是如何解决的。
最终发现，虽然没有人对 `_rpc_dtablesize()` 在 `Manjaro` 下所出现的这种问题做出过处理，但是有人对函数 `__rpc_dtbsize()` 提出过相同的问题，并且做出了相应的修改：

```diff
 if (getrlimit(RLIMIT_NOFILE, &rl) == 0) {
-               return (tbsize = (int)rl.rlim_max);
+               return (tbsize = (int)rl.rlim_cur);
        }
```

可以看到，由于现在一些系统所设定的 `rl.rlim_max` 过大，导致允许打开的文件描述符数量过大，可能会被 OOM 杀死，而 `_rpc_dtablesize()` 与这个类似，所以我们做出了如下的尝试：

```diff
int _rpc_dtablesize(void)
{
        static int size;
-       size = sysconf(_SC_OPEN_MAX);
+       struct rlimit rl;
+       if (size == 0) {
+                if (getrlimit(RLIMIT_NOFILE, &rl) == 0) {
+                size = (int)rl.rlim_cur;
+                }
+                printf("size=%d\n",size);
        }
        return (size);
}
```

且其中加入了一句打印函数（或者直接观察 strace）来观察此时的 size 的值是否是一个较小值。然后我们再次运行 `rpcbind` 来观察信息：

```sh
2263  write(1, "rl.rlim_cur=0\n", 14)   = 14
```

我们可以看到此时的值为 0，所以这个方法并没有行得通。那么除此之外，我们还可以使用一种暴力的方法 —— 即直接将 size 写成一个固定值：

```diff
int _rpc_dtablesize(void)
{
        static int size;
-       size = sysconf(_SC_OPEN_MAX);
+       size = 1024;
        return (size);
}
```

这种办法可以不使用 `sysconf(_SC_OPEN_MAX)` 而直接规定 `calloc` 函数需要开辟多大的空间，但是这种办法的弊端也非常的明显，即它直接规定死所有系统均只能开辟相同大小的空间，不仅缺失了灵活性，而且还极有可能出错，所以这个办法过于激进。

## 规划

由于时间有限，有一些更好的办法可能还未想出来，所以此时我想的就是试图参考之前关于 `__rpc_dtbsize()` 的修改办法。理解一下该如何使用类似于 `rl.rlim_cur` 来解决这个办法。

## 总结

总的来说，首先提出了直接修改 nofile 的解决办法，然后再根据出现问题的函数针对性的提出了一些办法。然后再思考未来该如何更好对其进行一定的改进使其更加完美的贴合系统并且还能正常的启动起 `rpcbind` 与 `nfs`。

## 参考资料

- [QEMU 陈年老 Bug 的分析、修复与 Patch 提交实战 - 吴老师&蒙老师][001]
- [libtirpc 代码仓库][002]


[001]: https://www.bilibili.com/video/BV1jX4y1q7Tg/?spm_id_from=333.999.0.0&vd_source=98ca4c9a44f12a8822f1725a4e5bf880
[002]: http://git.linux-nfs.org/?p=steved/libtirpc.git;a=commit;h=99f943123d2832cdd0f77c989d82cc8cba26e90b

