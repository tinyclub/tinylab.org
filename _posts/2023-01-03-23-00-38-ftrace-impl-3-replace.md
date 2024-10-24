---
layout: post
author: 'song'
title: 'RISC-V Ftrace 实现原理（3）- 替换函数入口'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /ftrace-impl-3-replace/
description: 'RISC-V Ftrace 实现原理（3）- 替换函数入口'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - Ftrace
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [spaces header codeblock]
> Author:   sugarfillet <sugarfillet@yeah.net>
> Date:     2022/09/09
> Revisor:  Falcon falcon@tinylab.org
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V ftrace 相关技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I58N1O)
> Sponsor:  PLCT Lab, ISCAS


## 前言

上文讲到 RISC-V 架构下，ftrace 会在内核函数入口插入 16 Bytes 长的 nop 用来进行指令替换，继而进行函数跟踪，并且通过 `ftrace_pages_start` 记录所有的函数入口地址。那么这个函数入口表在平时的 ftrace 跟踪内核函数的过程中，又扮演什么样的角色呢？

我们先回顾下，使用 ftrace 来跟踪 `vfs_read` 函数是否被调用的操作步骤：

```sh
1. cd /sys/kernel/debug/tracing
2. echo function > current_tracer
3. echo vfs_read > set_ftrace_filter
4. echo 1 > tracing_on
5. cat trace
```

其中比较重要的是第 2 个和第 3 个命令，第 2 个命令表示使用 function 类型的 tracer，第 3 个命令表示只对 `vfs_read` 函数进行跟踪，在此命令返回后，此函数入口的 nop 就会被替换为对应的跳转指令。

本文我们在设置 function tracer 的前提下，以 `set_ftrace_filter` 文件的相关操作函数为切入点开始分析，过程中重点关注 `vfs_read` 这个函数相关信息如何被记录，并最终对其函数入口的 nop 进行替换，以及替换后如何执行到 function tracer 对应的跟踪函数。

**说明**：

* 本文的 Linux 版本采用 `Linux 5.18-rc1`

## set_ftrace_filter 的初始化过程

tracefs 初始化 `set_ftrace_filter` 文件，记录 `global_ops` 在 `inode->i_private`，注册 `ftrace_filter_fops` 在 `inode->i_fop`，相关代码如下：

```c
// kernel/trace/ftrace.c ：6434

static __init int ftrace_init_dyn_tracefs(struct dentry *d_tracer){

    ftrace_create_filter_files(&global_ops, d_tracer);

}

void ftrace_create_filter_files(struct ftrace_ops *ops,
                                struct dentry *parent)
{

    trace_create_file("set_ftrace_filter", TRACE_MODE_WRITE, parent,
                          ops, &ftrace_filter_fops);
}

tracefs_create_file()
  inode->i_private = data; // global_ops
  inode->i_fop = fops; // ftrace_filter_fops
```

`global_ops` 是一个全局结构体实例，主要用来记录跟踪函数 `ftrace_stub` 和记录目标函数的 hash 表 `func_hash`。

```c
// kernel/trace/ftrace.c ：1034

struct ftrace_ops global_ops = {
        .func                           = ftrace_stub,
        .local_hash.notrace_hash        = EMPTY_HASH,
        .local_hash.filter_hash         = EMPTY_HASH,
        INIT_OPS_HASH(global_ops)
        .flags                          = FTRACE_OPS_FL_INITIALIZED |
                                          FTRACE_OPS_FL_PID,
};
```

`ftrace_filter_fops` 中定义打开文件，读写文件，关闭文件的函数指针，每个函数的作用和调用的关键函数介绍如下：

- ftrace_filter_open

  在文件打开时执行，初始化 `iter` 结构体实例，并存放在 `file->private_data` 中

  关键函数：`ftrace_regex_open`

- ftrace_filter_write

  在对文件写入数据时执行，把目标函数更新到 `iter->hash` 中

  关键函数：`filter_parse_regex`, `enter_record`

- ftrace_regex_release

  在文件关闭时执行，遍历函数入口表，根据目标函数在新 hash 与旧 hash 中的存在状态，更新对应的 `rec->flags`，再次遍历函数入口表，根据 `rec->flags` 按需替换目标函数入口

  关键函数：`ftrace_hash_move`, `ftrace_run_update_code`

```c
// kernel/trace/ftrace.c ：5975
static const struct file_operations ftrace_filter_fops = {
        .open = ftrace_filter_open,
        .read = seq_read,
        .write = ftrace_filter_write,
        .llseek = tracing_lseek,
        .release = ftrace_regex_release,
};
```

## ftrace_filter_open

此函数在打开文件时执行，分配 `iter` 结构体实例，为其初始化相关成员，需要特别关注的成员是：

- `parser` 用于存放用户输入，当前操作流程中为 "vfs_read" 字符串
- `hash` 用于记录目标函数（vfs-read）对应的 `struct dyn_ftrace * rec`，当前操作流程中，hash 是 `ops->func_hash->filter_hash` 的一份拷贝

最后，写操作模式下，`iter` 记录在 `file->private_data` 中。具体代码如下：

```c
// kernel/trace/ftrace.c ：3890

static int ftrace_filter_open(struct inode *inode, struct file *file)
{
        struct ftrace_ops *ops = inode->i_private;  // 取出 ops
        return ftrace_regex_open(ops,
                        FTRACE_ITER_FILTER | FTRACE_ITER_DO_PROBES,
                        inode, file);
}

int ftrace_regex_open(struct ftrace_ops *ops, int flag,
                  struct inode *inode, struct file *file)
{
        if (trace_parser_get_init(&iter->parser, FTRACE_BUFF_MAX)) // 创建 FTRACE_BUFF_MAX 大小的 parser->buffer
                goto out;

        iter->ops = ops;
        iter->flags = flag;
        iter->tr = tr;

        hash = ops->func_hash->filter_hash;

        const int size_bits = FTRACE_HASH_DEFAULT_BITS;

        iter->hash = alloc_and_copy_ftrace_hash(size_bits, hash); // 拷贝 hash

        file->private_data = iter;
}
```

## ftrace_filter_write

此函数在对文件写入时执行，解析用户态字符串 `ubuf`，存放到 `parser->buffer`，遍历函数入口表 `ftrace_pages_start`，找到其匹配项 `rec`，并通过 `enter_record()` 函数将 `rec` 记录到 `iter->hash`，关键代码如下：

```c
// kernel/trace/ftrace.c ：4964

ssize_t ftrace_filter_write(struct file *file, const char __user *ubuf,
                    size_t cnt, loff_t *ppos)
{
        return ftrace_regex_write(file, ubuf, cnt, ppos, 1);
}

ftrace_regex_write(file, ubuf, cnt, ppos, 1);
  trace_get_user(parser, ubuf, cnt, ppos); // 解析用户态字符串 ubuf，存放到 parser->buffer
  ftrace_process_regex(iter, parser->buffer, parser->idx, enable); // 遍历函数入口表，找到匹配项，并记录到 iter->hash
    func_g.type = filter_parse_regex(func, len, &func_g.search, &clear_filter); // 解析目标函数到 func_g.search，用于后续的函数入口表匹配
    do_for_each_ftrace_rec(pg, rec) {  // 遍历 `ftrace_pages_start`
     if(ftrace_match_record(rec, &func_g, mod_match, exclude_mod)) // 通过 kallsyms_lookup 获取当前 rec->ip 对应的函数符号，与 func_g 进行匹配
       enter_record(hash, rec, clear_filter)  // 把当前函数更新到 iter->hash 中
```

值得关注的是，`do_for_each_ftrace_rec` 宏表示遍历函数入口表，在如下代码中可以看到，其实是在遍历 `ftrace_pages_start`，所有的函数入口记录在 `&pg->records` 指针数组中，以 `pg->index` 为检索范围来找对应的 `rec`。

而 `rec` 是一个 `struct dyn_ftrace *` 类型，此结构体中 `ip` 即函数入口，`flags` 用来控制对当前函数的跟踪，比如：是否开启跟踪，函数跟踪时是否保留寄存器，当前的引用计数等，详细可参考 `vim -t FTRACE_FL_ENABLED`。在后续代码中，ftrace 是否要执行指令修改，就是通过 `rec->flags` 来判断。

```c
// kernel/trace/ftrace.c ：1502

#define do_for_each_ftrace_rec(pg, rec)                                 \
        for (pg = ftrace_pages_start; pg; pg = pg->next) {              \
                int _____i;                                             \
                for (_____i = 0; _____i < pg->index; _____i++) {        \
                        rec = &pg->records[_____i];

#define while_for_each_ftrace_rec()             \
                }                               \
        }

// kernel/trace/ftrace.c ：1087

struct ftrace_page {
        struct ftrace_page      *next;
        struct dyn_ftrace       *records;
        int                     index;
        int                     order;
};

// include/linux/ftrace.h ：1141

struct dyn_ftrace {
        unsigned long           ip; /* address of mcount call-site */
        unsigned long           flags;
        struct dyn_arch_ftrace  arch;
};
```

为了加深对上述过程的理解，这里我们做个小实验，判断 `ftrace_process_regex` 函数执行后 `vfs_read` 是否在 `iter->hash` 中，操作步骤如下：

1. VM 中执行 `echo 'vfs_read' >> set_ftrace_filter`
2. 在 `ftrace_pages_start` 中获取 `vfs_read` 对应的函数入口
3. 断点到 `ftrace_process_regex` 函数，`b ftrace_process_regex`，使此函数运行结束 `finish`，引用 `iter->hash`
4. 调用内核的 `ftrace_lookup_ip()` 函数，判断函数入口是否在 `iter->hash` 中存在

```sh
(gdb) x ftrace_pages_start->records[7224]->ip     ## 为啥是 7724 ?
   0xffffffff801f8b24 <vfs_read>:       nop
(gdb) b ftrace_process_regex
(gdb) c
(gdb) finish
Run till exit from #0  ftrace_process_regex (buff=0xff600000031ee600 "vfs_read", len=8,
    enable=enable@entry=1, iter=<optimized out>, iter=<optimized out>) at ../kernel/trace/ftrace.c:4887
ftrace_regex_write (file=<optimized out>, ubuf=<optimized out>, cnt=<optimized out>,
    ppos=<optimized out>, enable=enable@entry=1) at ../kernel/trace/ftrace.c:4953
4953                    trace_parser_clear(parser);
Value returned is $122 = 0
(gdb)
(gdb) p ftrace_lookup_ip(iter->hash,0xffffffff801f8b24)
$123 = (struct ftrace_func_entry *) 0xff60000002c863e0
```

这里可以看到 `$123` 不是空指针，所以 `vfs_read` 的函数入口确实存在于 `iter->hash` 中。至于为啥通过 7724 来获取 vfs_read 的函数入口，在 VM 中执行 `grep -n 'vfs_read$' available_filter_functions`，相信你可以得到答案。

## ftrace_regex_release

此函数在文件关闭时执行，把当前的 `iter->hash` 移动到旧的 hash (`ops->func_hash->filter_hash`)，在移动过程中，对比两个 hash 中的目标函数，按需更新每个函数的 `rec->flags` 的计数及相关功能 flags，后以 `FTRACE_UPDATE_CALLS` 命令执行 `ftrace_run_update_code()`，此函数会检测每个函数 `rec->flags` 的状态，执行 `FTRACE_UPDATE_MAKE_CALL` 操作，将当前函数入口替换为 `ftrace_caller`。代码摘录如下：

```c
// kernel/trace/ftrace.c ：5911

ftrace_regex_release()
 orig_hash = &iter->ops->func_hash->filter_hash // 记录之前的 hash
 filter_hash = !!(iter->flags & FTRACE_ITER_FILTER);  // 这里是 true
 ftrace_hash_move_and_update_ops(iter->ops, orig_hash, iter->hash, filter_hash);
 free_ftrace_hash(iter->hash);
```

`ftrace_hash_move_and_update_ops()` 函数执行 `ftrace_hash_move()`，如果前者正常返回表示有函数入口需要替换，则执行 `ftrace_ops_update_code()`。

```c
// kernel/trace/ftrace.c ：4140
static int ftrace_hash_move_and_update_ops(struct ftrace_ops *ops, struct ftrace_hash **orig_hash, struct ftrace_hash *hash, int enable)
{
        struct ftrace_ops_hash old_hash_ops;
        struct ftrace_hash *old_hash;
        int ret;

        old_hash = *orig_hash;
        old_hash_ops.filter_hash = ops->func_hash->filter_hash;
        old_hash_ops.notrace_hash = ops->func_hash->notrace_hash;  // old_hash_ops 是 ops->func_hash->{filter_hash,notrace_hash} 更新前的备份，在修改代码前备份到 ops->old_hash
        ret = ftrace_hash_move(ops, enable, orig_hash, hash);
        if (!ret) {
                ftrace_ops_update_code(ops, &old_hash_ops);
                free_ftrace_hash_rcu(old_hash);
        }
        return ret;
}
```

`ftrace_hash_move()` 通过新旧两个 hash 对比来更新函数入口表中的 `rec->flags`，并最终把 new_hash 更新到 old_hash。关键代码如下：

```c
// kernel/trace/ftrace.c ：1407

static int ftrace_hash_move(struct ftrace_ops *ops, int enable,struct ftrace_hash **dst, struct ftrace_hash *src){
     new_hash = __ftrace_hash_move(src);
     ret = __ftrace_hash_update_ipmodify(ops, old_hash, new_hash); // 遍历函数入口表，更新 rec->flags 的 FTRACE_FL_IPMODIFY，避免多 ftrace 用户并发修改
     ftrace_hash_rec_disable_modify(ops, enable);  // 将 old_hash 中的函数的 flags 计数减一并清空相关功能 flags
     rcu_assign_pointer(*dst, new_hash);           // 将 new_hash 覆盖到 old_hash (ops->func_hash->filter_hash)
     ftrace_hash_rec_enable_modify(ops, enable);  // 将 new_hash 中的函数的 flags 计数加一并初始化相关功能 flags
}
```

我们通过实验来查看，此函数执行前后，`vfs_read` 对应的 `rec->flags` 分别是什么状态，`old_hash` 中是否存在 `vfs_read`。

```sh
(gdb) p ftrace_pages_start->records[7224]
$133 = {ip = 18446744071564135204, flags = 0, arch = {<No data fields>}}
(gdb) p/x ftrace_pages_start->records[7224]->ip
$134 = 0xffffffff801f8b24
(gdb) p/x ftrace_pages_start->records[7224]->flags
$135 = 0x0                                           ## flags 为 0
(gdb) p ftrace_lookup_ip(global_ops->func_hash->filter_hash,0xffffffff801f8b24)
$136 = (struct ftrace_func_entry *) 0x0              ## old_hash 中没有 `vfs_read`

### ftrace_hash_move 执行之前

(gdb) b ftrace_hash_move
Breakpoint 7 at 0xffffffff800d324c: file ../kernel/trace/ftrace.c, line 1414.
(gdb) c
Continuing.

Breakpoint 7, 0xffffffff800d324c in ftrace_hash_move (src=<optimized out>, dst=<optimized out>,
    enable=<optimized out>, ops=<optimized out>) at ../kernel/trace/ftrace.c:1414
1414            if (ops->flags & FTRACE_OPS_FL_IPMODIFY && !enable)
(gdb) finish
Run till exit from #0  0xffffffff800d324c in ftrace_hash_move (src=<optimized out>, dst=<optimized out>,
    enable=<optimized out>, ops=<optimized out>) at ../kernel/trace/ftrace.c:1414
ftrace_hash_move_and_update_ops (ops=0xffffffff81495850 <global_ops>,
    orig_hash=orig_hash@entry=0xffffffff81495880 <global_ops+48>, hash=0xff60000001b4b6c0,
    enable=enable@entry=1) at ../kernel/trace/ftrace.c:4152
4152            ret = ftrace_hash_move(ops, enable, orig_hash, hash);
(gdb) n
4154                    ftrace_ops_update_code(ops, &old_hash_ops);

### ftrace_hash_move 执行之后

(gdb) p ftrace_lookup_ip(global_ops->func_hash->filter_hash,0xffffffff801f8b24)
$138 = (struct ftrace_func_entry *) 0xff60000002c863e0   ## old hash 中存在
(gdb) p/x ftrace_pages_start->records[7224]->flags
$139 = 0x1                                               ## flags 更新为 1
(gdb) p/x ftrace_pages_start->records[7224]->ip
$140 = 0xffffffff801f8b24

```

从上面的输出可以看到，`ftrace_hash_move` 之前后，`vfs_read` 对应的函数更新到了 `old_hash` 中，`vfs_read` 对应的 `rec->flags` 从 0 变更为 1，代表该函数需要被跟踪，需要对其执行函数入口的指令替换。

`ftrace_ops_update_code（）` 函数，通过指定 `FTRACE_UPDATE_CALLS` 调用 `ftrace_run_update_code()` 函数，用来执行函数入口的指令替换：

```c
// kernel/trace/ftrace.c ：4109

ftrace_ops_update_code(ops, &old_hash_ops);
     ftrace_run_modify_code(op, FTRACE_UPDATE_CALLS, old_hash); // FTRACE_UPDATE_CALLS 表示执行函数入口修改

static void ftrace_run_modify_code(struct ftrace_ops *ops, int command,
                                   struct ftrace_ops_hash *old_hash)
{
        ops->flags |= FTRACE_OPS_FL_MODIFYING;
        ops->old_hash.filter_hash = old_hash->filter_hash;
        ops->old_hash.notrace_hash = old_hash->notrace_hash;   // 代码替换前更新备份 old_hash
        ftrace_run_update_code(command);
        ops->old_hash.filter_hash = NULL;
        ops->old_hash.notrace_hash = NULL;
        ops->flags &= ~FTRACE_OPS_FL_MODIFYING;
}
```

## ftrace_run_update_code

此函数在接受命令后经过一连串的调用最终执行到 `ftrace_modify_all_code()`，这里执行 `FTRACE_UPDATE_CALLS` 命令，遍历函数入口表，执行 `__ftrace_replace_code()`。关键代码如下：

```c
// kernel/trace/ftrace.c ：2805

ftrace_run_update_code(command);
  arch_ftrace_update_code(command);
    ftrace_run_stop_machine(command);
      stop_machine(__ftrace_modify_code, &command, NULL);
        ftrace_modify_all_code(*command);

void ftrace_modify_all_code(int command){
        if (command & FTRACE_UPDATE_CALLS)
                ftrace_replace_code(mod_flags | FTRACE_MODIFY_ENABLE_FL);
}

void __weak ftrace_replace_code(int mod_flags){
  do_for_each_ftrace_rec(pg, rec){
    __ftrace_replace_code(rec, enable);
  }
}
```

`__ftrace_replace_code()` 函数会选择对应的跳转目标，这里是 `ftrace_caller`，通过 `ftrace_update_record()` 判断目标函数的修改方式，这里是 `FTRACE_UPDATE_MAKE_CALL`，表示当前函数入口要从 nop 替换为对 `ftrace_caller` 的调用，继而执行 `ftrace_make_call()`。具体代码如下：

```c
// kernel/trace/ftrace.c ：2555

static int __ftrace_replace_code(struct dyn_ftrace *rec, bool enable)
{
        unsigned long ftrace_old_addr;
        unsigned long ftrace_addr;
        int ret;

        ftrace_addr = ftrace_get_addr_new(rec); // 选择要跳转的目标地址 FTRACE_ADDR ftrace_caller

        /* This needs to be done before we call ftrace_update_record */
        ftrace_old_addr = ftrace_get_addr_curr(rec);

        ret = ftrace_update_record(rec, enable); // 判断修改类型 MAKE_CALL: FMAKE_NOP:MODIFY_CALL:

        ftrace_bug_type = FTRACE_BUG_UNKNOWN;

        switch (ret) {
        case FTRACE_UPDATE_IGNORE:
                return 0;

        case FTRACE_UPDATE_MAKE_CALL:
                ftrace_bug_type = FTRACE_BUG_CALL;
                return ftrace_make_call(rec, ftrace_addr);  // 执行函数地址替换，从 nop 替换为 ftrace_caller

        case FTRACE_UPDATE_MAKE_NOP:
                ftrace_bug_type = FTRACE_BUG_NOP;
                return ftrace_make_nop(NULL, rec, ftrace_old_addr);

        case FTRACE_UPDATE_MODIFY_CALL:
                ftrace_bug_type = FTRACE_BUG_UPDATE;
                return ftrace_modify_call(rec, ftrace_old_addr, ftrace_addr);
        }

        return -1; /* unknown ftrace bug */
}
```

`ftrace_make_call()` 函数根据 `ftrace_caller` 与 `rec->ip` 之间的距离，构造 `auipc` 和 `jalr` 指令，调用 `patch_text_nosync()` 进行 nop 的替换。

```c
// arch/riscv/kernel/ftrace.c ：101

int ftrace_make_call(struct dyn_ftrace *rec, unsigned long addr)
{
        unsigned int call[4] = {INSN0, 0, 0, INSN3};
        unsigned long target = addr;
        unsigned long caller = rec->ip + FUNC_ENTRY_JMP;

        call[1] = to_auipc_insn((unsigned int)(target - caller));
        call[2] = to_jalr_insn((unsigned int)(target - caller));

        if (patch_text_nosync((void *)rec->ip, call, FUNC_ENTRY_SIZE))
                return -EPERM;

        return 0;
}
```

那么 `vfs_read` 函数入口被替换后是什么样的呢？我们通过反汇编来看一下：

```
(gdb) x/-4i vfs_read
   0xffffffff801f8b24 <vfs_read>:       sd      ra,-8(sp)
   0xffffffff801f8b28 <vfs_read+4>:     auipc   ra,0xffe10
   0xffffffff801f8b2c <vfs_read+8>:     jalr    428(ra)
   0xffffffff801f8b30 <vfs_read+12>:    ld      ra,-8(sp)
```

1. 第一条指令，ra 保存的是 caller 的地址，即当前函数的返回地址，sd 指令把 ra 内容入栈
2. 第二条指令，auipc 把立即数左移 12 位，加到 pc 上，并存入 ra
3. 第三条指令，jalr 跳转到 ra 中地址偏移 428 的地址，并将第四条指令地址存入 ra，确保能在目标地址指令执行完后，可以回到第四条指令
4. 第四条指令，是第一条指令的反操作，弹栈，并存入 ra 中，此指令执行完后，与全 nop 的指令入口相比，ra sp 都无变化

现在 `vfs_read` 函数的入口，会通过第三条指令跳转到 `ftrace_caller`，那么这个函数又是干嘛的呢？

## ftrace_caller

`ftrace_caller` 被上文第三条指令跳转调用，执行上下文的保存与恢复，为 `ftrace_func_t` 类型的跟踪函数设置入参，并调用跟踪函数，具体内容如下：

1. `SAVE_ABI` 让所有 ABI 相关寄存器入栈保存
   1. 栈增 8 字节，存放上文第一条指令中提到的当前函数的返回地址
   2. 栈增 72 字节，存放 `a0-a7` 以及 `ra` 共 9 个寄存器的内容
2. 以 `ftrace_func_t` 函数指针为跟踪函数原型，设置入参：
   1. a0：对应参数 `ip`，代表 `vfs_read` 函数入口地址，通过存放函数入口第四条指令的 ra 减去 `FENTRY_RA_OFFSET` (12) 获得函数入口
   2. a1：对应参数 `parent_ip`，代表 `vfs_read` 函数的返回地址，通过 sp 的 72 字节偏移获取当前函数的返回地址
   3. a2: 对应参数 `op`，代表当前使用的 `ftrace_ops`，通过 `function_trace_op` 取值获取
   4. a3: 对应参数 `fregs`，代表当前函数的所有 ABI 寄存器的值，通过 sp 获取
3. 定义 `ftrace_call` label，并调用 `call ftrace_stub`
4. `RESTORE_ABI` 让所有 ABI 相关寄存器弹栈
5. ret 返回到函数入口执行第四条指令

从功能上来看，`ftrace_caller` 跟静态 ftrace 中的 `_mount` 是一致的。

```c
// include/linux/ftrace.h ：132

typedef void (*ftrace_func_t)(unsigned long ip, unsigned long parent_ip,struct ftrace_ops *op, struct ftrace_regs *fregs);
```

```c
// arch/riscv/kernel/mcount-dyn.S ：28
        .macro SAVE_ABI
        addi    sp, sp, -SZREG  // 8
        addi    sp, sp, -ABI_SIZE_ON_STACK // 9*8 = 72

        REG_S   a0, ABI_A0(sp)
        REG_S   a1, ABI_A1(sp)
        REG_S   a2, ABI_A2(sp)
        REG_S   a3, ABI_A3(sp)
        REG_S   a4, ABI_A4(sp)
        REG_S   a5, ABI_A5(sp)
        REG_S   a6, ABI_A6(sp)
        REG_S   a7, ABI_A7(sp)
        REG_S   ra, ABI_RA(sp)
        .endm

// arch/riscv/kernel/mcount-dyn.S ：114
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

        RESTORE_ABI
        ret
ENDPROC(ftrace_caller)

```

正如，[ftrace 实现原理（1）- 函数跟踪][2] 中所述，`ftrace_stub` 只是个直接返回的函数，用来在关闭函数跟踪的时候直接返回。而从上述汇编码的逻辑上看，即使开启函数跟踪，也只会执行 `ftrace_stub` 并不会调用跟踪函数。但实际上是这样么？我们在设置 function tracer 的前提，在 gdb 环境中对 `ftrace_caller` 执行反汇编：

```sh
(gdb) disassemble ftrace_caller
Dump of assembler code for function ftrace_caller:
   0xffffffff80008cd4 <+0>:     addi    sp,sp,-8
   0xffffffff80008cd6 <+2>:     addi    sp,sp,-72
   0xffffffff80008cda <+6>:     sd      a0,0(sp)
   0xffffffff80008cdc <+8>:     sd      a1,8(sp)
   0xffffffff80008cde <+10>:    sd      a2,16(sp)
   0xffffffff80008ce0 <+12>:    sd      a3,24(sp)
   0xffffffff80008ce2 <+14>:    sd      a4,32(sp)
   0xffffffff80008ce4 <+16>:    sd      a5,40(sp)
   0xffffffff80008ce6 <+18>:    sd      a6,48(sp)
   0xffffffff80008ce8 <+20>:    sd      a7,56(sp)
   0xffffffff80008cea <+22>:    sd      ra,64(sp)
   0xffffffff80008cec <+24>:    addi    a0,ra,-12
   0xffffffff80008cf0 <+28>:    auipc   a1,0x15b2
   0xffffffff80008cf4 <+32>:    addi    a1,a1,-920 # 0xffffffff815ba958 <function_trace_op>
   0xffffffff80008cf8 <+36>:    ld      a2,0(a1)
   0xffffffff80008cfa <+38>:    ld      a1,72(sp)
   0xffffffff80008cfc <+40>:    mv      a3,sp     ## 设置跟踪函数的第四个参数
   0xffffffff80008cfe <+42>:    auipc   ra,0xe1
   0xffffffff80008d02 <+46>:    jalr    -1220(ra) # 0xffffffff800e983a <function_trace_call>
   ...
```

可以看到 `ftrace_call` 替换成了对跟踪函数 `function_trace_call()` 的调用，这个函数就是 function tracer 所注册的跟踪函数。那这个替换过程又是怎么实现的呢？我们放在下篇文章中介绍。

## 总结

本文主要介绍在设置 function tracer 的前提下，`echo vfs_read >> set_ftrace_filter` 命令在内核的执行过程，我们以 `set_ftrace_filter` 文件的相关操作函数为切入点开始分析，分别分析 `{open,write,release}` 三个接口的实现：

- `ftrace_filter_open()`，在文件打开时执行，初始化 `iter` 结构体实例，并存放在 `file->private_data` 中
- `ftrace_filter_write()`，在对文件写入数据时执行，把目标函数更新到 `iter->hash`，其中对 `do_for_each_ftrace_rec` 宏进行展开分析
- `ftrace_regex_release()`，在文件关闭时执行，遍历函数入口表，根据目标函数是否在新旧 hash 中，更新对应的 `rec->flags`，再次遍历函数入口表，根据 `rec->flags` 按需替换目标函数入口

`vfs_read` 目标函数依次通过 `iter->parser => func_g.search => iter->hash => ops->func_hash->filter_hash => rec->flags` 这些结构来记录，后续由 `ftrace_run_update_code()` 函数根据 `rec->flags` 将函数入口替换为对 `ftrace_caller` 的调用。

然后，我们对与静态 ftrace 中 `_mcount` 功能相同的 `ftrace_caller` 进行分析，分析其如何设置跟踪函数的入参，并调用 function tracer 的跟踪函数 `function_trace_call()`，最后，抛出一个问题：`ftrace_call` 是如何被替换为 function tracer 所注册的跟踪函数 `function_trace_call()`，这个我们放在下篇文章来分析。

## 参考资料

* [探秘 ftrace][1]

[1]: https://richardweiyang-2.gitbook.io/kernel-exploring/00-index-3/04-ftrace_internal#gai-dai-ma
[2]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220812-ftrace-impl-1-mcount.md
