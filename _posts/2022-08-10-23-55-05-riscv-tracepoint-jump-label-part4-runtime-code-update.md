---
layout: post
author: 'Wu Zhangjin'
title: 'RISC-V jump_label 详解，第 4 部分：运行时代码改写'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-tracepoint-jump-label-part4-runtime-code-update/
description: 'RISC-V jump_label 详解，第 4 部分：运行时代码改写'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Author:  Falcon <falcon@tinylab.org>
> Date:    2022/06/09
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)


## 背景简介

该系列有多篇文章，旨在分析 RISC-V 架构上的 `jump_label` 实现。

前 3 篇已经介绍了 Jump Label 的工作原理、`nop` 和 `goto label(foo)` 的指令编码以及最为关键的 `static_branch(foo)` 的实现和 Tracepoint 的用法。

这里是最后 1 节，介绍遗留的运行时代码修改逻辑，即 `patch_text_nosync()` 以及相关变体的实现：

```
// arch/riscv/kernel/jump_label.c:39

patch_text_nosync(addr, &insn, sizeof(insn));
```

本文以 v5.18 为例，与 v5.17 应该大同小异。

## 运行时代码改写概述

在前述 3 篇的基础上，不难理解，Jump Label 其实是内核中 JIT 思想的一种具体应用：根据用户需求、动态生成代码、动态改写代码，进而达到提升运行效率的目标。

除了 JIT，其实这部分跟内核中的 Ftrace, Livepatch, eBPF 等都有相似之处，都涉及运行时的代码修改。

本文继续讨论其中的『动态改写代码』部分。

在运行过程中动态地改写内核中的代码，听起来就是比较容易出事的事情：

1. Jump Label 目前在内核的很多地方都用到了，所以，需要改写的目标地址可能落在任意的各种路径上。
2. 如何处理单核与多核的情况。
3. 如何处理中断的情况。
4. 如果有人正在执行目标地址的代码呢？
5. 改写的目标地址在哪里？模块中，还是内核中，虚拟地址还是物理地址？

接下来，我们先来分析两个基础函数 `patch_text_nosync` 和 `patch_text`。

## 分析 code patching

Jump Label 和 Ftrace 都用到了 code patching，这部分代码主要牵涉 `arch/riscv/kernel/patch.c`，光看代码不是那么容易理解，所以可以结合 git log 查看提交历史。

不难发现，其中主要是提交了两个接口：

* patch_text_nosync()：一个是保护动作由使用者来做
* 另外一个是直接放在 `stop_machine()` 下运行。

这两者最终都用到了 `patch_insn_write`，并最终调用了 `copy_to_kernel_nofault` 来完成目标地址指令的写入。

### 分析 copy_to_kernel_nofault()

```
// mm/maccess.c:15

#define copy_to_kernel_nofault_loop(dst, src, len, type, err_label)	\
	while (len >= sizeof(type)) {					\
		__put_kernel_nofault(dst, src, type, err_label);		\
		dst += sizeof(type);					\
		src += sizeof(type);					\
		len -= sizeof(type);					\
	}

long copy_to_kernel_nofault(void *dst, const void *src, size_t size)
{
	unsigned long align = 0;

	if (!IS_ENABLED(CONFIG_HAVE_EFFICIENT_UNALIGNED_ACCESS))
		align = (unsigned long)dst | (unsigned long)src;

	pagefault_disable();
	if (!(align & 7))
		copy_to_kernel_nofault_loop(dst, src, size, u64, Efault);
	if (!(align & 3))
		copy_to_kernel_nofault_loop(dst, src, size, u32, Efault);
	if (!(align & 1))
		copy_to_kernel_nofault_loop(dst, src, size, u16, Efault);
	copy_to_kernel_nofault_loop(dst, src, size, u8, Efault);
	pagefault_enable();
	return 0;
Efault:
	pagefault_enable();
	return -EFAULT;
}
```

从代码上看，主要是对齐的处理和 pagefault 的关闭。

### 分析 patch_insn_write()

这部分在 noMMU 下，直接等同于 `copy_to_kernenl_nofault()`。

在 MMU 下，通过 git log 查看作者是这么介绍的：

> On strict kernel memory permission, we couldn't patch code without
> writable permission. Preserve two holes in fixmap area, so we can map
> the kernel code temporarily to fixmap area, then patch the instructions.
>
> We need two pages here because we support the compressed instruction, so
> the instruction might be align to 2 bytes. When patching the 32-bit
> length instruction which is 2 bytes alignment, it will across two pages.

所以，这段代码逻辑就很清晰了：

```
/*
 * The fix_to_virt(, idx) needs a const value (not a dynamic variable of
 * reg-a0) or BUILD_BUG_ON failed with "idx >= __end_of_fixed_addresses".
 * So use '__always_inline' and 'const unsigned int fixmap' here.
 */
static __always_inline void *patch_map(void *addr, const unsigned int fixmap)
{
	uintptr_t uintaddr = (uintptr_t) addr;
	struct page *page;

	if (core_kernel_text(uintaddr))
		page = phys_to_page(__pa_symbol(addr));
	else if (IS_ENABLED(CONFIG_STRICT_MODULE_RWX))
		page = vmalloc_to_page(addr);
	else
		return addr;

	BUG_ON(!page);

	return (void *)set_fixmap_offset(fixmap, page_to_phys(page) +
					 (uintaddr & ~PAGE_MASK));
}

static void patch_unmap(int fixmap)
{
	clear_fixmap(fixmap);
}
NOKPROBE_SYMBOL(patch_unmap);

static int patch_insn_write(void *addr, const void *insn, size_t len)
{
	void *waddr = addr;
	bool across_pages = (((uintptr_t) addr & ~PAGE_MASK) + len) > PAGE_SIZE;
	int ret;

	/*
	 * Before reaching here, it was expected to lock the text_mutex
	 * already, so we don't need to give another lock here and could
	 * ensure that it was safe between each cores.
	 */
	lockdep_assert_held(&text_mutex);

	if (across_pages)
		patch_map(addr + len, FIX_TEXT_POKE1);

	waddr = patch_map(addr, FIX_TEXT_POKE0);

	ret = copy_to_kernel_nofault(waddr, insn, len);

	patch_unmap(FIX_TEXT_POKE0);

	if (across_pages)
		patch_unmap(FIX_TEXT_POKE1);

	return ret;
}
NOKPROBE_SYMBOL(patch_insn_write);

```

在具体写入前后，做了额外的 `patch_map` 和 `patch_unamp`，主要是通过 fixmap 临时申请写入权限，针对模块与内核做了差异化处理（address to page）。

而考虑到 32-bit 的压缩指令（2字节，虽然 Jump Label 是不支持压缩指令的）可能跨页，所以在 fixmap 中打了两个洞：

```
// arch/riscv/include/asm/fixmap.h: 15

/*
 * Here we define all the compile-time 'special' virtual addresses.
 * The point is to have a constant address at compile time, but to
 * set the physical address only in the boot process.
 *
 * These 'compile-time allocated' memory buffers are page-sized. Use
 * set_fixmap(idx,phys) to associate physical memory with fixmap indices.
 */
enum fixed_addresses {
	...
	FIX_TEXT_POKE1,
	FIX_TEXT_POKE0,
	...
};
```

### 分析 patch_text_nosync()

在调用 `patch_insn_write()` 写完以后，`patch_text_nosync()` 需要确保指令 cache 中的内容同步更新了，否则处理器执行到了其他内容。

```
// arch/riscv/kernel/patch.c:88

int patch_text_nosync(void *addr, const void *insns, size_t len)
{
	u32 *tp = addr;
	int ret;

	ret = patch_insn_write(tp, insns, len);

	if (!ret)
		flush_icache_range((uintptr_t) tp, (uintptr_t) tp + len);

	return ret;
}
NOKPROBE_SYMBOL(patch_text_nosync);
```

### 分析 patch_text()

`patch_text()` 在 `patch_text_nosync()` 的基础上加上了 `stop_machine()` 支持，确保所有处理器都停下来等我们执行代码更新，这样子的话就可以避免刚开始提到的那些问题。

```
// arch/riscv/kernel/patch.c:102

static int patch_text_cb(void *data)
{
	struct patch_insn *patch = data;
	int ret = 0;

	if (atomic_inc_return(&patch->cpu_count) == num_online_cpus()) {
		ret =
		    patch_text_nosync(patch->addr, &patch->insn,
					    GET_INSN_LENGTH(patch->insn));
		atomic_inc(&patch->cpu_count);
	} else {
		while (atomic_read(&patch->cpu_count) <= num_online_cpus())
			cpu_relax();
		smp_mb();
	}

	return ret;
}
NOKPROBE_SYMBOL(patch_text_cb);

int patch_text(void *addr, u32 insn)
{
	struct patch_insn patch = {
		.addr = addr,
		.insn = insn,
		.cpu_count = ATOMIC_INIT(0),
	};

	return stop_machine_cpuslocked(patch_text_cb,
				       &patch, cpu_online_mask);
}
NOKPROBE_SYMBOL(patch_text);
```

这里先撇开 `stop_machine()` 不管，`patch_text_cb()` 这个回调，主要是通过原子变量 `cpu_count` 的累加，一直等到最后一个 cpu 停下来才做代码的写动作，如果没达到则继续等（`cpu_relax()`）。

需要提到的是，这个代码在 v5.18 之前都有 Bug，回调的第一个分支原来是判断等于 1，而不是 `num_online_cpus()`，可能出现其他 cpu 还在继续执行就改写代码的情况。

### stop_machine() 机制

`stop_machine()` 机制有专门的内核实现：

```
// kernel/stop_machine.c:588

int stop_machine_cpuslocked(cpu_stop_fn_t fn, void *data,
			    const struct cpumask *cpus)
{
	struct multi_stop_data msdata = {
		.fn = fn,
		.data = data,
		.num_threads = num_online_cpus(),
		.active_cpus = cpus,
	};

	lockdep_assert_cpus_held();

	if (!stop_machine_initialized) {
		/*
		 * Handle the case where stop_machine() is called
		 * early in boot before stop_machine() has been
		 * initialized.
		 */
		unsigned long flags;
		int ret;

		WARN_ON_ONCE(msdata.num_threads != 1);

		local_irq_save(flags);
		hard_irq_disable();
		ret = (*fn)(data);
		local_irq_restore(flags);

		return ret;
	}

	/* Set the initial state and stop all online cpus. */
	set_state(&msdata, MULTI_STOP_PREPARE);
	return stop_cpus(cpu_online_mask, multi_cpu_stop, &msdata);
}
```

这个机制中比较核心的应该是这部分：

```
// kernel/stop_machine.c:202

/* This is the cpu_stop function which stops the CPU. */
static int multi_cpu_stop(void *data)
{
	struct multi_stop_data *msdata = data;
	enum multi_stop_state newstate, curstate = MULTI_STOP_NONE;
	int cpu = smp_processor_id(), err = 0;
	const struct cpumask *cpumask;
	unsigned long flags;
	bool is_active;

	/*
	 * When called from stop_machine_from_inactive_cpu(), irq might
	 * already be disabled.  Save the state and restore it on exit.
	 */
	local_save_flags(flags);

	if (!msdata->active_cpus) {
		cpumask = cpu_online_mask;
		is_active = cpu == cpumask_first(cpumask);
	} else {
		cpumask = msdata->active_cpus;
		is_active = cpumask_test_cpu(cpu, cpumask);
	}

	/* Simple state machine */
	do {
		/* Chill out and ensure we re-read multi_stop_state. */
		stop_machine_yield(cpumask);
		newstate = READ_ONCE(msdata->state);
		if (newstate != curstate) {
			curstate = newstate;
			switch (curstate) {
			case MULTI_STOP_DISABLE_IRQ:
				local_irq_disable();
				hard_irq_disable();
				break;
			case MULTI_STOP_RUN:
				if (is_active)
					err = msdata->fn(msdata->data);
				break;
			default:
				break;
			}
			ack_state(msdata);
		} else if (curstate > MULTI_STOP_PREPARE) {
			/*
			 * At this stage all other CPUs we depend on must spin
			 * in the same loop. Any reason for hard-lockup should
			 * be detected and reported on their side.
			 */
			touch_nmi_watchdog();
		}
		rcu_momentary_dyntick_idle();
	} while (curstate != MULTI_STOP_EXIT);

	local_irq_restore(flags);
	return err;
}

```

从代码逻辑上看，主要是：

1. 投喂 nmi watchdog，因为 cpu 都停下来了，不然会误报 lockup
2. 关闭中断
3. 执行目标函数

所以，这个机制保证了代码修改是在关闭中断并且其他 CPU 都停下来的情况下执行的。

## Jump Label 动态改写过程

Jump Label 并未用到 `stop_machine()` 机制。

### 启动中更新

首先是启动过程中，针对 NOP 的这种有 `rewrite NOPS`，这个是直接写的。

```
// kernel/jump_label.c:463

void __init jump_label_init(void)
{
	...
	cpus_read_lock();
	jump_label_lock();

	for (iter = iter_start; iter < iter_stop; iter++) {
		...
		/* rewrite NOPs */
		if (jump_label_type(iter) == JUMP_LABEL_NOP)
			arch_jump_label_transform_static(iter, JUMP_LABEL_NOP);
		...
	}
	static_key_initialized = true;
	jump_label_unlock();
	cpus_read_unlock();
}

```

这个 `jump_label_init()` 是在 `setup_arch()` 执行的：

```
// arch/riscv/kernel/setup.c:263

void __init setup_arch(char **cmdline_p)
{
	parse_dtb();
	setup_initial_init_mm(_stext, _etext, _edata, _end);

	*cmdline_p = boot_command_line;

	early_ioremap_setup();
	jump_label_init();         // jump_label 初始化
	...
#ifdef CONFIG_SMP
	setup_smp();
#endif
	...
}
```

可以看到，时机非常早，这个时候多核还没有初始化，中断要到 `setup_arch()` 之后的 `init_IRQ()` 才初始化（见 `init/main.c: start_kernel()`），所以直接写就没问题。

### 运行时更新

在该系列第 3 篇已经介绍到，Static Branch 的两个动态使能/禁用接口是如何调用到最终的架构相关接口的。

咱们这里仅关心这中间的保护问题，为了简便起见，这里把所有保护放到一块来介绍，忽略内核模块相关支持，并且仅以使能接口为例：

```
void static_key_enable(struct static_key *key)
{
	cpus_read_lock();  // cpu hotplug lock, 定义在 kernel/cpu.c
	jump_label_lock();

	if (atomic_read(&key->enabled) == 0) {
		atomic_set(&key->enabled, -1);

	        mutex_lock(&text_mutex);  // text_mutex, 定义在 kernel/extable.c
	        patch_text_nosync(addr, &insn, sizeof(insn));
		mutex_unlock(&text_mutex);

		/*
		 * See static_key_slow_inc().
		 */
		atomic_set_release(&key->enabled, 1);
	}

	jump_label_unlock();
	cpus_read_unlock();
}
```

这里有一个 lock order：`cpus_rwsem -> jump_label_lock -> text_mutex`，通过查看修改记录，是在这个 commit 中明确的：`f2545b`。

综合其他的修改记录：`a40527f8f0`，这里的 `cpus_rwsem` 锁主要作用为：

> Note that switching branches results in some locks being taken,
> particularly the CPU hotplug lock (in order to avoid races against
> CPUs being brought in the kernel whilst the kernel is getting
> patched).

而变体 `static_key_enable_cpuslocked()` 允许在 cpu hotplug notifier 中使用，避免二次持锁导致死锁。

`text_mutex` 的说明如下：

>
> mutex protecting text section modification (dynamic code patching).
> some users need to sleep (allocating memory...) while they hold this lock.
>

注意，这里并没有禁用中断，也就是在修改代码的过程中，可能会发生中断，但是这种情况其实是有风险的，比如在修改代码的过程中或者修改完和 flush icache 之前。当然，这个中间如果有其他处理器执行进来其实也是有风险的。

通过查阅代码，并对比其他架构。RISC-V 部分早期是有 irqs 禁用的，但是它假设用户只有 Ftrace，而 Ftrace 是通过 `stop_machine()` 禁用了中断的，所以这种假设其实有问题。

具体修改记录见：`0ff7c3b33127`，这里需要提交一笔 Patch 把 irqs 操作加回去，具体改法可参考 powerpc：

```
// arch/powerpc/lib/code-patching.c:163

static int do_patch_instruction(u32 *addr, ppc_inst_t instr)
{
	int err;
	unsigned long flags;

	/*
	 * During early early boot patch_instruction is called
	 * when text_poke_area is not ready, but we still need
	 * to allow patching. We just do the plain old patching
	 */
	if (!this_cpu_read(text_poke_area))
		return raw_patch_instruction(addr, instr);

	local_irq_save(flags);
	err = __do_patch_instruction(addr, instr);
	local_irq_restore(flags);

	return err;
}
```

考虑到目前 Jump Label 修改的 nop/jal 都是 4 字节的，都能在一个 cpu cycle 内完成，所以在代码修改过程中即使来了中断或者来了其他处理器执行，这部分风险是没有的。至于在 icache flush 来之前被中断/抢占，也最多是执行老的 branch，也就是 branch 延迟修改。

## 小结

以上详细介绍了 Jump Label 最后的代码更新过程。

内核代码更新目前大多采用 `stop_machine()` 机制，确保更新代码时仅有一个核在工作，而且中断是关闭的。

Jump Label 的代码更新较为简单，要求遵循 `cpus_rwsem -> jump_label_lock -> text_mutex` 这个保护顺序，并尽量关闭中断，只是目前 RISC-V 具体实现中，有一笔修改导致当前 Jump Label 调用路径中漏掉了关闭中断操作，经上面的分析，这部分即使不关闭中断目前影响有限。

至此，整个 Jump Label 系列就分析完毕了。

## 参考资料

* [Jump Label](https://lwn.net/Articles/412072/)
* [Tracepoint](https://www.kernel.org/doc/html/latest/core-api/tracepoint.html)
