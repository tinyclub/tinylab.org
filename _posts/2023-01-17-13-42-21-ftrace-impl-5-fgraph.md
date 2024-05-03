---
layout: post
author: 'Song Shuai'
title: 'RISC-V Ftrace 实现原理（5）- 动态函数图跟踪'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /ftrace-impl-5-fgraph/
description: 'RISC-V Ftrace 实现原理（5）- 动态函数图跟踪'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - Ftrace
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [comments codeblock codeinline epw]
> Author:   sugarfillet <sugarfillet@yeah.net>
> Date:     2022/09/28
> Revisor:  Falcon falcon@tinylab.org
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V ftrace 相关技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I58N1O)
> Sponsor:  PLCT Lab, ISCAS


## 前言

本系列的 [第三篇文章][2]，我们分析了指定一个目标函数 `vfs_read` 进行跟踪的工作过程，并从运行时的角度，观察到内核函数入口经过指令替换后，会跳转到 `ftrace_caller` 这个 `mcount` 函数。

[第四篇文章][3]，我们分析了 `function` tracer 使能的工作过程，观察 `ftrace_caller` 中的 `ftrace_call` 是如何被替换成 `function` tracer 的跟踪函数，以及 `ftrace_caller` 如何为跟踪函数设置上下文。

如果把 tracefs 拿掉再去看 ftrace 会发现，动态函数跟踪才是 ftrace 的核心机制，其至少实现了以下功能：

- 运行时角度
  - 实现 `ftrace_caller` 为跟踪函数设置上下文，并调用跟踪函数

- 指令替换的角度
  - 能够对指定的内核函数入口进行指令替换，使其跳转到 `ftrace_caller`
  - 能够对跟踪函数进行更新，使指定的跟踪函数能够被调用

动态函数跟踪还以我们熟悉的 `ftrace_run_update_code()` 函数为基础向上提供了以 `struct ftrace_ops` 为参数的 `ftrace_set_filter()`、`register_ftrace_function()` 两个接口。

1. `ftrace_set_filter()` 函数作为辅助函数，指定目标函数，并将其添加到 `ops->func_hash->filter_hash` 中
2. `register_ftrace_function()` 函数更新跟踪函数，并执行对内核函数入口及 `ftrace_call` 的指令替换

这两个函数是在非 tracefs 场景下使用 ftrace 进行函数跟踪的标准接口，内核文档中也对其做了详细的使用介绍，可以参考 [这里][1]，而其用户就有我们熟知的 livepatch、kprobe、fprobe 等。而在 tracefs 场景下，所有的 function 类型 tracer（即调用 `register_ftrace_function()` 函数来注册跟踪函数的 tracer）共用 `global_ops`，通过 `set_ftrace_filter` 文件接口来设置目标函数，通过把自己的跟踪函数设置在 `global_ops->func` 上来实现跟踪函数的更新。

而动态函数跟踪只是在函数入口调用跟踪函数，那有没有机制能够在函数返回时也能调用跟踪函数呢？当然有，它就是函数图跟踪（`HAVE_FUNCTION_GRAPH_TRACER`）。

函数图跟踪机制，最初只是作为 `function_graph` tracer 的一部分出现在内核中，用来跟踪某个内核函数运行时的子函数调用及其时间消耗，并输出一个函数调用图，后来作为 ftrace 跟踪内核函数入口和返回的核心机制，独立到 `kernel/trace/fgraph.c` 文件中。

与动态函数跟踪相比，动态函数图跟踪机制对以下内容作出调整：

1. `ftrace_caller` 的支持

   引入 `prepare_ftrace_return()` 函数与 `return_to_handler` 汇编码。在函数入口跳转到 `ftrace_caller` 时执行 `prepare_ftrace_return()`，调用入口跟踪函数，并以 `return_to_handler` 覆盖函数返回地址，使得 `return_to_handler` 在函数返回时执行，调用返回跟踪函数，跳转到原函数的返回地址。

   `ftrace_caller` 需要为调用 `prepare_ftrace_return()` 函数准备上下文。

2. 替换指定函数入口

   替换函数入口，使得内核运行时可以在函数入口跳转到 `ftrace_caller` 执行，此功能在动态函数跟踪中已经实现，可以参考本系列的第三篇文章。

   而指定某个函数进行跟踪，相比于动态函数跟踪的 `ftrace_set_filter` 接口，动态函数图跟踪只提供 `ftrace_graph_hash`、`ftrace_graph_notrace_hash` 两个 hash 用来指定需要进行图跟踪的函数，通过 tracefs 的 `set_graph_function|set_graph_notrace` 文件接口和内核命令行选项 `ftrace_graph_filter=` 来设置，并提供 `ftrace_graph_addr()` 函数用来在入口跟踪函数中校验指定函数是否需要跟踪。

3. 更新跟踪函数

   相比于动态函数跟踪中的全局函数跟踪函数 `ftrace_trace_function`，动态函数图跟踪提供全局入口跟踪函数 `ftrace_graph_entry()` 与全局返回跟踪函数 `ftrace_graph_return()`，分别在 `prepare_ftrace_return()` 函数与 `return_to_handler` 汇编码中被调用。而对于这两个函数的设置，通过图跟踪函数（入口/返回跟踪函数）的标准注册接口 `register_ftrace_graph()` 来实现。

指定某个函数进行图跟踪部分的实现相对简单，且与另外两部分关系不大，有兴趣的同学可以以 `set_graph_function` 文件相关操作结构为切入点进行分析，这里不做展开。

本文重点以 `ftracer_caller` 对动态函数图跟踪的支持、图跟踪函数的更新过程两个部分进行分析。

**说明**：

  * 动态函数图跟踪：即 Function Graph 机制，实现对内核函数入口和函数返回的跟踪
  * 图跟踪函数：即 Function Graph 使用的两个分别对函数入口和函数返回进行跟踪的跟踪函数
  * 本文的 Linux 版本采用 `Linux 5.18-rc1`

## ftrace_caller 的支持

`ftrace_caller` 中为 `prepare_ftrace_return()` 函数设置参数：

1. a0 对应第一个参数 `* parent`，代表当前函数的返回地址的指针，通过 `sp + ABI_SIZE_ON_STACK (72)` 获取
2. a1 对应第二个参数 `self_addr`，代表当前函数的入口地址，通过存放函数入口第四条指令的 ra 减去 `FENTRY_RA_OFFSET (12)` 获得函数入口
3. a2 对应第三个参数 `frame_pointer`，代表帧指针，通过 s0 获取

并定义 `ftrace_graph_call` 标签，默认调用直接返回的 `ftrace_stub`。`ftrace_caller` 相关实现及 `prepare_ftrace_return()` 声明代码如下：

```c
// arch/riscv/kernel/mcount-dyn.S ：144

ENTRY(ftrace_caller)
        SAVE_ABI

        addi    a0, ra, -FENTRY_RA_OFFSET
        la      a1, function_trace_op
        REG_L   a2, 0(a1)
        REG_L   a1, ABI_SIZE_ON_STACK(sp)
        mv      a3, sp

ftrace_call:
        .global ftrace_call
        call    ftrace_stub

#ifdef CONFIG_FUNCTION_GRAPH_TRACER
        addi    a0, sp, ABI_SIZE_ON_STACK  // parent 指针
        REG_L   a1, ABI_RA(sp)
        addi    a1, a1, -FENTRY_RA_OFFSET  // self_addr
#ifdef HAVE_FUNCTION_GRAPH_FP_TEST
        mv      a2, s0   // ftrame_pointer
#endif
ftrace_graph_call:
        .global ftrace_graph_call
        call    ftrace_stub   // replaced by prepare_ftrace_return
#endif
        RESTORE_ABI
        ret
ENDPROC(ftrace_caller)

void prepare_ftrace_return(unsigned long *parent, unsigned long self_addr,
                           unsigned long frame_pointer);
```

`prepare_ftrace_return()` 函数，执行 `function_graph_enter()` 函数调用入口跟踪函数，并用 `return_to_handler` 地址覆盖当前函数的返回地址的指针，从而能在函数返回时调用到。关键代码如下：

```c
// arch/riscv/kernel/ftrace.c ：181

void prepare_ftrace_return(unsigned long *parent, unsigned long self_addr,
                           unsigned long frame_pointer)
{
        unsigned long return_hooker = (unsigned long)&return_to_handler;
        unsigned long old;

        old = *parent;

        if (!function_graph_enter(old, self_addr, frame_pointer, parent))
                *parent = return_hooker;
}

```

`function_graph_enter()` 函数记录当前函数入口地址到 `trace.func`，当前线程的调用深度到 `trace.depth`，并将函数返回地址 `ret`、函数入口地址 `func`、帧指针 `frame_pointer`、返回地址指针 `retp` 存入当前线程的函数返回栈 `current->ret_stack[]`，之后以 `trace` 为入参调用全局入口跟踪函数 `ftrace_graph_entry()`。关键代码如下：

```c
// kernel/trace/fgraph.c : 102

int function_graph_enter(unsigned long ret, unsigned long func, unsigned long frame_pointer, unsigned long *retp)
  trace.func = func;
  trace.depth = ++current->curr_ret_depth;
  ftrace_push_return_trace(ret, func, frame_pointer, retp)
    index = ++current->curr_ret_stack;
	current->ret_stack[index].ret = ret; // ret func calltime fp retp
  ftrace_graph_entry(&trace)   // 全局函数入口跟踪函数
```

`return_to_handler` 在函数返回时被调用，执行如下操作：

1. `SAVE_RET_ABI_STATE`，栈增 4 字节，a0、s0、ra 依次入栈，将 s0 指向栈底
2. 原帧指针通过 t6 赋值给 a0，作为 `ftrace_return_to_handler()` 函数的入参
3. 调用 `ftrace_return_to_handler()` 函数，a0 寄存器保存此函数的返回值，即当前目标函数返回地址，为防止出栈操作覆盖 a0，保存 a0 到 a1
4. `RESTORE_RET_ABI_STATE`，恢复 a0、s0、ra、sp 寄存器
5. 跳转到 a1 即函数返回地址，至此函数执行完毕

关键代码如下：

```c
// arch/riscv/kernel/mcount.S ：57

ENTRY(return_to_handler)

#ifdef HAVE_FUNCTION_GRAPH_FP_TEST
        mv      t6, s0
#endif
        SAVE_RET_ABI_STATE
#ifdef HAVE_FUNCTION_GRAPH_FP_TEST
        mv      a0, t6
#endif
        call    ftrace_return_to_handler
        mv      a1, a0
        RESTORE_RET_ABI_STATE
        jalr    a1
ENDPROC(return_to_handler)
#endif

        .macro SAVE_RET_ABI_STATE
        addi    sp, sp, -32
        sd      s0, 16(sp)
        sd      ra, 24(sp)
        sd      a0, 8(sp)
        addi    s0, sp, 32
        .endm
```

`ftrace_return_to_handler()` 函数调用 `ftrace_pop_return_trace()` 函数，检查帧指针是否与目标函数入口保存的帧指针一致，并设置函数入口地址 `trace->func`、函数入口调用时间 `trace->calltime`、当前线程调用深度 `trace->depth`、函数返回地址 `ret`。`ftrace_return_to_handler()` 函数之后以 `trace` 为入参调用全局返回跟踪函数 `ftrace_graph_return()`，并以函数地址 `ret` 返回。

```c
// kernel/trace/fgraph.c ：223

unsigned long ftrace_return_to_handler(unsigned long frame_pointer)
{
        struct ftrace_graph_ret trace;
        unsigned long ret;

        ftrace_pop_return_trace(&trace, &ret, frame_pointer);
          index = current->curr_ret_stack;
          if current->ret_stack[index].fp != frame_pointer // 测试帧指针是否与函数入口保存的一致
             *ret = (unsigned long)panic;
          *ret = current->ret_stack[index].ret;
          trace->func = current->ret_stack[index].func;
          trace->calltime = current->ret_stack[index].calltime;
          trace->depth = current->curr_ret_depth--;

        trace.rettime = trace_clock_local();
        ftrace_graph_return(&trace);
        current->curr_ret_stack--;
        return ret;
}
```

动态图跟踪机制中，`ftrace_caller` 在函数入口时被调用，执行 `prepare_function_return()` 函数，执行 `function_graph_enter()` 函数调用入口跟踪函数，并以 `return_to_handler` 函数覆盖函数返回地址指针，在函数返回时，执行 `ftrace_graph_return()` 函数调用返回跟踪函数，之后，跳转到原函数返回地址。

## 更新图跟踪函数

全局入口跟踪函数 `ftrace_graph_entry()` 与全局返回跟踪函数 `ftrace_graph_return()`，跟我们在动态函数跟踪机制中提到的全局跟踪函数 `ftrace_trace_function()` 类似，后者通过跟踪函数标准注册接口 `register_ftrace_function()` 进行设置，而前者通过图跟踪函数（入口/返回跟踪函数）的标准注册接口 `register_ftrace_graph()` 将其赋值为当前注册者指定的图跟踪函数。由于 `function_graph` tracer 就是此接口的使用者，我们就以此 tracer 的使能为例进行说明：

与 `function` tracer 一致，`function_graph` 使能时会调用此 tracer 注册时指定的 `.init` 函数 - `graph_trace_init`，直接调用 `register_ftrace_graph()` 设置图跟踪函数。关键代码如下：

```c
// kernel/trace/trace_functions_graph.c ：294

static struct fgraph_ops funcgraph_ops = {
        .entryfunc = &trace_graph_entry,
        .retfunc = &trace_graph_return,
};

static int graph_trace_init(struct trace_array *tr){
        set_graph_array(tr);
        ret = register_ftrace_graph(&funcgraph_ops); // 设置图跟踪函数
        tracing_start_cmdline_record();

        return 0;
}
```

> 对比分析
>
> `register_ftrace_function()` 函数以 `struct ftrace_ops *` 为入参，注册用户指定的 ops
>
> `register_ftrace_graph()` 以 `struct fgraph_ops *` 为入参，只注册 `graph_ops`

`register_ftrace_graph()` 函数执行如下步骤：

1. 设置全局返回跟踪函数 `ftrace_graph_return()` 为 `gops->retfunc`
2. 临时设置 `__ftrace_graph_entry()` 为 `gops->entryfunc`，并把全局入口跟踪函数 `ftrace_graph_entry()` 设置为 `ftrace_graph_entry_test()`，之后执行 `update_function_graph_func()` 重新设置全局入口跟踪函数
3. 执行 `ftrace_startup()`，注册全局图操作结构 `graph_ops` 到 `ftrace_ops_list`，并执行 `FTRACE_START_FUNC_RET` 指令替换命令

关键代码如下：

```c
// kernel/trace/fgraph.c : 588

register_ftrace_graph(struct fgraph_ops *gops)
  ret = start_graph_tracing();
  ftrace_graph_return = gops->retfunc; // 设置全局返回跟踪函数
  __ftrace_graph_entry = gops->entryfunc;
  ftrace_graph_entry = ftrace_graph_entry_test; // 临时设置为 ftrace_graph_entry_test
  update_function_graph_func();
  ret = ftrace_startup(&graph_ops, FTRACE_START_FUNC_RET);
```

步骤 2 中，`ftrace_graph_entry_test()` 跟踪函数会先判断当前函数是否在 `global_ops->func_hash` 中，再执行 `__ftrace_graph_entry()`。在 `update_function_graph_func()` 函数中，遍历 `ftrace_ops_list`，如果存在不为 `global_ops` 或 `graph_ops` 的 ops，则继续采用 `ftrace_graph_entry_test()` 进行有判断的函数跟踪，避免不属于 `global_ops` 或者 `graph_ops` 需要跟踪的内核函数调用到 tracer 指定的入口跟踪函数。关键代码如下：

```c
static int ftrace_graph_entry_test(struct ftrace_graph_ent *trace)
{
        if (!ftrace_ops_test(&global_ops, trace->func, NULL))
                return 0;
        return __ftrace_graph_entry(trace);
}

void update_function_graph_func(void)
{
        struct ftrace_ops *op;
        bool do_test = false;

        do_for_each_ftrace_op(op, ftrace_ops_list) {
                if (op != &global_ops && op != &graph_ops &&
                    op != &ftrace_list_end) {
                        do_test = true;
                        goto out;
                }
        } while_for_each_ftrace_op(op);
 out:
        if (do_test)
                ftrace_graph_entry = ftrace_graph_entry_test;
        else
                ftrace_graph_entry = __ftrace_graph_entry;
}
```

步骤 3 中，`ftrace_startup()` 函数也会被 `register_ftrace_function()` 函数调用，而在注册图跟踪函数的过程中，涉及到以下变化：

1. `__register_ftrace_function()` 函数将 `graph_ops` 添加到全局链表中，并将全局跟踪函数设置为 `graph_ops->func` - `ftrace_stub`，全局入口跟踪函数设置为 `gops->entryfunc`
2. `ftrace_modify_all_code()` 函数处理 `FTRACE_START_FUNC_RET` 命令，执行 `ftrace_enable_ftrace_graph_caller()`，对 `ftrace_graph_call` 进行指令替换

关键代码如下：

```c
// kernel/trace/ftrace.c : 2910

ftrace_startup(struct ftrace_ops *ops, int command)
  __register_ftrace_function(ops)
    add_ftrace_ops(&ftrace_ops_list, ops); // 添加到 ops 列表中
    ops->saved_func = ops->func;
    update_ftrace_function(); // 设置 ftrace_trace_function
      update_function_graph_func(); // 设置 ftrace_graph_entry 为 gops->entryfunc，变化 1

  ftrace_hash_ipmodify_enable(ops); // 更新 rec 的 ipmodify flag
  if (ftrace_hash_rec_enable(ops, 1))  // 初始化 rec->flags，判断是否有函数入口需要更新
                command |= FTRACE_UPDATE_CALLS;

  ftrace_startup_enable(command);  // 更新 saved_ftrace_func，并执行 FTRACE_UPDATE_{CALLS,TRACE_FUNC} FTRACE_START_FUNC_RET 命令
    command |= FTRACE_UPDATE_TRACE_FUNC; // 更新 ftrace_call
    ftrace_run_update_code(command);
      ftrace_modify_all_code()
           if (command & FTRACE_START_FUNC_RET)         // 变化 2
           err = ftrace_enable_ftrace_graph_caller();  // 更新 ftrace_graph_call
```

`ftrace_enable_ftrace_graph_caller()` 函数调用我们熟悉的 `__ftrace_modify_call()` 函数，将 `ftrace_graph_call` 替换为对 `prepare_ftrace_return()` 的调用，代码如下：

```c
// arch/riscv/kernel/ftrace.c ：203

int ftrace_enable_ftrace_graph_caller(void)
{
        int ret;

        ret = __ftrace_modify_call((unsigned long)&ftrace_graph_call,
                                    (unsigned long)&prepare_ftrace_return, true);
}
```

这里做个实验，观察 `current_tracer` 从 `function` 设置为 `function_graph` 后，`ftrace_graph_call` 的变化，以及相关全局变量的变化：

```sh
(gdb) p ftrace_trace_function                                    ## function tracer
$16 = (ftrace_func_t) 0xffffffff800d75c4 <function_trace_call>   ## 全局跟踪函数
(gdb) p ftrace_graph_entry
$17 = (trace_func_graph_ent_t) 0xffffffff800e3da4 <ftrace_graph_entry_stub> ## 全局入口跟踪函数
(gdb) p ftrace_graph_return
$18 = (trace_func_graph_ret_t) 0xffffffff80008960 <ftrace_stub> ## 全局返回跟踪函数
(gdb) p ftrace_ops_list
$19 = (struct ftrace_ops *) 0xffffffff8129cb40 <global_ops>     ## ftrace_ops_list 全局 ops 链表
(gdb) p ftrace_ops_list->next
$20 = (struct ftrace_ops *) 0xffffffff8129ca50 <ftrace_list_end>
(gdb) disassemble  ftrace_caller+40,ftrace_caller+66
Dump of assembler code from 0xffffffff80008dfc to 0xffffffff80008e16:
   0xffffffff80008dfc <ftrace_caller+40>:       mv      a3,sp
   0xffffffff80008dfe <ftrace_caller+42>:       auipc   ra,0xce      ## ftrace_call
   0xffffffff80008e02 <ftrace_caller+46>:       jalr    1990(ra) # 0xffffffff800d75c4 <function_trace_call>
   0xffffffff80008e06 <ftrace_caller+50>:       addi    a0,sp,72
   0xffffffff80008e08 <ftrace_caller+52>:       ld      a1,64(sp)
   0xffffffff80008e0a <ftrace_caller+54>:       addi    a1,a1,-12
   0xffffffff80008e0c <ftrace_caller+56>:       mv      a2,s0
   0xffffffff80008e0e <ftrace_caller+58>:       auipc   ra,0x0      ## ftrace_graph_call
   0xffffffff80008e12 <ftrace_caller+62>:       jalr    -1198(ra) # 0xffffffff80008960 <ftrace_stub>
End of assembler dump.
(gdb) c
Continuing.
^C
Program received signal SIGINT, Interrupt.
arch_cpu_idle () at ../arch/riscv/kernel/process.c:42
42              raw_local_irq_enable();
(gdb) p ftrace_trace_function                                 ## function_graph tracer
$21 = (ftrace_func_t) 0xffffffff80008960 <ftrace_stub>
(gdb) p p ftrace_graph_entry
No symbol "p" in current context.
(gdb)  p ftrace_graph_entry
$22 = (trace_func_graph_ent_t) 0xffffffff800df404 <trace_graph_entry>
(gdb) p ftrace_graph_return
$23 = (trace_func_graph_ret_t) 0xffffffff800df806 <trace_graph_return>
(gdb) p ftrace_ops_list
$24 = (struct ftrace_ops *) 0xffffffff812a0f08 <graph_ops>
(gdb) p ftrace_ops_list->next
$25 = (struct ftrace_ops *) 0xffffffff8129ca50 <ftrace_list_end>
(gdb) disassemble  ftrace_caller+40,ftrace_caller+66
Dump of assembler code from 0xffffffff80008dfc to 0xffffffff80008e16:
   0xffffffff80008dfc <ftrace_caller+40>:       mv      a3,sp
   0xffffffff80008dfe <ftrace_caller+42>:       auipc   ra,0x0
   0xffffffff80008e02 <ftrace_caller+46>:       jalr    -1182(ra) # 0xffffffff80008960 <ftrace_stub>
   0xffffffff80008e06 <ftrace_caller+50>:       addi    a0,sp,72
   0xffffffff80008e08 <ftrace_caller+52>:       ld      a1,64(sp)
   0xffffffff80008e0a <ftrace_caller+54>:       addi    a1,a1,-12
   0xffffffff80008e0c <ftrace_caller+56>:       mv      a2,s0
   0xffffffff80008e0e <ftrace_caller+58>:       auipc   ra,0x0
   0xffffffff80008e12 <ftrace_caller+62>:       jalr    -1014(ra) # 0xffffffff80008a18 <prepare_ftrace_return>
End of assembler dump.
```

从上面的实验，我们可以看到，tracer 的切换过程中：

1. 全局跟踪函数，由 `function_trace_call()` 变为 `ftrace_stub`
2. 全局入口跟踪函数，由 `ftrace_graph_entry_stub` 变为 `trace_graph_entry()`
3. 全局返回跟踪函数，由 `ftrace_stub` 变为 `trace_graph_return()`
4. 全局 ops 链表，由 `global_ops => ftrace_list_end` 变为 `graph_ops => ftrace_list_end`
5. `ftrace_call`，由对 `function_trace_call()` 的调用变为对 `ftrace_stub` 的调用
6. `ftrace_graph_call`，由对 `ftrace_stub` 的调用变为对 `prepare_ftrace_return()` 的调用

## 总结

动态函数图跟踪机制的整体工作过程如下：

用户通过 `register_ftrace_graph()` 函数更新全局入口与返回跟踪函数，并以 `prepare_ftrace_return()` 函数替换 `ftrace_graph_call`。在内核执行时，内核函数入口会跳转到 `ftrace_caller`，继而执行 `prepare_ftrace_return()`，调用全局入口跟踪函数，并以 `return_to_handler` 覆盖函数返回地址，使得 `return_to_handler` 在函数返回时执行，调用全局返回跟踪函数，之后跳转到原函数的返回地址。

自此，我们了解了 ftrace 的两个核心机制 -- 动态函数跟踪、动态函数图跟踪，二者分别向用户提供 `register_ftrace_function()`、`register_ftrace_graph()` 接口来注册对函数进行跟踪以及对函数入口和返回进行跟踪的跟踪函数。最后我们以一张 ftrace 的架构图来结束本文。

![ftrace_arch](/wp-content/uploads/2022/03/riscv-linux/images/riscv_ftrace/ftrace_arch.png)

## 参考资料

* [ftrace-use][1]

[1]: https://www.kernel.org/doc/Documentation/trace/ftrace-uses.rst
[2]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220909-ftrace-impl-3-replace.md
[3]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220910-ftrace-impl-4-replace-trace-function.md
