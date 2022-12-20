---
layout: post
author: 'song'
title: 'RISC-V Ftrace 实现原理（1）- 函数跟踪'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /ftrace-impl-1-mcount/
description: 'ftrace 实现原理（1）- 函数跟踪'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [spaces header comments codeblock codeinline]
> Author:   sugarfillet <18705174754@163.com>
> Date:     2022/08/12
> Revisor:  Falcon falcon@tinylab.org
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V ftrace 相关技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I58N1O)
> Sponsor:  PLCT Lab, ISCAS


本文主要介绍函数跟踪的实现原理以及静态 ftrace 在 RISC-V 架构下的实现。

## 函数跟踪

如果你想要统计程序中函数的执行时间或者执行次数来提升程序的性能，如果你要想要打印某个的函数的调用栈来了解程序的运行，你会选择什么工具？如果你是上世纪 80 年代的 unix 程序员，你可能会选择 gprof。当然，现在更多的人会选择 perf。既然 gprof 能实现函数跟踪的功能，那不妨先来了解下 gprof 是啥以及是如何工作的。

### gprof 介绍

gprof 是程序性能分析工具，可以用来计算函数的执行时间，统计函数的调用次数，收集函数的的调用栈，基于这些功能就可以为程序的性能优化指明方向。那我们先来看一下 gprof 怎么用。

gprof 用来分析程序的过程分为以下三个步骤：

1. 编译时，使能用于分析程序行为的 profile 信息
2. 执行程序时，生成分析数据 gmon.out 文件
3. 运行 gprof，对分析数据进行分析，并生成分析报告

具体的 gprof 实战教程，在此不做赘述，可以参考 [这里][1]。那么 gprof 生成分析数据的过程是如何实现的呢？

接下来，我们来了解下 gprof 的工作原理，特别的，这里重点关注 gprof 如何实现函数跟踪。gprof 的其他实现原理，比如：运行时分析，语句执行计数，gmon.out 格式等，这里不做讨论，如有兴趣，可参考 [这里][2]。

### gprof 工作原理介绍

gprof 的工作过程大致是这样的：

1. 首先，程序编译时指定 `-pg` 选项，会在每个函数入口处，插入一段代码，这段代码去调用 `mcount` ( 还可能是 `_mcount` or `__mcount`，这取决于你的编译器）
2. 而 mcount 实现在 glibc 代码中，以汇编码编码，收集 frompc 和 selfpc，然后调用 `mcount_internal`
    - frompc 代表当前函数的返回地址
    - selfpc 代表当前函数的真实入口地址
3. `mcount_internal` 函数会在内存中维护调用栈，frompc，selfpc，函数调用计数等信息
4. 最后，在函数退出时，调用 `mcleanup`，将以上信息汇总到 gmon.out，供 gprof 程序来分析

> 如果对 RISC-V glibc mcount 实现有兴趣的同学，可以以 glibc source c776fa113:sysdeps/riscv/machine-gmon.h 为切入点来研究

前面提到 mcount 的名称，可能由于编译器的不同而不同，那我们编译内核用的 `riscv64-linux-gnu-gcc` 编译出的 mcount 名称是啥？

```bash
$  echo 'main(){}' | riscv64-linux-gnu-gcc -x c -S -o - - -pg | grep mcount
        .globl  _mcount
        call    _mcount@plt
```

哦，是 `_mcount` 啊，那这样的话，我们在内核中观察 mcount 的实现就可以用这个 `_mcount` 了。

### gprof 函数跟踪小结

从 gprof 的函数跟踪实现中，我们了解到：如果要实现函数跟踪，需要在程序编译时采用 `-pg` 选项，并且运行时动态链接 libc 继而实现对 mcount 的调用。而像内核这种特殊的程序，就需要自己来实现 mcount 了。那我们就来了解下内核编译时的 `-pg` 选项如何指定，以及 `_mcount` 如何在内核中实现？

## 内核中的函数跟踪

ftrace 在实现上分为静态和动态，默认使用的是动态 ftrace。在内核编译时，选择 `FUNCTION_TRACER` 会默认开启 `DYNAMIC_FTRACE`，如需静态，需要手动禁用 `DYNAMIC_FTRACE`。

动态 ftrace 相比静态 ftrace，在内核编译、ftrace 初始化、运行时指令替换等实现机制上都更复杂。但功能上也更灵活，可以实现函数的单独跟踪，而不是全体函数的跟踪。比如：我们常见的 `set_ftrace_filter` 文件，可以只跟踪一个或一部分的函数，静态 ftrace 就做不到。

本文主要关注内核的函数跟踪，简单的静态 ftrace 就够用了，所以下文中使用的内核是在关闭 `DYNAMIC_FTRACE` 后编译的。

如果你的实验输出与本文有较大差异，可以关闭 `DYNAMIC_FTRACE` 后再编译内核来实验。

OK，我们继续介绍内核如何实现函数跟踪。

### -pg 选项如何指定

通过查看 kernel 源码目录下的 `./Makefile` 文件，我们可以观察到：`CC_FLAGS_FTRACE` 是用于指定实现函数跟踪所需要的编译参数，在编译时会组合到内核编译选项 `KBUILD_CFLAGS` 中。

```c
// ./Makefile : 695
# The arch Makefiles can override CC_FLAGS_FTRACE. We may also append it later.
ifdef CONFIG_FUNCTION_TRACER
  CC_FLAGS_FTRACE := -pg
endif

include $(srctree)/arch/$(SRCARCH)/Makefile

KBUILD_CFLAGS   += $(CC_FLAGS_FTRACE) $(CC_FLAGS_USING)

```

那么编译内核文件时，这个选项有用到么？我们来查看 `read_write.c` 文件在编译时是否使用此选项：

```
$ grep -o 'gp' fs/.read_write.o.cmd
gp

```

通过上述结果，不难看到，`-pg` 选项确实在编译选项列表中。

细心的同学会发现，`CC_FLAGS_FTRACE` 在 `./Makefile` 中还有会其他赋值，比如 `-mrecord-mcount`，`-mnop-mcount`，`-mfentry`，甚至在 `./arch/riscv/Makefile`，显式指定为 `-fpatchable-function-entry=8`。

其实，这些选项都是跟动态 ftrace 所依赖的 FTRACE_MCOUNT_RECORD 有关。如果只开启静态的 ftrace 功能，默认的选项就是 `-pg`。

### 如何实现内核的 mcount

[ftrace-design.txt][3] 文档中采用一段伪代码来介绍 mcount 的实现，它已经写的很清晰，在这里直接引用，做一些注释，删除了一些上下文切换的保存和恢复操作，以突出 mcount 的实现逻辑。

需要说明的是：mcount 以及 ftrace_stub 的实现，涉及汇编指令，是硬件架构相关的，所以实现在 `arch/riscv` 中。

```c
void ftrace_stub(void)
{
	return;
}

void mcount(void)   // 入口
{
	extern void (*ftrace_trace_function)(unsigned long， unsigned long);
	if (ftrace_trace_function != ftrace_stub)  // 如果不是默认的直接返回的 ftrace_stub，就执行指向的跟踪函数
		goto do_trace;
	return;

do_trace:

	unsigned long frompc = ...;
	unsigned long selfpc = <return address> - MCOUNT_INSN_SIZE;
	ftrace_trace_function(frompc， selfpc);
	// 这里就是跟踪函数；比如，可以让 ftrace_trace_function -> printk，就可以打印 函数调用过程中入口地址和返回地址

}

extern void mcount(void);  // 导出为 extern，这样才能保证 mcount 能被所有 mcount 的 caller 调用到
EXPORT_SYMBOL(mcount);

```

接下来，我们看下 RISC-V 架构中的 `_mcount` 是如何实现上述伪代码的。

### mcount RISC-V 架构实现

初始实现可以在源码树中执行 `git show  10626c32e3827:arch/riscv/kernel/mcount.S` 看到。

咱们重点关注，`ftrace_stub`, `_mcount`, `do_trace` 的实现，它的实现逻辑和 `ftrace-desigin.txt` 中描述的基本一致。

为了深化对 mcount 的理解，我们接下来用 gdb 调试 mcount 的执行过程。

## 调试内核 mcount

在这里做个回顾，静态 ftrace 是通过 `-pg` 选项在几乎每个函数开头插入并运行时调用 `_mcount`，`_mcount` 调用 `ftrace_trace_function` 函数指针来执行函数跟踪。

### _mcount 反汇编

首先，通过 gdb 的 `disassemble _mcount` 反汇编得到如下结果：

```bash
(gdb) disassemble _mcount
Dump of assembler code for function _mcount:
   0xffffffff80007dd4 <+0>:     auipc   t4，0x0
   0xffffffff80007dd8 <+4>:     addi    t4，t4，-4 # 0xffffffff80007dd0 <ftrace_stub>
   0xffffffff80007ddc <+8>:     addi    t3，gp，-584
   0xffffffff80007de0 <+12>:    ld      t5，0(t3)    // t5 is ftrace_trace_function
   0xffffffff80007de4 <+16>:    bne     t5，t4，0xffffffff80007dea <_mcount+22>
   0xffffffff80007de8 <+20>:    ret
   0xffffffff80007dea <+22>:    ld      a1，-8(s0)   // do_trace
   0xffffffff80007dee <+26>:    mv      a0，ra
   0xffffffff80007df0 <+28>:    addi    sp，sp，-16
   0xffffffff80007df2 <+30>:    sd      s0，0(sp)
   0xffffffff80007df4 <+32>:    sd      ra，8(sp)
   0xffffffff80007df6 <+34>:    addi    s0，sp，16
   0xffffffff80007df8 <+36>:    jalr    t5           // goto ftrace_trace_function
   0xffffffff80007dfa <+38>:    ld      ra，8(sp)
   0xffffffff80007dfc <+40>:    ld      s0，0(sp)
   0xffffffff80007dfe <+42>:    addi    sp，sp，16
   0xffffffff80007e00 <+44>:    ret
```

从上述结果中，我们可以得到以下结论：

- `ftrace_stub` 通过 `_mcount` 偏移来获取，存放在 `$t4`
- `ftrace_trace_function` 通过 `gp` 来计算，存放在 `$t5`
- 比较二者的是否相同，如果不同，则跳转到 `do_trace <_mcount+22>`，如果相同，则直接返回原函数

### 观察 vfs_read 调用 _mcount

为了分析 `_mcount` 的实际调用过程，我们以 `vfs_read` 为例来做个具体分析。

首先通过 gdb 对 `vfs_read` 反汇编，

```
(gdb) disassemble vfs_read，+38
Dump of assembler code for function vfs_read:
   0xffffffff8019f43e <+0>:     addi    sp，sp，-64
   0xffffffff8019f440 <+2>:     sd      s0，48(sp)
   0xffffffff8019f442 <+4>:     sd      ra，56(sp)
   0xffffffff8019f444 <+6>:     addi    s0，sp，64
   0xffffffff8019f446 <+8>:     sd      s1，40(sp)
   0xffffffff8019f448 <+10>:    sd      s2，32(sp)
   0xffffffff8019f44a <+12>:    sd      s3，24(sp)
   0xffffffff8019f44c <+14>:    sd      s4，16(sp)
   0xffffffff8019f44e <+16>:    sd      s5，8(sp)
   0xffffffff8019f450 <+18>:    sd      s6，0(sp)
   0xffffffff8019f452 <+20>:    mv      s2，a0
   0xffffffff8019f454 <+22>:    mv      a0，ra
   0xffffffff8019f456 <+24>:    mv      s5，a1
   0xffffffff8019f458 <+26>:    mv      s1，a2
   0xffffffff8019f45a <+28>:    mv      s3，a3
   0xffffffff8019f45c <+30>:    auipc   ra，0xffe69
=> 0xffffffff8019f460 <+34>:    jalr    -1672(ra) # 0xffffffff80007dd4 <_mcount>
   0xffffffff8019f464 <+38>:    lw      a5，84(s2)    // _mcount frame $ra value
```

我们可以看到在 `0xffffffff8019f460 <vfs_read+34>` 跳转到 `_mcount`，这里是 `-pg` 选项决定的。

然后，断点在 `vfs_read` 调用 `_mcount` 的地方，`break *0xffffffff8019f460`，使用 `si` 执行指令单步调试，并观察 `$t4`, `$t5` 的值，

```
(gdb) si
_mcount () at ../arch/riscv/kernel/mcount.S:82
82              la      t4， ftrace_stub
(gdb) info registers pc
pc             0xffffffff80007dd4       0xffffffff80007dd4 <_mcount>
(gdb) si
0xffffffff80007dd8      82              la      t4， ftrace_stub
(gdb) si
93              la      t3， ftrace_trace_function
(gdb) si
94              ld      t5， 0(t3) // t5 is ftrace_trace_function
(gdb) si
95              bne     t5， t4， do_trace
(gdb) info registers pc t4 t5
pc             0xffffffff80007de4       0xffffffff80007de4 <_mcount+16>
t4             0xffffffff80007dd0       -2147451440
t5             0xffffffff80007dd0       -2147451440
(gdb) x $t4
   0xffffffff80007dd0 <ftrace_stub>:    ret
(gdb) x $t5    // t5 == t4  do ret
   0xffffffff80007dd0 <ftrace_stub>:    ret

(gdb) si
96              ret
(gdb) info registers pc ra  // ret 前
pc             0xffffffff80007de8       0xffffffff80007de8 <_mcount+20>
ra             0xffffffff8019f464       0xffffffff8019f464 <vfs_read+38>  // next pc
(gdb) si
vfs_read (file=0xff600000057ebb40， buf=0xffffffc37ca2af "o\030"， count=1， pos=0xff20000010993e60) at ../fs/read_write.c:466
466             if (!(file->f_mode & FMODE_READ))
(gdb) info registers pc ra  // ret 后
pc             0xffffffff8019f464       0xffffffff8019f464 <vfs_read+38>
ra             0xffffffff8019f464       0xffffffff8019f464 <vfs_read+38>

```

从上面的调试过程，我们可以看到 `ftrace_trace_function` 就是 `ftrace_stub`，不执行 `do_trace`，直接返回到 `vfs_read`。如果 `ftrace_trace_function` 指向了其他函数（比如：`function_trace_call`），就会走到 `do_trace`，继而调用对应的跟踪函数 `function_trace_call`。那如何更改它的指向呢？

这里做个小练习吧，

> 在虚拟机中，执行 `echo function > current_tracer`，再走一遍上述调试流程，了解不同跟踪函数在静态 ftrace 下的调用过程。

## 总结

本篇文章主要介绍 gprof 工具如何实现函数跟踪，其底层机制在内核静态 ftrace 中的应用，以及 RISC-V 架构中 mcount 的实现。然后，通过一些调试实验，了解了静态 ftrace 的工作原理。

这里罗列些速记词，帮助大家回忆上述分析过程：pg，mcount，ftrace_stub，ftrace_trace_function，do_trace。

如上文所说，ftrace 默认采用动态 ftrace，那它又是怎么实现的呢？且看下文分解。

## 参考资料

* [GPROF Tutorial – How to use Linux GNU GCC Profiling Tool][1]
* [gprof manual][2]
* [function design][3]

[1]: https://www.thegeekstuff.com/2012/08/gprof-tutorial/
[2]: https://ftp.gnu.org/old-gnu/Manuals/gprof-2.9.1/html_chapter/gprof_9.html#SEC24
[3]: https://www.kernel.org/doc/Documentation/trace/ftrace-design.txt
