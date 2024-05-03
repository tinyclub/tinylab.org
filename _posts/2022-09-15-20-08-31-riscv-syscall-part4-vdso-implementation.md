---
layout: post
author: 'cc'
title: 'RISC-V Syscall 系列 4：vDSO 实现原理分析'
draft: false
plugin: 'mermaid'
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-syscall-part4-vdso-implementation/
description: 'RISC-V Syscall 系列 4：vDSO 实现原理分析'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - vDSO
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc1 - [images urls]
> Author:  envestcc <chen1233216@hotmail.com>
> Date:    2022/08/16
> Revisor: Falcon <falcon@tinylab.org>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Environment: [泰晓 Linux 实验盘](https://tinylab.org/linux-lab-disk/)
> Sponsor: PLCT Lab, ISCAS


## 概述

在上一篇文章 [什么是 vDSO][007] 中介绍了 vDSO 的相关背景和概念，本篇文章会进一步通过对 Linux 内核及 glibc 相关代码的研究，来分析 vDSO 的实现原理。

说明：文中涉及的 Linux 源码是基于 5.17 版本，glibc 是基于 2.35 版本。

## Build

Linux 内核中 vDSO 代码包括以下几部分：
* lib/vdso/：架构无关部分
  * gettimeofday.c
* arch/riscv/kernel/：架构相关部分
  * vdso.c：数据结构定义及初始化
  * vdso/：导出函数入口
    * flush_icache.S
    * getcpu.S
    * rt_sigreturn.S
    * vgettimeofday.c
    * vdso.S
    * vdso.lds.S

> 下面未加路径的文件默认路径为 arch/riscv/kernel/vdso

<pre><div class="mermaid">
flowchart LR;
J(lib/vdso/gettimeofday.c)-->F;
A(vgettimeofday.c)-->F(vdso.so.dbg / linux-vdso.so.1);
B(flush_icache.S)-->F;
C(getcpu.S)-->F;
D(rt_sigreturn.S)-->F;
M(note.S)-->F;
E(vdso.lds.S)-->F;
F-- objcopy -S --->G(vdso.so)
G-->H(vdso.o)
I(vdso.S)-- .incbin --->H
H-->K(kernel)
L(arch/riscv/kernel/vdso.c)-->K
</div></pre>
（[下载由 Mermaid 生成的 PNG 图片][008]）

上图描述了上述代码如何编译成 `linux-vdso.so.1` 及如何集成到内核中的大体流程。整个流程大致可以分为两个阶段：
1. 生成共享库 `linux-vdso.so.1`
2. 共享库集成到内核

下面会结合内核编译日志和内核源码一起分析整个构建过程。

### 生成共享库 linux-vdso.so.1

生成共享库主要分为两个阶段：
1. 编译生成 .o 文件
2. 链接生成 .so 共享库文件

#### 编译生成 .o 文件

在 Linux Lab 下，可通过 `make kernel arch/riscv/kernel/vdso/*.o V=1` 查看到生成 .o 的过程：

```sh
  riscv64-linux-gnu-gcc -E -Wp,-MMD,arch/riscv/kernel/vdso/.vdso.lds.d  -nostdinc -I./arch/riscv/include -I./arch/riscv/include/generated  -I./include -I./arch/riscv/include/uapi -I./arch/riscv/include/generated/uapi -I./include/uapi -I./include/generated/uapi -include ./include/linux/compiler-version.h -include ./include/linux/kconfig.h -D__KERNEL__ -fmacro-prefix-map=./=    -P -C -Uriscv -P -Uriscv -D__ASSEMBLY__ -DLINKER_SCRIPT -o arch/riscv/kernel/vdso/vdso.lds arch/riscv/kernel/vdso/vdso.lds.S
  riscv64-linux-gnu-gcc -Wp,-MMD,arch/riscv/kernel/vdso/.rt_sigreturn.o.d  -nostdinc -I./arch/riscv/include -I./arch/riscv/include/generated  -I./include -I./arch/riscv/include/uapi -I./arch/riscv/include/generated/uapi -I./include/uapi -I./include/generated/uapi -include ./include/linux/compiler-version.h -include ./include/linux/kconfig.h -D__KERNEL__ -fmacro-prefix-map=./= -D__ASSEMBLY__ -fno-PIE -mabi=lp64 -march=rv64imafdc -Wa,-gdwarf-2    -c -o arch/riscv/kernel/vdso/rt_sigreturn.o arch/riscv/kernel/vdso/rt_sigreturn.S
  riscv64-linux-gnu-gcc -Wp,-MMD,arch/riscv/kernel/vdso/.vgettimeofday.o.d  -nostdinc -I./arch/riscv/include -I./arch/riscv/include/generated  -I./include -I./arch/riscv/include/uapi -I./arch/riscv/include/generated/uapi -I./include/uapi -I./include/generated/uapi -include ./include/linux/compiler-version.h -include ./include/linux/kconfig.h -include ./include/linux/compiler_types.h -D__KERNEL__ -fmacro-prefix-map=./= -Wall -Wundef -Werror=strict-prototypes -Wno-trigraphs -fno-strict-aliasing -fno-common -fshort-wchar -fno-PIE -Werror=implicit-function-declaration -Werror=implicit-int -Werror=return-type -Wno-format-security -std=gnu89 -mabi=lp64 -march=rv64imac -mno-save-restore -DCONFIG_PAGE_OFFSET=0xffffaf8000000000 -mcmodel=medany -fno-omit-frame-pointer -mstrict-align -fno-delete-null-pointer-checks -Wno-frame-address -Wno-format-truncation -Wno-format-overflow -Wno-address-of-packed-member -O2 --param=allow-store-data-races=0 -Wframe-larger-than=2048 -fstack-protector-strong -Wimplicit-fallthrough=5 -Wno-main -Wno-unused-but-set-variable -Wno-unused-const-variable -fno-omit-frame-pointer -fno-optimize-sibling-calls -fno-stack-clash-protection -Wdeclaration-after-statement -Wvla -Wno-pointer-sign -Wcast-function-type -Wno-stringop-truncation -Wno-array-bounds -Wno-stringop-overflow -Wno-restrict -Wno-maybe-uninitialized -Wno-alloc-size-larger-than -fno-strict-overflow -fno-stack-check -fconserve-stack -Werror=date-time -Werror=incompatible-pointer-types -Werror=designated-init -Wno-packed-not-aligned -g -fno-stack-protector -fPIC -include /labs/linux-lab/src/linux-stable/lib/vdso/gettimeofday.c    -DKBUILD_MODFILE='"arch/riscv/kernel/vdso/vgettimeofday"' -DKBUILD_BASENAME='"vgettimeofday"' -DKBUILD_MODNAME='"vgettimeofday"' -D__KBUILD_MODNAME=kmod_vgettimeofday -c -o arch/riscv/kernel/vdso/vgettimeofday.o arch/riscv/kernel/vdso/vgettimeofday.c
  riscv64-linux-gnu-gcc -Wp,-MMD,arch/riscv/kernel/vdso/.getcpu.o.d  -nostdinc -I./arch/riscv/include -I./arch/riscv/include/generated  -I./include -I./arch/riscv/include/uapi -I./arch/riscv/include/generated/uapi -I./include/uapi -I./include/generated/uapi -include ./include/linux/compiler-version.h -include ./include/linux/kconfig.h -D__KERNEL__ -fmacro-prefix-map=./= -D__ASSEMBLY__ -fno-PIE -mabi=lp64 -march=rv64imafdc -Wa,-gdwarf-2    -c -o arch/riscv/kernel/vdso/getcpu.o arch/riscv/kernel/vdso/getcpu.S
  riscv64-linux-gnu-gcc -Wp,-MMD,arch/riscv/kernel/vdso/.flush_icache.o.d  -nostdinc -I./arch/riscv/include -I./arch/riscv/include/generated  -I./include -I./arch/riscv/include/uapi -I./arch/riscv/include/generated/uapi -I./include/uapi -I./include/generated/uapi -include ./include/linux/compiler-version.h -include ./include/linux/kconfig.h -D__KERNEL__ -fmacro-prefix-map=./= -D__ASSEMBLY__ -fno-PIE -mabi=lp64 -march=rv64imafdc -Wa,-gdwarf-2    -c -o arch/riscv/kernel/vdso/flush_icache.o arch/riscv/kernel/vdso/flush_icache.S
  riscv64-linux-gnu-gcc -Wp,-MMD,arch/riscv/kernel/vdso/.note.o.d  -nostdinc -I./arch/riscv/include -I./arch/riscv/include/generated  -I./include -I./arch/riscv/include/uapi -I./arch/riscv/include/generated/uapi -I./include/uapi -I./include/generated/uapi -include ./include/linux/compiler-version.h -include ./include/linux/kconfig.h -D__KERNEL__ -fmacro-prefix-map=./= -D__ASSEMBLY__ -fno-PIE -mabi=lp64 -march=rv64imafdc -Wa,-gdwarf-2    -c -o arch/riscv/kernel/vdso/note.o arch/riscv/kernel/vdso/note.S

```

从上述编译日志可以看出，首先 `vdso.lds.S` 是链接脚本文件，会通过 `gcc -E` 命令执行预处理。然后 `lib/vdso/gettimeofday.c`，`vgettimeofday.c`，`flush_icache.S`，`getcpu.S`，`rt_sigreturn.S`，`note.S` 这几个文件会通过 `gcc -c` 命令编译成 `.o` 文件。

#### 链接生成 .so 共享库文件

在 Linux Lab 下，可通过 `make kernel arch/riscv/kernel/vdso/vdso.so V=1` 查看到生成 .so 的过程：

```
riscv64-linux-gnu-ld  -melf64lriscv   -shared -S -soname=linux-vdso.so.1 --build-id=sha1 --hash-style=both --eh-frame-hdr -T arch/riscv/kernel/vdso/vdso.lds arch/riscv/kernel/vdso/rt_sigreturn.o arch/riscv/kernel/vdso/vgettimeofday.o arch/riscv/kernel/vdso/getcpu.o arch/riscv/kernel/vdso/flush_icache.o arch/riscv/kernel/vdso/note.o -o arch/riscv/kernel/vdso/vdso.so.dbg.tmp && riscv64-linux-gnu-objcopy  -G __vdso_rt_sigreturn  -G __vdso_vgettimeofday  -G __vdso_getcpu  -G __vdso_flush_icache arch/riscv/kernel/vdso/vdso.so.dbg.tmp arch/riscv/kernel/vdso/vdso.so.dbg && rm arch/riscv/kernel/vdso/vdso.so.dbg.tmp
```

通过把上一步生成的中间文件通过 `ld` 命令链接起来，最后生成 `vdso.so.dbg` 共享库文件。这里通过 `-soname=linux-vdso.so.1` 参数指定了库的真实名字。另外其中的 `objcopy -G` 命令是将本地函数变为全局函数，我理解现在的版本中已经不需要了，因为在后面的流程中，会移除静态符号表信息。

`vdso.so.dbg` 的真实名字就是 `linux-vdso.so.1`，也可以通过下面的命令进行验证：

```sh
$ readelf -d  /labs/linux-lab/build/riscv64/virt/linux/v5.17/arch/riscv/kernel/vdso/vdso.so.dbg

Dynamic section at offset 0x390 contains 14 entries:
  Tag        Type                         Name/Value
 0x000000000000000e (SONAME)             Library soname: [linux-vdso.so.1]
 0x0000000000000004 (HASH)               0x120
 0x000000006ffffef5 (GNU_HASH)           0x158
 0x0000000000000005 (STRTAB)             0x270
 0x0000000000000006 (SYMTAB)             0x198
 0x000000000000000a (STRSZ)              143 (bytes)
 0x000000000000000b (SYMENT)             24 (bytes)
 0x0000000000000007 (RELA)               0x0
 0x0000000000000008 (RELASZ)             0 (bytes)
 0x0000000000000009 (RELAENT)            24 (bytes)
 0x000000006ffffffc (VERDEF)             0x318
 0x000000006ffffffd (VERDEFNUM)          2
 0x000000006ffffff0 (VERSYM)             0x300
 0x0000000000000000 (NULL)               0x0
```

### 共享库集成到内核

```sh
riscv64-linux-gnu-objcopy -S  arch/riscv/kernel/vdso/vdso.so.dbg arch/riscv/kernel/vdso/vdso.so
```

先通过 `objcopy -S` 命令将 `vdso.so.dbg` 移除符号信息进而生成 `vdso.so`。这主要是为了减少集成到内核的代码大小。

```sh
$ readelf -sW /labs/linux-lab/build/riscv64/virt/linux/v5.17/arch/riscv/kernel/vdso/vdso.so.dbg

Symbol table '.dynsym' contains 9 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     ...
     __vdso_gettimeofday@@LINUX_4.15
     3: 0000000000000bee   122 FUNC    GLOBAL DEFAULT   11
     ...

Symbol table '.symtab' contains 29 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
    ...
    14: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS vgettimeofday.c
    15: 0000000000000000     0 FILE    LOCAL  DEFAULT  ABS
    16: fffffffffffff000     0 NOTYPE  LOCAL  DEFAULT  ABS _timens_data
    17: 0000000000000390     0 OBJECT  LOCAL  DEFAULT  ABS _DYNAMIC
    18: 0000000000000c80     0 OBJECT  LOCAL  DEFAULT  ABS _PROCEDURE_LINKAGE_TABLE_
    19: ffffffffffffe000     0 NOTYPE  LOCAL  DEFAULT    1 _vdso_data
    ...

$ readelf -sW /labs/linux-lab/build/riscv64/virt/linux/v5.17/arch/riscv/kernel/vdso/vdso.so

Symbol table '.dynsym' contains 9 entries:
   Num:    Value          Size Type    Bind   Vis      Ndx Name
     ...
     2: 0000000000000a64   394 FUNC    GLOBAL DEFAULT   11 __vdso_gettimeofday@@LINUX_4.15
     ...
```

通过上面两个命令输出的对比，能看出 `vdso.dbg.so` 生成 `vdso.so` 之后移除了静态符号表信息。

```sh
  riscv64-linux-gnu-gcc -Wp,-MMD,arch/riscv/kernel/.vdso.o.d  -nostdinc -I./arch/riscv/include -I./arch/riscv/include/generated  -I./include -I./arch/riscv/include/uapi -I./arch/riscv/include/generated/uapi -I./include/uapi -I./include/generated/uapi -include ./include/linux/compiler-version.h -include ./include/linux/kconfig.h -include ./include/linux/compiler_types.h -D__KERNEL__ -fmacro-prefix-map=./= -Wall -Wundef -Werror=strict-prototypes -Wno-trigraphs -fno-strict-aliasing -fno-common -fshort-wchar -fno-PIE -Werror=implicit-function-declaration -Werror=implicit-int -Werror=return-type -Wno-format-security -std=gnu89 -mabi=lp64 -march=rv64imac -mno-save-restore -DCONFIG_PAGE_OFFSET=0xffffaf8000000000 -mcmodel=medany -fno-omit-frame-pointer -mstrict-align -fno-delete-null-pointer-checks -Wno-frame-address -Wno-format-truncation -Wno-format-overflow -Wno-address-of-packed-member -O2 --param=allow-store-data-races=0 -Wframe-larger-than=2048 -fstack-protector-strong -Wimplicit-fallthrough=5 -Wno-main -Wno-unused-but-set-variable -Wno-unused-const-variable -fno-omit-frame-pointer -fno-optimize-sibling-calls -fno-stack-clash-protection -Wdeclaration-after-statement -Wvla -Wno-pointer-sign -Wcast-function-type -Wno-stringop-truncation -Wno-array-bounds -Wno-stringop-overflow -Wno-restrict -Wno-maybe-uninitialized -Wno-alloc-size-larger-than -fno-strict-overflow -fno-stack-check -fconserve-stack -Werror=date-time -Werror=incompatible-pointer-types -Werror=designated-init -Wno-packed-not-aligned -g    -DKBUILD_MODFILE='"arch/riscv/kernel/vdso"' -DKBUILD_BASENAME='"vdso"' -DKBUILD_MODNAME='"vdso"' -D__KBUILD_MODNAME=kmod_vdso -c -o arch/riscv/kernel/vdso.o arch/riscv/kernel/vdso.c

```

然后通过 `gcc` 命令将 `arch/riscv/kernel/vdso.c` 编译成 `arch/riscv/kernel/vdso.o` 文件。

```
  riscv64-linux-gnu-gcc -Wp,-MMD,arch/riscv/kernel/vdso/.vdso.o.d  -nostdinc -I./arch/riscv/include -I./arch/riscv/include/generated  -I./include -I./arch/riscv/include/uapi -I./arch/riscv/include/generated/uapi -I./include/uapi -I./include/generated/uapi -include ./include/linux/compiler-version.h -include ./include/linux/kconfig.h -D__KERNEL__ -fmacro-prefix-map=./= -D__ASSEMBLY__ -fno-PIE -mabi=lp64 -march=rv64imafdc -Wa,-gdwarf-2    -c -o arch/riscv/kernel/vdso/vdso.o arch/riscv/kernel/vdso/vdso.S
```

然后又通过 `gcc` 命令将 `vdso.S` 编译生成了 `vdso.o` 文件。`vdso.S` 文件内部其实就是通过 `.incbin` 将 `vdso.so` 共享库包含进来，同时设置一下内存页对齐。`vdso.S` 的代码如下：

```asm
#include <linux/init.h>
#include <linux/linkage.h>
#include <asm/page.h>

	__PAGE_ALIGNED_DATA

	.globl vdso_start, vdso_end
	.balign PAGE_SIZE
vdso_start:
	.incbin "arch/riscv/kernel/vdso/vdso.so"
	.balign PAGE_SIZE
vdso_end:

	.previous
```

> 注意这里的 `vdso.o` 文件和上一步生成的 `arch/riscv/kernel/vdso.o` 不在同一个目录下。

```sh
  riscv64-linux-gnu-ar cDPrST arch/riscv/kernel/vdso/built-in.a arch/riscv/kernel/vdso/vdso.o
  riscv64-linux-gnu-ar cDPrST arch/riscv/kernel/built-in.a arch/riscv/kernel/vdso.o arch/riscv/kernel/vdso/built-in.a ...
```

然后通过 `ar` 命令将 `vdso.o` 打包到 `built-in.a` 文件中，再将 `built-in.a` 和 `arch/riscv/kernel/vdso.o` 一起打包到 `arch/riscv/kernel/built-in.a` 文件中，最终被打包进内核中。

## vDSO 初始化

vDSO 的初始化按照触发时机可以分为两部分：
* 内核启动时初始化
* 用户进程启动时初始化

### 内核启动时初始化

内核启动时初始化的主要是 `vdso_info` 这个内核对象。它包含的主要信息包括：
* vDSO 代码在内核中的地址
* vDSO 数据在内核中的地址
* vDSO 代码部分虚拟内存映射结构
* vDSO 数据部分虚拟内存映射结构

`vdso_info` 源码中的相关定义如下：

```c
// arch/riscv/kernel/vdso.c
extern char vdso_start[], vdso_end[];

struct __vdso_info {
	const char *name;
	const char *vdso_code_start;  // vdso 代码起始地址
	const char *vdso_code_end;    // vdso 代码结束地址
	unsigned long vdso_pages;     // vdso 代码部分所占内存页数
	/* Data Mapping */
	struct vm_special_mapping *dm;
	/* Code Mapping */
	struct vm_special_mapping *cm;
};

// include/linux/mm_types.h
struct vm_special_mapping {
	const char *name;	/* The name, e.g. "[vdso]". */

	/*
	 * If .fault is not provided, this points to a
	 * NULL-terminated array of pages that back the special mapping.
	 *
	 * This must not be NULL unless .fault is provided.
	 */
	struct page **pages;

	/*
	 * If non-NULL, then this is called to resolve page faults
	 * on the special mapping.  If used, .pages is not checked.
	 */
	vm_fault_t (*fault)(const struct vm_special_mapping *sm,
				struct vm_area_struct *vma,
				struct vm_fault *vmf);

	int (*mremap)(const struct vm_special_mapping *sm,
		     struct vm_area_struct *new_vma);
};
```

vDSO 内核中代码部分地址初始化的时候，`vdso_code_start` 和 `vdso_code_end` 分别赋值了 `vdso_start` 和 `vdso_end`。它们声明成了外部引用，实际上 `vdso_start` 和 `vdso_end` 这两个变量定义在本文 `共享库集成到内核` 章节中提到的 `vdso.S` 文件中，它们表示了 vDSO 代码段的起始位置和结束位置。

vDSO 内核中数据部分的定义就是 `vdso_data`。它直接定义在内核代码中。

```c
// arch/riscv/kernel/vdso.c
static union {
	struct vdso_data	data;
	u8			page[PAGE_SIZE];
} vdso_data_store __page_aligned_data;
struct vdso_data *vdso_data = &vdso_data_store.data;

static struct __vdso_info vdso_info __ro_after_init = {
	.name = "vdso",
	.vdso_code_start = vdso_start,
	.vdso_code_end = vdso_end,
};
```

`dm` 和 `cm` 分别表示代码和数据部分的 `vm_special_mapping`（虚拟内存特殊映射对象）。

`cm` 使用定义在内核的静态变量 `rv_vdso_maps` 进行初始化，其中比较重要的 `pages` 内存页成员在 `__vdso_init` 函数中进行初始化，申请代码部分所占页数量的内存页，并建立虚拟内存和物理内存页映射。

```c
// arch/riscv/kernel/vdso.c
static struct vm_special_mapping rv_vdso_maps[] __ro_after_init = {
	[RV_VDSO_MAP_VVAR] = {
		.name   = "[vvar]",
		.fault = vvar_fault,
	},
	[RV_VDSO_MAP_VDSO] = {
		.name   = "[vdso]",
		.mremap = vdso_mremap,
	},
};

static int __init vdso_init(void)
{
	vdso_info.dm = &rv_vdso_maps[RV_VDSO_MAP_VVAR];
	vdso_info.cm = &rv_vdso_maps[RV_VDSO_MAP_VDSO];

	return __vdso_init();
}

static int __init __vdso_init(void)
{
	unsigned int i;
	struct page **vdso_pagelist;
	unsigned long pfn;

	if (memcmp(vdso_info.vdso_code_start, "\177ELF", 4)) {
		pr_err("vDSO is not a valid ELF object!\n");
		return -EINVAL;
	}

	vdso_info.vdso_pages = (
		vdso_info.vdso_code_end -
		vdso_info.vdso_code_start) >>
		PAGE_SHIFT;

	vdso_pagelist = kcalloc(vdso_info.vdso_pages,
				sizeof(struct page *),
				GFP_KERNEL);
	if (vdso_pagelist == NULL)
		return -ENOMEM;

	/* Grab the vDSO code pages. */
	pfn = sym_to_pfn(vdso_info.vdso_code_start);

	for (i = 0; i < vdso_info.vdso_pages; i++)
		vdso_pagelist[i] = pfn_to_page(pfn + i);

	vdso_info.cm->pages = vdso_pagelist;

	return 0;
}
```

`dm` 的初始化在 `vvar_fault` 函数中实现。`vvar_fault` 是 `dm` 缺页中断的回调函数。从代码中可以看出，实际映射的对象是上文中提到的内核定义的数据部分对象 `vdso_data`。

```c
// arch/riscv/kernel/vdso.c
static vm_fault_t vvar_fault(const struct vm_special_mapping *sm,
			     struct vm_area_struct *vma, struct vm_fault *vmf)
{
  ...
  pfn = sym_to_pfn(vdso_data);
  ...
}
```

### 用户进程启动时初始化

接下来是在用户进程启动时才会执行的初始化过程，主要的目的是初始化加速系统调用的几个函数指针，以达到用户程序调用 glibc 中支持 vDSO 函数时能够正确跳转到 vDSO 相应的代码地址。

但是程序启动过程有些复杂，涉及到 vDSO 相关的大致可以分为三个阶段：
1. 在内核态执行 execve 系统调用，将 vDSO 代码和数据映射到用户内存，并将代码地址记录在用户栈内存中
2. 在用户态执行 dynamic linker，找到 vDSO 代码地址并加载，初始化 vDSO 函数的地址
3. 在用户态执行 libc init，针对静态链接的程序进行初始化 vDSO 函数的地址

![vdso_setup](/wp-content/uploads/2022/03/riscv-linux/images/riscv_syscall/vdso_setup.png)
> 图片来自 [Unified_vDSO_LPC_2020][1]

#### execve

在 Linux 系统中，运行一个程序依赖 `fork` 和 `execve` 这两个系统调用。`fork` 会创建一个新进程并复制父进程的数据到新进程中；而 `execve` 则是解析 ELF 文件，将其载入内存，并修改进程的堆栈数据来准备运行环境。而 vDSO 的初始化功能也是在 `execve` 中完成的。

```c
// fs/exec.c
SYSCALL_DEFINE3(execve,
		const char __user *, filename,
		const char __user *const __user *, argv,
		const char __user *const __user *, envp)
{
	return do_execve(getname(filename), argv, envp);
}
```

`SYSCALL_DEFINE3` 是定义系统调用的宏，详情可以参考本系列之前的文章 [RISC-V Syscall 系列 2：Syscall 过程分析][006]。

`execve` 会先经过如下函数调用到达 `load_elf_binary`：
1. `do_execve`
2. `do_execveat_common`：初始化环境和启动参数信息
3. `bprm_execve`：打开文件，使调度器负载均衡等
4. `exec_binprm`
5. `search_binary_handler`：寻找文件格式对应的解析模块
6. `fmt->load_binary()`：调用格式对应的载入函数

而对于 ELF 文件来说，`load_binary` 就是 `load_elf_binary`，下面是 ELF 文件格式载入函数的初始化代码和 `load_elf_binary` 函数代码。

```c
// fs/binfmt_elf.c
static struct linux_binfmt elf_format = {
	.module		= THIS_MODULE,
	.load_binary	= load_elf_binary,
	.load_shlib	= load_elf_library,
	.core_dump	= elf_core_dump,
	.min_coredump	= ELF_EXEC_PAGESIZE,
};

static int load_elf_binary(struct linux_binprm *bprm)
{
  ...
  retval = ARCH_SETUP_ADDITIONAL_PAGES(bprm, elf_ex, !!interpreter);
  ...
  retval = create_elf_tables(bprm, elf_ex,load_addr, interp_load_addr, e_entry);
  ...
}

// include/linux/elf.h
#define ARCH_SETUP_ADDITIONAL_PAGES(bprm, ex, interpreter) arch_setup_additional_pages(bprm, interpreter)
```

`load_elf_binary` 函数内容比较庞大，实现了加载 ELF 文件的核心逻辑。其中跟 vDSO 初始化相关的有如下两个函数：
1. `arch_setup_additional_pages`
2. `create_elf_tables`

##### arch_setup_additional_pages

`arch_setup_additional_pages` 是处理器架构相关的函数，里面主要调用了 `__setup_additional_pages`，它的主要功能是将 vDSO 的代码部分 (text) 和数据部分（vvar）载入用户内存。具体代码如下：

```c
// arch/riscv/kernel/vdso.c
enum vvar_pages {
	VVAR_DATA_PAGE_OFFSET,
	VVAR_TIMENS_PAGE_OFFSET,
	VVAR_NR_PAGES,
};

#define VVAR_SIZE  (VVAR_NR_PAGES << PAGE_SHIFT)

int arch_setup_additional_pages(struct linux_binprm *bprm, int uses_interp)
{
  ...
  ret = __setup_additional_pages(mm, bprm, uses_interp);
  ...
}

static int __setup_additional_pages(struct mm_struct *mm, struct linux_binprm *bprm, int uses_interp)
{
  unsigned long vdso_base, vdso_text_len, vdso_mapping_len;
  void *ret;

  BUILD_BUG_ON(VVAR_NR_PAGES != __VVAR_PAGES);

  vdso_text_len = vdso_info.vdso_pages << PAGE_SHIFT;
  /* Be sure to map the data page */
  vdso_mapping_len = vdso_text_len + VVAR_SIZE;

  vdso_base = get_unmapped_area(NULL, 0, vdso_mapping_len, 0, 0);
  if (IS_ERR_VALUE(vdso_base)) {
    ret = ERR_PTR(vdso_base);
    goto up_fail;
  }

  ret = _install_special_mapping(mm, vdso_base, VVAR_SIZE,
    (VM_READ | VM_MAYREAD | VM_PFNMAP), vdso_info.dm);
  if (IS_ERR(ret))
    goto up_fail;

  vdso_base += VVAR_SIZE;
  mm->context.vdso = (void *)vdso_base;
  ret =
      _install_special_mapping(mm, vdso_base, vdso_text_len,
    (VM_READ | VM_EXEC | VM_MAYREAD | VM_MAYWRITE | VM_MAYEXEC),
    vdso_info.cm);

  if (IS_ERR(ret))
    goto up_fail;

  return 0;

up_fail:
	mm->context.vdso = NULL;
	return PTR_ERR(ret);
}
```

首先计算 vDSO 映射需要占用的内存空间大小 `vdso_mapping_len`。它由 `vdso_text_len` 代码部分和 `VVAR_SIZE` 数据部分相加得到。`vdso_text_len` 很显然可以由 `vdso_info.vdso_pages` 代码段所占内存页数乘以内存页大小计算得到，而代码中 `vdso_info.vdso_pages << PAGE_SHIFT` 的计算可以达到相同的效果。而通过查看 `VVAR_SIZE` 的定义可知，目前内核给 vDSO 数据部分分配了两个内存页。

然后调用 `get_unmapped_area` 内核接口在当前进程的用户空间中获取一个为映射区间的起始地址，其中第三个参数表示获取的为映射空间的大小。

然后调用 `_install_special_mapping` 将 vDSO 的数据部分映射到用户内存中。这里的第四个参数可以设置内存页的访问标记，这里可以简单理解为用户程序对 vDSO 的数据部分是只读的，具体分别设置了三个值：

* VM_READ：内存页可读取
* VM_MAYREAD：VM_READ 标志可被设置
* VM_PFNMAP：Page-ranges managed without "struct page", just pure PFN

最后再次调用 `_install_special_mapping` 将 vDSO 的代码部分映射到用户内存中，位置紧接着数据部分。与数据页标记不同，用户程序对代码部分是可读可执行的，具体设置了五个值：

* VM_READ：内存页可读取
* VM_EXEC：内存页可执行
* VM_MAYREAD：VM_READ 标志可被设置
* VM_MAYWRITE：VM_WRITE 标志可被设置
* VM_MAYEXEC：VM_EXEC 标志可被设置

##### create_elf_tables

`create_elf_tables` 主要负责添加需要的信息到应用程序用户栈中，包括 `auxiliary vector`（辅助向量），`argv`（命令行参数），`environ`（环境变量）。而 vDSO 的地址信息就写入了 `auxiliary vector`。

`auxiliary vector` 是一种用户态和内核态之间通信的一种机制。本质上来说，它是由一系列键值对组成的一个列表。内核在加载应用程序时会将其存储在用户栈上。可以通过在运行程序时添加 `LD_SHOW_AUXV` 环境变量来查看列表的具体内容，其中 `AT_SYSINFO_EHDR` 对应的就是 vDSO 代码部分的起始地址。示例如下：

```sh
$ LD_SHOW_AUXV=1 sleep 1
AT_SYSINFO_EHDR:      0x7fff9d185000
AT_HWCAP:             bfebfbff
AT_PAGESZ:            4096
AT_CLKTCK:            100
AT_PHDR:              0x55c64e14c040
AT_PHENT:             56
AT_PHNUM:             13
AT_BASE:              0x7fd3399b8000
AT_FLAGS:             0x0
AT_ENTRY:             0x55c64e14e850
AT_UID:               1000
AT_EUID:              1000
AT_GID:               1000
AT_EGID:              1000
AT_SECURE:            0
AT_RANDOM:            0x7fff9d111309
AT_HWCAP2:            0x2
AT_EXECFN:            /usr/bin/sleep
AT_PLATFORM:          x86_64
```

`create_elf_tables` 的具体代码如下：

```c
// fs/binfmt_elf.c
static int create_elf_tables(struct linux_binprm *bprm, const struct elfhdr *exec, unsigned long load_addr, unsigned long interp_load_addr,unsigned long e_entry)
{
  ...
  elf_info = (elf_addr_t *)mm->saved_auxv;
  #define NEW_AUX_ENT(id, val) \
	do { \
		*elf_info++ = id; \
		*elf_info++ = val; \
	} while (0)
  ...
  ARCH_DLINFO;
  ...
}
```

`NEW_AUX_ENT` 是一个用来给 `auxiliary vector` 添加健值对的宏，其中 `elf_info` 的实际是指向 `unsigned long saved_auxv[AT_VECTOR_SIZE]` 这样一个存储在 `mm` 中的一个数组，每两个元素组成一个键值对。

`ARCH_DLINFO` 是一个初始化多个键值对的宏定义，展开如下：

```c
// arch/riscv/include/asm/elf.h
#define ARCH_DLINFO						\
do {								\
	NEW_AUX_ENT(AT_SYSINFO_EHDR,				\
		(elf_addr_t)current->mm->context.vdso);		\
	...
} while (0)
```

可以看出，这里将 `AT_SYSINFO_EHDR` 对应的值赋值成了 `mm->context.vdso`，而根据上文中列出的 `__setup_additional_pages` 函数代码，可以看出实际上赋值的就是 vDSO 代码部分的起始地址。

##### start_thread

```c
// fs/binfmt_elf.c
#define START_THREAD(elf_ex, regs, elf_entry, start_stack) start_thread(regs, elf_entry, start_stack)
START_THREAD(elf_ex, regs, elf_entry, bprm->p);

// arch/riscv/kernel/process.c
void start_thread(struct pt_regs *regs, unsigned long pc,
	unsigned long sp)
{
  ...
	regs->epc = pc;
	regs->sp = sp;
}
```

最后，`start_thread` 会将 epc 和 sp 改成新的地址，使得 execve 系统调用返回到用户空间时就能进入新的程序入口。

```c
// fs/binfmt_elf.c
static int load_elf_binary(struct linux_binprm *bprm)
{
  ...
  e_entry = elf_ex->e_entry + load_bias;
  ...
  if (interpreter) {
		elf_entry = load_elf_interp(interp_elf_ex,interpreter,load_bias, interp_elf_phdata,&arch_state);
    ...
  } else {
    elf_entry = e_entry;
    ...
  }
  ...
}
```

根据上述代码所示，程序入口 `elf_entry` 的取值分以下两种情况：
* 需要载入解释器（有动态链接的依赖库）：就通过 `load_elf_interp` 载入解释器，并返回值（解释器的入口地址）赋值给 `elf_entry`
* 不需要载入解释器（静态链接依赖库）：`elf_entry` 取值为当前 ELF 本身的入口地址

#### dynamic linker

当应用程序有依赖共享库时，程序启动时会进入 `dynamic linker`。

`dynamic linker` 位于 glibc 的代码中，执行时会经过如下函数调用到达 `dl_main`：
* `_dl_start` (elf/rtld.c)
* `_dl_start_final`
* `_dl_sysdep_start`
* `dl_main`

`dl_main` 函数中跟 vDSO 初始化相关的有 `setup_vdso` 和 `setup_vdso_pointers` 两个函数调用。

`setup_vdso` 会初始化 vDSO 相关的数据结构，其中就包含 `_dl_sysinfo_map`，它在后面的 `setup_vdso_pointers` 中会用到。

```c
// elf/setup-vdso.h
static inline void __attribute__ ((always_inline)) setup_vdso (struct link_map *main_map __attribute__ ((unused)), struct link_map ***first_preload __attribute__ ((unused)))
{
  ...
  l->l_phdr = ((const void *) GLRO(dl_sysinfo_dso) + GLRO(dl_sysinfo_dso)->e_phoff);
  l->l_phnum = GLRO(dl_sysinfo_dso)->e_phnum;
  ...
  GLRO(dl_sysinfo_map) = l;
  ...
}
```

`setup_vdso_pointers` 用来初始化 vDSO 相关函数指针。

```c
// sysdeps/unix/sysv/linux/dl-vdso-setup.h

/* Initialize the VDSO functions pointers.  */
static inline void __attribute__ ((always_inline))
setup_vdso_pointers (void)
{
...
#ifdef HAVE_CLOCK_GETTIME64_VSYSCALL
  GLRO(dl_vdso_clock_gettime64) = dl_vdso_vsym (HAVE_CLOCK_GETTIME64_VSYSCALL);
#endif
#ifdef HAVE_GETTIMEOFDAY_VSYSCALL
  GLRO(dl_vdso_gettimeofday) = dl_vdso_vsym (HAVE_GETTIMEOFDAY_VSYSCALL);
#endif
#ifdef HAVE_CLOCK_GETRES64_VSYSCALL
  GLRO(dl_vdso_clock_getres_time64) = dl_vdso_vsym (HAVE_CLOCK_GETRES64_VSYSCALL);
#endif

}

// string/test-string.h
#define GLRO(x) _##x

// sysdeps/unix/sysv/linux/riscv/sysdep.h
/* List of system calls which are supported as vsyscalls only
   for RV64.  */
```

`GLRO` 将变量名前加上下划线（例如 `GLRO(dl_vdso_gettimeofday)` 表示 `_dl_vdso_gettimeofday`），其变量类型是函数指针，具体定义如下：

```c
// sysdeps/unix/sysv/linux/dl-vdso-setup.c
PROCINFO_CLASS int (*_dl_vdso_clock_gettime64) (clockid_t,
						struct __timespec64 *) RELRO;
#endif
PROCINFO_CLASS int (*_dl_vdso_gettimeofday) (struct timeval *, void *) RELRO;
#endif
PROCINFO_CLASS int (*_dl_vdso_clock_getres_time64) (clockid_t,
						    struct __timespec64 *) RELRO;
```

`dl_vdso_vsym` 会根据 `_dl_sysinfo_map` 这个对象找到指定函数名在 vDSO 中的地址并返回。

```c
// sysdeps/unix/sysv/linux/dl-vdso.h

/* Functions for resolving symbols in the VDSO link map.  */
static inline void *
dl_vdso_vsym (const char *name)
{
  struct link_map *map = GLRO (dl_sysinfo_map);
  if (map == NULL)
    return NULL;

  /* Use a WEAK REF so we don't error out if the symbol is not found.  */
  ElfW (Sym) wsym = { 0 };
  wsym.st_info = (unsigned char) ELFW (ST_INFO (STB_WEAK, STT_NOTYPE));

  struct r_found_version rfv = { VDSO_NAME, VDSO_HASH, 1, NULL };

  /* Search the scope of the vdso map.  */
  const ElfW (Sym) *ref = &wsym;
  lookup_t result = GLRO (dl_lookup_symbol_x) (name, map, &ref,
					       map->l_local_scope,
					       &rfv, 0, 0, NULL);
  return ref != NULL ? DL_SYMBOL_ADDRESS (result, ref) : NULL;
}

// include/link.h

/* Structure describing a loaded shared object.  The `l_next' and `l_prev'
   members form a chain of all the shared objects loaded at startup.

   These data structures exist in space used by the run-time dynamic linker;
   modifying them may have disastrous results.

   This data structure might change in future, if necessary.  User-level
   programs must avoid defining objects of this type.  */

struct link_map {...}
```

根据上面的 `setup_vdso` 函数代码可以看出，我们根据 `_dl_sysinfo_dso` 结构的信息对 `_dl_sysinfo_map` 结构进行初始化。

而 `_dl_sysinfo_dso` 的初始化函数由上至下依次调用路径如下：
* `_dl_start_final`（elf/rtld.c）
* `_dl_sysdep_start`（sysdeps/unix/sysv/linux/dl-sysdep.c）
* `_dl_sysdep_parse_arguments`（sysdeps/unix/sysv/linux/dl-sysdep.c）
* `_dl_parse_auxv`（sysdeps/unix/sysv/linux/dl-parse-auxv.h）

在 `_dl_sysdep_parse_arguments` 函数中，找到辅助向量的位置并作为参数传递给 `_dl_parse_auxv`。

![auxvec memory layout](/wp-content/uploads/2022/03/riscv-linux/images/riscv_syscall/auxvec.png)
（图片源自 LWN.net）

辅助向量在内存中的位置如上图所示，所以只要从栈顶开始，越过 argv（命令行参数）和 environ（环境变量）就能找到辅助向量的地址。

```c
// sysdeps/unix/sysv/linux/dl-sysdep.c
static void _dl_sysdep_parse_arguments (void **start_argptr, struct dl_main_arguments *args)
{
  _dl_argc = (intptr_t) *start_argptr;
  _dl_argv = (char **) (start_argptr + 1); /* Necessary aliasing violation.  */
  _environ = _dl_argv + _dl_argc + 1;
  for (char **tmp = _environ; ; ++tmp)
    if (*tmp == NULL)
      {
	/* Another necessary aliasing violation.  */
	GLRO(dl_auxv) = (ElfW(auxv_t) *) (tmp + 1);
	break;
      }

  dl_parse_auxv_t auxv_values = { 0, };
  _dl_parse_auxv (GLRO(dl_auxv), auxv_values);

  args->phdr = (const ElfW(Phdr) *) auxv_values[AT_PHDR];
  args->phnum = auxv_values[AT_PHNUM];
  args->user_entry = auxv_values[AT_ENTRY];
}
```

`_dl_parse_auxv` 函数将辅助向量的信息存储到 `AUXV_VALUES` 中，并初始化 GLRO 变量，这其中就包括 `_dl_sysinfo_dso`。

```c
// sysdeps/unix/sysv/linux/dl-parse-auxv.h
typedef ElfW(Addr) dl_parse_auxv_t[AT_MINSIGSTKSZ + 1];
/* Copy the auxiliary vector into AUXV_VALUES and set up GLRO
   variables.  */
static inline void _dl_parse_auxv (ElfW(auxv_t) *av, dl_parse_auxv_t auxv_values)
{
...
  for (; av->a_type != AT_NULL; av++)
    if (av->a_type <= AT_MINSIGSTKSZ)
      auxv_values[av->a_type] = av->a_un.a_val;

  GLRO(dl_sysinfo_dso) = (void *) auxv_values[AT_SYSINFO_EHDR];
...
}
```

在 `setup_vdso_pointers` 函数里初始化的函数指针是 `_dl_vdso_gettimeofday`，它跟我们使用的 `gettimeofday` 又有什么关系？

```c
// sysdeps/unix/sysv/linux/gettimeofday.c
int __gettimeofday (struct timeval *restrict tv, void *restrict tz)
{
  if (__glibc_unlikely (tz != 0))
    memset (tz, 0, sizeof *tz);

  return INLINE_VSYSCALL (gettimeofday, 2, tv, tz);
}

weak_alias (__gettimeofday, gettimeofday)
```
`gettimeofday` 实际是 `__gettimeofday` 的别名，而 `__gettimeofday` 内部实际调用的是 `INLINE_VSYSCALL`。

```c
// sysdeps/unix/sysv/linux/sysdep-vdso.h
     funcptr (args)

#define INLINE_VSYSCALL(name, nr, args...)				      \
  ({									      \
    __label__ out;							      \
    __label__ iserr;							      \
    long int sc_ret;							      \
									      \
    __typeof (GLRO(dl_vdso_##name)) vdsop = GLRO(dl_vdso_##name);	      \
    if (vdsop != NULL)							      \
      {									      \
	sc_ret = INTERNAL_VSYSCALL_CALL (vdsop, nr, ##args);	      	      \
	if (!INTERNAL_SYSCALL_ERROR_P (sc_ret))			      	      \
	  goto out;							      \
	if (INTERNAL_SYSCALL_ERRNO (sc_ret) != ENOSYS)		      	      \
	  goto iserr;							      \
      }									      \
									      \
    sc_ret = INTERNAL_SYSCALL_CALL (name, ##args);		      	      \
    if (INTERNAL_SYSCALL_ERROR_P (sc_ret))			      	      \
      {									      \
      iserr:								      \
        __set_errno (INTERNAL_SYSCALL_ERRNO (sc_ret));		      	      \
        sc_ret = -1L;							      \
      }									      \
  out:									      \
    sc_ret;								      \
  })
```

从上面的宏定义可以看出，`INLINE_VSYSCALL (gettimeofday, 2, tv, tz)` 实际上是执行 `_dl_vdso_gettimeofday(tv, tz)`。而 `_dl_vdso_gettimeofday` 就是 `setup_vdso_pointers` 里初始化的函数指针。

#### libc init

而对那些静态链接的程序来说，虽然不会执行上述 dynamic linker，但会在应用程序开始部分进行类似的初始化过程。而初始化的关键在于，从辅助向量中找到 vDSO 地址并初始化对应的函数指针。

大致的初始化过程如下：

* `ENTRY_POINT` / `_start`（sysdeps/riscv/start.S）
  * `__libc_start_main@plt`
    * `LIBC_START_MAIN` / `__libc_start_main_impl`（csu/libc-start.c）
      * `_dl_aux_init`（elf/dl-support.c）
        * `_dl_parse_auxv`（sysdeps/unix/sysv/linux/dl-parse_auxv.h）
      * `__libc_init_first`（csu/init-first.c）
        * `_dl_non_dynamic_init`（elf/dl-support.c）
          * `setup_vdso`
          * `setup_vdso_pointers`

从上面的调用过程可以看出，最终也是通过执行 `_dl_parse_auxv`，`setup_vdso`，`setup_vdso_pointers` 这几个关键函数进行 vDSO 的初始化。

至此 vDSO 的初始化部分就完成了。先小结一下，经过上述过程的初始化，目前准备就绪的有：
* vDSO 的代码和数据均在用户内存中完成映射
* 用户内存中的加速系统调用的函数指针已经指向 vDSO
* 内核中可以使用 `vdso_data` 对象访问 vDSO 数据部分
* 用户态中可以使用 `_vdso_data` 对象访问 vDSO 数据部分（这部分会在下文中阐述）

## vDSO Read & Write

vDSO 初始化完成后，就可以对其数据部分进行读写操作了。

![vdso implement](/wp-content/uploads/2022/03/riscv-linux/images/riscv_syscall/vdso_implement.jpeg)
> 图片来自 [Unified_vDSO_LPC_2020][1]

### read

当用户程序需要读取系统时间的时候，一般会调用 glibc 中提供的 `gettimeofday` 方法，该方法会通过上一节中设置好的相关变量，找到 vDSO 中对应函数 `__vdso_gettimeofday` 并执行调用。

```c
// arch/riscv/kernel/vdso/vgettimeofday.c
int __vdso_gettimeofday(struct __kernel_old_timeval *tv, struct timezone *tz)
{
	return __cvdso_gettimeofday(tv, tz);
}

// lib/vdso/gettimeofday.c
static __maybe_unused int
__cvdso_gettimeofday(struct __kernel_old_timeval *tv, struct timezone *tz)
{
	return __cvdso_gettimeofday_data(__arch_get_vdso_data(), tv, tz);
}
```

`__vdso_gettimeofday` 函数直接调用了 `__cvdso_gettimeofday`，`__cvdso_gettimeofday` 里面涉及两个函数：
* `__arch_get_vdso_data`：获取 vDSO 数据部分地址
* `__cvdso_gettimeofday_data`：获取系统时间具体逻辑

#### __arch_get_vdso_data

```c
// arch/riscv/include/asm/vdso/gettimeofday.h
static __always_inline const struct vdso_data *__arch_get_vdso_data(void)
{
	return _vdso_data;
}
```

`__arch_get_vdso_data` 里面直接返回 `_vdso_data` 变量，说明该变量存储的是用户态中 vDSO 数据部分内存地址。那它是如何初始化的呢？

```asm
// arch/riscv/kernel/vdso/vdso.lds.S
PROVIDE(_vdso_data = . - __VVAR_PAGES * PAGE_SIZE);
```
```c
// arch/riscv/include/asm/vdso.h
#define __VVAR_PAGES    2

// arch/riscv/include/asm/page.h
#define PAGE_SHIFT	(12)
#define PAGE_SIZE	(_AC(1, UL) << PAGE_SHIFT)
```

首先，在本文 Build 章节中提到，`vdso.lds.S` 用于生成 `vdso.so.dbg` 共享库文件，这个链接脚本里对 `_vdso_data` 进行了初始化，具体赋值成了 `- 2 * 4096`。这个值可以通过查看 `vdso.so.dbg` 库文件进行验证：

```sh
$ readelf -s /labs/linux-lab/build/riscv64/virt/linux/v5.17/arch/riscv/kernel/vdso/vdso.so.dbg | grep _vdso_data
    19: ffffffffffffe000     0 NOTYPE  LOCAL  DEFAULT    1 _vdso_data
```

我们知道共享库加载进内存后需要进行地址重定位，操作系统通过上文提到的 `setup_vdso` 对 vDSO 执行重定位。

```c
// elf/setup-vdso.h
static inline void __attribute__ ((always_inline))
setup_vdso (struct link_map *main_map __attribute__ ((unused)), struct link_map ***first_preload __attribute__ ((unused)))
{
  ...
  l->l_map_start = (ElfW(Addr)) GLRO(dl_sysinfo_dso);
  ...
}
```

从上面的代码来看，重定位的起始地址被赋值成了 `_dl_sysinfo_dso`。而根据本文之前的描述，`_dl_sysinfo_dso` 在用户进程启动时会初始化为 vDSO 代码部分的起始地址，所以重定向后的 `_vdso_data = _dl_sysinfo_dso - __VVAR_PAGES * PAGE_SIZE`。而 vDSO 数据部分正好位于代码部分之前，所以 `_vdso_data` 就被初始化为 vDSO 数据部分起始地址。

#### __cvdso_gettimeofday_data

`__cvdso_gettimeofday_data` 函数实现逻辑主要分两部分：
* 优先调用 `do_hres` 函数从 `_vdso_data` 中获取系统时间
* 如果 `do_hres` 返回失败，则调用 `gettimeofday_fallback` 执行系统调用

```c
// lib/vdso/gettimeofday.c
static __maybe_unused int
__cvdso_gettimeofday_data(const struct vdso_data *vd,
			  struct __kernel_old_timeval *tv, struct timezone *tz)
{

	if (likely(tv != NULL)) {
		struct __kernel_timespec ts;

		if (do_hres(&vd[CS_HRES_COARSE], CLOCK_REALTIME, &ts))
			return gettimeofday_fallback(tv, tz);

		tv->tv_sec = ts.tv_sec;
		tv->tv_usec = (u32)ts.tv_nsec / NSEC_PER_USEC;
	}
	...
}

static __always_inline int do_hres(const struct vdso_data *vd, clockid_t clk, struct __kernel_timespec *ts)
{
	const struct vdso_timestamp *vdso_ts = &vd->basetime[clk];
  ...
  ns = vdso_ts->nsec;
  sec = vdso_ts->sec;
  ...
  ts->tv_sec = sec + __iter_div_u64_rem(ns, NSEC_PER_SEC, &ns);
	ts->tv_nsec = ns;
  return 0;
}
```

```c
// arch/riscv/include/asm/vdso/gettimeofday.h
static __always_inline
int gettimeofday_fallback(struct __kernel_old_timeval *_tv,
			  struct timezone *_tz)
{
	register struct __kernel_old_timeval *tv asm("a0") = _tv;
	register struct timezone *tz asm("a1") = _tz;
	register long ret asm("a0");
	register long nr asm("a7") = __NR_gettimeofday;

	asm volatile ("ecall\n"
		      : "=r" (ret)
		      : "r"(tv), "r"(tz), "r"(nr)
		      : "memory");

	return ret;
}
```

### write

vDSO 数据部分的更新按照触发的方式可以分为以下两种情况：
* 时钟中断时更新（timekeeping_update）
* 应用程序主动触发（settimeofday）

#### timekeeping_update

当发生时钟中断时，中断处理程序会调用 `timekeeping_update`，进一步调用 `update_vsyscall` 来更新 vDSO 中系统时间信息。

```c
// kernel/time/timekeeping.c
static void timekeeping_update(struct timekeeper *tk, unsigned int action)
{
	...
	update_vsyscall(tk);
  ...
}
```

`update_vsyscall` 函数里通过调用 `__arch_get_k_vdso_data` 获取内核中 vDSO 数据对象。

```c
// kernel/time/vsyscall.c
void update_vsyscall(struct timekeeper *tk)
{
	struct vdso_data *vdata = __arch_get_k_vdso_data();
	struct vdso_timestamp *vdso_ts;
	s32 clock_mode;
	u64 nsec;

	/* copy vsyscall data */
	vdso_write_begin(vdata);

	clock_mode = tk->tkr_mono.clock->vdso_clock_mode;
	vdata[CS_HRES_COARSE].clock_mode	= clock_mode;
	vdata[CS_RAW].clock_mode		= clock_mode;

	/* CLOCK_REALTIME also required for time() */
	vdso_ts		= &vdata[CS_HRES_COARSE].basetime[CLOCK_REALTIME];
	vdso_ts->sec	= tk->xtime_sec;
	vdso_ts->nsec	= tk->tkr_mono.xtime_nsec;

	/* CLOCK_REALTIME_COARSE */
	vdso_ts		= &vdata[CS_HRES_COARSE].basetime[CLOCK_REALTIME_COARSE];
	vdso_ts->sec	= tk->xtime_sec;
	vdso_ts->nsec	= tk->tkr_mono.xtime_nsec >> tk->tkr_mono.shift;

	/* CLOCK_MONOTONIC_COARSE */
	vdso_ts		= &vdata[CS_HRES_COARSE].basetime[CLOCK_MONOTONIC_COARSE];
	vdso_ts->sec	= tk->xtime_sec + tk->wall_to_monotonic.tv_sec;
	nsec		= tk->tkr_mono.xtime_nsec >> tk->tkr_mono.shift;
	nsec		= nsec + tk->wall_to_monotonic.tv_nsec;
	vdso_ts->sec	+= __iter_div_u64_rem(nsec, NSEC_PER_SEC, &vdso_ts->nsec);

	/*
	 * Read without the seqlock held by clock_getres().
	 * Note: No need to have a second copy.
	 */
	WRITE_ONCE(vdata[CS_HRES_COARSE].hrtimer_res, hrtimer_resolution);

	/*
	 * If the current clocksource is not VDSO capable, then spare the
	 * update of the high resolution parts.
	 */
	if (clock_mode != VDSO_CLOCKMODE_NONE)
		update_vdso_data(vdata, tk);

	__arch_update_vsyscall(vdata, tk);

	vdso_write_end(vdata);

	__arch_sync_vdso_data(vdata);
}
```

`__arch_get_k_vdso_data` 实际返回的是 `vdso_data` 对象。

```c
// arch/riscv/include/asm/vdso/vsyscall.h
/*
 * Update the vDSO data page to keep in sync with kernel timekeeping.
 */
static __always_inline struct vdso_data *__riscv_get_k_vdso_data(void)
{
	return vdso_data;
}

#define __arch_get_k_vdso_data __riscv_get_k_vdso_data

// arch/riscv/kernel/vdso.c
static union {
	struct vdso_data	data;
	u8			page[PAGE_SIZE];
} vdso_data_store __page_aligned_data;
struct vdso_data *vdso_data = &vdso_data_store.data;

```

#### settimeofday

`settimeofday` 系统调用执行过程中会调用 `update_vsyscall_tz` 更新 vDSO 的数据。

```c
// kernel/time/vsyscall.c
void update_vsyscall_tz(void)
{
	struct vdso_data *vdata = __arch_get_k_vdso_data();

	vdata[CS_HRES_COARSE].tz_minuteswest = sys_tz.tz_minuteswest;
	vdata[CS_HRES_COARSE].tz_dsttime = sys_tz.tz_dsttime;

	__arch_sync_vdso_data(vdata);
}
```

`update_vsyscall_tz` 和 `update_vsyscall` 类似，都是通过调用 `__arch_get_k_vdso_data` 获取内核中 vDSO 数据对象并进行更新。

## 总结

本文依据 Linux 和 glibc 源代码，先从编译期解释了 vDSO 共享库如何集成到 Linux 操作系统内核，然后从运行期解释了 vDSO 相关数据结构的初始化，最后分析了用户程序读取 vDSO 数据和内核更新数据的过程。希望能帮助读者理解 vDSO 技术的实现原理。

## 参考资料

* [getauxval() and the auxiliary vector][2]
* [Bug 19767 - vdso is not used with static linking][3]
* [How programs get run: ELF binaries][5]

[1]: https://lpc.events/event/7/contributions/664/attachments/509/918/Unified_vDSO_LPC_2020.pdf
[2]: https://lwn.net/Articles/519085/
[3]: https://sourceware.org/bugzilla/show_bug.cgi?id=19767
[4]: https://static.lwn.net/images/2012/auxvec.png
[5]: https://lwn.net/Articles/631631/
[006]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220623-riscv-syscall-part2-procedure.md
[007]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220717-riscv-syscall-part3-vdso-overview.md
[008]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/riscv_syscall/mermaid-riscv-syscall-part4-vdso-implementation-1.png
