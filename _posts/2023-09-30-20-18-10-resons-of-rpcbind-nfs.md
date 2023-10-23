---
layout: post
author: 'wcwfta'
title: '最新 Manjaro 下，rpcbind 和 nfs 服务启动失败问题分析实战'
draft: false
license: 'cc-by-nc-nd-4.0'
permalink: /reasons-of-rpcbind-nfs/
description: '分析rpcbind和nfs服务启动失败的原因'
category:
  - 开源项目
  - manjaro
tags:
  - Linux
  - manjaro
  - rpcbind
  - nfs
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [tounix spaces toc codeblock codeinline]<br/>
> Author:    kevin <1292311636@qq.com><br/>
> Date:      2023/09/29<br/>
> Revisor:   ForrestNiu <><br/>
> Project:   [Linux Lab](https://gitee.com/tinylab/linux-lab)<br/>
> Proposal:  [在新版 Manjaro 中确保 Linux Lab 正常启动 rpcbind 和 nfs 服务](https://gitee.com/tinylab/cloud-lab/issues/I79Q6V)<br/>


## 背景

rpcbind 工具可以将 RPC 程序号码和通用地址互相转换。要让某主机能向远程主机的服务发起 RPC 调用，则该主机上的 rpcbind 必须处于已运行状态。而 NFS 服务器可以让 PC 将网络中的 NFS 服务器共享的目录挂载到本地端的文件系统中，而在本地端的系统中来看，那个远程主机的目录就好像是自己的一个磁盘分区一样，在使用上相当便利。

## 问题复现

首先，先找到一个较新的 Manjaro 版本，如果没有的话，可以直接从泰晓社区的淘宝店选购一支，在某宝检索 “泰晓 Linux” 即可，注明一下需要 Manjaro 版本。接着，进入到 Linux Lab Shell，然后尝试将 `rpcbind` 启动起来，观察它在启动的时候出现什么问题：

```sh
$ sudo service rpcbind start
* Starting RPC port mapper daemon rpcbind                               [ OK ]
$ sudo service rpcbind start
* Starting RPC port mapper daemon rpcbind                               [ OK ]
$ sudo service --status-all
 [ ? ]  binfmt-support
 [ - ]  dbus
 [ - ]  fail2ban
 [ ? ]  hwclock.sh
 [ ? ]  kmod
 [ - ]  nfs-common
 [ - ]  nfs-kernel-server
 [ - ]  procps
 [ - ]  pulseaudio-enable-autospawn
 [ - ]  rpcbind
 [ - ]  rsync
 [ - ]  rsyslog
 [ + ]  ssh
 [ + ]  start_rpcbind_with_libtirpc.sh
 [ + ]  supervisor
 [ + ]  tftpd-hpa
 [ - ]  udev
 [ - ]  x11-common
```

可以看到虽然终端显示的为 `rpcbind` 服务成功启动，但是通过使用 `top` 指令观察以及使用 `sudo service --status-all` 来观察所有 service 服务的启动情况，可以看到 `rpcbind` 服务并没有成功启动起来。
于是此时需要下载它的 [源码](https://sourceforge.net/projects/rpcbind/) 来继续进行分析。

## 问题调试与分析

在下载好源码后，就需要进入到主函数来进行分析，具体为使用 gdb 来对其进行一步一步的调试。

### gdb 调试

```sh
$ gdb /path/to/rpcbind
Reading symbols from rpcbind...
(gdb) break main
Breakpoint 1 at 0x3f10: file src/rpcbind.c, line 148.
(gdb) run
Starting program: /labs/linux-lab/test/rpcbind-1.2.6/rpcbind
[Thread debugging using libthread_db enabled]
Using host libthread_db library "/lib/x86_64-linux-gnu/libthread_db.so.1".

Breakpoint 1, main (argc=1, argv=0x7fffffffe4a8) at src/rpcbind.c:148
148	{
(gdb)
```

然后此时进行运行，来观察 `rpcbind` 是否是因为未跑完而无法启动的。

```bash
(gdb) n
240		(void) signal(SIGUSR2, SIG_IGN);
(gdb) n
249		if (dofork) {
(gdb) n
250			if (daemon(0, 0))
(gdb) n
[Detaching after fork from child process 511]
[Inferior 1 (process 507) exited normally]
```

此时遇到了 `daemon` 函数，它使得程序在后台运行，所以需要继续使用 gdb 来调试它的子进程，即 511 进程。

```bash
303		syslog(LOG_ERR, "svc_run returned unexpectedly");
(gdb) n
304		rpcbind_abort();
(gdb) n

Thread 2.1 "rpcbind" received signal SIGABRT, Aborted.
__GI_raise (sig=sig@entry=6) at ../sysdeps/unix/sysv/linux/raise.c:50
50	../sysdeps/unix/sysv/linux/raise.c: No such file or directory.
```

可以看到程序成功地运行完毕，所以问题可能并不是 `rpcbind` 未跑完。当时我们在看到这个结果后有点束手无策了，因为似乎程序非常的顺利，但是就是没有成功地将 `rpcbind` 运行起来。所以下一步就希望使用 strace 来跟踪系统调用的情况，来观察此时 `rpcbind` 运行情况与正常情况下的不同。

### strace 跟踪系统调用

使用 strace 来跟踪：

```bash
$ sudo strace -f -o strace-rpcbind-test-1.log rpcbind
```

这时将跟踪的具体情况写入到了 strace-rpcbind-test-1.log 文件中。观察这个文件的信息，并且搜索报错的地方

```bash
4224  mmap(NULL, 8589934592, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (Cannot allocate memory)
4224  brk(0x55d1e70db000)               = 0x55cfe70da000
4224  mmap(NULL, 8590069760, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (Cannot allocate memory)
```

为了更好地找出问题，在 Ubuntu 下也使用了 strace 来跟踪了 `rpcbind` 的系统调用情况，结果对比发现在 Manjaro 下它会出现这样的信息。这代表了在运行时程序需要开辟一块非常大的内存，但是通过返回值为 -1 以及 (Cannot allocate memory) 等信息，此时就可以得到此时他开辟内存是失败的，那么或许这就是为什么无法启动 `rpcbind` 的原因。那么此时就需要再次回到 `rpcbind` 的源码当中，从中寻找到出现这种问题的函数了。

### 寻找问题函数

此时我们使用了一种非常古老的办法 —— 使用 `printf` 函数来判断出现问题的位置。具体为首先在 `main` 函数中多处使用 `printf` 函数来判断出现问题的位置大约是哪两个打印函数之间。然后找到关于这个问题函数结构的描述，然后再次使用 `printf` 函数来判断这个函数具体是哪一行或者哪一段指令出现了需要非常大内存的问题。

```c
static int init_transport(struct netconfig *nconf)
```

最后发现是这个函数会出现这个问题，然后继续观察 strace 信息，并且与该函数的结构进行比对，最终发现这个函数会再使用 `svc_tli_create` 函数 `my_xprt = (SVCXPRT *)svc_tli_create(fd, nconf, &taddr, RPC_MAXDATASIZE, RPC_MAXDATASIZE);`，而它所用到的这个函数就会发生需要开辟一块非常大内存的问题。
在检查到这里后，起初会认为是它传参失误，即可能有参数过大或者过小，从而导致函数计算需要的内存错误，于是乎，当时我们就将它的所有函数进行了打印。并且与Ubuntu 下的信息进行了比对，最终我们发现两个系统下的参数均处于正常的范围间。所以我们此时猜测或许是 `svc_tli_create` 这个函数的内部出问题了。但是这个函数的定义并不在 `rpcbind` 的源码中。所以此时就需要再次寻找 `svc_tli_create` 被定义的地方 —— 即 `libtirpc` 库，它的 [源码](https://sourceforge.net/projects/libtirpc/) 在这里，其 git 仓库为：<https://git.linux-nfs.org/?p=steved/libtirpc.git>。

### libtirpc 库的分析

我们下载了库后对此继续分析。具体的方法仍然是与 strace 信息继续比对。

```
getpeername(5, 0x7fff7f27d180, [128]) = -1 ENOTCONN (Transport endpoint is not connected)
```

```c
if (getpeername(fd, (struct sockaddr *)(void *)&ss, &slen)
                            == 0) {
                                /* accepted socket */
                                xprt = svc_fd_create(fd, sendsz, recvsz);
                        } else
                                xprt = svc_vc_create(fd, sendsz, recvsz);

```

在 `svc_tli_create` 函数中，它需要 `getpeername` 的返回值来判断此时是 socket 是否是 accepted，而通过 strace 信息我们发现返回值为 -1，所以此时需要再次查看 `svc_vc_create` 函数。而在观察这些函数的时候，除了观察 strace 的信息以便与源码相对应外，我们还需要观察源码中关于 `malloc`、`calloc` 等函数的使用。因为或许就是这些函数的错误使用或者参数错误导致的问题。
此时继续寻找 `svc_vc_create` 函数：

```c
        if (getsockname(fd, (struct sockaddr *)(void *)&sslocal, &slen) < 0) {
                warnx("svc_vc_create: could not retrieve local addr");
                goto cleanup_svc_vc_create;
        }

        if (!__rpc_set_netbuf(&xprt->xp_ltaddr, &sslocal, sizeof(sslocal))) {
                warnx("svc_vc_create: no mem for local addr");
                goto cleanup_svc_vc_create;
        }
        xprt_register(xprt);
        return (xprt);
```

在这个函数的最后它需要再次使用到 `getsockname`，那观察 strace：

```c
4224  getsockopt(5, SOL_SOCKET, SO_TYPE, [1], [4]) = 0
4224  getsockname(5, {sa_family=AF_UNIX, sun_path="/var/run/rpcbind.sock"}, [128->24]) = 0
4224  prlimit64(0, RLIMIT_NOFILE, NULL, {rlim_cur=1073741816, rlim_max=1073741816}) = 0
4224  mmap(NULL, 8589934592, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (Cannot allocate memory)
4224  brk(0x55d1e70db000)               = 0x55cfe70da000
4224  mmap(NULL, 8590069760, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (Cannot allocate memory)
```

发现在报错前系统使用过 `getsockname` 函数，所以至少说明它或许成功的运行了 `svc_vc_create` 函数，但是又通过前面的排查知道了，`svc_vc_create` 大概率出现了问题，所以我们此时做了一个大胆的猜测，或许是 `xprt_register(xprt);` 出错，于是再次深究，观察这个函数。

```c
void
xprt_register (xprt)
     SVCXPRT *xprt;
{
  int sock;

  assert (xprt != NULL);

  sock = xprt->xp_fd;

  rwlock_wrlock (&svc_fd_lock);
  if (__svc_xports == NULL)
    {
      __svc_xports = (SVCXPRT **) calloc (_rpc_dtablesize(), sizeof (SVCXPRT *));
      if (__svc_xports == NULL)
            goto unlock;
    }
  if (sock < _rpc_dtablesize())
    {
      int i;
      struct pollfd *new_svc_pollfd;

      __svc_xports[sock] = xprt;
      if (sock < FD_SETSIZE)
        {
          FD_SET (sock, &svc_fdset);
          svc_maxfd = max (svc_maxfd, sock);
        }

      /* Check if we have an empty slot */
      for (i = 0; i < svc_max_pollfd; ++i)
        if (svc_pollfd[i].fd == -1)
          {
            svc_pollfd[i].fd = sock;
            svc_pollfd[i].events = (POLLIN | POLLPRI |
                                    POLLRDNORM | POLLRDBAND);
            goto unlock;
          }

    new_svc_pollfd = (struct pollfd *) realloc (svc_pollfd,
                                                  sizeof (struct pollfd)
                                                  * (svc_max_pollfd + 1));
      if (new_svc_pollfd == NULL) /* Out of memory */
        goto unlock;
      svc_pollfd = new_svc_pollfd;
      ++svc_max_pollfd;

      svc_pollfd[svc_max_pollfd - 1].fd = sock;
      svc_pollfd[svc_max_pollfd - 1].events = (POLLIN | POLLPRI |
                                               POLLRDNORM | POLLRDBAND);
    }
unlock:
  rwlock_unlock (&svc_fd_lock);
}
```

我们发现了它出现了 `realloc` 函数，于是为了验证是否是这个函数出现了错误，我们将它的所有参数进行了打印。
在观察 `svc_max_pollfd` 的时候我们发现了一件有意思的事情：

```bash
4224  write(1, "svc_max_pollfd=0\n", 17) = 17
```

此时 `svc_max_pollfd` 的值为 0，而正常运行的情况下，这个值最终将会 +1，也就是说他并没有执行 `++svc_max_pollfd` 的命令，那么反推来说，或许这个程序没有执行到这里，但是这个 `realloc` 函数是需要这个值的，这个值为 0，那么或许可以说明 `realloc` 是正常的。那么继续往上看，发现还有一处使用了 `calloc` 函数，即：

```c
__svc_xports = (SVCXPRT **) calloc (_rpc_dtablesize(), sizeof (SVCXPRT *));
```

那么好，观察这个参数是否发生了错误，继续观察 `_rpc_dtablesize()`：

```sh
4224  write(1, "_rpc_dtablesize()=1073741816\n", 29) = 29
4224  write(1, "size SVCXPRT*=8\n", 16) = 16
```

可以看到 `_rpc_dtablesize()` 的值非常的大，而与 `sizeof (SVCXPRT *)` 相乘后得到的结果与报错的信息非常的相似。所以我们就推断或许源头就是这个函数，即 `_rpc_dtablesize()`。
而 `_rpc_dtablesize()` 的定义如下：

```c
int _rpc_dtablesize(void)
{
        static int size;
        struct rlimit rl;
        size = sysconf(_SC_OPEN_MAX);
        return (size);
}
```

那么应该就是 `sysconf(_SC_OPEN_MAX)` 的问题了，查阅资料发现是这个获取每个进程运行时打开的最大文件数目，接着查了 Manjaro 系统下的这个值：

```sh
$ ulimit -n
1073741816
```

看起来是对应的，所以我们认为是因为最新版下 Manjaro 的打开的最大文件数目被设置的过大导致的 `rpcbind` 启动失败，进而导致了 `nfs` 启动失败。

## 总结

总的来说，首先通过 service 服务来试着启动 `rpcbind`，接着查找对应的源码来分析是否发生了程序未跑完的情况，然后对照 strace 的信息一步步地深挖问题，从而找到发生问题的函数，即 `_rpc_dtablesize`，而关于其解决办法，我们将在下一篇进行讲解。

## 参考资料

- [QEMU 陈年老 Bug 的分析、修复与 Patch 提交实战 - 吴老师&蒙老师][001]
- [sysconf(3) — Linux manual page][002]
- [rpcbind 源码下载][003]
- [libtirpc 源码下载][004]

[001]: https://www.bilibili.com/video/BV1jX4y1q7Tg/?spm_id_from=333.999.0.0&vd_source=98ca4c9a44f12a8822f1725a4e5bf880
[002]: https://www.man7.org/linux/man-pages/man3/sysconf.3.html
[003]: https://sourceforge.net/projects/rpcbind/
[004]: https://sourceforge.net/projects/libtirpc/

