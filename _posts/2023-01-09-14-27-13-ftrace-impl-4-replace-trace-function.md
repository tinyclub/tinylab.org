---
layout: post
author: 'song'
title: 'RISC-V Ftrace 实现原理（4）- 替换跟踪函数'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /ftrace-impl-4-replace-trace-function/
description: 'RISC-V Ftrace 实现原理（4）- 替换跟踪函数'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - Ftrace
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [header]
> Author:    sugarfillet <sugarfillet@yeah.net>
> Date:      2022/09/10
> Revisor:   Falcon falcon@tinylab.org
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V ftrace 相关技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I58N1O)
> Sponsor:   PLCT Lab, ISCAS


## 前言

[上文][1]讲到，在 ftrace 执行完内核函数入口的指令替换后，函数执行时会跳转到 `ftrace_caller` 调用跟踪函数，而此函数就是 `function` tracer 所注册的跟踪函数 `function_trace_call()`。并且在观察 `ftrace_caller` 执行的过程中，我们留了一个问题：`ftrace_call` 是如何被替换为对 `function_trace_call()` 的调用？本篇文章就对此问题展开分析。

既然 `function_trace_call()` 是 `function` tracer 的跟踪函数，那么我们就从 `echo function > current_tracer` 命令是如何工作的角度进行分析，与[上文][1]类似，同样以 `current_tracer` 文件的相关操作函数为切入点，分析过程中重点关注跟踪函数如何变化以及最终如何实现对 `ftrace_call` 的替换。

**说明**：

* 本文的 Linux 版本采用 `Linux 5.18-rc1`

## current_tracer 的初始化

tracefs 初始化 `current_tracer` 文件，记录 `global_trace` 在 `inode->i_private`，注册 `set_tracer_fops` 在 `inode->i_fop`，相关代码如下：

```c
init_tracer_tracefs(&global_trace, NULL);
    trace_create_file("current_tracer", TRACE_MODE_WRITE, d_tracer,
                        tr, &set_tracer_fops);
```

`global_trace` 是一个 `struct trace_array` 结构体实例，用来表示 `/sys/kernel/debug/tracing/` 顶级目录下的相关 tracing 配置，比如：`.array_buffer` 代表 ftrace 跟踪日志的缓冲区，`.buffer_disabled` 代表 tracing 开启或者关闭，`.current_trace` 代表当前的 tracer，`.ops` 挂接到 `global_ops`，等等。其定义及相关初始化代码如下：

```c
// kernel/trace/trace.c ：449

static struct trace_array global_trace = {
        .trace_flags = TRACE_DEFAULT_FLAGS,
};

// kernel/trace/trace.c : 10177

early_trace_init()
  tracer_alloc_buffers();
    allocate_trace_buffers(&global_trace, ring_buf_size) // 分配跟踪日志缓冲区
    global_trace.current_trace = &nop_trace; // 设置默认 tracer 为 nop tracer
    ftrace_init_global_array_ops(&global_trace);  // 挂接 global_ops
    init_function_trace(); // 注册 function tracer
      register_tracer(&function_trace); // 注册 function_trace 到全局 tracer 链表 - trace_type，如果命令行指定 `ftrace=function` 则执行此 tracer 的初始化
    list_add(&global_trace.list, &ftrace_trace_arrays); // 添加 `global_trace_list` 到 ftrace_trace_arrays 链表
```

`set_ftrace_fops` 中分别定义了对 `current_tracer` 文件打开、读取、写入的相关操作：

1. `tracing_open_generic()` 在文件打开时执行，设置 `global_trace` 到 `filp->private_data`
2. `tracing_set_trace_read` 在文件读取时执行，简单地把当前 tracer 的名字 `tr->current_trace->name` 拷贝到用户态
3. `tracing_set_trace_write()` 在文件写入时执行，匹配到对应的 tracer 并执行对应的初始化工作，并最终执行对 `ftrace_call` 的指令替换

   关键函数：`tracing_set_tracer`, `function_trace_init`, `register_ftrace_function`, `update_ftrace_function`, `ftrace_run_update_code`

```c
static const struct file_operations set_tracer_fops = {
        .open           = tracing_open_generic,
        .read           = tracing_set_trace_read,
        .write          = tracing_set_trace_write,
        .llseek         = generic_file_llseek,
};
```

接下来，我们展开来分析 `tracing_set_trace_write()` 函数的实现。

## tracing_set_trace_write

此函数从用户态拷贝输入的字符串，调用 `tracing_set_tracer()` 函数在全局 tracer 表 `trace_types` 中匹配对应的 tracer，然后执行 tracer 的初始化，并将当前 tracer 记录到 `tr->current_trace`，关键代码如下：

```c
// kernel/trace/trace.c ：6345

tracing_set_trace_write()
  struct trace_array *tr = filp->private_data;
  copy_from_user(buf, ubuf, cnt)   // 拷贝输入的字符串
  err = tracing_set_tracer(tr, buf);

tracing_set_tracer()
  for (t = trace_types; t; t = t->next) {   // 全局 tracer 链表
                if (strcmp(t->name, buf) == 0)
                        break;
  }
  tracer_init(t, tr);         // 执行 tracer 的初始化 t->init()
    t->init(tr);
  tr->current_trace = t;
```

`trace_init()` 函数会调用 `t->init()`，`t->init()` 对应到的是 `function` tracer 通过 `register_tracer()` 函数注册的 `struct tracer function_trace` 的 `.init` 定义，即 `function_trace_init()`。`function_trace` 代码如下：

```c
// kernel/trace/trace_functions.c ：428

static struct tracer function_trace __tracer_data =
{
        .name           = "function",
        .init           = function_trace_init,
        .reset          = function_trace_reset,
        .start          = function_trace_start,
        .flags          = &func_flags,
        .set_flag       = func_set_flag,
        .allow_instances = true,
#ifdef CONFIG_FTRACE_SELFTEST
        .selftest       = trace_selftest_startup_function,
#endif
};
```

`function_trace_init()` 函数执行 `select_ftrace_function()` 选择 function tracer 的跟踪函数，默认通过 `TRACE_FUNC_NO_OPTS` 选择到 `function_trace_call()` 函数，并将其设置到 `ops->func`(`global_ops->func`)，之后执行 `register_ftrace_function()` 注册跟踪函数。关键代码如下：

```c
// kernel/trace/trace_functions.c ：132

function_trace_init()
  func = select_trace_function(func_flags.val); // 选择跟踪函数
      case TRACE_FUNC_NO_OPTS:
          return function_trace_call;
  tr->ops->func = func;
  tr->ops->private = tr;
  register_ftrace_function(tr->ops);  // 注册跟踪函数
```

## register_ftrace_function

`register_ftrace_function()` 函数执行如下内容：

1. `__register_ftrace_function()` 函数，添加当前 `ops` (`global_ops`) 到全局 ops 链表 `ftrace_ops_list`，并设置全局跟踪函数 `ftrace_trace_funcion()()` 为 `ops->func`
2. `ftrace_hash_ipmodify_enbale()` 函数，根据 `ops->func_hash->filter_hash` 更新函数入口表中每个函数记录 `rec` 的 ipmodify 标志位
3. `ftrace_hash_rec_enable()` 函数，判断是否有函数入口需要更新，如果需要更新则为 `command` 设置 `FTRACE_UPDATE_CALLS` 标志
4. `ftrace_startup_enable()` 函数，判断保存的跟踪函数 `saved_ftrace_func` 与当前跟踪函数 `ftrace_trace_function()` 是否相同，如果不同，则表示需要更新跟踪函数，为 `command` 设置 `FTRACE_UPDATE_TRACE_FUNC`，之后执行 `ftrace_run_update_code(command)`

关键代码如下：

```c
// kernel/trace/ftrace.c : 7878

register_ftrace_function()
  __register_ftrace_function(ops)
    add_ftrace_ops(&ftrace_ops_list, ops); // 添加到 ops 列表中
    ops->saved_func = ops->func;
    update_ftrace_function(); // 设置 ftrace_trace_function 为 ops->func

  ftrace_hash_ipmodify_enable(ops); // 更新 rec 的 ipmodify flag
  if (ftrace_hash_rec_enable(ops, 1))  // 初始化 rec->flags，判断是否有函数入口需要更新
                command |= FTRACE_UPDATE_CALLS;

  ftrace_startup_enable(command);  // 更新 saved_ftrace_func，并执行 FTRACE_UPDATE_{CALLS,TRACE_FUNC} 命令
    command |= FTRACE_UPDATE_TRACE_FUNC; // 更新 ftrace_call
    ftrace_run_update_code(command);
```

值得关注的是，`update_ftrace_function()` 是如何将全局跟踪函数 `ftrace_trace_funcion()` 设置为 `ops->func` 的呢？我们接下来展开来分析：

`ftrace_ops_list` 是一个初始只有 `ftrace_list_end` 单个结点的 ops 全局链表，一般通过 `register_ftrace_function()` 函数来添加 ops 结点。`update_ftrace_function()` 函数首先获取 `ftrace_ops_list` 链表头结点，进行如下判断：

1. 如果头结点是 `ftrace_list_end`，表示没有 ops 注册，代表无需函数跟踪，将 `func` 设置为空的跟踪函数 `ftrace_stub`
2. 如果头结点的下一个结点是 `ftrace_list_end`，表示只有一个 ops 注册，且当此 ops 不是动态 ops（比如：livepatch），且架构支持传递 ops 到跟踪函数，则将 `func` 设置为 `ops->func`，否则设置为 `ftrace_ops_list_func()`
3. 如果链表中有不止一个的 ops 注册，则将 `func` 设置为 `ftrace_ops_list_func()`

> `ftrace_ops_list_func()` 为区别于全局跟踪函数，我们在此称之为列表跟踪函数。此函数在 vmlinux 链接时，指向 `arch_ftrace_ops_list_func`，执行时会遍历 `ftrace_ops_list`，结合 `ops->func_hash` 来判断是否需要对当前 `ip` 执行 `ops->func`，也就是说 `ftrace_ops_list_func()` 不仅会调用多个 ops 的跟踪函数，也会保证 ops 跟踪函数处理的函数是应该被跟踪的。

最后，将 `func` 设置到 `ftrace_trace_function()`。当前设置 function tracer 的流程中，`ops` 就是 `global_ops` 且 `ftrace_ops_list` 链表只有 `global_ops` 这一个注册，故最终 `ftrace_trace_function()` 为 `global_ops->func` 即 `function_trace_call()`。关键代码如下：

```c
// kernel/trace/ftrace.c ：174

static void update_ftrace_function(void)
{
        ftrace_func_t func;

        set_function_trace_op = rcu_dereference_protected(ftrace_ops_list,
                                                lockdep_is_held(&ftrace_lock));

        /* If there's no ftrace_ops registered, just call the stub function */
        if (set_function_trace_op == &ftrace_list_end) {
                func = ftrace_stub;

        } else if (rcu_dereference_protected(ftrace_ops_list->next,
                        lockdep_is_held(&ftrace_lock)) == &ftrace_list_end) {
                func = ftrace_ops_get_list_func(ftrace_ops_list);

        } else {
                /* Just use the default ftrace_ops */
                set_function_trace_op = &ftrace_list_end;
                func = ftrace_ops_list_func;
        }

        if (ftrace_trace_function == func)
                return;

        if (func == ftrace_ops_list_func) {
                ftrace_trace_function = func;
                                return;
        }
        ftrace_trace_function = func;
}
```

`ftrace_ops_list_func()` 函数的实现的关键代码如下：

```c
// include/asm-generic/vmlinux.lds.h ： 178

ftrace_ops_list_func() = arch_ftrace_ops_list_func;

// kernel/trace/ftrace.c ：7362

void arch_ftrace_ops_list_func(unsigned long ip, unsigned long parent_ip,
                               struct ftrace_ops *op, struct ftrace_regs *fregs)
{
        __ftrace_ops_list_func(ip, parent_ip, NULL, fregs);
}

__ftrace_ops_list_func()
  do_for_each_ftrace_op(op, ftrace_ops_list)
    if ((!(op->flags & FTRACE_OPS_FL_RCU) || rcu_is_watching()) && ftrace_ops_test(op, ip, regs)) // 在 ftrace_ops_test 中检查当前 ip 是否在 ops 对应的 hash 中
                      op->func(ip, parent_ip, op, fregs);

ftrace_ops_test()
        rcu_assign_pointer(hash.filter_hash, ops->func_hash->filter_hash);
        rcu_assign_pointer(hash.notrace_hash, ops->func_hash->notrace_hash);
        if (hash_contains_ip(ip, &hash))

```

再次回顾下 `register_ftrace_function()` 函数的功能，首先注册 `global_ops` 到 `ftrace_ops_list`，并设置 `function_trace_function`，其次判断函数入口是否需要更新，最后会以 `FTRACE_UPDATE_CALLS | FTRACE_UPDATE_TRACE_FUNC` 为命令执行 `ftrace_run_update_code()` 来进行函数入口和跟踪函数的替换。接下来，我们来分析这个函数。

## 再探 ftrace_run_update_code

在上篇文章 - [ftrace 实现原理（3）- 替换函数入口][1] 中，我们已经对 `ftrace_run_update_code()` 函数进行了分析，其中提到：

> 此函数在接受命令后经过一连串的调用最终执行到 `ftrace_modify_all_code()`

“一连串的调用”，其实是在对将要执行的指令替换进行并发保护。目前 RISC-V 架构中，通过内核代码段锁 `text_mutex` 来保证对内核代码进行指令修改的唯一性，通过 `stop_machine()` 机制确保所有处理器都停下来等待执行代码更新的完成。关于 `stop_machine()` 的工作原理可以参考 RISCV-Linux 社区的这篇文章 [RISC-V jump_label 详解，第 4 部分：运行时代码改写][2]。值得一提的是，RISC-V 主线正在尝试去除 ftrace 对 `stop_machine()` 的依赖来兼容内核抢占，详细内容可参考[这里][3]。

```c
// kernel/trace/ftrace.c ：2806

ftrace_run_update_code()
  ftrace_arch_code_modify_prepare();
    mutex_lock(&text_mutex);
  arch_ftrace_update_code(command);
    stop_machine(__ftrace_modify_code, &command, NULL);
        ftrace_modify_all_code(*command);
  ftrace_arch_code_modify_post_process();
```

而对 `ftrace_modify_all_code()` 函数，上篇文章只是简单介绍其会调用 `ftrace_replace_code()` 进行函数入口的替换。由于此函数也涉及对跟踪函数的替换，所以我们在这里对 `ftrace_modify_all_code()` 进行展开分析，此函数主要执行以下步骤：

1. 如果需要替换跟踪函数，则调用 `ftrace_update_ftrace_func()` 替换 `ftrace_call` 为 `ftrace_ops_list_func()`
2. 如果需要替换函数入口，则执行 `ftrace_replace_code()` 进行函数入口的替换
3. 如果需要替换跟踪函数，且 `ftrace_trace_function()` 不为 `ftrace_ops_list_func()`，则再次调用 `ftrace_update_ftrace_func()` 替换 `ftrace_call` 为 `ftrace_trace_function()`

为何要执行步骤 1 呢，直接通过步骤 3 替换跟踪函数不行么？

考虑在并发场景下（比如：当前核执行当前代码修改，其他的核执行内核函数并调用跟踪函数），如果直接执行后面两个步骤，在步骤 2 的过程中，可能出现旧的跟踪函数被不属于自己跟踪列表（`ops->func_hash`）中的函数调用到的情况，所以在此之前，要把 `ftrace_call` 替换为列表跟踪函数 `ftrace_ops_list_func()`，避免错误调用。细节可参考 `59338f754` 这个提交。

`ftrace_modify_all_code()` 关键代码如下：

```c
// kernel/trace/ftrace.c ：2724

void ftrace_modify_all_code(int command)
{
        int update = command & FTRACE_UPDATE_TRACE_FUNC;

        if (update) {
                err = ftrace_update_ftrace_func(ftrace_ops_list_func);
                if (FTRACE_WARN_ON(err))
                        return;
        }
        if (command & FTRACE_UPDATE_CALLS)
                ftrace_replace_code(mod_flags | FTRACE_MODIFY_ENABLE_FL);
        else if (command & FTRACE_DISABLE_CALLS)
                ftrace_replace_code(mod_flags);

        if (update && ftrace_trace_function != ftrace_ops_list_func) {
                function_trace_op = set_function_trace_op;  //
                err = ftrace_update_ftrace_func(ftrace_trace_function);
                if (FTRACE_WARN_ON(err))
                        return;
        }
        // ....
}
```

`ftrace_update_ftrace_func()` 根据跟踪函数 `ftrace_trace_function()` 与 `ftrace_call` 的地址偏移，构造 8 Bytes 的 `call` 指令对，之后执行 `patch_text_nosync()` 函数以 `call` 指令对替换 `ftrace_call`。关键代码如下：

```c
// arch/riscv/kernel/ftrace.c ：146

ftrace_update_ftrace_func()
  __ftrace_modify_call((unsigned long)&ftrace_call, (unsigned long)func, true);

// arch/riscv/kernel/ftrace.c ：224

static int __ftrace_modify_call(unsigned long hook_pos, unsigned long target,
                                bool enable)
{
        unsigned int call[2];
        unsigned int nops[2] = {NOP4, NOP4};

        make_call(hook_pos, target, call);

        if (patch_text_nosync
            ((void *)hook_pos, enable ? call : nops, MCOUNT_INSN_SIZE))
                return -EPERM;

        return 0;
}
```

`patch_text_nosync()` 函数大致的工作流程是，通过 fixmap 临时申请写入权限，并做指令替换，最后更新指令 cache，确保其他核能执行修改后的指令。此函数同样在 [RISC-V jump_label 详解，第 4 部分：运行时代码改写][2] 文章中也有详细说明，有兴趣的同学可移步。关键代码如下：

```c
// arch/riscv/kernel/patch.c:88

patch_text_nosync()
  patch_insn_write()
    waddr = patch_map(addr, FIX_TEXT_POKE0);
    copy_to_kernel_nofault(waddr, insn, len);
    patch_unmap(FIX_TEXT_POKE0);
  flush_icache_range((uintptr_t) tp, (uintptr_t) tp + len);
```

最后，我们来观察下，tracer 从 `nop` 变更为 `function` 前后，`ftrace_call` 是如何变化的：

```sh
(gdb) disassemble ftrace_caller+40,+8
Dump of assembler code from 0xffffffff80008cfc to 0xffffffff80008d04:
   0xffffffff80008cfc <ftrace_caller+40>:       mv      a3,sp
   0xffffffff80008cfe <ftrace_caller+42>:       auipc   ra,0x0
   0xffffffff80008d02 <ftrace_caller+46>:       jalr    -1182(ra) # 0xffffffff80008860 <ftrace_stub>
End of assembler dump.
(gdb) c
Continuing.    # execute : echo function > current_tracer
^C
Program received signal SIGINT, Interrupt.
arch_cpu_idle () at ../arch/riscv/kernel/process.c:42
42              raw_local_irq_enable();

(gdb) disassemble ftrace_caller+40,+8
Dump of assembler code from 0xffffffff80008cfc to 0xffffffff80008d04:
   0xffffffff80008cfc <ftrace_caller+40>:       mv      a3,sp
   0xffffffff80008cfe <ftrace_caller+42>:       auipc   ra,0xe1
   0xffffffff80008d02 <ftrace_caller+46>:       jalr    -1220(ra) # 0xffffffff800e983a  <function_trace_call>
End of assembler dump.
```

可以看到，`ftrace_call` 从对 `ftrace_stub` 的调用替换为对 `function_trace_call()` 的调用。

## 总结

本文分析 `ftrace_call` 标签替换为对 `function` tracer 的跟踪函数 `function_trace_call()` 的实现过程。

首先，介绍 `current_tracer` 文件的相关操作函数，其中重点介绍了 `global_trace` 的定义与初始化过程；然后，分析 `tracing_set_trace_write()` 函数的实现以及 `function` tracer 的初始化函数 `function_trace_init()` 的实现；再然后，分析注册跟踪函数的标准接口 `register_ftrace_function()`，其中重点介绍了更新全局跟踪函数的 `update_ftrace_function()` 与列表跟踪函数 `ftrace_ops_list_func()`；最后，我们再次对执行指令替换的标准接口 `ftrace_run_update_code()` 进行分析，简单介绍了其如何在修改指令时做并发保护，分析了 `ftrace_modify_all_code()` 如何解决并发问题以及 `ftrace_update_ftrace_func()` 如何实现对 `ftrace_call` 的指令替换。

整个替换跟踪函数的过程中，`function` tracer 的跟踪函数大致经历 `function_trace => select_trace_function() => tr->ops->func => ftrace_trace_function()` 这些过程或结构来查找或记录，并最终通过替换 `ftrace_call` 标签来实现对 `function_trace_call()` 函数的调用。

自此，我们通过两篇文章分别介绍了函数入口以及跟踪函数的替换过程，相信大家对采用 tracefs 接口进行动态函数跟踪有了更进一步的理解。下文我们来介绍下 Ftrace 中另一个重要的跟踪机制 -- 动态函数图跟踪。

## 参考资料

* [RISC-V jump_label 详解，第 4 部分：运行时代码改写][2]
* [Enable ftrace with kernel preemption for RISC-V][3]

[1]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220909-ftrace-impl-3-replace.md
[2]: https://tinylab.org/riscv-jump-label-part4/
[3]: https://lore.kernel.org/linux-riscv/20220913094252.3555240-1-andy.chiu@sifive.com/T/#t
