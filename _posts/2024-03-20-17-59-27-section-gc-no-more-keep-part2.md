---
layout: post
author: 'Yuan Tan'
title: '解决 Linux 内核 Section GC 失败问题 - Part 2'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /section-gc-no-more-keep-part2/
description: '解决 Linux 内核 Section GC 失败问题 - Part 2'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - Section GC
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [spaces toc urls]
> Author:    Yuan Tan <tanyuan@tinylab.org>
> Date:      20230929
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 概述

本文为 [解决 Linux 内核 Section GC 失败问题][008] 系列文章的一部分。

- [Section GC 分析 - Part 1 原理简介][003]
- [Section GC 分析 - Part 2  gold 源码解析][004]
- [Section GC 分析 - Part 3 引用建立过程][005]
- [解决 Linux 内核 Section GC 失败问题 - Part 1][006]
- [解决 Linux 内核 Section GC 失败问题 - Part 2][007]

前面几篇文章介绍了 Section GC 的使用方法和原理，以及 Linux 内核中的 Section GC 失败问题。

要彻底解决这个问题，我们需要让 `.pushsection` 能够正确地建立引用关系，避免强制保留的使用，以杜绝依赖反转。

经过翻阅文档和社区的讨论，我们总结了两种能够手动建立引用关系的方法。

## 解决方案

### Section Group

在同一个 section group 中的节只要有一个节被保留，那么 group 中的所有节都会被保留，这是我们解决 Section GC 失败的有力工具。

section 所属的 section group 可以在汇编创建 section 的时候指定。

```assembly
.section name , "flags"G, @type, GroupName[, linkage]
```

或者使用 flag `?`，让该 section 跟随父 section 的 section group。

```assembly
.section name , "flags"?
```

现在的思路是：

1. 为父函数增加 section group 属性。
2. 使用 flag `?`，让 Pushed Section 跟随父 Section 的 section group。

这样两个节就能被同时保留。

有两种方法可以完成第一步，给 C 语言的函数添加 section group 属性。

- 方法一：

使用汇编指令 `.attach_to_group name`，在 section 已经创建完毕后为其添加 group。

```C
int fun1() {
  asm(".attach_to_group \"MyGroup\"");

  asm(".pushsection .test,\"ax?\",@progbits\n"
      ".string \"hello\"\n"
      ".popsection");
  return 0;
}

int main() {
  fun1();
  return 0;
}
```

```bash
$ riscv64-linux-gnu-gcc -ffunction-sections -Wl,--gc-sections example.c -c
$ riscv64-linux-gnu-readelf -g example.o

group section [    1] `.group' [MyGroup] contains 2 sections:
   [Index]    Name
   [    5]   .text.fun1
   [    6]   .test
$ riscv64-linux-gnu-gcc -ffunction-sections  -Wl,--gc-sections,--print-gc-sections example.c
ld: removing unused section '.rodata.cst4' in file '/usr/riscv64-linux-gnu/usr/lib/Scrt1.o'
ld: removing unused section '.riscv.attributes' in file '/usr/lib/gcc/riscv64-linux-gnu/12.2.0/crti.o'
ld: removing unused section '.riscv.attributes' in file '/usr/lib/gcc/riscv64-linux-gnu/12.2.0/crtn.o'
```

`.test` 没有被 GC，和 group 中的 `.text.main` 一起被保留了下来。

- 方法二：

不推荐该方法。

在 `__attribute__((section("section-name)))` 中写汇编，加入 flag 和 GroupName，然后用类似 SQL 注入的方式，手动添加 `#` 来截断编译器生成的该行后续的汇编代码。

```C
int __attribute__((section(".text.fun1,\"axG\",@progbits,\"MyGroup\" #")))fun1()
{
    asm(".pushsection .test1,\"axG\",@progbits,\"MyGroup\"\n"
    "        .string \"hello\"\n"
    ".popsection");
    return 0;
}
```

生成的汇编代码为：

```assembly
.section	.text.fun1,"axG",@progbits,"MyGroup" #,"ax",@progbits
```

汇编器实际上处理的是

```assembly
.section	.text.fun1,"axG",@progbits,"MyGroup"
```

#### 有缺陷的解决方案

上一篇文章中提到，`__ex_table` 的 `.pushsection` 引入了依赖反转问题，它的建立方式是这样定义的：

```C
// arch/riscv/include/asm/asm-extable.h:14

#define __ASM_EXTABLE_RAW(insn, fixup, type, data)	\
	".pushsection	__ex_table, \"a\"\n"		\
	".balign	4\n"				\
	".long		((" insn ") - .)\n"		\
	".long		((" fixup ") - .)\n"		\
	".short		(" type ")\n"			\
	".short		(" data ")\n"			\
	".popsection\n"
```

要让它和父函数在一个 section group 中，和父函数同时被保留下来，最简单的做法是，直接在该宏里增加 `.attach_to_group "GroupName"`，同时在 `.pushsection` 的 flag 中增加 `?`：

```c
#define __ASM_EXTABLE_RAW(insn, fixup, type, data)	\
	".attach_to_group GroupName" \
	".pushsection	__ex_table, \"a?\"\n"		\
	".balign	4\n"				\
	".long		((" insn ") - .)\n"		\
	".long		((" fixup ") - .)\n"		\
	".short		(" type ")\n"			\
	".short		(" data ")\n"			\
	".popsection\n"
```

这样无论该宏在何处展开，都会为 Section Pusher 增加一个 group，并且和 `.pushsection` 在同一个 group 中。

每个 Section Pusher 都应该处于不同的 group，否则一个 Section Pusher 被保留，其他没被使用到的 Section Pusher 也被保留了。

此外，这个宏可能会在一个函数内多次展开，即 Section Pusher 调用了多次 `.pushsection`，那么 Section Pusher 就会执行多次 `.attach_to_group`，链接器会产生警告。我们希望 `.attach_to_group` 在一个函数里只执行一次。

- 如果仅使用文件名作为 GroupName，并且使用 ifdef 来辅助判断当前 Section Pusher 是否已经在 group 中，如果不在，则 `.attach_to_group`。那么一个文件的所有函数都会加入一个 group 里，会被同时 GC 或者保留，不满足需求。
- 如果使用文件名和行号作为 GroupName，宏仍可能一个函数内展开多次，且无法判断当前 Section Pusher 是否在 group 中。

因此我们需要一个**函数级别**独特的字符串来作为 GroupName。就能使用 ifdef 来辅助判断当前 Section Pusher 是否已经在 group 中

函数名是做容易想到的方法，但是无论是 `__func__` 或者 `__FUNCTION__` 都不是宏，是在编译时候才能确定的。因此我们无法使用函数名来作为 GroupName。我们只能暂时使用类似文件名和行号的形式。

```
#define ___PASTE(a,b) a##b
#define __PASTE(a,b) ___PASTE(a,b)

#ifndef __UNIQUE_ID
# define __UNIQUE_ID __PASTE(__PASTE(__COUNTER__, _), __LINE__)
#endif

#define __ASM_EXTABLE_RAW(insn, fixup, type, data)	\
	".attach_to_group "__stringify(__UNIQUE_ID_Extable)"\n" \
	".pushsection	__ex_table, \"a?\"\n"		\
	".balign	4\n"				\
	".long		((" insn ") - .)\n"		\
	".long		((" fixup ") - .)\n"		\
	".short		(" type ")\n"			\
	".short		(" data ")\n"			\
	".popsection\n"
```

这样编译后会出现警告：

```
Warning: section .text.main already has a group (GroupName)
```

内核社区是不接受有警告的代码存在的，而且链接器并未提供选项来关闭这个警告，所以这个方案虽然能解决问题，但并不能合入主线。

### SHF_LINK_ORDER

查看 as 的 [文档][001]，可以查看 `.pushsection` 和 `.section` 的定义。

```
.pushsection name [, subsection] [, "flags"[, @type[,arguments]]]
.section name [, "flags"[, @type[,flag_specific_arguments]]]
```

`flags` 中有一个符合我们的要求：

```
o
section references a symbol defined in another section (the linked-to section) in the same file.

If flags contains the o flag, then the type argument must be present along with an additional field like this:

.section name,"flags"o,@type,SymbolName|SectionIndex
```

我们可以使用该 flag 来手动指定该 section 引用到了 Section Pusher，来建立引用。

```C
void unused_function() {
    return;
}

int main() {
    asm("Section_Pusher_Symbol:\n");
    asm(".pushsection .should_not_GC,\"ao\",@progbits,Section_Pusher_Symbol\n"
        ".popsection");
    return 0;
}
```

```
$ riscv64-linux-gnu-gcc -ffunction-sections -Wl,--gc-sections,--print-gc-sections example_shf.c
ld: removing unused section '.rodata.cst4' in file '/usr/lib/gcc-cross/riscv64-linux-gnu/11/../../../../riscv64-linux-gnu/lib/Scrt1.o'
ld: removing unused section '.riscv.attributes' in file '/usr/lib/gcc-cross/riscv64-linux-gnu/11/crti.o'
ld: removing unused section '.text.unused_function' in file '/tmp/cceocy7f.o'
ld: removing unused section '.riscv.attributes' in file '/usr/lib/gcc-cross/riscv64-linux-gnu/11/crtn.o'
```

在这段代码中，我们在 `main()` 中新建了一个 label `Section_Pusher_Symbol`，然后在 `.pushsection` 使用 `o` flag，指定为该 symbol。

可以看到，在增加了 `o` flag 后，pushsed section 没有被 GC，实现了项目目标。

## 在 Linux 内核中验证

Linux Lab 已经集成了基于上述两种方案的 Patch。切换到 Linux Lab 的 section-gc 分支即可进行验证。

```bash
git checkout section-gc
```

启用 dse feature 并编译：

```
make test b=riscv64/virt f=dse LINUX=v6.6-rc2
```

查看保留的系统调用数量：

```
$ nm build/riscv64/virt/linux/v6.6-rc2/vmlinux | grep "T __riscv_sys" | grep -v sys_ni_syscall | wc -l
40
```

结果表明，裁剪掉了许多系统调用，验证了方案可行性。

## 总结

这篇文章中我们提出了两种解决 Linux 内核 Section GC 失败问题方法。它们能在不产生副作用的情况下，避免 `KEEP` 的使用，让所有节建立正确的依赖关系，为链接器提供更多的信息。

## 参考资料

- [Section (Using as)][001]
- [\[PATCH 0/1\] gas: add new command line option --no-group-check][002]

[001]: https://sourceware.org/binutils/docs/as/Section.html
[002]: https://sourceware.org/pipermail/binutils/2023-July/128521.html
[003]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230526-section-gc-part1.md
[004]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230526-section-gc-part2.md
[005]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230615-section-gc-part3.md
[006]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230730-section-gc-no-more-keep-part1.md
[007]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230928-section-gc-no-more-keep-part2.md
[008]: https://summer-ospp.ac.cn/org/prodetail/2341f0584
