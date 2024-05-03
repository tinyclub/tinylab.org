---
layout: post
author: 'Song Shuai'
title: 'RISC-V Ftrace 实现原理（6）- trace ring buffer'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /ftrace-impl-6-ringbuffer/
description: 'RISC-V Ftrace 实现原理（6）- trace ring buffer'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - Ftrace
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces header toc codeblock codeinline epw]
> Author:    sugarfillet <sugarfillet@yeah.net>
> Date:      2022/12/20
> Revisor:   Falcon falcon@tinylab.org
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V ftrace 相关技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I58N1O)
> Sponsor:   PLCT Lab, ISCAS


## 前言

ftrace 跟踪目标函数 vfs_read，需要在 tracefs 中执行如下一组基本命令。其中，命令 2 用于设置 tracer 为 function tracer，命令 3 用于设置目标函数，在这两条命令执行之后，function tracer 的跟踪函数就可以在目标函数执行前调用。命令 4 用于开启对 trace ring buffer 的写入，这样跟踪函数就可以把目标函数的执行信息写入 trace ring buffer 中，命令 5 用于读取 trace ring buffer 中的内容。

```sh
1. cd /sys/kernel/debug/tracing
2. echo function > current_tracer
3. echo vfs_read > set_ftrace_filter
4. echo 1 > tracing_on
5. cat trace
```

本文以 trace ring buffer 为线索，分析命令 4 和命令 5 的实现原理。

**说明**：

  * 本文的 Linux 版本采用 `Linux v6.0`

## trace ring buffer 的初始化

系统初始化时，调用 `ring_buffer_alloc()` 为 `global_trace->array_buffer` 分配 trace_buffer 结构 `(struct trace_buffer *) buffer` 以及每个 cpu 上的 trace_array 结构 `(struct trace_array_cpu*) data`，之后设置 `data[cpu]->entries` 为各 cpu 对应的 cpu_buffer 大小。

为了区分各种 buffer，我们在后文中以 trace_buffer 代表 `(struct trace_buffer *) global_trace->array_buffer->buffer`，以 cpu_buffer 代表 `(struct ring_buffer_per_cpu *) global_trarce->array_buffer->buffer->buffers[cpu]`。

trace_buffer 初始化的关键代码如下：

```c
// kernel/trace/trace.c : 10325

early_trace_init()
  tracer_alloc_buffers()
    allocate_trace_buffers(&global_trace, ring_buf_size)
	  allocate_trace_buffer(tr, &tr->array_buffer, size); // trace_buffer
	    buf->buffer = ring_buffer_alloc(size, rb_flags);
			buffer->buffers[cpu] = rb_allocate_cpu_buffer(buffer, nr_pages, cpu); // cpu_buffer
		buf->data = alloc_percpu(struct trace_array_cpu);                         // trace_array_per_cpu
		per_cpu_ptr(buf->data, cpu)->entries = ring_buffer_size(tr->array_buffer.buffer, 0)
	...
	init_function_trace();
	list_add(&global_trace.list, &ftrace_trace_arrays);
	...
```

## 开启对 trace_buffer 的写操作

tracing_on 文件对应的文件操作集为 `rb_simple_fops`，在对此文件写入时，执行 `rb_simple_write()` 函数。当执行 `echo 1 > tracing_on` 时，先执行 `ring_buffer_record_on` 函数开启对 trace_buffer 的写操作，反之执行 `ring_buffer_record_off` 函数关闭对 trace_buffer 的写操作；之后执行当前开启的 tracer 的 `->start()` 函数。

我们以 function tracer 的 `->start()` 函数 -- `function_trace_start` 进行说明：
1. 关闭对 trace_buffer 的写操作
2. 记录当前时间到 `trace_buffer->time_start`
3. 重置每个 online 的 cpu 对应的 cpu_buffer 相关结构
4. 开启对 trace_buffer 的写操作

关键代码如下：

```c
// kernel/trace/trace.c : 9085

static const struct file_operations rb_simple_fops = {
        .open           = tracing_open_generic_tr,
        .read           = rb_simple_read,
        .write          = rb_simple_write,
        .release        = tracing_release_generic_tr,
        .llseek         = default_llseek,
};
```

```c
// kernel/trace/trace.c : 9050

rb_simple_write
  tracer_tracing_on(tr);
    ring_buffer_record_on(tr->array_buffer.buffer);
	tr->buffer_disabled = 0;

  tr->current_trace->start(tr);  // if function tracer
    function_trace_start
	  ring_buffer_record_disable(buffer) // 1
	  buf->time_start = buffer_ftrace_now(buf, buf->cpu); // 2
	  ring_buffer_reset_online_cpus(buffer);  // 3
	  ring_buffer_record_enable(buffer)  // 4
```

## event_function and struct ftrace_entry

在介绍对 trace_buffer 进行数据读写操作之前，先介绍两个关键的定义 -- 全局变量 `struct trace_event_call event_function` 和结构体 `struct ftrace_entry`，二者通过 `FTRACE_ENTRY_REG` 宏来声明。

`FTRACE_ENTRY_REG` 首先以 `struct type_entry` 结构为基础以及 `F_STRUCT` 内容为动态成员构造 `struct ftrace_entry` 结构体，其展开后的定义如下：

```c
struct ftrace_entry {
	struct type_entry ent,
	unsigned long ip,
	unsigned long parent_ip,
};
```

之后定义 `struct trace_event_call event_function` 变量用来定义 function tracer 对应的打印格式、过滤函数等参数。gdb 中打印此变量的内容如下：

```c
(gdb) p event_function
$9 = {
  list = {
    next = 0xffffffff8149ba10 <event_funcgraph_entry>,
    prev = 0xffffffff8149cd68 <event_bpf_trace_printk>
  },
  class = 0xffffffff8157e970 <event_class_ftrace_function>,
  {
    name = 0xffffffff80f88ac8 "function",
    tp = 0xffffffff80f88ac8
  },
  event = {
    node = {
      next = 0x0,
      pprev = 0x0
    },
    list = {
      next = 0x0,
      prev = 0x0
    },
    type = 1,   // TRACE_FN
    funcs = 0x0
  },
  print_fmt = 0xffffffff80f99a20 "\" %ps <-- %ps\", (void *)REC->ip, (void *)REC->parent_ip", // 打印格式
  filter = 0x0,
  {
    module = 0x0,
    refcnt = {
      counter = 0
    }
  },
  data = 0x0,
  flags = 8,
  perf_refcount = 0,
  perf_events = 0x0,
  prog_array = 0x0,
  perf_perm = 0x0
}
```

相关定义代码如下：

```c
// kernel/trace/trace_entries.h : 59

FTRACE_ENTRY_REG(function, ftrace_entry,

        TRACE_FN,

        F_STRUCT(
                __field_fn(     unsigned long,  ip              )
                __field_fn(     unsigned long,  parent_ip       )
        ),

        F_printk(" %ps <-- %ps",
                 (void *)__entry->ip, (void *)__entry->parent_ip),

        perf_ftrace_event_register
);
```

了解了 `struct ftrace_entry` 结构体和 `event_function` 变量的定义之后，我们来看一下接下来如何对 trace_buffer 进行写入与读取。

## 写入 trace_buffer

本节我们以 function tracer 的跟踪函数 -- `function_trace_call` 为例，分析 function tracer 如何向 trace_buffer 中写入数据。

`function_trace_call` 函数执行时，先通过 `tracing_gen_ctx` 函数获取到软硬中断状态、调度状态、抢占计数等信息存储到 `trace_ctx` 变量中，之后检测当前 cpu 的 cpu_buffer 是否支持写入，如果支持则执行 `trace_function` 函数进行数据写入。

```c
// kernel/trace/trace_functions.c : 172

function_trace_call
	trace_ctx = tracing_gen_ctx();
	if (!atomic_read(&data->disabled))
		trace_function(tr, ip, parent_ip, trace_ctx);
```

`trace_function` 调用的几个重要函数分析如下：

`__trace_buffer_lock_reserve` 函数，此函数调用 `ring_buffer_lock_reserve` 函数从 cpu_buffer 中预定一块大小为 `sizeof(struct ftrace_entry)` 大小的 buffer，预定的 buffer 的实际位置为 `cpu_buffer[cpu]->tail_page->page->data`，以 ring_buffer_event 的形式返回，后续可通过 `ring_buffer_event_data(event)` 获取 buffer 数据。之后在 `trace_event_setup` 函数中对 event 中的 buffer 设置 `struct ftrace_entry` 中 `ent` 成员定义的基本数据项（preempt_count、pid、type、flags）以及事件类型 (TRACE_FN)。

`ring_buffer_event_data` 函数获取 event 中的 buffer 数据，设置 `struct ftrace_entry` 中的动态成员 ip 与 parent_ip。

`call_filter_check_discard` 函数以 `event_function` 中定义的过滤器对当前 event 进行过滤，如果不符合过滤条件，则执行 `ring_buffer_discard_commit` 从 trace_buffer 上释放掉此 event。在当前情况下，`event_function` 并无过滤功能，则执行后续流程。

`ftrace_exports` 函数可以把当前的 event 导出到非 trace_buffer 的地方，具体的导出方法可以通过 `register_ftrace_export` 进行注册。比如：`drivers/hwtracing/stm/ftrace.c` 就通过此注册实现了把 ftrace event 导出到 STM（System Trace Module）设备中。

`__buffer_unlock_commit` 函数，调用 `ring_buffer_unlock_commit` 提交当前申请的 event。关键代码如下：

```c
// kernel/trace/trace.c：2990

void
trace_function(struct trace_array *tr, unsigned long ip, unsigned long
               parent_ip, unsigned int trace_ctx)
{
        struct trace_event_call *call = &event_function;
        struct trace_buffer *buffer = tr->array_buffer.buffer;
        struct ring_buffer_event *event;
        struct ftrace_entry *entry;

        event = __trace_buffer_lock_reserve(buffer, TRACE_FN, sizeof(*entry), trace_ctx);
			event = ring_buffer_lock_reserve(buffer, len);
				preempt_disable_notrace();
				event = rb_reserve_next_event(buffer, cpu_buffer, length);
				event = __rb_page_index(tail_page, tail); // cpu_buffer->tail_page->page->data + index

			trace_event_setup(event, type, trace_ctx);
				tracing_generic_entry_update(ent, type, trace_ctx); // update trace_entry.{preempt_count,pid,type,flags}

        entry   = ring_buffer_event_data(event);
        entry->ip                       = ip;
        entry->parent_ip                = parent_ip;

        if (!call_filter_check_discard(call, entry, buffer, event)) {
                if (static_branch_unlikely(&trace_function_exports_enabled))
                        ftrace_exports(event, TRACE_EXPORT_FUNCTION);
                __buffer_unlock_commit(buffer, event);
					ring_buffer_unlock_commit()
						rb_commit(cpu_buffer, event);
							rb_end_commit(cpu_buffer);
								rb_set_commit_to_write(cpu_buffer) // commit_page = tail_page
						rb_wakeups(buffer, cpu_buffer)
						preempt_enable_notrace();
        }
}
```

## 读取 trace_buffer

在跟踪函数向 trace_buffer 中写入 event 数据后，我们可以通过 `cat trace` 命令查看写入的内容。本节对 `cat trace` 命令的执行过程进行分析。

trace 文件以 `tracing_fops` 文件操作符创建。关键代码如下：

```c
// kernel/trace/trace.c : 9533

init_tracer_tracefs(struct trace_array *tr, struct dentry *d_tracer)
  trace_create_file("trace", TRACE_MODE_WRITE, d_tracer, tr, &tracing_fops);
  	inode->i_fop = fops ? fops : &tracefs_file_operations
```

```c
// kernel/trace/trace.c : 5110

static const struct file_operations tracing_fops = {
        .open           = tracing_open,
        .read           = seq_read,
        .write          = tracing_write_stub,
        .llseek         = tracing_lseek,
        .release        = tracing_release,
};
```

### tracing_open

文件以读模式打开时，会调用 `tracing_open` 函数，关键过程有：

1. 调用 `__seq_open_private` 初始化 seq_file 并设置 seq_file 文件操作集 `tracer_seq_ops` 到 seq_file->op，连接 trace_iter 到 seq_file->private
2. 分配并设置 `struct ring_buffer_iter * (iter->buffer_iter)` 用来管理对 cpu_buffer 的读操作
3. 调用 `ring_buffer_read_prepare` 对 cpu_buffer 进行读操作的准备，为 buffer_iter 分配内存，并将 buffer_iter->cpu_buffer 赋值为 cpu_buffer，同时要关闭对 cpu_buffer 的写操作。
4. 调用 `ring_buffer_read_prepare_sync` 执行对所有读操作准备的同步
5. 调用 `ring_buffer_read_start` 开启对 cpu_buffer 的读操作，主要是调用 `rb_iter_reset` 连接 buffer_iter 与 cpu_buffer 中相关结构，比如让 iter->head_page 指向 cpu_buffer->reader_page 用来让后续的读操作，可以直接基于 buffer_iter 进行数据的读取。

关键代码如下：

```c
// kernel/trace/trace.c : 4943

tracing_open(struct inode *inode, struct file *file)
  FMODE_READ : __tracing_open(inode, file, false);
    iter = __seq_open_private(file, &tracer_seq_ops, sizeof(*iter));
	*iter->trace = *tr->current_trace;
	iter->cpu_file = tracing_get_cpu(inode);
	iter->trace->open(iter); // tracer open function invoked when trace file open
    iter->buffer_iter[cpu] = ring_buffer_read_prepare(iter->array_buffer->buffer,cpu, GFP_KERNEL);
	  iter->cpu_buffer=buffer->buffers[cpu];
    ring_buffer_read_prepare_sync(); // ring_buffer_read_prepare_sync - Synchronize a set of prepare calls
    ring_buffer_read_start(iter->buffer_iter[cpu]); // ring_buffer_read_start - start a non consuming read of the buffer
	  rb_iter_reset(iter);   // 连接 iter->head_page 到 cpu_buffer->reader_page
```

```c
// kernel/trace/trace.c : 4712
static const struct seq_operations tracer_seq_ops = {
        .start          = s_start,
        .next           = s_next,
        .stop           = s_stop,
        .show           = s_show,
};
```

### seq_read

`tracer_seq_ops` 是在 trace 文件打开时创建的 seq_file 结构的操作集合，这些函数统一在 `seq_read => seq_read_iter` 中被调用，其中 `.start` 用来在迭代开始时执行必要的初始化，`.stop` 用来在迭代结束时清理资源，`.next` 用来获取下一个迭代对象，`.show` 用来输出对象内容到 `trace` 文件。我们在这里重点关注 `.next` 和 `.show` 的实现，对于 seq_file 更详细的使用及实现可以参考 [SeqFileHowto][1]。

`s_next` 函数关键过程如下：

1. `ring_buffer_iter_peek` 获取 `buffer_iter->head_page + buffer_iter->head` 上存储的 event，并拷贝此 event 到 `buffer_iter->event`
2. `peek_next_entry` 调用 `ring_buffer_event_data` 从 event 中获取 trace_entry 并设置到 `trace_iter->ent`

关键代码如下：

```c
// kernel/trace/trace.c : 4037

static void *s_next(struct seq_file *m, void *v, loff_t *pos)
  ent = trace_find_next_entry_inc(iter);
     __find_next_entry(iter, &iter->cpu, &iter->lost_events, &iter->ts)
	   ent = peek_next_entry(iter, cpu_file, ent_ts, missing_events);
		 event = ring_buffer_iter_peek(buf_iter, ts);
		   event = rb_iter_peek(iter, ts);
		     event = rb_iter_head_event(iter);
			 	event = __rb_page_index(iter->head_page, iter->head); // 获取 event
				memcpy(iter->event, event, length);  // 拷贝 event 到 buffer_iter->event
		     rb_advance_iter(iter);   // head_page ++
		 return ring_buffer_event_data(event);
```

`s_show` 函数关键过程如下：

首先检查 `trace_iter->ent` 是否为空，如果是则打印 tracer 名称，并执行 `trace_default_header` 打印 trace 文件的头信息。

之后调用 `print_trace_fmt` 打印 `struct trace_entry * (trace_iter->ent)`，trace_entry 需要通过一个以 `trace_entry.type` 为 key 值的 HASH 表（`event_hash`）查找到其对应类型的打印函数。对于 TRACE_FN 类型 trace_entry 来说，就是 `trace_fn_trace` 函数。`trace_fn_trace` 又将 `trace_iter->ent` 格式化为 `struct ftrace_entry*`，再调用 `print_fn_trace` 打印 ip 和 parent_ip 到 `struct trace_seq trace_iter->seq` 中。

最后调用 `trace_print_seq` 将 trace_seq 中内容移动到 seq_file，最终实现 event 的输出。

`s_show` 函数关键代码如下：

```c
// kernel/trace/trace.c : 4657

static int s_show(struct seq_file *m, void *v)
  if (iter->ent == NULL)
	seq_printf(m, "# tracer: %s\n", iter->trace->name);
	trace_default_header(m);

  print_trace_fmt(iter);
	  entry = iter->ent;
	  event = ftrace_find_event(entry->type);
	    hlist_for_each_entry(event, &event_hash[key], node) // init_events trace_fn_event
      return event->funcs->trace(iter, sym_flags, event);  // trace_fn_trace
  trace_print_seq(m, &iter->seq); // trace_print_seq - move the contents of trace_seq into a seq_file
```

`trace_fn_trace` 函数关键代码如下：

```c
// kernel/trace/trace_output.c : 864

trace_fn_trace()
        struct ftrace_entry *field;
        struct trace_seq *s = &iter->seq;

        trace_assign_type(field, iter->ent);
		  IF_ASSIGN(var, ent, struct ftrace_entry, TRACE_FN); // field = (struct ftrace_entry*)(iter->ent);

        print_fn_trace(s, field->ip, field->parent_ip, flags);
		  seq_print_ip_sym(s, ip, flags);
		    trace_seq_printf()
		  seq_print_ip_sym(s, parent_ip, flags);
```

`events` HASH 相关代码如下：

```c
// kernel/trace/trace_output.c : 929

static struct trace_event_functions trace_fn_funcs = {
        .trace          = trace_fn_trace,
        .raw            = trace_fn_raw,
        .hex            = trace_fn_hex,
        .binary         = trace_fn_bin,
};

static struct trace_event trace_fn_event = {
        .type           = TRACE_FN,
        .funcs          = &trace_fn_funcs,
};

static struct trace_event *events[] __initdata = {
        &trace_fn_event,
        &trace_ctx_event,
        &trace_wake_event,
		...
}

__init static int init_events(void)
	for (i = 0; events[i]; i++)
		register_trace_event(events[i]);
early_initcall(init_events);
```

## 总结

本文以 trace ring buffer 为线索分析了对 `tracing_on` 和 `trace` 文件操作的实现原理，涉及了 trace ring buffer 的初始化、写入过程、读取过程。这里以一个对 trace ring buffer 的读写示意图结束本文。

```
[ftrace_entry] =>  [ring_buffer_event]
                                  |
						  /+++++++++++++++++++++++++++++++++++++++++++++++++\
                         | ---- [tail_page] --<commit>-- [reader_page] ----- | trace ring buffer
						  \+++++++++++++++++++++++++++++++++++++++++++++++++/
                                                            |
[ftrace_entry] <=  [trace_iter->ent] <= [buffer_iter->head_page]
```

## 参考资料

* [SeqFileHowTo][1]
* [Linux 内核跟踪之 ringbuffer 的实现][2]

[1]: https://kernelnewbies.org/Documents/SeqFileHowTo
[2]: https://blog.csdn.net/ds1130071727/article/details/78528626
