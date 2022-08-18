---
layout: post
author: 'Wu Zhangjin'
title: 'RISC-V jump_label 详解，第 5 部分：优化案例'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-tracepoint-jump-label-part5-examples/
description: 'RISC-V jump_label 详解，第 5 部分：优化案例'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Author:  Falcon <falcon@tinylab.org>
> Date:	   2022/03/28
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor: PLCT Lab, ISCAS


## 背景简介

该系列已经连载 4 篇文章，旨在分析 RISC-V 架构上的 jump_label 实现。前面 4 篇已经系统地分析了其原理和实现，该篇继续结合 RISC-V 架构介绍实际使用 jump_label 的优化案例。

最近观察到，在 RISC-V Linux 邮件列表中，有一位名叫 Jisheng Zhang 的内核开发者提交了多笔采用 Static Branch 优化 RISC-V Linux 热点路径上的条件判断的 patch，本文直接基于相关 patch 进行介绍。

如果没有特别说明，本文以 Linux v5.17 为例。

## RISC-V 处理器扩展

RISC-V 作为一种采用精简指令集的处理器架构，其特征是围绕核心指令集 RV32I/RV64I，通过一系列扩展来增强处理器的功能，不同厂家可以根据自身需要选择是否实现这些扩展。

这类 RISC-V 扩展要么存在要么不存在，这个状态其实是确定的，这种情况就特别适合用 Jump Label 来做优化，也就是把扩展存在与否的判断进行静态处理，转变为 Static Branch 的方式。

这类 RISC-V 扩展在很多路径上会存在，根据我们前期的 [测试数据](https://tinylab.org/riscv-perf-benchmark/)，优化的效果一定是可以预期的，当扩展数增加到一定程度，这种优化的效果会更为可观。

## 单独优化与统一优化

RISC-V 的扩展非常多，并且可能会以 “爆炸性” 的方式增长。早期 Jisheng Zhang 仅仅对 FPU 扩展的条件判断代码做了优化（已经合并进主线），他后面考虑复用性，重新改造了代码，以便轻松追加对其他扩展的支持，这部分目前已经通过了 Review，但是截止到 v5.19-rc6，还没有被合并进主线。

### 早期的 FPU 条件判断优化

通过早期的 FPU 优化能够非常直观明了的学习如何使用 Static Branch 来优化一个条件判断：

```
commit 37a7a2a10ec525a79d733008bc7fe4ebbca34382
Author: Jisheng Zhang <jszhang@kernel.org>
Date:	Wed May 12 22:55:45 2021 +0800

    riscv: Turn has_fpu into a static key if FPU=y

    The has_fpu check sits at hot code path: switch_to(). Currently, has_fpu
    is a bool variable if FPU=y, switch_to() checks it each time, we can
    optimize out this check by turning the has_fpu into a static key.

    Signed-off-by: Jisheng Zhang <jszhang@kernel.org>
    Signed-off-by: Palmer Dabbelt <palmerdabbelt@google.com>
```

在优化之前，定义了一个 `has_fpu` 变量，默认为 0，并在检测到该扩展存在时置 true：

```
// arch/riscv/kernel/cpufeature.c

#ifdef CONFIG_FPU
bool has_fpu __read_mostly;
#endif

void riscv_fill_hwcap(void) {
       ...
#ifdef CONFIG_FPU
       if (elf_hwcap & (COMPAT_HWCAP_ISA_F | COMPAT_HWCAP_ISA_D))
	       has_fpu = true;
#endif
}
```

然后在进程启动、进程切换、信号处理等位置都涉及对 FPU 扩展的判断，从而确定是否需要初始化、保存或恢复 FPU 寄存器，这些路径都是比较频繁执行的。

```
// arch/riscv/include/asm/switch_to.h

extern struct task_struct *__switch_to(struct task_struct *,
do {						       \
       struct task_struct *__prev = (prev);	       \
       struct task_struct *__next = (next);	       \
       if (has_fpu)				       \
	       __switch_to_aux(__prev, __next);	       \
		       ((last) = __switch_to(__prev, __next));	       \
} while (0)

// arch/riscv/kernel/process.c

void start_thread(struct pt_regs *regs, unsigned long pc,
	unsigned long sp)
{
       regs->status = SR_PIE;
       if (has_fpu) {
	       regs->status |= SR_FS_INITIAL;
	       /*
		* Restore the initial value to the FP register

// arch/riscv/kernel/signal.c

static long restore_sigcontext(struct pt_regs *regs,
       /* sc_regs is structured the same as the start of pt_regs */
       err = __copy_from_user(regs, &sc->sc_regs, sizeof(sc->sc_regs));
       /* Restore the floating-point state. */
       if (has_fpu)
	       err |= restore_fp_state(regs, &sc->sc_fpregs);
       return err;
}

static long setup_sigcontext(struct rt_sigframe __user *frame,
       /* sc_regs is structured the same as the start of pt_regs */
       err = __copy_to_user(&sc->sc_regs, regs, sizeof(sc->sc_regs));
       /* Save the floating-point state. */
       if (has_fpu)
	       err |= save_fp_state(regs, &sc->sc_fpregs);
       return err;
}
```

通过上面的代码，可以看到 `has_fpu` 的判断都在进程切换、任务启动和信号处理这样的热点路径上，所以优化的必要性是很明显的。

接下来，看看如何做这块的优化。

首先是，把 `has_fpu` 替换为一个 Static Key 变量：

```
// arch/riscv/kernel/cpufeature.c: 21

#ifdef CONFIG_FPU
__ro_after_init DEFINE_STATIC_KEY_FALSE(cpu_hwcap_fpu);
#endif

// arch/riscv/kernel/cpufeature.c: 62

void riscv_fill_hwcap(void) {
       ...
#ifdef CONFIG_FPU
       if (elf_hwcap & (COMPAT_HWCAP_ISA_F | COMPAT_HWCAP_ISA_D))
	      static_branch_enable(&cpu_hwcap_fpu);
#endif
```

然后在 `has_fpu` 判断的地方全部用 `static_branch_likely()` 替代，变量 `has_fpu` 也被转为了宏：

```
// arch/riscv/include/asm/switch_to.h: 59

extern struct static_key_false cpu_hwcap_fpu;
static __always_inline bool has_fpu(void)
{
	return static_branch_likely(&cpu_hwcap_fpu);
}
#else
static __always_inline bool has_fpu(void) { return false; }
```

这里用 `static_branch_likely()` 表示如果开启了 `CONFIG_FPU` 则大概率是存在 fpu 扩展的，好让编译器优化选取 fpu 存在时的那路分支。

最后一部分就是把所有的 `has_fpu` 变量判断替换为宏 `has_fpu()`变量：

```
$ grep "has_fpu()" -nur arch/riscv/
arch/riscv/include/asm/switch_to.h:78:	if (has_fpu())					\
arch/riscv/kernel/process.c:90: if (has_fpu()) {
arch/riscv/kernel/signal.c:93:	if (has_fpu())
arch/riscv/kernel/signal.c:146: if (has_fpu())
```

### 所有扩展通用的优化

考虑到 RISC-V 存在大量扩展的因素，Jisheng Zhang 又提交了一笔新的 [riscv: introduce unified static key mechanism for ISA extensions](https://lore.kernel.org/linux-riscv/20220522153543.2656-2-jszhang@kernel.org/)，这笔 patchset 考虑了统一支持所有的扩展，并把 FPU 也纳入了新的 patchset，替换掉了早期的变更。

这个思路比较清晰，主要是在上一节的基础上把 Static key 扩充为了数组：

```
--- a/arch/riscv/kernel/cpufeature.c
+++ b/arch/riscv/kernel/cpufeature.c
@@ -24,6 +24,8 @@ static DECLARE_BITMAP(riscv_isa, RISCV_ISA_EXT_MAX) __read_mostly;
 #ifdef CONFIG_FPU
 __ro_after_init DEFINE_STATIC_KEY_FALSE(cpu_hwcap_fpu);
 #endif
+__ro_after_init DEFINE_STATIC_KEY_ARRAY_FALSE(riscv_isa_ext_keys, RISCV_ISA_EXT_KEY_MAX);
+EXPORT_SYMBOL(riscv_isa_ext_keys);
```

可以看到，主要是用到了 `DEFINE_STATIC_KEY_ARRAY_FALSE`，注意与之前的 `DEFINE_STATIC_KEY_FALSE` 的不同之处是，这里可以传入一个范围值 `RISCV_ISA_EXT_KEY_MAX`。

其中，`RISCV_ISA_EXT_KEY_MAX` 是一个枚举值：

```
--- a/arch/riscv/include/asm/hwcap.h
+++ b/arch/riscv/include/asm/hwcap.h
@@ -12,6 +12,7 @@
 #include <uapi/asm/hwcap.h>

 #ifndef __ASSEMBLY__
+#include <linux/jump_label.h>
 /*
  * This yields a mask that user programs can use to figure out what
  * instruction set this cpu supports.
@@ -55,6 +56,16 @@ enum riscv_isa_ext_id {
	RISCV_ISA_EXT_ID_MAX = RISCV_ISA_EXT_MAX,
 };

+/*
+ * This enum represents the logical ID for each RISC-V ISA extension static
+ * keys. We can use static key to optimize code path if some ISA extensions
+ * are available.
+ */
+enum riscv_isa_ext_key {
+	RISCV_ISA_EXT_KEY_FPU,		/* For 'F' and 'D' */
+	RISCV_ISA_EXT_KEY_MAX,
+};
+
```

这个值会随着未来新引入的扩展自动递增，下一节我们会再看一个引入新的 RISC-V 扩展的例子。

之后就是如何根据 RISC-V 扩展来使能 Static Branch，即当某个 RISC-V 扩展存在时就使能 `riscv_isa_ext_keys` 数组中相应的元素。

这里有一个映射动作需要做，就是从 RISC-V 扩展对应的标志位（目前一般是直接从 dts 的 `riscv,isa` 节中读取出来并赋值到 `riscv_isa` bitmap 中）映射到 `riscv_isa_ext_keys[]` 数组的下标，即 `riscv_isa_ext_key` 类型的枚举值。

考虑到不同的 RISC-V 扩展可能会共享代码，这个映射存在多个 RISC-V 扩展共享同一个 Static Branch Key 的情况。比如说，如果检测到硬件有 `F` 或 `D` 扩展，都是对应到 `RISCV_ISA_EXT_KEY_FPU`。

```
+extern struct static_key_false riscv_isa_ext_keys[RISCV_ISA_EXT_KEY_MAX];
+
+static __always_inline int riscv_isa_ext2key(int num)
+{
+	switch (num) {
+	case RISCV_ISA_EXT_f:
+		return RISCV_ISA_EXT_KEY_FPU;
+	case RISCV_ISA_EXT_d:
+		return RISCV_ISA_EXT_KEY_FPU;
+	default:
+		return -EINVAL;
+	}
+}
+
```

有了这个映射关系，就是去使能相关的 Static Branch 了：

```
index 1b2d42d7f589..89f886b35357 100644
--- a/arch/riscv/kernel/cpufeature.c
+++ b/arch/riscv/kernel/cpufeature.c
 /**
  * riscv_isa_extension_base() - Get base extension word
@@ -232,6 +234,11 @@ void __init riscv_fill_hwcap(void)
			print_str[j++] = (char)('a' + i);
	pr_info("riscv: ELF capabilities %s\n", print_str);

+	for_each_set_bit(i, riscv_isa, RISCV_ISA_EXT_MAX) {
+		j = riscv_isa_ext2key(i);
+		if (j >= 0)
+			static_branch_enable(&riscv_isa_ext_keys[j]);
+	}
```

`j >= 0` 表示找到了 RISC-V 扩展对应的枚举值（最小的是 0），如果相应的扩展还不支持，则返回的是 `-EINVAL`，就不会启用 Static Branch。

最后一部分，就是把早期的 FPU 优化替换为所有扩展通用的方式：

```
--- a/arch/riscv/include/asm/switch_to.h
+++ b/arch/riscv/include/asm/switch_to.h
@@ -8,6 +8,7 @@

 #include <linux/jump_label.h>
 #include <linux/sched/task_stack.h>
+#include <asm/hwcap.h>
 #include <asm/processor.h>
 #include <asm/ptrace.h>
 #include <asm/csr.h>
@@ -56,10 +57,9 @@ static inline void __switch_to_aux(struct task_struct *prev,
	fstate_restore(next, task_pt_regs(next));
 }

-extern struct static_key_false cpu_hwcap_fpu;
 static __always_inline bool has_fpu(void)
 {
-	return static_branch_likely(&cpu_hwcap_fpu);
+	return static_branch_likely(&riscv_isa_ext_keys[RISCV_ISA_EXT_KEY_FPU]);
 }
 #else
```

最主要就是这个 `has_fpu()` 的判断改成对 `&riscv_isa_ext_keys[RISCV_ISA_EXT_KEY_FPU]` 数组中元素的判断。另外一个是，把早期对 `cpu_hwcap_fpu` 的设定删除掉：

```
--- a/arch/riscv/kernel/cpufeature.c
+++ b/arch/riscv/kernel/cpufeature.c
@@ -21,9 +21,6 @@ unsigned long elf_hwcap __read_mostly;
 /* Host ISA bitmap */
 static DECLARE_BITMAP(riscv_isa, RISCV_ISA_EXT_MAX) __read_mostly;

-#ifdef CONFIG_FPU
-__ro_after_init DEFINE_STATIC_KEY_FALSE(cpu_hwcap_fpu);
-#endif
 __ro_after_init DEFINE_STATIC_KEY_ARRAY_FALSE(riscv_isa_ext_keys, RISCV_ISA_EXT_KEY_MAX);
 EXPORT_SYMBOL(riscv_isa_ext_keys);

@@ -239,8 +236,4 @@ void __init riscv_fill_hwcap(void)
		if (j >= 0)
			static_branch_enable(&riscv_isa_ext_keys[j]);
	}
-#ifdef CONFIG_FPU
-	if (elf_hwcap & (COMPAT_HWCAP_ISA_F | COMPAT_HWCAP_ISA_D))
-		static_branch_enable(&cpu_hwcap_fpu);
-#endif
```

## 新扩展如何直接启用优化

上面的 “统一优化” 方式已经全部通过了 Review，预计最迟会在 Linux v5.20 合入，最早可能会在 v5.19 的 rc7/rc8 合入，所以后续 RISC-V 扩展在增加内核支持时可以直接启用 Static Branch 优化。

咱们来看一个例子 [arch/riscv: add Zihintpause support](https://lore.kernel.org/linux-riscv/20220620201530.3929352-1-daolu@rivosinc.com/)了。

扩展本身的支持代码咱们这里不做分析，主要是看看如何启用 Static Branch 优化。

首先是在 `riscv_isa_ext_key` 增加一个枚举值，以便扩充 Static Key 数组并获得一个下标。

```
--- a/arch/riscv/include/asm/hwcap.h
+++ b/arch/riscv/include/asm/hwcap.h

@@ -64,6 +66,7 @@ enum riscv_isa_ext_id {
  */
 enum riscv_isa_ext_key {
	RISCV_ISA_EXT_KEY_FPU,		/* For 'F' and 'D' */
+	RISCV_ISA_EXT_KEY_ZIHINTPAUSE,
	RISCV_ISA_EXT_KEY_MAX,
 };
```

接着在映射表里头，加上对应的扩展到 Static Key 数组下标的映射关系：

```
static __always_inline int riscv_isa_ext2key(int num)
		return RISCV_ISA_EXT_KEY_FPU;
	case RISCV_ISA_EXT_d:
		return RISCV_ISA_EXT_KEY_FPU;
+	case RISCV_ISA_EXT_ZIHINTPAUSE:
+		return RISCV_ISA_EXT_KEY_ZIHINTPAUSE;
	default:
		return -EINVAL;
	}
```

最后就是在具体代码中启用 Static Branch 来做条件判断：

```
--- a/arch/riscv/include/asm/vdso/processor.h
+++ b/arch/riscv/include/asm/vdso/processor.h
@@ -4,15 +4,30 @@

 #ifndef __ASSEMBLY__

+#include <linux/jump_label.h>
 #include <asm/barrier.h>
+#include <asm/hwcap.h>

 static inline void cpu_relax(void)
 {
+	if (!static_branch_likely(&riscv_isa_ext_keys[RISCV_ISA_EXT_KEY_ZIHINTPAUSE])) {
```

如果用的地方比较多，想好看一点，可以类似 FPU 的 `has_fpu()`，可以定义一个 `has_zihintpause()` 宏，记得包含相应的头文件：`jump_label.h` 和 `hwcap.h`。

## 小结

本文结合 RISC-V Linux 内核中的多个实例详细分析了如何利用 Jump Label 即 Static Branch 来优化热点路径上的条件分支，非常适合内核或者驱动开发工程师作为使用 Jump Label 的必备资料。

对于 RISC-V 芯片公司的 Linux 内核开发人员，这篇文章会更具针对性，大家在为公司的处理器扩展增加代码时，一定不要忘记加几行代码顺手把低效的扩展判断代码给优化掉。

最后，我们也观察到 JiSheng 工程师还在继续针对 RISC-V Linux 内核进行 Static Branch 方面的优化，比如最近他正在优化 `pgtable_l4_enabled` 和 `pgtable_l4_enabled`。由于暂时无法确定这块相应的 SV48 and SV57 是否会作为 RISC-V 的扩展放到 dts 对应的 `riscv,isa` 中进行管理，所以，他是单独提交的。这份代码里头涉及一些小技巧，感兴趣可参考一下 [riscv: turn pgtable_l4|[l5]_enabled to static key for RV64](https://lore.kernel.org/linux-riscv/20220716115059.3509-3-jszhang@kernel.org/)。

## 参考资料

* [riscv: introduce unified static key mechanism for ISA extensions](https://lore.kernel.org/linux-riscv/20220522153543.2656-2-jszhang@kernel.org/)
* [riscv: switch has_fpu() to the unified static key mechanism](https://lore.kernel.org/linux-riscv/20220522153543.2656-3-jszhang@kernel.org/)
* [arch/riscv: add Zihintpause support](https://lore.kernel.org/linux-riscv/20220620201530.3929352-1-daolu@rivosinc.com/)
* [riscv: turn pgtable_l4|[l5]_enabled to static key for RV64](https://lore.kernel.org/linux-riscv/20220716115059.3509-3-jszhang@kernel.org/)
