---
layout: post
author: 'Jinyu'
title: 'RISC-V 架构下内核线程返回函数探究'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-kthread-ret/
description: '本文探究 RISC-V 架构下的内核线程返回函数。'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - 内核线程
  - 返回函数
---

> Author:  tjytimi  <tjytimi@163.com>
> Date:    2022/07/25
> Revisor: lzufalcon <falcon@tinylab.org>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)

## 简介

在分析 RISC-V 架构下进程创建代码时，对内核线程创建有个困惑：即内核线程创建时设置的返回函数 `ret_from_kernel_thread` 最后有恢复内核堆栈中寄存器上下文和返回用户态的步骤，看起来非常反直觉。代码中也没有注释。MIPS 架构下处理类似，但查阅 MIPS 架构相关书籍也没有对此进行解说。

在具备调试环境后，对此问题进行分析并实验验证，发现与进程创建，用户程序加载，内核启动时 1 号进程和 2 号进程行为均有关联。

本文中关于内核线程创建，进程调度等介绍较为简略，读者可参考本项目有关进程创建与进程调度相关分析文章。

本文内核版本为 Linux 5.17。分析调试时使用 [Linux Lab](https://tinylab.org/linux-lab) 中 `ricsv64/virt` 虚拟板。

## ret_from_kernel_thread 会恢复内核栈并回到用户态所带来的疑问

在内核线程创建时，`copy_thread` 函数会将内核堆栈中寄存器上下文 `childregs` 置 0 ，将线程上下文 `thread` 中 `ra` 设置成 `ret_from_kernel_thread` 函数地址，线程上下文的 `s[0]` 设置为 `fn` 的地址（`fn` 为新建内核线程时传入执行函数），`s[1]` 设置为 `arg`（`arg` 为 `fn` 的参数）。

```c
// arch/riscv/kernel/process.c : 128
if (unlikely(p->flags & (PF_KTHREAD | PF_IO_WORKER))) {
		/* Kernel thread */
		memset(childregs, 0, sizeof(struct pt_regs));
		childregs->gp = gp_in_global;
		/* Supervisor/Machine, irqs on: */
		childregs->status = SR_PP | SR_PIE;

		p->thread.ra = (unsigned long)ret_from_kernel_thread;
		p->thread.s[0] = usp; /* fn */
		p->thread.s[1] = arg;
}
```

新建的内核线程被调度后，`__switch_to` 汇编将存储在线程上下文 `p->thread` 中的寄存器值加载到 CPU 后，最后 `ret` 指令会让CPU执行 `ra` 寄存器对应的 `ret_from_kernel_thread` 汇编程序。该汇编定义如下：

```
// arch/riscv/kernel/entry.S :493
ENTRY(ret_from_kernel_thread)
	call schedule_tail
	/* Call fn(arg) */
	la ra, ret_from_exception
	move a0, s1
	jr s0
ENDPROC(ret_from_kernel_thread)
```

该汇编函数首先调用 `schedule_tail` 进行调度收尾工作。随后将 `ret_from_exception` 汇编地址压入寄存器 `ra`，接着调用 `s0` 寄存器对应的函数， `s1` 寄存器作为此函数的参数，执行上文所述的 `fn(arg)` 。

从代码来看，`fn(arg)` 执行完成返回后，将执行 `ret_from_exception` 汇编函数，而 `ret_from_exception` 汇编会调用恢复内核堆栈寄存器上下文至寄存器并返回用户态的汇编函数 `restore_all` （此汇编的详细分析见本项目进程创建分析）。这就带来一个疑问，内核线程初始化时，已经将该线程内核堆栈寄存器上下文 `childregs` 置 0，且内核线程并不是从用户态创建并陷入内核态的，为何会有恢复内核堆栈寄存器上下文并返回用户态的动作？

## 返回用户态的目的探究

首先，我们将 `ret_from_exception` 从 `ret_from_kernel_thread` 中注释掉，看看不返回用户态会出现什么问题。

```
ENTRY(ret_from_kernel_thread)
	call schedule_tail
	/* Call fn(arg) */
/*	la ra, ret_from_exception */
	move a0, s1
	jr s0
ENDPROC(ret_from_kernel_thread)
```

用 Linux Lab 编译后启动，打印信息如下后就停止运行：

```
VFS: Mounted root (ext2 filesystem) on device 254:0.
devtmpfs: mounted
Freeing unused kernel image (initmem) memory: 2436K
Run /sbin/init as init proces
```

搜索代码可知，内核启动停止在 `kernel_init` 内核线程启动文件系统中的用户 `init` 程序处。`kernel_init` 是在初始进程（0 号进程）中启动的 1 号进程。Linux 的 1 号进程加载用户态 `init` 程序后，会变成第一个用户进程，成为其他所有用户进程的祖先。

原来 `ret_from_exception` 返回用户态的动作是为了保证 1 号进程 `kernel_init` 能顺利从内核态进入到用户态。从而完成 Linux 启动过程由内核态到用户态的跳转，这是后续用户态程序得以创建并执行的基础。

### 1 号进程加载 init 程序并返回用户态的代码实现

1 号进程是在 `rest_init` 函数中调用 `kernel_thread` 启动的。

```c
// init/main.c : 679
noinline void __ref rest_init(void)
{
	struct task_struct *tsk;
	int pid;

	rcu_scheduler_starting();
	/*
	 * We need to spawn init first so that it obtains pid 1, however
	 * the init task will end up wanting to create kthreads, which, if
	 * we schedule it before we create kthreadd, will OOPS.
	 */
	pid = kernel_thread(kernel_init, NULL, CLONE_FS);

	...
}
```

该进程执行的函数实体是 `kernel_init` 函数，该函数无参数输入。`kernel_init` 完成内核态的相关工作后（这部分内容与本文无关不进行说明），调用 `try_to_run_init_process` 做执行用户态 init 程序的准备工作。init 程序有多个可能路径，按照顺序优先级搜索，只执行最先找到的。`try_to_run_init_process` 函数如下：

```c
// fs/binfmt_els.c : 823
static int try_to_run_init_process(const char *init_filename)
{
	int ret;

	ret = run_init_process(init_filename);

	if (ret && ret != -ENOENT) {
		pr_err("Starting init: %s exists but couldn't execute it (error %d)\n",
		       init_filename, ret);
	}

	return ret;
}
```

可见其主要调用 `run_init_process` 实现功能。`run_init_process` 调用 `kernel_execve` 函数，此函数为内核态执行应用程序的接口。通过如下调用链，最终会调用 `load_elf_binary`。

```
run_init_process
	-->kernel_execve
		-->bprm_execve
			-->exec_binprm
				-->search_binary_handler
					-->fmt->load_binary
						-->load_elf_binary
```

`load_elf_binary` 为启动 elf 格式应用程序的函数，实际上在用户态执行 exec 类系统调用时，陷入内核态后也会调用此函数执行加载应用程序功能。此函数非常庞大复杂，这里只抽取与本文相关的内容如下：

```c
static int load_elf_binary(struct linux_binprm *bprm)
{

...

regs = current_pt_regs();


	finalize_exec(bprm);
	START_THREAD(elf_ex, regs, elf_entry, bprm->p);

...

}
```

可见其获取了该进程内核栈寄存器上下文地址 `regs`，用户程序入口地址 `elf_entry` 和用户堆栈指针 `bprm->p` 并传给 `START_THREAD` 宏。

```c
#define START_THREAD(elf_ex, regs, elf_entry, start_stack)	\
	start_thread(regs, elf_entry, start_stack)
#endif
```

`START_THREAD` 宏展开后为 `start_thread` 函数，定义如下：

```c
void start_thread(struct pt_regs *regs, unsigned long pc,
	unsigned long sp)
{
	printk("come to start_thread\n");
	regs->status = SR_PIE;
	if (has_fpu()) {
		regs->status |= SR_FS_INITIAL;
		/*
		 * Restore the initial value to the FP register
		 * before starting the user program.
		 */
		fstate_restore(current, regs);
	}
	regs->epc = pc;
	regs->sp = sp;
}
```

`start_thread` 函数将入口地址和用户栈地址分别传入内核栈寄存器上下文对应字段。这就解答了之前关于已经将内核栈寄存器上下文初始化为 0 却要从中恢复寄存器的值的疑惑。

完成上述工作后，1 号进程结束 `kernel_init` 函数执行。`kernel_init` 函数汇编后最后的 `ret` 指令使处理器执行存储在 `ra` 寄存器所指向的 `ret_from_exception`。
`ret_from_exception` 汇编最后执行 `restore_all` 即恢复内核栈存储的寄存器上下文到寄存器，并在执行完最后一个 `sret` 指令后，将内核线程变为用户态进程，`epc` 寄存器中入口地址就是上文所述的 `elf_entry`。

至此，系统第一个用户进程 `init` 诞生，这将是今后所有用户进程的祖先。

### 非 1 号进程的内核线程是否需要返回用户态？

通过上文分析可知，内核线程 `ret_from_kernel_thread` 汇编中有返回用户态流程是为了 1 号进程能转到用户态执行用户态程序。那对其他内核线程，是否也有作用呢？修改代码进行了实验。

增加一个没有 `ret_from_exception` 的汇编 `ret_from_kernel_thread_no_ret`，并在内核线程创建的代码处，把非 1 号 和 2 号 线程（父进程非 0 的内核线程）的线程上下文结构体中 ra 设为`ret_from_kernel_thread_no_ret`。具体如下：

```
ENTRY(ret_from_kernel_thread_no_ret)
	call schedule_tail
	/* Call fn(arg) */
/*	la ra, ret_from_exception */
	move a0, s1
	jr s0
ENDPROC(ret_from_kernel_thread_no_ret)
```

```c
int copy_thread(unsigned long clone_flags, unsigned long usp, unsigned long arg,
		struct task_struct *p, unsigned long tls)
{
...
		if (p->pid)
			p->thread.ra = (unsigned long)ret_from_kernel_thread_no_ret;
		else
			p->thread.ra =  (unsigned long)ret_from_kernel_thread;
...
}
```

使用 Linux Lab 进行测试，发现可正常运行。

所以可以确认只要内核线程没有执行用户态程序的需求，根本不需要执行到汇编 `ret_from_exception`。



## 通过模板建立的内核线程不会运行到 ret_from_exception

通过上面的分析可知，除了 1 号进程外，内核线程根本不需要返回用户态。并且可以预见，如果非 1 号的内核线程执行到 `ret_from_exception` ，还会由于对应内核栈寄存器上下文 `epc` 等已设置为 0，导致系统错误。

那内核是如何避免这种情况发生的呢？答案是通过模板建立内核线程，让 2 号线程代理。

一般内核或驱动中创建内核线程会直接或间接调用 `kthread_create_on_node`（如 `kthread_run`，`kthread_crate` 等宏均会扩展到 `kthread_create_on_node`）来创建内核线程，`kthread_create_on_node` 函数通过将待执行的内核线程信息加入 `kthread_create_list` 队列，委托 2 号进程代为建立。

和 1 号进程一样，2 号进程同样在 `rest_init` 函数中调用 `kernel_thread` 启动。

```c
// init/main.c : 679
noinline void __ref rest_init(void)
{
	...

	numa_default_policy();
	pid = kernel_thread(kthreadd, NULL, CLONE_FS | CLONE_FILES);

	...

}
```
2 号进程的设计可以保证不会运行到 `ret_from_exception` 函数而造成错误。

以下对 2 号进程代为创建内核线程的流程进行说明：

- 2 号进程会执行 `kthreadd` 函数实体，`kthreadd` 函数从 `kthread_create_list` 队列中取出一个待启动的内核线程信息结构体元素 `create`。

- 接着调用 `create_kthread` 函数，该函数会调用 `kernel_thread` 创建一个内核线程，该线程执行 `kthread` 函数，`create` 作为 `kthread` 的参数。此时在 `kthread_create_on_node` 希望创建的内核线程实体才真正开始建立。

- `kthread` 函数取出 `create` 中包含的真正待执行的 `fn` 和 `arg` 分别赋给 `threadfn` 和 `data`，在 `ret = threadfn(data)` 代码处真正执行在 `kthread_create_on_node` 中指定的函数;

- 如果 `fn` 是一个会退出的函数，那么在 `ret = threadfn(data)` 运行结束后，会执行 `kthread` 中最后的 `kthread_exit(ret)`， `kthread_exit` 实际上调用了 `do_exit` 函数，也就是主动退出了该内核线程。这样，就保证不会运行到 `ret_from_exception` 处，不会有返回用户态的流程。

- 2 号内核线程的 for 循环没有跳出出语句，2 号内核线程不断的尝试从队列中获取希望执行的内核线程，其本身也不会执行到 `ret_from_exception`。

以上流程中涉及的代码如下，非相关部分已去除：

```c
////kernel/kthread.c : 718
int kthreadd(void *unused)
{
	...

	for (;;) {

		...

		spin_lock(&kthread_create_lock);
		while (!list_empty(&kthread_create_list)) {
			struct kthread_create_info *create;

			create = list_entry(kthread_create_list.next,
					    struct kthread_create_info, list);
			list_del_init(&create->list);
			spin_unlock(&kthread_create_lock);

			create_kthread(create);

			spin_lock(&kthread_create_lock);
		}
		spin_unlock(&kthread_create_lock);
	}

	return 0;
}


//kernel/kthread.c : 392
static void create_kthread(struct kthread_create_info *create)
{
	...
	pid = kernel_thread(kthread, create, CLONE_FS | CLONE_FILES | SIGCHLD);
	...
}


//kernel/kthread.c : 331
static int kthread(void *_create){
	...
	if (!test_bit(KTHREAD_SHOULD_STOP, &self->flags)) {
		cgroup_kthread_ready();
		__kthread_parkme(self);
		ret = threadfn(data);
	}
	kthread_exit(ret);
}

```

## 如何直接用 kernel_thread API 创建非循环运行的内核线程？


如果说就想调用 `kernel_thread` 来创建内核线程，且线程函数实体不是永远循环的，有没有什么办法呢？

经测试，需要手动在函数实体最后加一句 `kthread_exit(0)`，保证该内核线程执行完函数实体就退出，不会执行到 `ret_from_exception`。

在内核代码中增加的测试代码如下：

```
@@ -676,11 +676,21 @@ static void __init setup_command_line(char *command_line)

 static __initdata DECLARE_COMPLETION(kthreadd_done);

+static int __ref kernel_try(void * unused)
+{
+       int i = 0;
+       printk("come to kernel_try\n");
+       for (i = 0; i < 10; i++)
+               printk("hello banana %d\n",i);
+       kthread_exit(0);
+}
+
 noinline void __ref rest_init(void)
 {
        struct task_struct *tsk;
+
        int pid;
-
+       printk("come to rest_init\n");
        rcu_scheduler_starting();
        /*
         * We need to spawn init first so that it obtains pid 1, however
@@ -688,6 +698,8 @@ noinline void __ref rest_init(void)
         * we schedule it before we create kthreadd, will OOPS.
         */
        pid = kernel_thread(kernel_init, NULL, CLONE_FS);
+
+       pid = kernel_thread(kernel_try, NULL, CLONE_FS );

```

使用 Linux Lab 进行编译并运行，系统可正常启动并运行，得到相关的打印如下：

```
come to rest_init
come to kernel_try
hello banana 0
hello banana 1
hello banana 2
hello banana 3
hello banana 4
hello banana 5
hello banana 6
hello banana 7
hello banana 8
hello banana 9
```

如果函数中不增加 `kthread_exit(0)`，则会出现宕机。

## 总结

本文分析并实验了内核线程创建时设置的返回函数 `ret_from_kernel_thread` 有关细节，该细节与进程创建，用户程序加载，内核启动时 1 号进程和 2 号进程的行为均有联系，这反映了内核各部分之间存在普遍的联系。不断深挖的过程也是学习内核的有趣之处。

## 参考资料

[1] 陈华才. 用"芯"探核 基于龙芯的 Linux 内核探索解析[M].北京:中国工信出版社/人民邮电出版社,2020.
