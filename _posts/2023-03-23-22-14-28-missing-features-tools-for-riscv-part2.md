---
layout: post
author: 'nfk'
title: 'RISC-V 缺失的 Linux 内核功能-Part2'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /missing-features-tools-for-riscv-part2/
description: 'RISC-V 缺失的 Linux 内核功能-Part2'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [urls pangu autocorrect epw]
> Author:    牛工 - 通天塔 985400330@qq.com
> Date:      2022/08/28
> Revisor:   Falcon <falcon@ruma.tech>; iOSDevLog <iosdevlog@iosdevlog.com>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [Missing Features/Tools for RISC-V](https://gitee.com/tinylab/riscv-linux/issues/I5L9H0)
> Sponsor:   PLCT Lab, ISCAS


## 前言

上一篇文章对 RISC-V 架构下缺失的 Linux 内核功能进行了分析，现在 Linux 内核升级到 V6.0 之后，新增了一些 RISC-V 未能加入的功能，现进一步进行缺失功能的分析，希望能够帮助大家完善 RISC-V 缺失的功能。

## cBPF-JIT (Kernel Feature)

- **功能：**

  BPF 全称 Berkeley Packet Filter

  > BPF is a highly flexible and efficient virtual machine-like construct in the Linux kernel allowing to execute bytecode at various hook points in a safe manner. It is used in a number of Linux kernel subsystems, most prominently networking, tracing and security (e.g. sandboxing).

  BPF 是 Linux 内核中的一种高度灵活和高效的类虚拟机结构，允许以安全的方式在各种钩子点上执行字节码。它被用于许多 Linux 内核子系统中，最突出的是网络、跟踪和安全（例如沙箱）。

  以下引自 [BPF 内核实现详解 - 知乎（zhihu.com）][011]：

  > 本质上它是一种内核代码注入的技术：
  >
  > 内核中实现了一个 cBPF/eBPF 虚拟机；
  >
  > 用户态可以用 C 来写运行的代码，再通过一个 Clang&LLVM 的编译器将 C 代码编译成 BPF 目标码；
  >
  > 用户态通过系统调用 bpf() 将 BPF 目标码注入到内核当中；
  >
  > 内核通过 JIT(Just-In-Time) 将 BPF 目编码转换成本地指令码；如果当前架构不支持 JIT 转换内核则会使用一个解析器（interpreter）来模拟运行，这种运行效率较低；
  >
  > 内核在 packet filter 和 tracing 等应用中提供了一系列的钩子来运行 BPF 代码。

  BPF 分为 cBPF（经典 BPF）和 eBPF（扩展 BPF），当前缺失的是 cBPF。[Classic BPF vs eBPF — The Linux Kernel documentation][010] 文章中讲述了关于 cBPF 和 eBPF 的区别。

  **状态**

  - 社区提交 [[PATCH v9 bpf-next 8/9] bpf: introduce bpf_jit_binary_pack_[alloc|finalize|free] - Song Liu (kernel.org)][002]
  - **ok**: mips, powerpc, sparc
  - **TODO**: alpha, arc, arm arm64, csky, hexagon, ia64, loongarch, m68k, microblaze, nios2, openrisc, parisc riscv, s390, sh, um, x86 xtensa

  **资料**

  - [[PATCH v9 bpf-next 8/9] bpf: introduce bpf_jit_binary_pack_[alloc|finalize|free] - Song Liu (kernel.org)][002]
  - [cBPF-JIT - search results (kernel.org)][005]
  - [BPF 内核实现详解 - 知乎（zhihu.com）][011]
  - [BPF and XDP Reference Guide — Cilium 1.12.90 documentation][001]
  - [Classic BPF vs eBPF — The Linux Kernel documentation][010]

## cmpxchg-local(Kernel Feature)

- 功能：

  > HAVE_CMPXCHG_LOCAL
  >
  > arch supports the this_cpu_cmpxchg() API

  如果开启了 HAVE_CMPXCHG_LOCAL，架构将支持 this_cpu_cmpxchg() API。

  CMPXCHG 是一条汇编指令，意思是 “Compare and Exchange”，比较并且交换。

  ```
   // version：Linux 6.1-rc1
   // arch/x86/include/asm/cmpxchg.h
   /*
   * Atomic compare and exchange.  Compare OLD with MEM, if identical,
   * store NEW in MEM.  Return the initial value in MEM.  Success is
   * indicated by comparing RETURN with OLD.
   * 原子的比较和交换，比较旧的 MEM，如果完全相同，保存新的到 MEM 中，返回 MEM 的初始化值，
   * 通过比较返回值与旧的值判断是否成功。
   */
  #define __raw_cmpxchg(ptr, old, new, size, lock)                        \
  ({                                                                      \
          __typeof__(*(ptr)) __ret;                                       \
          __typeof__(*(ptr)) __old = (old);                               \
          __typeof__(*(ptr)) __new = (new);                               \
          switch (size) {                                                 \
          case __X86_CASE_B:                                              \
          {                                                               \
                  volatile u8 *__ptr = (volatile u8 *)(ptr);              \
                  asm volatile(lock "cmpxchgb %2,%1"                      \
                               : "=a" (__ret), "+m" (*__ptr)              \
                               : "q" (__new), "0" (__old)                 \
                               : "memory");                               \
                  break;                                                  \
          }
          ...
  ```

  cmpxchg 主要是实现原子级别的比较和切换，在 x86 架构下，主要依赖于 cmpxchgb 指令，RISC-V 架构下也有相关的代码实现。

  ```
   // version：Linux 6.1-rc1
   // mm/vmstat.c
  #ifdef CONFIG_HAVE_CMPXCHG_LOCAL
  /*
   * If we have cmpxchg_local support then we do not need to incur the overhead
   * that comes with local_irq_save/restore if we use this_cpu_cmpxchg.
   * 如果我们支持 cmpxchg_local，并且使用 this_cpu_cmpxchg，
   * 我们将不会有 local_irq_save/restore 所带来的额外开销。
   *
   * mod_state() modifies the zone counter state through atomic per cpu
   * operations.
   * mod_state()通过每个 cpu 操作对区域计数器状态进行修改。

   * Overstep mode specifies how overstep should handled:
   *     0       No overstepping
   *     1       Overstepping half of threshold
   *     -1      Overstepping minus half of threshold
   *
   * Overstep 模式指定如何处理：
   * 0 不超过
   * 1 超过阈值的一半
   * -1 超过负一半的阈值
  */
  static inline void mod_zone_state(struct zone *zone,
         enum zone_stat_item item, long delta, int overstep_mode)
  {
          struct per_cpu_zonestat __percpu *pcp = zone->per_cpu_zonestats;
          s8 __percpu *p = pcp->vm_stat_diff + item;
          long o, n, t, z;

          do {
                  z = 0;  /* overflow to zone counters */
  ...
  ```

  通过以上代码及注释分析可知，cmpxchg-local 是基于 cmpxchg 的功能拓展，可以在多核的情况下，减少系统开销，提高运行效率。

  具体 cmpxchg_local 是怎么基于架构进行实现的需要进一步分析，感兴趣的大佬可以继续分析一下。

- 状态
  - 社区刚提交 [[RFC PATCH 1/4] vmstat: percpu: Rename HAVE_CMPXCHG_LOCAL to HAVE_CMPXCHG_PERCPU_BYTE][003]
  - **ok**: arm64, s390, x86
  - **TODO**: alpha, arc, arm csky, hexagon, ia64, loongarch, m68k, microblaze, mips nios2, openrisc, parisc, powerpc, riscv, sh, sparc um, xtensa

- 资料
  - [[RFC PATCH 1/4] vmstat: percpu: Rename HAVE_CMPXCHG_LOCAL to HAVE_CMPXCHG_PERCPU_BYTE][003]
  - [Linux 内核中的 cmpxchg 函数][009]
  - [邮件列表最新动态][006]

## Avoiding retpolines with static calls(Kernel Feature)

该功能的历史：

- 2018 年发现漏洞 Meltdown 和 Spectre
- 谷歌提出 Retpolines 解决了这个安全问题，但引入了 4% 的性能影响。
- 开发者们不断寻求解决方法：[Relief for retpoline pain][007]
- 2020 年使用 static calls 方法避免使用 retpolines，性能影响降低至 1.6%：[Avoiding retpolines with static calls][008]

通过代码查询，可知 static_call 功能是架构相关的功能，当前仅在两个架构下进行了实现。

查询结果如下：

```
$ find arch -name "*static*call*"
arch/powerpc/include/asm/static_call.h
arch/powerpc/kernel/static_call.c
arch/x86/include/asm/static_call.h
arch/x86/kernel/static_call.c
```

文件中有较多的汇编代码，要分析清楚该部分功能，需要基于理解该功能引入时解决的问题，追溯该功能的历史。

- 状态
  - **ok**: x86，powerpc
  - **TODO**: arm64, s390, alpha, arc, arm, csky, hexagon, ia64, loongarch, m68k, microblaze, mips, nios2, openrisc, riscv, sh, sparc um, xtensa

- 资料
  - [Relief for retpoline pain][007]
  - [Avoiding retpolines with static calls][008]
  - [邮件列表最新动态][004]

## 小结

本文写了 3 个在 RISC-V 架构下缺失的 Linux 内核功能，其中 cBPF-JIT 和 cmpxchg-local 是在内核的 doc 文档中明确写出来了 TODO 任务的。Avoiding retpolines with static calls 功能是吴老师关注到的 RISC-V 架构下缺失的功能，该功能意义非常大，但适配的架构还非常少，后续我也会输出一些关于该功能的一些文章。

## 参考资料

- [[PATCH v9 bpf-next 8/9] bpf: introduce bpf_jit_binary_pack_[alloc|finalize|free] - Song Liu (kernel.org)][002]
- [cBPF-JIT - search results (kernel.org)][005]
- [BPF 内核实现详解 - 知乎（zhihu.com）][011]
- [BPF and XDP Reference Guide — Cilium 1.12.90 documentation][001]
- [Classic BPF vs eBPF — The Linux Kernel documentation][010]
- [Linux 内核中的 cmpxchg 函数][009]
- [Relief for retpoline pain][007]
- [Avoiding retpolines with static calls][008]
- [[RFC PATCH 1/4] vmstat: percpu: Rename HAVE_CMPXCHG_LOCAL to HAVE_CMPXCHG_PERCPU_BYTE][003]

[001]: https://docs.cilium.io/en/latest/bpf/
[002]: https://lore.kernel.org/all/20220204185742.271030-9-song@kernel.org/
[003]: https://lore.kernel.org/all/20220808080600.3346843-2-guoren@kernel.org/
[004]: https://lore.kernel.org/all/?q=Avoiding+retpolines+with+static+call
[005]: https://lore.kernel.org/all/?q=cBPF-JIT
[006]: https://lore.kernel.org/all/?q=cmpxchg-local
[007]: https://lwn.net/Articles/774743/
[008]: https://lwn.net/Articles/815908/
[009]: https://www.bbsmax.com/A/1O5EEv4W57/
[010]: https://www.kernel.org/doc/html/latest/bpf/classic_vs_extended.html
[011]: https://zhuanlan.zhihu.com/p/470680443
