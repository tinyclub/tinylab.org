---
layout: post
author: 'Zhizhou Tian'
title: "一个gdb调试multi thread的小技巧"
draft: false
# tagline: " 子标题，如果存在的话 "
# album: " 所属文章系列/专辑，如果有的话"
# group: " 默认为 original，也可选 translation, news, resume or jobs, 详见 _data/groups.yml"
license: "cc-by-sa-4.0"
permalink: /the-first-post-slug/
description: " 文章摘要 "
plugin: mermaid
category:
  - category1
  - category2
tags:
  - tag1
  - tag2
---

> By Your Nick Name of [TinyLab.org][1]
> May 01, 2019
##### GDB调试多线程程序
###### 基本步骤和说明
gdb调试multi thread时会有些麻烦，因为没法将全部线程都停止下来，因此break会并不如想象的停止在指定的点上。
而gdb手册里提到了一种小技巧，那就是在想要停止的地方添加如下代码：
```
static volatile int hold = 1;
while (hold) ;
```
这样，当程序运行到while位置的时候就会循环在那里，等待你的调试：
1. `info threads`命令，查看哪个线程正在执行你关心的path
2. `thread xx`命令切换到那个线程
3. `set hold=0`设置hold为0，使程序继续运行。

然而multi thread的麻烦之处就在于它们会发生进程间通信。一旦数据流发送往另外一个thread了，那么对当前thread的跟踪也就没有了意义。因此此时需要做的是，删除之前的while代码，添加到最新跟踪到的thread这里。重复上述步骤。通过这种方式，一些很复杂的多线程程序也可以很清晰的被调试。

本文中以libvirt的分析为例，libvirt的基本操作和大概结构是这样的：
- libvirt组件有一个shell，被称为virsh，提供类似shell的界面，可以输入start、shutdown等命令操作虚拟机
- libvirt有一个守护进程，libvirtd，其对virsh的命令做出响应
    - 以non-root执行`virsh start`时，将以`qemu://session`的方式运行。libvirtd将启动一个non-root的子进程来与virsh进行socket通信
    - 以root执行`virsh start`时，将以`qemu://system`方式运行，libvirtd直接与virsh进行socket通信
- 无论是上述哪种方式，都会创建多个（一般16个）线程，该线程的的作用是将socket传递过来的各个命令和配置进行解析，最终形成一个cmd。
- 子线程会将cmd通过pipe传递给libvirtd主线程，由主线程执行cmd

但如果我们想弄清楚virsh启动qemu的全过程的细节，即在virsh里敲入start xxx_domain，到exec qemu bin，这中间究竟发生了什么细节呢？这就必须要gdb调试了。可以想象，这过程中必定有大量的进程间通信（socket、pipe），这时就出现了文章开头说明的问题：当前thread将数据流发给了另外的thread，而另外的thread却没法跟踪并停止。

###### 例子说明
1. 我们通过log大概知道了qemuProcessStart是启动的必经之路，因此在这个函数里添加while代码：
```
int
qemuProcessStart(virConnectPtr conn, unsigned int flags)
{
...
    static volatile int hold = 1;
    while (hold) ;
}
```
2. 重新编译、安装、重启libvirtd
```
make && make install
service libvirtd restart
```
3. 跟踪libvirtd
```
# ps -ef | grep libvirtd
root     16529     1  0 16:34 ?        00:00:00 /usr/local/sbin/libvirtd --listen

# gdb  /usr/local/sbin/libvirtd 16529
```

4. 在其他的console里启动虚拟机
`virsh start xxx`

5. 按下Ctrl+c停止gdb，查看所有threads：
```
(gdb) info threads
  Id   Target Id         Frame
  15   Thread 0x7f915bccd700 (LWP 16531) "libvirtd" 0x00007f9156ba3296 in qemuProcessStart (conn=conn@entry=0x7f914c1056e0, flags=flags@entry=1)
...
* 1    Thread 0x7f916325d840 (LWP 16529) "libvirtd" 0x00007f9160c0ca4d in poll () from /lib64/libc.so.6
(gdb)
```

6. 切换到thread 15，set hold=0
```
(gdb) thread 17
[Switching to thread 17 (Thread 0x7fb9ac921700 (LWP 27260))]
#0  qemuProcessStart (conn=conn@entry=0x7fb97c000aa0, driver=driver@entry=0x7fb99c00da90, vm=vm@entry=0x7fb99c00b910, updatedCPU=updatedCPU@entry=0x0,
    asyncJob=asyncJob@entry=QEMU_ASYNC_JOB_START, migrateFrom=migrateFrom@entry=0x0, migrateFd=migrateFd@entry=-1, migratePath=migratePath@entry=0x0,
    snapshot=snapshot@entry=0x0, vmop=vmop@entry=VIR_NETDEV_VPORT_PROFILE_OP_CREATE, flags=flags@entry=1) at qemu/qemu_process.c:5878
5878        while (hold)
(gdb) set hold=0
```
接下来就可以继续调试下去了。

通过这种办法，我们就可以得知整个过程了。以下是通过重复上述步骤获取到的知识。

###### 子线程将cmd通过pipe传递给libvirtd主线程
```
#0  virCommandHandshakeNotify (cmd=cmd@entry=0x7f6e4400fa40) at util/vircommand.c:2757
#1  0x00007f6e5e7666cd in qemuProcessLaunch (conn=conn@entry=0x7f6e500009a0, driver=driver@entry=0x7f6e54000e80, vm=vm@entry=0x7f6e54012ec0,
    asyncJob=asyncJob@entry=QEMU_ASYNC_JOB_START, incoming=incoming@entry=0x0, snapshot=snapshot@entry=0x0, vmop=vmop@entry=VIR_NETDEV_VPORT_PROFILE_OP_CREATE,
    flags=flags@entry=17) at qemu/qemu_process.c:5685
```
```
2729 int virCommandHandshakeNotify(virCommandPtr cmd)
...
2749     if (safewrite(cmd->handshakeNotify[1], &c, sizeof(c)) != sizeof(c)) {
2750         virReportSystemError(errno, "%s", _("Unable to notify child process"));
2751         VIR_FORCE_CLOSE(cmd->handshakeNotify[1]);
2752         return -1;
2753     }
...
2756 }
```

###### 主线程执行virExec()的过程
- libvirtd收到cmd后，会执行virExec，
- virExec()将会fork出子进程，子进程将会执行exec(qmeu-system-x86_64)
```
#0  virExec (cmd=cmd@entry=0x7f72bc0026d0) at util/vircommand.c:491
#1  0x00007f72d2219b07 in virCommandRunAsync (cmd=cmd@entry=0x7f72bc0026d0, pid=pid@entry=0x0) at util/vircommand.c:2452
#2  0x00007f72d221a0c4 in virCommandRun (cmd=cmd@entry=0x7f72bc0026d0, exitstatus=exitstatus@entry=0x7f72c29fab64) at util/vircommand.c:2284
#3  0x00007f72d222c166 in virFirewallCheckUpdateLock (lockflag=lockflag@entry=0x7f72d26768a3 <iptablesUseLock>, args=args@entry=0x7f72c29fabc0) at util/virfirewall.c:124
...
#20 0x00007f72d072035d in clone () from /lib64/libc.so.6
```
```
475 virExec(virCommandPtr cmd)
...
749      if (cmd->uid != (uid_t)-1 || cmd->gid != (gid_t)-1 || cmd->capabilities || (cmd->flags & VIR_EXEC_CLEAR_CAPS)) {
753         if (virSetUIDGIDWithCaps(cmd->uid, cmd->gid, groups, ngroups,
...
790     if (cmd->env)
791         execve(binary, cmd->args, cmd->env); <--- 启动了qemu
...
```
