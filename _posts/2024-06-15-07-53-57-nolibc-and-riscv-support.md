---
layout: post
author: 'Wu Zhangjin'
title: 'Linux 内核内置 C 库 nolibc 及其 RISC-V 架构支持分析'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /nolibc-and-riscv-support/
description: 'Linux 内核内置 C 库 nolibc 及其 RISC-V 架构支持分析'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - nolibc
  - rcutorture
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces newline urls]
> Author:    Falcon <falcon@tinylab.org>
> Date:      2023/02/10
> Revisor:   Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 简介

早在 [内核观察-v5.19][002] 节目中，我们就注意到了 nolibc，那时社区正好把作为单一文件存在的 nolibc.h 按照函数类别拆分到多个不同的文件，比如 string.h, types.h, time.h 等，而架构相关的部分则被拆分为 arch.h 和 `arch-<ARCH>.h`，这么做是为了更好的维护，当然，这也提供了类似 glibc 那样的按需包含目标头文件的标准方式。

nolibc 是一个仅提供头文件的小型用户态 C 库，它也是唯一合并进内核代码树的用户态 C 库，它跟标准 C 库相比有什么不同？它的特点和应用场景是什么？为什么内核源码中需要合并一个用户态的 C 库？带着这些问题，让我们开始 nolibc 的探索。

如果没有特别说明，本文以 Linux v6.1.1 作为实验源代码。

## 缘起：rcutorture

RCU 的作者 Paul 写了一个名叫 rcutorture 的测试工具，这个工具的用户态程序是一个极其简单的 while loop：

```
# 38e6304^:tools/testing/selftests/rcutorture/bin/mkinitrd.sh
#!/bin/sh
while :
do
        sleep 1000000
done
```

为了构建一个仅包含上述程序的文件系统，Paul 费尽了心机（参考 [Kernel-only deployments?][005]）：

1. 首先是尝试用 mkinitramfs 构建，构建出来的程序多达 40M
2. 然后是用 drafcut 来构建，构建出来的程序依然有 10M 之巨
3. 后面发现部分平台不支持 drafcut，所以 Paul 想到直接静态编译这个程序为 initrd 的 init，瞬间减少到 800k

```
// 38e6304:tools/testing/selftests/rcutorture/bin/mkinitrd.sh
#include <unistd.h>

int main(int argc, int argv[])
{
        for (;;)
                sleep(1000*1000*1000); /* One gigasecond is ~30 years. */
        return 0;
}
```

编译验证：

```
$ gcc -s -static -Os -o init init.c
$ ls -lh init
-rwxrwxr-x 1 ubuntu ubuntu 780K 2月  10 15:07 init
```

后来发现这个静态编译的 init 够用，因此 Paul 在 commit 9aa55ec2 中彻底删除了 drafcut 的支持。

## 灵魂拷问：Kernel-only deployments?

在经过一系列的尝试之后，Paul 在 LKML 发出了灵魂拷问式的邮件 [Kernel-only deployments?][005]：

> Does anyone do kernel-only deployments, for example, setting up an
> embedded device having a Linux kernel and absolutely no userspace
> whatsoever?

Paul 列举了上面做过的所有尝试：

> The mkinitramfs approach results in about 40MB of initrd, and dracut
> about 10MB.  Most of this is completely useless for rcutorture, which
> isn't interested in mounting filesystems, opening devices, and almost
> all of the other interesting things that mkinitramfs and dracut enable.
>
> ...
>
> Those who know me will not be at all surprised to learn that I went
> overboard making the resulting initrd as small as possible.  I started
>
> by throwing out everything not absolutely needed by the dash and sleep
> binaries, which got me down to about 2.5MB, 1.8MB of which was libc.
> This situation of course prompted me to create an initrd containing
> a statically linked binary named "init" and absolutely nothing else
> (not even /dev or /tmp directories), which weighs in at not quite 800KB.

到最后，Paul 甚至提议：

> This further prompted the idea of modifying kernel_init() to just loop
> forever, perhaps not even reaping orphaned zombies [*], given an appropriate
> Kconfig option and/or kernel boot parameter.

整个邮件的讨论不够激烈，但也够全面：

* 纯内核的部署并没有被大家认可
    - 一个是灵活性，用户空间的 init 比 hacking kernel_init() 更灵活方便
    - 另外一个是 License，编译进内核意味着软件部分的 License 受限于 GPL，完全不同于现有的先制作成 initramfs，再打包进内核的方式

* 优化的方向需要同时考虑 Size 和 Portability
    - 有人提出了完全免 libc 的汇编代码调用 sleep 甚至 pause 系统调用的方式，但是他也提出了这个需要考虑跨平台
        - nolibc 的作者 Willy 恰如其分地抓到了这个点，提供了自己早期做过的面向 [preinit loader][007] 设计的 nolibc 库，基于这个库编译出来的 sleep 程序只有 664 个字节
    - 另有更多的人建议采用包括 musl, dietlibc 等在内的其他小型 libc，因为 glibc 的 printf 和 locale 等方面的支持带来了太多的额外空间占用
        - nolibc 相比较而言更为轻量级，以头文件方式存在，当前实现只是 glibc 等大型 C 库的一个极小子集，并且各种库函数的实现也更为简洁

Willy 在邮件中回复：

> I've developed a "nolibc" include file which implements most
> common syscalls and string functions (those I use in early boot)
> as static inlines so the resulting executable only contains the
> code you really use: http://git.formilux.org/?p=people/willy/nolibc.git;a=tree

他也给了仅使用 `sleep()` 的例子：

```
$ echo "int main() { return sleep(3);}" | gcc -Os -nostdlib -include ../nolibc/nolibc.h -s
 -fno-exceptions -fno-asynchronous-unwind-tables -fno-unwind-tables  -lgcc -o sleep -xc -
$ ls -l sleep
-rwxr-xr-x 1 willy users 664 Aug 23 20:37 sleep
```

基于 nolibc 编译出来的 sleep 仅需 664 字节，是 Paul 用 glibc 编译出来的 init 字节数的约 1/1000。

后来，Willy 和 Paul 合作，致力于为 rcutorture 添加 nolibc 支持。

## rcutorture + nolibc

Paul 早前用 glibc，而不是 musl 或者其他小型 C 库的另外一个可能原因是，C 库和 gcc toolchain 一般会同时安装，至少各大 Linux 发行版的软件仓库基本都会提供，而其他小型 C 库不一定有那么幸运，一般都得另外下载，便利性差距是显而易见的。

对于 musl 是这样，对于 nolibc 也是这样，所以在后来的代码提交中，Paul 和 Willy 直接把 nolibc，以单一的 nolibc.h 头文件的形式，导入到了 Linux 内核源码的 `tools/testing/selftests/rcutorture/bin/` 目录下：

```
commit 66b6f755ad45d354c5b74abd258f67aa8b40b3c7
Author: Willy Tarreau <w@1wt.eu>
Date:   Sun Sep 9 13:26:04 2018 +0200

    rcutorture: Import a copy of nolibc

    This is a definition of the most common syscalls needed in minimalist
    init executables, allowing to statically build them with no external
    dependencies. It is sufficient in its current form to build rcutorture's
    init on x86_64, i386, arm, and arm64. Others have not been ported or
    tested. Updates may be found here :

         http://git.formilux.org/?p=people/willy/nolibc.git

    Signed-off-by: Willy Tarreau <w@1wt.eu>
    Signed-off-by: Paul E. McKenney <paulmck@linux.vnet.ibm.com>
```

把 nolibc 库导入到 Linux 内核源码中就完全消除了额外的 C 库安装需要，从而让 initramfs 的构建和打包进内核镜像变得完全自动化和透明，甚至效果上基本达成了 Paul 最初提出的 “Kernel-only deployments”，因为用户态程序的编译和部署变得非常容易，用户几乎感知不到。

有了 nolibc 以后，就要基于 nolibc 来支持 init 的自动编译：

```
commit b94ec36896dafc0a12106b1536fe87f99e9a0c5d
Author: Willy Tarreau <w@1wt.eu>
Date:   Sun Sep 9 13:33:02 2018 +0200

    rcutorture: Make use of nolibc when available

    This reduces the size of the init executable from ~800 kB to ~800 bytes
    on x86_64. This is only implemented for x86_64, i386, arm and arm64.
    Others not tested.

    Signed-off-by: Willy Tarreau <w@1wt.eu>
    Signed-off-by: Paul E. McKenney <paulmck@linux.vnet.ibm.com>

diff --git a/tools/testing/selftests/rcutorture/bin/mkinitrd.sh b/tools/testing/selftests/rcutorture/bin/mkinitrd.sh
index 56a56ea06983..da298394daa2 100755
--- a/tools/testing/selftests/rcutorture/bin/mkinitrd.sh
+++ b/tools/testing/selftests/rcutorture/bin/mkinitrd.sh
@@ -82,8 +82,10 @@ cd $D
 mkdir -p initrd
 cd initrd
 cat > init.c << '___EOF___'
+#ifndef NOLIBC
 #include <unistd.h>
 #include <sys/time.h>
+#endif

 volatile unsigned long delaycount;

@@ -113,7 +115,21 @@ int main(int argc, int argv[])
        return 0;
 }
 ___EOF___
-${CROSS_COMPILE}gcc -s -static -Os -o init init.c
+
+# build using nolibc on supported archs (smaller executable) and fall
+# back to regular glibc on other ones.
+if echo -e "#if __x86_64__||__i386__||__i486__||__i586__||__i686__" \
+           "||__ARM_EABI__||__aarch64__\nyes\n#endif" \
+   | ${CROSS_COMPILE}gcc -E -nostdlib -xc - \
+   | grep -q '^yes'; then
+       # architecture supported by nolibc
+        ${CROSS_COMPILE}gcc -fno-asynchronous-unwind-tables -fno-ident \
+               -nostdlib -include ../bin/nolibc.h -lgcc -s -static -Os \
+               -o init init.c
+else
+       ${CROSS_COMPILE}gcc -s -static -Os -o init init.c
+fi
+
 rm init.c
 echo "Done creating a statically linked C-language initrd"
```

不过早期仅支持 x86_64, i386, arm 和 arm64，不支持的架构还是用 glibc 来编译。

## nolibc 更多改进

后来，Ingo 建议把 nolibc 搬到更为通用的目录下，因为 rcutorture 之外的其他工具也可能会用到：

```
commit 30ca20517ac136e63967396899af89f359f16f36
Author: Willy Tarreau <w@1wt.eu>
Date:   Sat Dec 29 19:04:53 2018 +0100

    tools headers: Move the nolibc header from rcutorture to tools/include/nolibc/

    As suggested by Ingo, this header file might benefit other tools than
    just rcutorture. For now it's quite limited, but is easy to extend, so
    exposing it into tools/include/nolibc/ will make it much easier to
    adopt by other tools.

    The mkinitrd.sh script in rcutorture was updated to use this new location.

    Cc: Ingo Molnar <mingo@kernel.org>
    Cc: Arnaldo Carvalho de Melo <acme@redhat.com>
    Cc: Paul E. McKenney <paulmck@linux.vnet.ibm.com>
    Signed-off-by: Willy Tarreau <w@1wt.eu>
    Signed-off-by: Paul E. McKenney <paulmck@linux.ibm.com>
```

所以，nolibc 目前已经被搬运到了 `tools/include/` 下面。

更多已经开展的工作包括：

- 类似标准 C 库，按函数类别拆分出独立的 string.h, types.h, time.h

- 添加了编译目标 `headers_standalone` 来安装包含 nolibc 和内核 UAPI headers 的 sysroot
    - 方便以类似标准 C 库的方式来引用头文件：`-I /path/to/sysroot`
    - sysroot 的路径由 `OUTPUT` 指定

- 添加了 selftest 用例：`tools/testing/selftests/nolibc`
    - 提供了以 sysroot 方式引用 nolibc 的 Makefile 示例
    - 提供了采用 nolibc 的较为复杂的应用程序示例：nolibc-test.c

- 陆续添加了更多处理器架构的支持
    - 比如 RISC-V，MIPS 以及 LoongArch（还未合入）等

- 陆续添加更多的库函数
    - 比如：`usleep()`, `getenv()`, `getppid()`, `mmap/munmap()`, `malloc/calloc/realloc/free()`, `strcmp/strncmp/strnlen/strdup/strndup()` 等

- 修复各种问题
    - 包括对编译器 LLVM 的支持以及其他编译器参数的支持

nolibc 还在持续地迭代和完善中，目前非常活跃，Willy 前不久刚在 lwn.net 发表了一篇文章：[Nolibc: a minimal C-library replacement shipped with the kernel][004]，感兴趣的小伙伴们也可以去看看，这是参与一个全新 C 库开发过程的极佳机会。

## nolibc 两种用法

综合前面介绍的内容，不难发现 nolibc 有两种用法：

1. 极简方式

   rcutorture 是通过 `-include /path/to/nolibc.h` 来直接引用的，此时 UAPI headers 来自当前使用的 toolchain。在这种方式下，nolibc.h 会自动定义 NOLIBC 的宏，可以据此判断做一些特定的动作。

   ```
   // tools/testing/selftests/rcutorture/bin/mkinitrd.sh

   ${CROSS_COMPILE}gcc -fno-asynchronous-unwind-tables -fno-ident \
     -nostdlib -include ../../../../include/nolibc/nolibc.h \
     -s -static -Os -o init init.c -lgcc
   ```

2. 通用方式

   而 nolibc-test.c 则是通过 sysroot 的方式来引用，UAPI headers 来自当前内核，需要通过 `headers_standalone` 提前安装。在这种方式下，需要额外在编译器通过 `-DNOLIBC` 来做差异化处理。

   ```
   // tools/testing/selftests/nolibc/Makefile

   sysroot/$(ARCH)/include:
        $(QUIET_MKDIR)mkdir -p sysroot
        $(Q)$(MAKE) -C ../../../include/nolibc ARCH=$(ARCH) OUTPUT=$(CURDIR)/sysroot/ headers_standalone
        $(Q)mv sysroot/sysroot sysroot/$(ARCH)

   nolibc-test: nolibc-test.c sysroot/$(ARCH)/include
        $(QUIET_CC)$(CC) $(CFLAGS) $(LDFLAGS) -o $@ \
          -nostdlib -static -Isysroot/$(ARCH)/include $< -lgcc
   ```

## nolibc for RISC-V

这一节我们来讨论 nolibc 的架构支持，主要以 RISC-V 为例。

前面介绍到，nolibc 已经支持了绝大部分主流的处理器架构：

```
$ git show v6.2-rc7:tools/include/nolibc/ | grep arch-
arch-aarch64.h
arch-arm.h
arch-i386.h
arch-mips.h
arch-riscv.h
arch-x86_64.h
```

架构相关的支持目前仅有 200 行左右，非常短小：

```
$ git show v6.2-rc7:tools/include/nolibc/ | grep arch- | xargs -i wc -l tools/include/nolibc/{}
199 tools/include/nolibc/arch-aarch64.h
204 tools/include/nolibc/arch-arm.h
219 tools/include/nolibc/arch-i386.h
215 tools/include/nolibc/arch-mips.h
204 tools/include/nolibc/arch-riscv.h
215 tools/include/nolibc/arch-x86_64.h
```

接下来以 RISC-V 为例，简单做个分析。

剔除空行，仅剩 183 行：

```
$ cat tools/include/nolibc/arch-riscv.h | egrep -v '^[[:space:]]*$|^[[:space:]]*\\$' | wc -l
183
```

基于当前的情况，整个架构相关的部分大体可以分成 3 部分：

1. 第一部分是架构相关的宏定义和结构体定义
    - 比如 fntl/open 函数中用到的 `O_RDONLY` 等宏定义
    - 以及 `sys_stat()` 用到的 `sys_stat_struct` 结构体

2. 第二部分是包含不同个数参数的系统调用的宏定义，这些宏定义最终被库函数调用以便实现不同的功能函数
    - 系统调用宏定义从 `my_syscall0()` 到 `my_syscall6()` 共 7 个，因为涉及系统调用指令、系统调用号传递、函数参数传递和返回值接收，这部分完全跟处理器架构相关
    - 另外一部分是类似 `__ARCH_WANT_SYS_PSELECT6` 这样的系统调用函数选择开关，用于选择架构特定的系统调用，有些功能可能有多个不同的系统调用实现，有些架构仅实现了部分变体

3. 第三部分是 Startup Code
    - 这部分是纯粹的汇编代码，是进入 `main()` 函数之前的程序入口代码
    - 需要设定 gp 寄存器并从 Stack 中获取到 argc, argv, envp 参数并传递给 `main()` 函数，最后调用 exit 系统调用正确退出程序

代码的注释其实已经非常清楚，这里简单贴一个系统调用的例子：

```
/* Syscalls for RISCV :
 *   - stack is 16-byte aligned
 *   - syscall number is passed in a7
 *   - arguments are in a0, a1, a2, a3, a4, a5
 *   - the system call is performed by calling ecall
 *   - syscall return comes in a0
 *   - the arguments are cast to long and assigned into the target
 *     registers which are then simply passed as registers to the asm code,
 *     so that we don't have to experience issues with register constraints.
 *
 * On riscv, select() is not implemented so we have to use pselect6().
 */
#define __ARCH_WANT_SYS_PSELECT6

#define my_syscall0(num)                                                      \
({                                                                            \
        register long _num  __asm__ ("a7") = (num);                           \
        register long _arg1 __asm__ ("a0");                                   \
                                                                              \
        __asm__  volatile (                                                   \
                "ecall\n\t"                                                   \
                : "=r"(_arg1)                                                 \
                : "r"(_num)                                                   \
                : "memory", "cc"                                              \
        );                                                                    \
        _arg1;                                                                \
})

#define my_syscall1(num, arg1)                                                \
({                                                                            \
        register long _num  __asm__ ("a7") = (num);                           \
        register long _arg1 __asm__ ("a0") = (long)(arg1);                    \
                                                                              \
        __asm__  volatile (                                                   \
                "ecall\n"                                                     \
                : "+r"(_arg1)                                                 \
                : "r"(_num)                                                   \
                : "memory", "cc"                                              \
        );                                                                    \
        _arg1;                                                                \
})
```

其中系统调用指令为 `ecall`，系统调用号通过 `a7` 寄存器传递，参数则依次通过 `a0-a5` 传递，而返回值放在 `a0` 寄存器。

然后是 Startup Code：

```
#if   __riscv_xlen == 64
#define PTRLOG "3"
#define SZREG  "8"
#elif __riscv_xlen == 32
#define PTRLOG "2"
#define SZREG  "4"
#endif

...

/* startup code */
__asm__ (".section .text\n"
    ".weak _start\n"
    "_start:\n"
    ".option push\n"
    ".option norelax\n"
    "lla   gp, __global_pointer$\n"
    ".option pop\n"
    "lw    a0, 0(sp)\n"          // argc (a0) was in the stack
    "add   a1, sp, "SZREG"\n"    // argv (a1) = sp
    "slli  a2, a0, "PTRLOG"\n"   // envp (a2) = SZREG*argc ...
    "add   a2, a2, "SZREG"\n"    //             + SZREG (skip null)
    "add   a2,a2,a1\n"           //             + argv
    "andi  sp,a1,-16\n"          // sp must be 16-byte aligned
    "call  main\n"               // main() returns the status code, we'll exit with it.
    "li a7, 93\n"                // NR_exit == 93
    "ecall\n"
    "");
```

这部分有几点需要解释：

- `_start` 是 ELF 可执行文件的标准入口，如果没有 `_start`，编译器需要用 "-e entry" 来明确指定一个

- gp 寄存器从 `__global_pointer` 获取
    - 链接器用 gp 来优化代码密度，减少程序 size
    - 有了 gp 寄存器以后，诸如 lui 或 auipc 的绝对或 PC 相对寻址可以替换成 gp 相对寻址，在访问 gp±2KB，即 4KB 范围内的全局变量时，可以节约一条指令
    - 这部分可以通过 `-Wl,--no-relax` 来关闭，也可以根据实际情况来决定是否需要通过链接脚本来调整 `__global_pointer` 指向的位置：`PROVIDE( __global_pointer$ = . + (4K / 2) );`

- 参数和环境变量全部通过栈传递
    - 栈的布局是通用的：argc 在栈顶，接着是所有的参数，然后是所有的环境变量
    - 栈的增长方向由架构定义：“The stack grows downwards (towards lower addresses)”

- 另外，RISC-V 要求栈是 16 字节对齐的
    - “the stack pointer shall be aligned to a 128-bit boundary upon procedure entry”

而像 `exit` 的系统调用号则可以从 unistd.h 中找到，RISC-V 用的是通用定义 `include/uapi/asm-generic/unistd.h`：

```
$ grep "__NR_exit " -ur include/uapi/asm-generic/unistd.h
#define __NR_exit 93
```

而 `exit` 的参数 a0 直接取 `main` 的返回值 `a0`，所以没有设定。

## nolibc in Linux Lab

由泰晓社区研发的 [Linux Lab][006] 开源内核实验环境已经添加了对 nolibc 的支持，可以透明地提供 "Kernel-only" 的编译和引导。

在 Linux Lab 中，我们尝试过前文提到的两种 nolibc 的使用方式，最终保留了跟标准 C 库用法更为一致的 sysroot 方式，这种方式有几个好处：

- 一个是 C 程序可以更为标准规范，方便移植
- 另外一个是因为只需要按需包含库函数所在的头文件，而不是整个 nolibc.h，因此编译出来的程序 Size 更小
- 再一个是用到的 UAPI headers 就来自当前的内核源码，不存在兼容性问题

接下来，以 `riscv64/virt` 虚拟开发板为例演示 nolibc 在 Linux Lab 中的用法：

```
// 切换板子
$ make BOARD=riscv64/virt

// 启用 nolibc 模式
$ export nolibc=1
$ make kernel nolibc_src=$PWD/src/examples/nolibc/hello.c
$ make boot
Starting kernel ...

Linux version 6.1.1 (ubuntu@linux-lab) (riscv64-linux-gnu-gcc (Ubuntu 9.3.0-17ubuntu1~20.04) 9.3.0, GNU ld (GNU Binutils for Ubuntu) 2.34) #35 SMP Fri Feb 10 13:24:36 CST 2023
...
Freeing unused kernel image (initmem) memory: 2468K
Run /init as init process
Hello, nolibc!
reboot: System halted
ubuntu@linux-lab:/labs/linux-lab$
```

以上 `nolibc_src` 可以指定自己的应用程序，当然，用到的库函数必须要在 nolibc 当前支持的范围内。而 `nolibc=1` 用于通知 Linux Lab 启用 nolibc 库来编译 hello.c 并自动生成 initramfs 然后打包进内核镜像，同时在引导内核后使用内核镜像中的 initramfs 而不是额外的文件系统。

相关源码和程序 Size 信息如下：

```
$ cat src/examples/nolibc/hello.c
#include <stdio.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
	printf("Hello, nolibc!\n");

#ifdef NOLIBC
	reboot(LINUX_REBOOT_CMD_HALT);
#endif

	return 0;
}

$ ls -lh build/riscv64/virt/linux/v6.1.1/nolibc/initramfs/init
-rwxr-xr-x 1 ubuntu ubuntu 1.5K 2月  10 13:24 build/riscv64/virt/linux/v6.1.1/nolibc/initramfs/init
```

有了该功能，对于一些简单的内核测试与验证，开发人员可以 “免 rootfs” 快速编写一个测试用例，然后编译进 Linux 内核镜像，快速引导，运行测试用例，非常高效！

## 总结

本文详细地追溯了极小 C 库 nolibc 的来龙去脉和开发进展，并以 RISC-V 为例分析了处理器架构相关的部分，最后在泰晓社区研发的 [Linux Lab][006] 开源内核实验环境中添加了 nolibc 的支持，透明地提供了 “Kernel-only” 的编译和引导支持，这将大大便利某些场景的 Linux 内核测试与验证。

通过本文的梳理，我们现在可以完整地回答一下文章开头提出的几个问题。

- 首先，nolibc 跟标准 C 库相比有什么不同？

  nolibc 是一个极小型的用户态 C 库，其当前实现只是标准 C 库的一个极小子集，并且现有库函数的实现非常简洁。这意味着 nolibc 的支持不会很全面，同时意味着它无法提供静态 libc 库和共享 libc 库，只能静态链接进目标程序。

- 其次，它的特点和应用场景是什么？

  nolibc 的核心特点是“小”，因此很方便开发、移植、下载和使用。nolibc 的另外一个特点是没有 libc 库，包括静态 libc 库和共享 libc 库，因此它只能跟目标应用程序编译到一起。

  nolibc 适合功能单一或简单的应用场景，这类场景通常只需要一个极其简单的应用程序，比如文中提到的 preinit 和 rcutorture 都是这种情况，它们的用户态工作量非常少，仅使用到极个别或少数的系统调用，以至于连完整的 C 库和完整的根文件系统都不需要。一旦系统功能需求变得复杂，nolibc 就无法满足：一方面是当前 nolibc 实现的库函数很少而且支持不全面很多应用可能连编译都无法通过，另外一方面，如果目标系统需要多个应用程序，那么每个应用都需要链接进相同功能的库函数，因此，采用 nolibc 的话整个目标文件系统因为库函数的冗余链接反而可能变得更加臃肿。

  一些极其简单的嵌入式应用将因 nolibc 而受益，文件系统的裁减需求将不复存在，只需要专注内核部分的裁减即可，甚至内核的裁减工作因为应用的简单也可以做得更为彻底。

- 最后，为什么内核源码中需要合并一个用户态的 C 库？

  nolibc 合并进 Linux 内核源码后，可以无外部源码依赖地实现 initramfs 的编译和打包，让 “Kernel-only” 的编译和部署变成水到渠成。在 rcutorture 之后，预计第一批潜在用户将是更多的内核 selftests。

nolibc 还在热火朝天地开发中，欢迎同学们关注该项目的后续进展。

## 参考资料

- tools/include/nolibc
- tools/testing/selftests/nolibc
- tools/testing/selftests/rcutorture/bin/mkinitrd.sh
- [nolibc: usability improvements (errno, environ, auxv)][003]
- [nolibc - libc-less wrapper to make tiny static executables for simple programs][001]
- [Kernel-only deployments?][005]
- [Nolibc: a minimal C-library replacement shipped with the kernel][004]

[001]: http://git.formilux.org/?p=people/willy/nolibc.git
[002]: https://gitee.com/tinylab/linux-observe
[003]: https://lwn.net/Articles/919442/
[004]: https://lwn.net/Articles/920158/
[005]: https://lwn.net/ml/linux-kernel/20180823174359.GA13033@linux.vnet.ibm.com/
[006]: https://tinylab.org/linux-lab
[007]: https://github.com/formilux/flxutils/tree/master/init
