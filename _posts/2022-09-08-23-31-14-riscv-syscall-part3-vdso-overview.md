---
layout: post
author: 'cc'
title: 'RISC-V Syscall 系列 3：什么是 vDSO？'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-syscall-part3-vdso-overview/
description: 'RISC-V Syscall 系列 3：什么是 vDSO？'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - vDSO
---

> Author:  envestcc <chen1233216@hotmail.com>
> Date:    2022/07/17
> Revisor: Falcon <falcon@tinylab.org>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Environment: [泰晓 Linux 实验盘](https://tinylab.org/linux-lab-disk/)
> Sponsor: PLCT Lab, ISCAS


## 概述

本文阐述了什么是 vDSO 技术，以及该技术解决的问题是什么，解决效果如何，并举例说明用户程序如何使用它。

说明：文中涉及的 Linux 源码是基于 5.17 版本

## 背景

在 Linux 众多的系统调用中，有一部分存在以下特点：
* 系统调用本身很快，主要时间花费在 `trap` 过程
* 无需高特权级别权限

这部分系统调用如果能够直接在用户空间中执行，则能够对性能有较大的改善。`gettimeofday` 就是一个典型的例子，它仅仅只是读取内核中的时间信息，而且对于许多应用程序来说，读取系统时间是必要的同时也是频率很高的行为。

为了改善这部分系统调用的性能，先后出现了 `vsyscall`, `vDSO` 机制来加速系统调用。

### vsyscall

`vsyscall` 或 `virtual system call` 是第一种也是最古老的一种用于加快系统调用的机制，最早在 [Linux 2.5.53][2] 被引入内核。`vsyscall` 的工作原则其实十分简单。Linux 内核在用户空间映射一个包含一些变量及一些系统调用的实现的内存页。因此这些系统调用将在用户空间下执行，而不需要触发 trap 机制进入内核。

但是 `vsyscall` 存在以下问题：
1. vsyscall 映射到内存的固定位置 `ffffffffff600000` 处，有潜在的安全风险
2. vsyscall 内存页不包含符号表等信息，在程序出错时进行 `core dump` 会比较麻烦

为了解决上述问题，从而设计了 vDSO 机制，也就是本文讨论的主题。

## vDSO

vDSO (virtual dynamic shared object) 也是一种系统调用加速机制。vDSO 和 vsyscall 的基本原理类似，都是通过映射到用户空间的代码和数据来模拟系统调用，来达到加速的目的。而它们的主要区别在于：
* vDSO 是一个 ELF 格式的动态库，拥有完整的符号表信息
* 依赖 [ASLR][3] 技术，对 vDSO 的地址进行随机化

### linux-vdso.so.1

通过 `ldd` 命令可以查看程序依赖的共享库信息。
```sh
$ ldd /bin/ls
        linux-vdso.so.1 (0x00007fff8faed000)
        libselinux.so.1 => /lib/riscv64-linux-gnu/libselinux.so.1 (0x00007fff8faaa000)
        libc.so.6 => /lib/riscv64-linux-gnu/libc.so.6 (0x00007fff8f977000)
        /lib/ld-linux-riscv64-lp64d.so.1 (0x00007fff8faef000)
        libpcre2-8.so.0 => /lib/riscv64-linux-gnu/libpcre2-8.so.0 (0x00007fff8f925000)

```
其中 `linux-vdso.so.1` 就是 vDSO 对应的共享库名称，因为其被编译进内核代码中所以没有具体的文件路径。

### functions

因为依赖 vDSO 实现的系统调用需要满足本文背景中提到的两个特点，因此数量并不多，详细情况可以通过 `objdump` 工具查看 vDSO 定义的系统调用列表。内核编译过程中生成 `arch/riscv/kernel/vdso/vdso.so`，之后再链接进内核，因此可以通过 vdso.so 查看支持的系统调用有哪些：

```sh
$ objdump -T /labs/linux-lab/build/riscv64/virt/linux/v5.17/arch/riscv/kernel/vdso/vdso.so

/labs/linux-lab/build/riscv64/virt/linux/v5.17/arch/riscv/kernel/vdso/vdso.so:     file format elf64-little

DYNAMIC SYMBOL TABLE:
00000000000004e8 l    d  .eh_frame      0000000000000000              .eh_frame
0000000000000a64 g    DF .text  000000000000018a  LINUX_4.15  __vdso_gettimeofday
0000000000000bee g    DF .text  000000000000007a  LINUX_4.15  __vdso_clock_getres
0000000000000000 g    DO *ABS*  0000000000000000  LINUX_4.15  LINUX_4.15
0000000000000800 g    DF .text  0000000000000008  LINUX_4.15  __vdso_rt_sigreturn
000000000000080a g    DF .text  000000000000025a  LINUX_4.15  __vdso_clock_gettime
0000000000000c74 g    DF .text  000000000000000a  LINUX_4.15  __vdso_flush_icache
0000000000000c68 g    DF .text  000000000000000a  LINUX_4.15  __vdso_getcpu

```
可以看出 vDSO 中共有 6 个函数，分别对应 6 个系统调用，函数命名规则由统一前缀 `__vdso_` 拼接上系统调用名组成。比如 `__vdso_gettimeofday` 函数对应 `gettimeofday` 系统调用。

在 RISC-V 架构下，目前真正能够起到加速系统调用目的的其实只有时间相关的三个，其他函数的实现只是触发真实的系统调用而已。

## 各处理器架构上对比

在不同处理器架构下，vDSO 的实现存在一些差异，大致包括：
* vDSO 名称：如 i386 上命名为 `linux-gate.so.1`，`ppc/64` 上又命名为 `linux-vdso64.so.1`。
* 函数名前缀：如 x86 上前缀是 `__vdso_`，而 `mips` 上前缀是 `__kernel_`
* 支持的系统调用数量：如 arm 上支持两个，x86 上支持四个。
* 真正能实现加速的系统调用数量：一些架构上 vDSO 中虽然实现了系统调用，但背后还是通过真正的系统调用实现，没有起到加速的效果。

下面列出了部分架构下 vDSO 支持的系统调用，以及对比原生系统调用是否实现了加速的信息：

处理器架构\\系统调用 | rt_sigreturn | flush_icache | getcpu | clock_gettime | gettimeofday | clock_getres
--- | --- | --- | --- | --- | --- | ---
riscv   | n | n | n | s | s | s
arm64   | n |   |   | s | s | s
x86     |   |   | s | s | s | s

表格内容取值说明：
* s：表示支持该系统调用并实现了加速
* n：表示通过真正的系统调用进行支持
* 空白：表示未支持

其他更多详情具体可以参考 [vdso(7) — Linux manual page][4]。


## 与原生系统调用性能对比

vDSO 是为了加速系统调用而设计的机制，那到底效果如何呢？

![vdso performance](/wp-content/uploads/2022/03/riscv-linux/images/riscv_syscall/vdso_syscall_perf.png)
> 图片来自 [LPC_vDSO.pdf][1]

上面这张图中比较了 arm 下 vDSO 和原生系统调用的性能，从图中可以看出，经过 vDSO 加速后系统调用性能提升约 7 倍左右，加速效果还是挺明显的。

## 如何使用

用户程序使用 vDSO 有两种方法：
* 使用 C 标准库
* 使用 dlopen 获取函数地址
* 使用 getauxvel 获取函数地址

### 使用 C 标准库

C 标准库对 vDSO 进行了封装，在使用相关系统调用时会自动跳转到 vDSO 执行。下面的代码就是使用 C 标准库来进行 `gettimeofday` 的调用。

```c
// vdso.c
#include<sys/time.h>
#include <unistd.h>
#include <stdio.h>

int main()
{
  struct timeval tv;
  struct timezone tz;

  gettimeofday(&tv, &tz);
  printf("tv_sec=%d, tv_usec=%d\n", tv.tv_sec, tv.tv_usec);

  return 0;
}
```
用法上看起来和普通系统调用的没有区别，我们可以利用 `strace` 工具查看是否真正触发系统调用。`strace` 会输出程序使用的系统调用，而如果程序使用了 vDSO 则不会有系统调用的调用记录。

```sh
$ gcc vdso.c -o vdso.out
$ strace ./vdso.out 2>&1 | grep gettiemofday
$
```
上面的执行结果可以看出并没有实际触发真正的 `gettimeofday` 系统调用。也就是说 C 标准库封装的 `gettimeofday` 函数是直接在用户态执行，没有执行真正的系统调用。

而下面这段代码是通过原生系统调用的方式获取时间信息。

```c
// syscall.c
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <signal.h>
#include <sys/time.h>

int main()
{
    struct timeval tv;
    struct timezone tz;

    syscall(SYS_gettimeofday, &tv, &tz);
    printf("tv_sec=%d, tv_usec=%d\n", tv.tv_sec, tv.tv_usec);
    return 0;
}
```
通过下面的命令可以看出，使用 `syscall` 方法会触发真正的系统调用。

```sh
$ gcc syscall.c -o syscall.out
$ strace ./syscall.out 2>&1 | grep gettiemofday
gettimeofday({tv_sec=1657201564, tv_usec=553206}, {tz_minuteswest=0, tz_dsttime=0}) = 0
```

### 使用 dlopen 获取函数地址

因为 vDSO 是一个比较标准的共享动态链接库，所以也可以使用 dlopen 打开它，示例代码如下：

```c
#include <dlfcn.h>
#include <unistd.h>
#include <sys/time.h>

void *get_vdso_sym(const char *name)
{
	void *handle;
	void *sym;

	handle = dlopen("linux-vdso.so.1", RTLD_NOW | RTLD_GLOBAL);

	if (handle) {
		(void)dlerror();
		sym = dlsym(handle, name);
		if (dlerror())
			sym = NULL;
	} else {
		sym = NULL;
	}

	return sym;
}

typedef int (gettimeofday_t)(struct timeval * tv, struct timezone * tz);

int main()
{
    gettimeofday_t *my_gettimeofday = (gettimeofday_t*)get_vdso_sym("__vdso_gettimeofday");

    struct timeval tv;
    struct timezone tz;
    my_gettimeofday(&tv, &tz);
    printf("tv_sec=%d, tv_usec=%d\n", tv.tv_sec, tv.tv_usec);

    return 0;
}
```

虽然 `linux-vdso.so.1` 在文件系统上找不到，但是操作系统在启动进程时已经将其作为虚拟共享库加载过，所以再次使用 dlopen 时能够正确找到该共享库，然后再使用 dlsym 找到对应的导出函数即可。


### 使用 getauxvel 获取函数地址

另外，针对 vDSO 操作系统还给用户程序暴露了一些接口。我们可以通过 [getauxval][5] 找到 vDSO 共享库在当前进程用户态内存中的地址，然后根据共享库文件格式找到对应函数的地址进行调用。具体可以参考如下示例代码。

```c++
#include<sys/auxv.h>
#include <stdio.h>
#include <string.h>
#include <elf.h>
#include <sys/time.h>

typedef unsigned char u8;

void* vdso_sym(char* symname) {
    auto vdso_addr = (u8*)getauxval(AT_SYSINFO_EHDR);

    auto elf_header = (Elf64_Ehdr*)vdso_addr;
    auto section_header = (Elf64_Shdr*)(vdso_addr + elf_header->e_shoff);

    char* dynstr = 0;

    for (int i=0; i<elf_header->e_shnum; i++) {
        auto& s = section_header[i];
        auto& ss_ = section_header[elf_header->e_shstrndx];
        auto name = (char*)(vdso_addr + ss_.sh_offset + s.sh_name);
        if (strcmp(name, ".dynstr") == 0) {
            dynstr = (char*)(vdso_addr + s.sh_offset);
            break;
        }
    }

    void *ret = NULL;

    for (int i=0; i<elf_header->e_shnum; i++) {
        auto name = (char*)(vdso_addr + section_header[elf_header->e_shstrndx].sh_offset + section_header[i].sh_name);
        if (strcmp(name, ".dynsym") == 0) {
            for (int si=0; si<(section_header[i].sh_size/section_header[i].sh_entsize); si++) {
                auto name = dynstr + ((Elf64_Sym*)(vdso_addr + section_header[i].sh_offset))[si].st_name;
                if (strcmp(name, symname) == 0) {
                    ret = (vdso_addr + ((Elf64_Sym*)(vdso_addr + section_header[i].sh_offset))[si].st_value);
                    break;
                }
            }
            if (ret) break;
        }
    }
    return ret;
}

typedef int (gettimeofday_t)(struct timeval * tv, struct timezone * tz);

int main()
{
    auto my_gettimeofday = (gettimeofday_t*)vdso_sym("__vdso_gettimeofday");

    struct timeval tv;
    struct timezone tz;
    my_gettimeofday(&tv, &tz);
    printf("tv_sec=%d, tv_usec=%d\n", tv.tv_sec, tv.tv_usec);

    return 0;
}
```

上段代码中的 `vdso_sym` 函数就是返回 vDSO 中指定函数名的地址，通过 `vdso_sym` 方法找到 `__vdso_gettimeofday` 函数获取系统时间。在`vdso_sym` 函数内部，先通过 getauxval 函数获取 vDSO 在当前进程中的内存地址，然后根据 ELF 结构进行解析，从而找到指定函数的地址。

## 总结

本文通过对 vDSO 技术的概念，设计的目的以及目前效果进行阐述，帮助读者从宏观上了解该技术。

下一篇文章会接着本文继续深入探究 vDSO 技术的实现原理。

## 参考资料

- [什麼是 Linux vDSO 與 vsyscall？——發展過程](https://alittleresearcher.blogspot.com/2017/04/linux-vdso-and-vsyscall-history.html)
- [The vDSO on arm64][1]
- [System calls in the Linux kernel. Part 3.](https://github.com/0xAX/linux-insides/blob/master/SysCall/linux-syscall-3.md)
- [vdsotest](https://github.com/nlynch-mentor/vdsotest)


[1]: https://blog.linuxplumbersconf.org/2016/ocw/system/presentations/3711/original/LPC_vDSO.pdf
[2]: https://mirrors.edge.kernel.org/pub/linux/kernel/v2.5/ChangeLog-2.5.53
[3]: https://en.wikipedia.org/wiki/Address_space_layout_randomization
[4]: https://man7.org/linux/man-pages/man7/vdso.7.html
[5]: https://lwn.net/Articles/519085/
