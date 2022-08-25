---
layout: post
author: ' Chen Chen '
title: 'RISC-V Syscall 系列1：什么是 Syscall ?'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-syscall-part1-usage/
description: 'RISC-V Syscall 系列1：什么是 Syscall ?'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - Syscall
---

> Author:  envestcc <chen1233216@hotmail.com>
> Date:    2022/06/14
> Revisor: walimis、Falcon 
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor: PLCT Lab, ISCAS



## 什么是 Syscall ?

![Linux_API](/wp-content/uploads/2022/03/riscv-linux/images/riscv_syscall/linux_api.svg)
（图片源自 wikipedia）

Syscall 又称为系统调用，它是操作系统内核给用户态程序提供的一组 API，可以用来访问系统资源和内核提供的服务。比如用户态程序申请内存、读写文件等都需要通过 Syscall 完成。

通过 Linux 源码里可以看到(include/linux/syscalls.h)，大约有 400 多个 Syscall。其中一部分是兼容 [POSIX](https://en.wikipedia.org/wiki/POSIX) 标准，另一些是 Linux 特有的。


## 如何调用 Syscall ?

应用程序想要调用 Syscall 有两种方式，分别是直接调用和使用 C 标准库。

### 直接调用

下面我们通过一段汇编代码来看看如何直接调用 Syscall。

```asm
.data

msg:
    .ascii "Hello, world!\n"

.text
    .global _start

_start:
    li a7, 64    # linux write syscall
    li a0, 1     # stdout
    la a1, msg   # address of string
    li a2, 14    # length of string
    ecall        # call linux syscall

    li a7, 93    # linux exit syscall
    li a0, 0     # return value
    ecall        # call linux syscall
```

上面的代码的功能是通过系统调用往标准输出上打印一串字符。

```
$ cat test.S
.data

msg:
    .ascii "Hello, world!\n"

.text
    .global _start

_start:
    li a7, 64
    li a0, 1
    la a1, msg
    li a2, 14
    ecall

    li a7, 93
    li a0, 0
    ecall
$ riscv64-linux-gnu-gcc -c test.S
$ riscv64-linux-gnu-ld -o test test.o
$ qemu-riscv64 test
Hello, world!


```

RISC-V 中通过 `ecall` 指令进行 Syscall 的调用。 `ecall` 指令会将 CPU 从用户态转换到内核态，并跳转到 Syscall 的入口处。通过 a7 寄存器来标识是哪个 Syscall。至于调用 Syscall 要传递的参数则可以依次使用 a0-a5 这 6 个寄存器来存储。

> ecall 指令之前叫 scall，包括现在 Linux 源码里都用的是 scall，后来改为了 ecall。原因是该指令不仅可以用来进行系统调用，还可以提供更通用化的功能。

`write` 的系统调用号为 64，所以上述代码里将 64 存储到 a7 中。`write` 系统调用的参数有 3 个，第一个是文件描述符，第二个是要打印的字符串地址，第三个是字符串的长度，上述代码中将这三个参数分别存入到 a0、a1、a2 这三个寄存器中。

系统调用号列表可以在 Linux 源码中进行查看：include/uapi/asm-generic/unistd.h。

```c
#define __NR_write 64
  
#define __NR_exit 93
```

系统调用函数声明源码位置：include/linux/syscalls.h

```c
asmlinkage long sys_write(unsigned int fd, const char __user *buf, size_t count);

asmlinkage long sys_exit(int error_code);
```

### C 标准库

直接使用汇编调用 Syscall 比较繁琐也不安全，[C 标准库](https://en.wikipedia.org/wiki/C_standard_library)提供了对 Syscall 的封装。

![GNU C Library](/wp-content/uploads/2022/03/riscv-linux/images/riscv_syscall/kernel-syscall-glibc.png)
（图片源自 wikipedia）

下面用一段 C 代码例子看看如何使用 Syscall ，这种方式大家都比较熟悉。

```c
#include <unistd.h>

int main() {
  write(1, "Hello, world!\n", 14);
  return 0;
}

```

使用下面的命令进行测试即可输出结果。
```
$ cat testc.c
#include <unistd.h>

int main() {

  write(1, "Hello, world!\n", 14);
  return 0;
}
$ riscv64-linux-gnu-gcc -static testc.c -o testc
$ qemu-riscv64 testc
Hello, world!

```

## 总结

本篇文章主要从 Syscall 使用者的角度，阐述了什么是 Syscall。然后以实际代码为例，展示了在 RISC-V 架构下应用程序如何使用汇编代码和 C 标准库两种方式调用 Syscall 。

系列文章预告：RISC-V Syscall 系列2： Syscall 过程分析

## 参考资料

- [System call](https://en.wikipedia.org/wiki/System_call)
- [syscall(2) — Linux manual page](https://man7.org/linux/man-pages/man2/syscall.2.html)
- [Linux kernel interfaces](https://en.wikipedia.org/wiki/Linux_kernel_interfaces)
- [RISC-V Assembly Programmer's Manual](https://github.com/riscv-non-isa/riscv-asm-manual/blob/master/riscv-asm.md)
- [RISC-V架构下利用QEMU进行GDB调试](https://zhuanlan.zhihu.com/p/517497012)
- [Risc-V Assembly Language Hello World](https://smist08.wordpress.com/2019/09/07/risc-v-assembly-language-hello-world/)
- [System Interface & Headers Reference](https://pubs.opengroup.org/onlinepubs/007908799/xshix.html)
- [Misunderstanding RISC-V ecalls and syscalls](https://jborza.com/emulation/2021/04/22/ecalls-and-syscalls.html)

