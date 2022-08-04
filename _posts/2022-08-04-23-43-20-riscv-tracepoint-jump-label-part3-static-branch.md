---
layout: post
author: 'Wu Zhangjin'
title: 'RISC-V jump_label 详解，第 3 部分：核心实现'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-jump-label-part3/
description: '前两篇已经介绍了 Jump Label 的工作原理以及 nop 和 goto label(foo) 的指令编码，本节来介绍其中最为关键的 static_branch(foo) 的实现以及 Tracepoint 的用法。'
category:
  - 开源项目
  - Risc-V
  - Tracepoint
tags:
  - Linux
  - RISC-V
  - Jump Label
  - Static Branch
---

> Author:  Falcon <falcon@tinylab.org>
> Date:    2022/04/15
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)


## 背景简介

该系列有多篇文章，旨在分析 RISC-V 架构上的 `jump_label` 实现。

前两篇已经介绍了 Jump Label 的工作原理以及 `nop` 和 `goto label(foo)` 的指令编码，本节来介绍其中最为关键的 `static_branch(foo)` 的实现以及 Tracepoint 的用法。

## Static Branch 实现详解

根据前面的分析，Static Branch 必须做到 3 点：

1. 能根据条件变量 `foo` 记住 `addr(foo)` 和 `label(foo)`，用于运行时指令交换，foo 就是那个打开 Jump Label 大门的 `key`
2. 能保留编译器 `unlikely` 的基本功能，能根据 `foo` 的初始值生成效率最高的代码，也就是让常用分支走最短路径，所以实际上需要关注 `unlikely(static_branch(foo))` 的完整实现。
3. 能支持按需开启或禁用，也就是动态修改 `addr(foo)` 为 `nop` 和 `goto label(foo)`

### Jump Table 和 Jump Entry

首先是设计一张表格用于记录 `foo`, `addr(foo)` 和 `label(foo)`，这里对应到一张数据表：

```
// include/asm-generic/vmlinux.lds.h:401

#define JUMP_TABLE_DATA							\
	. = ALIGN(8);							\
	__start___jump_table = .;					\
	KEEP(*(__jump_table))						\
	__stop___jump_table = .;
```

以及一个数据结构体：

```
// include/linux/jump_label.h:122

struct jump_entry {
	s32 code;
	s32 target;
	long key;	// key may be far away from the core kernel under KASLR
};
```

Jump Table 作为内核镜像文件的一个 Data Section，用于存放若干个 Jump Entry，每个 Jump Entry 包含 code, target 和 key 三个值，分别用于换算出对应的 `addr(foo)`、`label(foo)` 和 `foo`。

**注意**，并不是直接记录三者的地址，而仅仅是存放了偏移，实际实现则更为复杂和取巧，下一节来专门介绍。

### Jump Entry 的存放与读取

内核巧妙地通过内联汇编中的 `.pushsection` 和 `.popsection` 实现了 `foo` 相关信息的记录，并由此建立了一张地址表：`__jump_table`：

```
// arch/riscv/include/asm/jump_label.h:15

#define JUMP_LABEL_NOP_SIZE 4

static __always_inline bool arch_static_branch(struct static_key *key,
					       bool branch)
{
	asm_volatile_goto(
		"	.option push				\n\t"
		"	.option norelax				\n\t"
		"	.option norvc				\n\t"
		"1:	nop					\n\t"
		"	.option pop				\n\t"
		"	.pushsection	__jump_table, \"aw\"	\n\t"
		"	.align		" RISCV_LGPTR "		\n\t"
		"	.long		1b - ., %l[label] - .	\n\t"
		"	" RISCV_PTR "	%0 - .			\n\t"
		"	.popsection				\n\t"
		:  :  "i"(&((char *)key)[branch]) :  : label);

	return false;
label:
	return true;
}

static __always_inline bool arch_static_branch_jump(struct static_key *key,
						    bool branch)
{
	asm_volatile_goto(
		"	.option push				\n\t"
		"	.option norelax				\n\t"
		"	.option norvc				\n\t"
		"1:	jal		zero, %l[label]		\n\t"
		"	.option pop				\n\t"
		"	.pushsection	__jump_table, \"aw\"	\n\t"
		"	.align		" RISCV_LGPTR "		\n\t"
		"	.long		1b - ., %l[label] - .	\n\t"
		"	" RISCV_PTR "	%0 - .			\n\t"
		"	.popsection				\n\t"
		:  :  "i"(&((char *)key)[branch]) :  : label);

	return false;
label:
	return true;
}

```

从该系列第 2 篇的 “指令长度” 一节可以看到，由于基础指令级（RV32I/RV64I）的编码长度为 32 位，`JUMP_LABEL_NOP_SIZE` 被定义成了 4 字节（32/8）。

`.option` 部分为汇编伪指令，用于限定 `.option push` 和 `.option pop` 之间的链接时代码优化。其中 `.option norvc` 禁用压缩指令（“C”扩展指令集，16位编码，占2字节），确保动态启停时刚好有 4 字节的 `nop` 和 `JAL offset` 写入空间。而 `.option norelax` 是阻止 Linker Relaxation，从 [RISC-V Assembly Programmer's Manual: .option](https://github.com/riscv-non-isa/riscv-asm-manual/blob/master/riscv-asm.md#.option) 的描述和 [All Aboard, Part 3: Linker Relaxation in the RISC-V Toolchain](https://www.sifive.com/blog/all-aboard-part-3-linker-relaxation-in-riscv-toolchain) 举的例子来看，主要是防止链接时编译器做进一步的指令精简，比如长跳转变为短跳转，虽然看上去这里的 `nop` 和 `jal zero,%l[label]` 都已经没有优化空间。

`.align RISCV_LGPTR` 用于 Data Section 的对齐要求，而 `RISCV_PTR` 用于设定数据空间大小，具体定义见 `arch/riscv/include/asm/asm.h`，这里不做进一步介绍。

接下来重点关注从 `.pushsection` 开始的几条汇编语句：

首先，`.pushsection __jump_table, \"aw\"` 和 `.popsection` 把中间的内容放入名为 `__jump_table` 的 ELF DATA Section，可参考 [Binutils Section](https://sourceware.org/binutils/docs/as/Section.html).

其次，在对齐指令之后，一次存入了三个数据，即上节提到的 `struct jump_entry` 数据结构。可以看到，所有的数据都被表示为相对当前链接地址（`.`）的偏移（offset），其中：

* `code`：表示目标 `addr(foo)` 即 `&1b` 相对当前链接地址（&code）的 offset
* `target`：表示目标 `label(foo)` 即 `%l[label]` 相对当前链接地址（&target）的 offset
* `key`：表示 `foo` 地址即 `%0` 指向的立即数 `"i"(&((char *)key)[branch])`，相对当前链接地址（&key）的 offset，这部分接下来会做更详细的解读

这里设计得非常巧妙，通过这样一段汇编代码，能很方便地记住条件变量 `foo` 所在位置的几个关键信息，并能够很方便的计算出来：

```
// arch/riscv/include/asm/jump_label.h: 128

static inline unsigned long jump_entry_code(const struct jump_entry *entry)
{
	return (unsigned long)&entry->code + entry->code;  // &code + code
}

static inline unsigned long jump_entry_target(const struct jump_entry *entry)
{
	return (unsigned long)&entry->target + entry->target;  // &target + target
}

static inline struct static_key *jump_entry_key(const struct jump_entry *entry)
{
	long offset = entry->key & ~3L;  // 刚好地址是 RISCV_LGPTR 对齐的，低两位可用做其他用途，这里 mask 掉，低两位的用途接下来再介绍

	return (struct static_key *)((unsigned long)&entry->key + offset);  // &key + (key & ~3L)
}
```

通过以上的 `jump_entry_code`，`jump_entry_target` 和 `jump_entry_key` 就能完整地还原需要的 `addr(foo)`、`label(foo)` 和 `foo`，即 code, target 和 key 的真实地址。

这里的 `foo` 被形象地命名为了 `key`，对，它就是打开所有 Jump Entry 的那个钥匙。

### Static Key 的定义

接下来，继续看看这个被命名为 `key` 的 `foo` 对应的数据结构 `Struct static_key` 的详细定义：

```
// include/linux/jump_label.h:87

struct static_key {
	atomic_t enabled;
/*
 * Note:
 *   To make anonymous unions work with old compilers, the static
 *   initialization of them requires brackets. This creates a dependency
 *   on the order of the struct with the initializers. If any fields
 *   are added, STATIC_KEY_INIT_TRUE and STATIC_KEY_INIT_FALSE may need
 *   to be modified.
 *
 * bit 0 => 1 if key is initially true
 *	    0 if initially false
 * bit 1 => 1 if points to struct static_key_mod
 *	    0 if points to struct jump_entry
 */
	union {
		unsigned long type;
		struct jump_entry *entries;
		struct static_key_mod *next;
	};
};
```

本文重点关心 `enabled` 和 `type`，前者用于开启和禁用，两者一起决定指令的类型：`nop` 还是 `JAL offset`。

```
// include/linux/jump_label.h:205

#define JUMP_TYPE_FALSE		0UL
#define JUMP_TYPE_TRUE		1UL
#define JUMP_TYPE_LINKED	2UL             // 用于内核模块，本篇不做展开
#define JUMP_TYPE_MASK		3UL

// include/linux/jump_label.h:252

#define STATIC_KEY_INIT_TRUE					\
	{ .enabled = { 1 },					\
	  { .entries = (void *)JUMP_TYPE_TRUE } }
#define STATIC_KEY_INIT_FALSE					\
	{ .enabled = { 0 },					\
	  { .entries = (void *)JUMP_TYPE_FALSE } }
```

考虑默认为 `false` 的情况，Static Key 被初始化为 `STATIC_KEY_INIT_FALSE`，`.eanbled` 为 0。

### Jump Type 与 unlikely 实现：static_key_false()/static_key_true()

支持 `unlikely` 的关键是能准确地记住 `foo` 的初始值，也就是保证禁用时的开销最小，对于 Tracepoint，这个默认是 `false`，但是不排除有的其他场景默认是 `true`，所以这里需要能区隔。

正常来说，这个 Jump Entry 需要加一个属性来单独记录该属性，但是它通过 `entry->key` 这个元素的最后两位编码了 `false` 与 `true` 的信息，即 `arch_static_branch()` 函数中 `branch` 参数的信息。

关于 `entry->key` 这块的设定比较晦涩难懂，但实际上这也是巧妙之处，这里特别做一个补充。

```
	"	" RISCV_PTR "	%0 - .			\n\t"
	...
	:  :  "i"(&((char *)key)[branch]) :  : label);
```

先来看这一段，`%0`，在 [arm64](https://gitee.com/mirrors/gcc/blob/master/gcc/config/aarch64/aarch64.cc) 上也写作 `%c0`，表示存放后面的不带符号的整形立即数。

而后面的 `&((char *)key)[branch]` 非常关键，它首先把本来指向 `struct static_key` 的 `&key` 强转为 `char *` 的数组，而 `branch` 作为下标，那么当 `branch` 为 `false` 时，这里取到的地址就是 `struct static_key *key`，如果 `branch` 为 `true` 时，则取到的地址为 `&((char *)key)[1]`，即 `&(char *)key + 1`，大体如下图：

```
                               branch=false <-- &key+0 &key+1  --> branch=true
                                                    |   |
                                                    V   V
struct static_key *key -> (char *)key -> key[n] =  [ ] [ ] [ ] [ ] ...
                                                    ^   ^
                                                    |   |
                                          &key[false]  &key[true] ...
                                                    ^   ^
                                                    |   |
                                         branch=false  branch=true
```

由于 `long key` 的最低地址对齐要求是 4，也就是末尾两位是 0，加一以后就变成了 `1`，这 1 位刚好用来作为 `jump_entry_is_branch` 的判断，而在计算 `&entry->key` 的时候则需要用 `entry->key & ~3L` 抹掉算出真正的 `struct static_key *key`。

所以，判断 `jump_entry_is_branch` 就变得很简单：

```
// include/linux/jump_label.h:164

static inline bool jump_entry_is_branch(const struct jump_entry *entry)
{
	return (unsigned long)entry->key & 1UL;
}
```

在 `jump_entry_is_branch` 判断的基础上，能获取到 Jump Label Type。

```
// kernel/jump_label.c:93

/*
 * There are similar definitions for the !CONFIG_JUMP_LABEL case in jump_label.h.
 * The use of 'atomic_read()' requires atomic.h and its problematic for some
 * kernel headers such as kernel.h and others. Since static_key_count() is not
 * used in the branch statements as it is for the !CONFIG_JUMP_LABEL case its ok
 * to have it be a function here. Similarly, for 'static_key_enable()' and
 * 'static_key_disable()', which require bug.h. This should allow jump_label.h
 * to be included from most/all places for CONFIG_JUMP_LABEL.
 */
int static_key_count(struct static_key *key)
{
	/*
	 * -1 means the first static_key_slow_inc() is in progress.
	 *  static_key_enabled() must return true, so return 1 here.
	 */
	int n = atomic_read(&key->enabled);

	return n >= 0 ? n : 1;
}
EXPORT_SYMBOL_GPL(static_key_count);


// include/linux/jump_label.h:414

#define static_key_enabled(x)							\
({										\
	if (!__builtin_types_compatible_p(typeof(*x), struct static_key) &&	\
	    !__builtin_types_compatible_p(typeof(*x), struct static_key_true) &&\
	    !__builtin_types_compatible_p(typeof(*x), struct static_key_false))	\
		____wrong_branch_error();					\
	static_key_count((struct static_key *)x) > 0;				\
})

// kernel/jump_label.c:393

static enum jump_label_type jump_label_type(struct jump_entry *entry)
{
	struct static_key *key = jump_entry_key(entry);
	bool enabled = static_key_enabled(key);  // 见 static_key_count()，-1 有特殊用途，只要 key->enabled 不为 0，则 static_key_enabled() 必返回 1
	bool branch = jump_entry_is_branch(entry);

	/* See the comment in linux/jump_label.h */
	return enabled ^ branch;
}

// include/linux/jump_label.h:196

enum jump_label_type {
	JUMP_LABEL_NOP = 0,
	JUMP_LABEL_JMP,
};

```

也就是 `Jump Type` 是 `enabled` 和 `branch` 的异或结果：

id |  enabled   | branch  |  Jump Type
---|------------|---------|-------------
 1 |        0   | 0       |  0 // JUMP_LABEL_NOP
 2 |        0   | 1       |  1 // JUMP_LABEL_JMP
 3 |        1   | 0       |  1 // JUMP_LABEL_JMP
 4 |        1   | 1       |  0 // JUMP_LABEL_NOP

考虑初始为 `false` 的情况，当 `enabled` 为 0 时，初始为 `JUMP_LABEL_NOP`，此时调用位置被替换为 `static_key_false(key)`：

```
// include/linux/jump_label.h:209

static __always_inline bool static_key_false(struct static_key *key)
{
	return arch_static_branch(key, false);
}

static __always_inline bool static_key_true(struct static_key *key)
{
	return !arch_static_branch(key, true);
}
```

完整的代码效果如下：

```
// include/linux/jump_label.h: 430

 * type\branch|	likely (1)	      |	unlikely (0)
 * -----------+-----------------------+------------------
 *            |                       |
 *  true (1)  |	   ...		      |	   ...
 *            |    NOP		      |	   JMP L   // static_key_false(key) 动态使能后等价代码，NOP 被替换为 JMP L
 *            |    <br-stmts>	      |	1: ...
 *            |	L: ...		      |
 *            |			      |
 *            |			      |	L: <br-stmts>
 *            |			      |	   jmp 1b
 *            |                       |
 * -----------+-----------------------+------------------
 *            |                       |
 *  false (0) |	   ...		      |	   ...
 *            |    JMP L	      |	   NOP     // static_key_false(key) 初始化等价代码
 *            |    <br-stmts>	      |	1: ...
 *            |	L: ...		      |
 *            |			      |
 *            |			      |	L: <br-stmts>
 *            |			      |	   jmp 1b
 *            |                       |
 * -----------+-----------------------+------------------

```

可以看到，`static_key_false(key)` 等价于在第 1 部分介绍到的 `unlikely(static_branch(*foo))`，本文最后一节，再进一步介绍最新的 `static_branch_unlikely()` 版本。

### 启停接口：static_key_enable()/static_key_disable()

而使能以后，即 `enabled` 设置为 1，此时就替换为 `JAL offset`。

```
// kernel/jump_label.c:164

void static_key_enable_cpuslocked(struct static_key *key)
{
	...
	jump_label_lock();
	if (atomic_read(&key->enabled) == 0) {
		atomic_set(&key->enabled, -1);  // 设置为 -1，如上节分析，`static_key_enabled()` 同样会取回 1，设置 enabled 为 1
		jump_label_update(key);         // 这里调用 __jump_label_update(key)
		/*
		 * See static_key_slow_inc().
		 */
		atomic_set_release(&key->enabled, 1);
	}
	jump_label_unlock();
}
EXPORT_SYMBOL_GPL(static_key_enable_cpuslocked);

void static_key_enable(struct static_key *key)
{
	cpus_read_lock();
	static_key_enable_cpuslocked(key);
	cpus_read_unlock();
}
EXPORT_SYMBOL_GPL(static_key_enable);

// kernel/jump_label.c:430

static void __jump_label_update(struct static_key *key,
				struct jump_entry *entry,
				struct jump_entry *stop,
				bool init)
{
	for (; (entry < stop) && (jump_entry_key(entry) == key); entry++) {
		if (jump_label_can_update(entry, init))
			arch_jump_label_transform(entry, jump_label_type(entry));  // 这里调用 arch/riscv/kernel/jump_label.c 中的 `arch_jump_label_transform()`，下一大节会再次介绍
	}
}
```

由于 `jump_label_type(entry)` 是用 `enabled` 和 `branch` 的异或来计算的，所以只要 `enabled` 发生变化后，上述 `arch_jump_label_transform` 就会进行代码替换。

相反地，只需要禁用，就能替换回 `nop`。

```
// kernel/jump_label.c:195

void static_key_disable_cpuslocked(struct static_key *key)
{
	...
	jump_label_lock();
	if (atomic_cmpxchg(&key->enabled, 1, 0))
		jump_label_update(key);
	jump_label_unlock();
}
EXPORT_SYMBOL_GPL(static_key_disable_cpuslocked);

void static_key_disable(struct static_key *key)
{
	cpus_read_lock();
	static_key_disable_cpuslocked(key);
	cpus_read_unlock();
}
EXPORT_SYMBOL_GPL(static_key_disable);

```

### 题外话：必须跳过 init sections 中的 Jump Entry

稍微延伸一下，`entry->key` 的另外 1 位用作了判断 `entry` 是否属于 init sections，因为 init sections 在内存在内核启动以后会交给 Buddy 系统，所以不能再去使用，需要额外的判断和处理，具体用法见。

```
// include/linux/jump_label.h:169

static inline bool jump_entry_is_init(const struct jump_entry *entry)
{
	return (unsigned long)entry->key & 2UL;
}

static inline void jump_entry_set_init(struct jump_entry *entry, bool set)
{
	if (set)
		entry->key |= 2;
	else
		entry->key &= ~2;
}

// kernel/jump_label.c:463

void __init jump_label_init(void)
{
	struct jump_entry *iter_start = __start___jump_table;
	struct jump_entry *iter_stop = __stop___jump_table;
	struct static_key *key = NULL;
	struct jump_entry *iter;
	...
	for (iter = iter_start; iter < iter_stop; iter++) {
		struct static_key *iterk;
		bool in_init;

		in_init = init_section_contains((void *)jump_entry_code(iter), 1);
		jump_entry_set_init(iter, in_init);
		...

	}

// kernel/jump_label.c:403

static bool jump_label_can_update(struct jump_entry *entry, bool init)
{
	/*
	 * Cannot update code that was in an init text area.
	 */
	if (!init && jump_entry_is_init(entry))
		return false;

```

init 相关部分与主题关系不大，不再展开。

## 再次回顾 arch_jump_label_transform()

再次回到架构相关的指令替换部分，即 `arch_jump_label_transform()`。

在该系列的第 2 部分，已经详细讨论了 `goto label(foo)` 的 `JAL offset` 的编码，但是 `offset` 的值是怎么算出来的并没有介绍。

在本文的基础上再来理解这部分就很轻松：

```
// arch/riscv/kernel/jump_label.c:17

void arch_jump_label_transform(struct jump_entry *entry,  // 从 __jump_table 中遍历或跟 key match
			       enum jump_label_type type) // 0: JUMP_LABEL_NOP, 1: JUMP_LABEL_JMP，见 include/linux/jump_label.h
{
	void *addr = (void *)jump_entry_code(entry);      // 先算出 addr(foo)
	u32 insn;

	if (type == JUMP_LABEL_JMP) {		          // 此时，需替换为 JAL offset
		long offset = jump_entry_target(entry) - jump_entry_code(entry); // offset = label(foo) - addr(foo)，即从 addr(foo) 跳转到 label(foo) 的距离

		if (WARN_ON(offset & 1 || offset < -524288 || offset >= 524288)) // 由于编码位数的限制，需要过滤掉一些值
			return;

		insn = RISCV_INSN_JAL |
			(((u32)offset & GENMASK(19, 12)) << (12 - 12)) |
			(((u32)offset & GENMASK(11, 11)) << (20 - 11)) |
			(((u32)offset & GENMASK(10,  1)) << (21 -  1)) |
			(((u32)offset & GENMASK(20, 20)) << (31 - 20));  // 指令编码部分请看该系列第 2 部分
	} else {
		insn = RISCV_INSN_NOP;
	}

	mutex_lock(&text_mutex);
	patch_text_nosync(addr, &insn, sizeof(insn)); // 替换目标 `addr(foo)` 所在位置为 nop 或 JAL offset，具体指令由 type 不同而编码出不同 insn
	mutex_unlock(&text_mutex);
```

## Tracepoint 如何使用 Jump Label

### 以 `sched_wait_task` Tracepoint 为例

先从用户态来看看内核提供的 Tracing events 接口：

```
$ sudo cat /sys/kernel/debug/tracing/available_events | grep ^sched
sched:sched_wake_idle_without_ipi
sched:sched_swap_numa
sched:sched_stick_numa
sched:sched_move_numa
sched:sched_process_hang
sched:sched_pi_setprio
sched:sched_stat_runtime
sched:sched_stat_blocked
sched:sched_stat_iowait
sched:sched_stat_sleep
sched:sched_stat_wait
sched:sched_process_exec
sched:sched_process_fork
sched:sched_process_wait
sched:sched_wait_task
sched:sched_process_exit
sched:sched_process_free
sched:sched_migrate_task
sched:sched_switch
sched:sched_wakeup_new
sched:sched_wakeup
sched:sched_waking
sched:sched_kthread_stop_ret
sched:sched_kthread_stop
```

其中就有 `sched_waait_task`，其启停接口为：

```
$ cat /sys/kernel/debug/tracing/events/sched/sched_wait_task/enable
0
```

默认为 0，可写入 1 开启。当然，也可以通过 `tracing/set_event` 来进行设置，该 event 的用法这里不做进一步介绍，请参考资料 `Documentation/trace/events.rst`。

### `sched_wait_task` Tracepoint 加在什么位置

内核中通过 `trace_sched_wait_task()` 函数来获取正在等待进入 unschedule 的进程，该 Tracepoint 被加在 `wait_task_inactive()`：

```
// kernel/sched/core.c: 3214

unsigned long wait_task_inactive(struct task_struct *p, unsigned int match_state)
{
		...
		rq = task_rq_lock(p, &rf);
		trace_sched_wait_task(p);
		running = task_running(rq, p);
		...
}
```

### `trace_sched_wait_task()` 跟踪函数如何定义

这部分的宏定义非常复杂，套了很多层，理解起来非常困难，大家感兴趣可以参考 `Documentation/trace/tracepoints.rst`。

咱们把相关的 `__DECLARE_TRACE` 和 `DEFINE_TRACE_FN` 两部分摘出来：

```
#define __DECLARE_TRACE(name, proto, args, cond, data_proto)		\
	extern int __traceiter_##name(data_proto);			\
	DECLARE_STATIC_CALL(tp_func_##name, __traceiter_##name);	\
	extern struct tracepoint __tracepoint_##name;			\
	static inline void trace_##name(proto)				\
	{								\
		if (static_key_false(&__tracepoint_##name.key))		\
			__DO_TRACE(name,				\
				TP_ARGS(args),				\
				TP_CONDITION(cond), 0);			\

#define DEFINE_TRACE_FN(_name, _reg, _unreg, proto, args)		\
	static const char __tpstrtab_##_name[]				\
	__section("__tracepoints_strings") = #_name;			\
	extern struct static_call_key STATIC_CALL_KEY(tp_func_##_name);	\
	int __traceiter_##_name(void *__data, proto);			\
	struct tracepoint __tracepoint_##_name	__used			\
	__section("__tracepoints") = {					\
		.name = __tpstrtab_##_name,				\
		.key = STATIC_KEY_INIT_FALSE,				\

```

其中 `__DECLARE_TRACE` 定义了最终 `trace_sched_wait_task` 函数，其中恰好就用到了 `static_key_false(&__tracepoint_sched_wait_task.key)`：

```
static inline void trace_##name(proto)				\
{								\
	if (static_key_false(&__tracepoint_##name.key))		\
		__DO_TRACE(name,				\
			TP_ARGS(args),				\
			TP_CONDITION(cond), 0);			\
```

而 `DEFINE_TRACE_FN` 则定义了 `__tracepoint_sched_wait_task.key` 并初始化成了 `STATIC_KEY_INIT_FALSE`：

```
	__section("__tracepoints") = {					\
		.name = __tpstrtab_##_name,				\
		.key = STATIC_KEY_INIT_FALSE,
```

### 如何实现 `sched_wait_task` Tracepoint 的启停

本文前面已经介绍了启停接口：`static_key_enable()` 和 `static_key_disable()`，Tracepoint 就是通过它们实现启用和停止的。

```
// kernel/tracepoint.c:320

/*
 * Add the probe function to a tracepoint.
 */
static int tracepoint_add_func(struct tracepoint *tp,
			       struct tracepoint_func *func, int prio,
			       bool warn)
{
	...
	switch (nr_func_state(tp_funcs)) {
	case TP_FUNC_1:		/* 0->1 */
		...
		static_key_enable(&tp->key);
		break;

// kernel/tracepoint.c:396

static int tracepoint_remove_func(struct tracepoint *tp,
		struct tracepoint_func *func)
{
	...
	switch (nr_func_state(tp_funcs)) {
	case TP_FUNC_0:		/* 1->0 */
		...
		static_key_disable(&tp->key);
		...
		break;
```

## 新版本接口：static_branch_unlikely()/static_branch_likely()

### 新版接口定义

虽然 Tracepoint 还在使用 `static_key_false()`，但是实际上 Jump Label 已经把这类接口说明为 `DEPRECATED`，并建议使用新版的接口，也就是：

```
#define static_branch_likely(x)							\
({										\
	bool branch;								\
	if (__builtin_types_compatible_p(typeof(*x), struct static_key_true))	\
		branch = !arch_static_branch(&(x)->key, true);			\
	else if (__builtin_types_compatible_p(typeof(*x), struct static_key_false)) \
		branch = !arch_static_branch_jump(&(x)->key, true);		\
	else									\
		branch = ____wrong_branch_error();				\
	likely_notrace(branch);								\
})

#define static_branch_unlikely(x)						\
({										\
	bool branch;								\
	if (__builtin_types_compatible_p(typeof(*x), struct static_key_true))	\
		branch = arch_static_branch_jump(&(x)->key, false);		\
	else if (__builtin_types_compatible_p(typeof(*x), struct static_key_false)) \
		branch = arch_static_branch(&(x)->key, false);			\
	else									\
		branch = ____wrong_branch_error();				\
	unlikely_notrace(branch);							\
})

```

`likely` 和 `unlikely` 涉及比较 “繁杂” 的逻辑思考，由于其他部分均可以类推出来，这里仅分析本文从开篇到现在的一种情况：即 `unlikely`（期待为 false/0）并且初始条件为 `false` 的情况，即：

```
#define static_branch_unlikely(x)						\
({										\
	bool branch;								\
	...
	else if (__builtin_types_compatible_p(typeof(*x), struct static_key_false)) \
		branch = arch_static_branch(&(x)->key, false);			\
	...
	unlikely_notrace(branch);							\
})
```

以上自动检测目标变量的类型，如果是 `static_key_false`，那么使用 `arch_static_branch(&(x)->key, false)` 这一情况，即默认为 `nop`，如果启用，才切换为 `JAL offset`。

```
// include/linux/compiler.h:20
#define likely_notrace(x)	__builtin_expect(!!(x), 1)
#define unlikely_notrace(x)	__builtin_expect(!!(x), 0)
```

如代码所示，`unlikely` 的本意是，期望目标值为 `0`，对应到 `arch_static_branch`，就是希望 `branch` 参数为 0，不跳转，也就是 `nop`。

相应地，启停接口也有新版本，虽然实际上还是调用的老版本：

```
// include/linux/jump_label.h:529

#define static_branch_enable(x)			static_key_enable(&(x)->key)
#define static_branch_disable(x)		static_key_disable(&(x)->key)
```

### 新版用法：以 schedstats 为例

新版在很多地方被广泛使用，本节举例介绍。同样地，以调度器中的调度统计功能 `schedstats` 为例，相关的定义如下：

```
// kernel/sched/core.c:

DEFINE_STATIC_KEY_FALSE(sched_schedstats);

static void set_schedstats(bool enabled)
{
	if (enabled)
		static_branch_enable(&sched_schedstats);
	else
		static_branch_disable(&sched_schedstats);
}

// kernel/sched/stats.h:35

#define   schedstat_enabled()		static_branch_unlikely(&sched_schedstats)
```

以上封装了一个使能接口：`set_schedstats` 和一个条件判断接口：`schedstat_enabled()`，分别调用了 Static Branch 提供的最新启停接口和 `unlikely` 条件判断接口。

如下所示，使用 `schedstat_enabled()` 判断的位置达 30+ 处，而且是核心的调度代码：

```
$ grep schedstat_enabled -ur kernel/sched/
kernel/sched/deadline.c:	if (!schedstat_enabled())
kernel/sched/deadline.c:	if (!schedstat_enabled())
kernel/sched/deadline.c:	if (!schedstat_enabled())
kernel/sched/deadline.c:	if (!schedstat_enabled())
kernel/sched/deadline.c:	if (!schedstat_enabled())
kernel/sched/core.c:	if (!schedstat_enabled())
kernel/sched/core.c:void force_schedstat_enabled(void)
kernel/sched/core.c:	if (!schedstat_enabled()) {
kernel/sched/core.c:	if (schedstat_enabled() && rq->core->core_forceidle_count) {
kernel/sched/core.c:	if (schedstat_enabled() && tg != &root_task_group) {
kernel/sched/debug.c:	if (schedstat_enabled()) {
kernel/sched/debug.c:	if (schedstat_enabled()) {
kernel/sched/debug.c:	if (schedstat_enabled()) {
kernel/sched/fair.c:	if (schedstat_enabled()) {
kernel/sched/fair.c:	if (!schedstat_enabled())
kernel/sched/fair.c:	if (!schedstat_enabled())
kernel/sched/fair.c:	if (!schedstat_enabled())
kernel/sched/fair.c:	if (!schedstat_enabled())
kernel/sched/fair.c:	if (!schedstat_enabled())
kernel/sched/fair.c:	if (schedstat_enabled() &&
kernel/sched/rt.c:	if (!schedstat_enabled())
kernel/sched/rt.c:	if (!schedstat_enabled())
kernel/sched/rt.c:	if (!schedstat_enabled())
kernel/sched/rt.c:	if (!schedstat_enabled())
kernel/sched/rt.c:	if (!schedstat_enabled())
kernel/sched/sched.h:	if (schedstat_enabled())
kernel/sched/sched.h:	if (sched_core_enabled(rq) && schedstat_enabled())
kernel/sched/stats.h:#define   schedstat_enabled()		static_branch_unlikely(&sched_schedstats)
kernel/sched/stats.h:#define   schedstat_inc(var)		do { if (schedstat_enabled()) { var++; } } while (0)
kernel/sched/stats.h:#define   schedstat_add(var, amt)	do { if (schedstat_enabled()) { var += (amt); } } while (0)
kernel/sched/stats.h:#define   schedstat_set(var, val)	do { if (schedstat_enabled()) { var = (val); } } while (0)
kernel/sched/stats.h:#define   schedstat_val_or_zero(var)	((schedstat_enabled()) ? (var) : 0)
kernel/sched/stats.h:	if (schedstat_enabled())
kernel/sched/stats.h:# define   schedstat_enabled()		0
```
根据第 1 部分测试的数据以及 `Documentation/staging/static-keys.rst` 中的性能数据分析，可以预期这一块会对整体性能有一定的提升效果。

接下来是最终调用启停接口的位置，有两处，一处是通过内核参数传递 `schedstats=enable|disable`，另外一处是 `/proc/sys/kernel/sched_schedstats` 接口。

```
$ cat /proc/sys/kernel/sched_schedstats
0
```

相关代码见：

```
// kernel/sched/core.c:4333

static int __init setup_schedstats(char *str)
{
	int ret = 0;
	if (!str)
		goto out;

	if (!strcmp(str, "enable")) {
		set_schedstats(true);   // static branch 启用
		ret = 1;
	} else if (!strcmp(str, "disable")) {
		set_schedstats(false);  // static branch 禁用
		ret = 1;
	}
out:
	if (!ret)
		pr_warn("Unable to parse schedstats=\n");

	return ret;
}
__setup("schedstats=", setup_schedstats);

#ifdef CONFIG_PROC_SYSCTL
int sysctl_schedstats(struct ctl_table *table, int write, void *buffer,
		size_t *lenp, loff_t *ppos)
{
	struct ctl_table t;
	int err;
	int state = static_branch_likely(&sched_schedstats);

	if (write && !capable(CAP_SYS_ADMIN))
		return -EPERM;

	t = *table;
	t.data = &state;
	err = proc_dointvec_minmax(&t, write, buffer, lenp, ppos);
	if (err < 0)
		return err;
	if (write)
		set_schedstats(state);   // static branch 启停
	return err;
}
#endif /* CONFIG_PROC_SYSCTL */
```

## 小结

以上详细介绍了 Jump Label 最核心的 Static Branch 的实现以及 Tracepoint 具体使用 Static Branch 技术的案例，同时也简单对比了新老接口与用法。

本文介绍的 `sched_wait_task` Tracepoint 以及 schedstats 案例非常经典，在其他内核、驱动等关键路径中也可以参考把 Static Branch 真正用起来，因为它能在禁用的情况下基本消除条件判断带来的性能开销，而且可以按需启停，从而允许在编译时开启各种调试、测试与统计选项，从而方便用户在线上按需使用。

在这之前，因为担心调试等功能带来的性能损失，对于线上产品，用户必须去掉相关功能从而避免带来性能损失，但是，有了 Static Branch 以后，用户基本可以消除这方面的顾虑，一方面，在禁用情况下，这些选项等同于 `nop`，带来的损失很小，另外一方面，可以很细粒度地开启需要的功能，把调试等功能带来的开销降低到很小，用完以后又可以随时关闭。

最后 1 篇将进一步介绍最底层的运行时代码修改逻辑，即 `patch_text_nosync()` 以及相关变体的实现。

```
// arch/riscv/kernel/jump_label.c:39

patch_text_nosync(addr, &insn, sizeof(insn));
```

## 参考资料

* [Jump Label](https://lwn.net/Articles/412072/)
* [Tracepoint](https://www.kernel.org/doc/html/latest/core-api/tracepoint.html)
* [RISC-V Assembly Programmer's Manual](https://github.com/riscv-non-isa/riscv-asm-manual/blob/master/riscv-asm.md)
* [All Aboard, Part 3: Linker Relaxation in the RISC-V Toolchain](https://www.sifive.com/blog/all-aboard-part-3-linker-relaxation-in-riscv-toolchain)
* Documentation/staging/static-keys.rst
* Documentation/trace/events.rst
* Documentation/trace/tracepoints.rst
