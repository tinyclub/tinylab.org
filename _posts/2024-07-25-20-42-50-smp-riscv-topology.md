---
layout: post
author: 'sugarfillet'
title: 'RISC-V CPU 拓扑'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /smp-riscv-topology/
description: 'RISC-V CPU 拓扑'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - CPU 拓扑
  - Cache
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces header codeblock codeinline pangu epw]
> Author:    sugarfillet <sugarfillet@yeah.net>
> Date:      2023/03/23
> Revisor:   Falcon falcon@tinylab.org
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V Linux SMP 技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I5MU96)
> Sponsor:   PLCT Lab, ISCAS


## 前言

CPU 拓扑是指在多个 CPU 核心和多个 CPU 插槽、多个 CPU cluster 之间的物理和逻辑布局关系。通过了解 CPU 拓扑信息，操作系统可以更好地进行任务调度和资源管理，以充分利用系统的硬件资源。

本文分析 RISC-V Linux 的 CPU 拓扑管理实现，主要涉及 CPU 拓扑和 cache 的初始化过程以及 CPU 算力和频率的计算过程。

**说明**：

- 本文的 Linux 版本采用 `Linux v6.2`

## CPU 拓扑初始化

Linux 启动过程中，boot CPU 上运行的 init 线程执行 `smp_prepare_cpus` 函数将非 boot CPU 设置为 `present` 状态，而在此操作之前会先调用 `init_cpu_topology` 函数执行 CPU 拓扑的初始化，此函数主要涉及以下关键过程：

`parse_dt_topology` 函数用于解析 dts 中 `cpu-map` 节点中描述的 CPU 拓扑信息，从下面代码可以看到依次调用 `parse_socket` - `parse_cluster` - `parse_core` 函数对全局的 `cpu_topology[cpu]` 数组的 id 类成员进行赋值。

在 `parse_core` 函数中会额外地调用 `topology_parse_cpu_capacity` 函数对当前 CPU 的算力和频率进行计算，其中 CPU 算力来自 `capacity-dmips-mhz` 属性，此值记录到 `raw_capacity[cpu]` 数组中；CPU 频率在没有复杂的时钟源（比如 PRIC）配置情况下，且此时 DVFS（动态调频）未初始化，简单地通过 dts 中定义的 `timebase-frequency` 得到，此值记录到 percpu 变量 `freq_factor` 中。

`parse_dt_topology` 函数之后调用 `topology_normalize_cpu_scale` 函数基于上述 CPU 算力和 CPU 频率对每个 CPU 的算力做归一化处理，限定在 `SCHED_CAPACITY_SCALE` 范围内，存储到 percpu 变量 `per_cpu(cpu_scale, cpu)` 中。

```c
// drivers/base/arch_topology.c : 826

init_cpu_topology()
    reset_cpu_topology(); // 重置 cpu_topology 数组
    parse_dt_topology(); // 解析 dts 中的 topo 数据，填充 cpu_topology.*id cpu_scale freq_factor
        parse_socket(map)
          parse_cluster(socket, 0, -1, 0);
            parse_core(c, package_id, cluster_id, core_id++)
                cpu_topology[cpu].package_id = package_id;
                cpu_topology[cpu].cluster_id = cluster_id;
                cpu_topology[cpu].core_id = core_id;
                cpu_topology[cpu].thread_id = i;
                topology_parse_cpu_capacity(cpu_node, cpu);
                    of_property_read_u32(cpu_node, "capacity-dmips-mhz", &cpu_capacity);
                    raw_capacity[cpu] = cpu_capacity;
                    per_cpu(freq_factor, cpu) = clk_get_rate(cpu_clk) / 1000; // no DVFS now

        topology_normalize_cpu_scale(); // 基于系统最大算力 capacity_scale 和最大频率因子 freq_factor 更新 cpu_scale
            capacity = raw_capacity[cpu] * per_cpu(freq_factor, cpu);
            capacity = div64_u64(capacity << SCHED_CAPACITY_SHIFT, capacity_scale);
            topology_set_cpu_scale(cpu, capacity);
```

`init_cpu_topology` 继续遍历 possible cpus，调用 `fetch_cache_info(cpu)` 函数进行 cacheinfo 的早期初始化，其中 `init_of_cache_level(cpu)` 函数负责解析 dts 中 CPU 节点以及 cache-controler 中定义的 cache 相关信息，统计 `[id]{0,1}cache-size` 的数目和最大 `cache-level` 到 percpu 变量 `ci_cpu_cacheinfo` 的 `num_leaves` 和 `num_levels` 成员中；`allocate_cache_info(cpu)` 函数根据 cache 数目为 `ci_cpu_cacheinfo` 分配 `struct cacheinfo info_list` 链表。

```c
// drivers/base/arch_topology.c : 826

init_cpu_topology()
    ...
    for_each_possible_cpu(cpu)
     fetch_cache_info(cpu);
        init_of_cache_level(cpu) // d-cache-size  i-cache-size cache-size next-level-cache cache-level
        allocate_cache_info(cpu);

struct cpu_cacheinfo {
        struct cacheinfo *info_list;
        unsigned int num_levels;
        unsigned int num_leaves;
        bool cpu_map_populated;
};

```

boot CPU 在 `init_cpu_topology` 函数执行完后会立刻调用 `store_cpu_topology()` 对其 CPU 拓扑做进一步的初始化，而非 boot CPU 则在其执行的第一个 C 语言函数 - `smp_callin` 的起始位置（执行热插拔 `STARTING` 阶段之前）调用此函数。`store_cpu_topology()` 函数调用 `update_siblings_masks()` 更新 `cpu_topology[cpu]` 数组中的 *sibing 等成员，关键过程如下：

`detect_cache_attributes` 函数首先判断 `fetch_cache_info` 阶段是否完成了 cacheinfo 的早期初始化，如果没有则执行架构的 cache 初始化函数 `init_cache_level()` 并执行 `allocate_cache_info(cpu)` 分配 cacheinfo 链表。之后执行架构函数 `populate_cache_leaves(cpu)` 对 `info_list` cache 链表成员进行早期初始化，依次解析 CPU 节点和 cache-controler 节点中定义的 cache 信息，记录 cache 类型、cache 级别、cache-size、cache-sets、cache-block-size 到链表节点的对应成员中。最后调用 `cache_shared_cpu_map_setup(cpu)` 函数，如果 cache 链表没有完全初始化（判断 `this_cpu_ci->cpu_map_populated` && `last_level_cache_is_valid(cpu)`)，则更新链表节点的 `fw_token` 和 `shared_cpu_map` 成员，前者存放当前 cache 的 dt 节点（struct device_node），后者描述共享此 cache 的 online cpus。

`update_siblings_masks` 函数最后为所有 online 状态的 CPU 更新 `cpu_topology[cpu]` 数组中的 `*sibing` 等成员：如果两个 CPU 的最后一级 cache 是一致的，则把彼此设置到各自的 `cpu_topology` 的 `llc_sibling` cpumask 中。如果两个 CPU 的 `package_id` 是一致的，则设置 `core_sibling`；`cluster_id` 一致则设置 `cluster_sibling`；`core_id` 一致则设置 `thread_sibling`。

```c
// drivers/base/arch_topology.c : 845

store_cpu_topology(cpu)
    update_siblings_masks(cpuid); // 填充 cpu_topology *sibling 成员
        detect_cache_attributes(cpuid);
            init_cache_level(cpu) && allocate_cache_info(cpu) // 如果在 init_cpu_topo - fetch_cache_info 中没有完成 cacheinfo 的早期初始化
            populate_cache_leaves() // 架构函数用于填充 this_cpu_ci->info_list
            cache_shared_cpu_map_setup(cpu); // 设置 fw_token and shared_cpu_map
                cache_setup_properties(cpu)
                for ... cpumask_set_cpu(cpu, &sib_leaf->shared_cpu_map)
        for_each_online_cpu(cpu)
        // update llc_sibling core_sibling,cluster_sibling,thread_sibling
```

> 上述内容比较枯燥，可以自己做个实验来加深印象：用 gdb 观察 qemu sifive_u 的 4 个 U54 Hart 在 CPU 拓扑和 cache 初始化后的全局数组 `cpu_topology[]` 的值

上文介绍了 CPU 拓扑的建立过程，大部分代码都集中在 `./drivers/base/arch_topology.c` 文件中，此文件为 `GENERIC_ARCH_TOPOLOGY` 配置的主要实现，此配置是在 commit (2ef7a2953c81 "arm, arm64: factorize common CPU capacity default code") 统一 arm 和 arm64 的 CPU 算力相关代码的过程中引入。RISC-V 在 commit (03f11f03dbfe "RISC-V: Parse CPU topology during boot") 中开启 `GENERIC_ARCH_TOPOLOGY` 以采用 arch_topology 来支撑 CPU 拓扑的相关功能。

## CPU 算力与频率

CFS (Completely Fair Scheduler) 是 Linux 中默认的进程调度器，其主要目标是在多个进程之间公平地分配 CPU 时间。其在任务放置（当任务创建或者唤醒时选择合适的 cpu）或者负载均衡时，需要给任务选择合适的 CPU，选择的基本匹配条件为任务利用率 < 目标 CPU 的算力。

任务利用率表示某个任务在单位时间内占用的 CPU 时间。在 big.LITTLE 系统中，假设一个周期执行的、有固定任务量的任务在 1GHz 的 LITTLE CPU 上的任务利用率为 50%，那么在 2GHz 的 LITTLE CPU 上的任务肯定不为 50%，同样在 1GHz 的 big CPU 上的任务利用率肯定也不是 50%，因此在支持 DVFS 的异构系统中，任务利用率可以通过如下公式来表示：

```
                                   curr_frequency(cpu)   capacity(cpu)
task_util_inv(p) = duty_cycle(p) * ------------------- * -------------
                                   max_frequency(cpu)    max_capacity
```

公式中：

- task_util_inv(p) 表示某个进程（或者调度实体）的不变任务利用率（英文为：Invariant task utilization），简单来说，此利用率计算时要考虑进程所在 CPU 的算力和运行频率
- duty_cycle(p) 表示某个进程在以最大频率运行的最大算力 CPU 上运行时的任务利用率
- curr_frequency(cpu)/max_frequency(cpu) 表示 CPU 当前频率与最大频率的比值，该比值由 CIE（Cpu/Capacity Invariance Engine）来进行计算
- capacity(cpu)/max_capacity 表示当前 CPU 算力与系统最大算力的比值，该比值由 FIE（Frequency Invariance Engine）来进行计算

> 所谓的 CIE/FIE，其实就是一个将多个频率值或者多个算力值限定到一个范围，并等比例地用范围内的值来表示的方法，跟下文使用的归一化是一个意思

> 为了描述方便，下文中的代码层面描述的 CPU 算力或者频率就代表归一化后的 CPU 算力或频率

### CPU 算力

CPU 算力即在单位时间内 CPU 处理的指令数目，通常表示为 MIPS (Millions of Instructions Per Second)，CPU 算力主要受两个因素的影响：

1. 微架构：不同类型的处理器有着不同的微架构，比如在 arm 的 big.LITTLE 系统中，大核要比小核有着更高规格的微架构（更深的流水线、更大的 cache、更好的分支预测）
2. 频率：不同类型的处理器有着不同的频率能耗表 (Operating Performance Points)，比如 big.LITTLE 系统中大核要比小核有着更高的 OPP

故而，cpu 算力从频率的角度可进一步描述为：`capacity(cpu) = work_per_hz(cpu) * max_freq(cpu)`，`work_per_hz(cpu)` 表示处理器单位 hz 处理指令的数目，`max_freq(cpu)` 表示处理器频率能耗表中定义的最大频率。换句话说，cpu 算力就是此运行在其最大频率所能处理指令的数目。

CPU 算力在 Linux 中通过 percpu 变量 `cpu_scale` 来表示，并提供接口 `topology_get_cpu_scale` 获取 CPU 算力。在 Linux 中无法自动计算原始的 CPU 算力，需要通过 dts 中的 "capacity-dmips-mhz" 属性来描述，在上文的 `topology_normalize_cpu_scale()` 阶段将其存储在 `raw_capacity[cpu]`。考虑到像 big.LITTLE 这样的异构处理器拓扑，Linux 对当前 CPU 算力基于系统最大算力进行归一化计算，范围限定在 [0,SCHED_CAPACITY_SCALE]，比如：raw_capacity[big] 为 2，raw_capacity[LITTLE] 为 1，则 `per_cpu(cpu_scale, big)` 为 1024，`per_cpu(cpu_scale, LITTLE)` 为 512。同时，在进行归一化之前，引入 CPU 最大频率因子（percpu 变量 `freq_factor`）计算 CPU 算力，在早期的 CPU 算力计算过程中，简单地通过 dts 中定义的 `timebase-frequency` 得到 `freq_factor`。而在 DVFS 初始化之后，明确了 CPU 的最大运行频率，则更新 `freq_factor` 并再次调用 `topology_normalize_cpu_scale()` 函数重新计算 CPU 算力。

相关代码如下：

```c
// include/linux/arch_topology.h :  23

static inline unsigned long topology_get_cpu_scale(int cpu) // 查询接口
{
        return per_cpu(cpu_scale, cpu);
}

// drivers/base/arch_topology.c : 271

topology_normalize_cpu_scale()  // 归一化 CPU 算力
        for_each_possible_cpu(cpu) {
                capacity = raw_capacity[cpu] * per_cpu(freq_factor, cpu);
                capacity_scale = max(capacity, capacity_scale);    // capacity_scale is the max capacity
        }
        for_each_possible_cpu(cpu) {
                capacity = raw_capacity[cpu] * per_cpu(freq_factor, cpu); // freq_factor
                capacity = div64_u64(capacity << SCHED_CAPACITY_SHIFT,capacity_scale);
                topology_set_cpu_scale(cpu, capacity);
        }

// drivers/base/arch_topology.c : 394

init_cpu_capacity_callback()  // DVFS 初始化后（准确说是 CPUFREQ_CREATE_POLICY 事件发生时），更新 freq_factor 并重新计算 CPU 算力
        ...
        for_each_cpu(cpu, policy->related_cpus)
                per_cpu(freq_factor, cpu) = policy->cpuinfo.max_freq / 1000;

        topology_normalize_cpu_scale();
        ...
```

与 CPU 算力相关的另一个接口为：`topology_update_cpu_topology`。此接口返回一个静态变量 `update_topology`，此变量在 CPU 算力更新后触发的 `update_topology_flags_work` 工作队列中更新，用来表示最大频率因子 `freq_factor` 更新导致的调度域重建是否完成。相关代码如下：

```c
// drivers/base/arch_topology.c : 244

int topology_update_cpu_topology(void)
{
        return update_topology;
}

// drivers/base/arch_topology.c : 394

init_cpu_capacity_callback()
    ...
    topology_normalize_cpu_scale();
    schedule_work(&update_topology_flags_work);
    ...

update_topology_flags_workfn(struct work_struct *work)
        update_topology = 1;
        rebuild_sched_domains();
        update_topology = 0;
```

### CPU 频率

CPU 频率指的是 CPU 的时钟频率，即 CPU 在单位时间内执行的时钟周期数。在开启 DVFS 的系统中，CPU 频率会在频率能耗表（OPP）定义的范围内变化。CPU 频率在 Linux 中通过 percpu 变量 `arch_freq_scale` 来表示，与 `cpu_scale` 类似，基于当前 CPU 最大频率进行 [0,SCHED_CAPACITY_SCALE] 范围内的归一化计算。相关访问接口如下：

`topology_scale_freq_tick` 接口在调度时钟中断过程中调用，底层调用调频源注册的 `.set_freq_scale()` 更新 `arch_freq_scale`。相关代码如下：

```c
scheduler_tick
  arch_scale_freq_tick

// drivers/base/arch_topology.c : 119

    topology_scale_freq_tick
      sfd->set_freq_scale();  // cppc_scale_freq_tick/amu_scale_freq_tick
        this_cpu_write(arch_freq_scale, (unsigned long)scale);
```

`topology_set_freq_scale` 接口在调频驱动的频率转换结束后调用，如果是非架构专有的调频源或者 arm64 的 Activity Monitors Unit，则由 `arch_scale_freq_tick` 来更新 `arch_freq_scale`，否则基于 cpufreq 提供的最大频率进行归一化处理，并更新 `arch_freq_scale`。

```c
cppc_cpufreq_set_target  // 以 cppc_cpufreq 为例
    cpufreq_freq_transition_end
      arch_set_freq_scale
        topology_set_freq_scale

// drivers/base/arch_topology.c : 130

void topology_set_freq_scale(const struct cpumask *cpus, unsigned long cur_freq, unsigned long max_freq)
    if (supports_scale_freq_counters(cpus)) return // 详见 topology_set_scale_freq_source

    scale = (cur_freq << SCHED_CAPACITY_SHIFT) / max_freq;
    for_each_cpu(i, cpus)
      per_cpu(arch_freq_scale, i) = scale;

```

`topology_get_freq_scale` 接口直接返回 `arch_freq_scale`。此接口会在 PELT 中计算任务利用率时调用到，相关调用点有：`update_irq_load_avg`、`update_rq_clock_pelt`。相关代码如下：

```c
// include/linux/arch_topology.h : 32

static inline unsigned long topology_get_freq_scale(int cpu)
        return per_cpu(arch_freq_scale, cpu);
```

`topology_scale_freq_invariant` 接口判断 cpufreq 或者调频源是否支持 FIE，调频源如果能在自己的 `.set_freq_scale()` 中进行频率的归一化处理，则表示支持 FIE，比如 arm64 Activity Monitors Unit 为频率源时，会在自己的 `.set_freq_scale()` 函数中，基于最大频率做归一化处理，并设置 `arch_freq_scale`。此接口会在 cpufreq_schedutil 和 EAS 的性能域构建中用到。相关代码如下：

```c
// drivers/base/arch_topology.c : 36

bool topology_scale_freq_invariant(void)
  return cpufreq_supports_freq_invariance() || supports_scale_freq_counters(cpu_online_mask);
```

如果架构采用 arch_topology 来管理 CPU 拓扑，需要在架构头文件中以上述接口重新定义调度器对架构 CPU 算力和频率的调用接口。以 `arch_scale_cpu_capacity` 为例，此函数的默认定义为直接返回 1024，即认为所有的 CPU 的算力是一致的，而通过重定义，就可以访问 arch_topology 提供的 `cpu_scale` 来获取异构系统中的归一化 CPU 算力。arm64 架构已经在其架构头文件中定义了（如下），而 RISC-V 目前还不支持，但在邮件列表中已经有个补丁 [riscv: export cpu/freq invariant to scheduler][1] 在讨论这个问题了。

```c
// include/linux/sched/topology.h: 257

static __always_inline
unsigned long arch_scale_cpu_capacity(int cpu)
{
        return SCHED_CAPACITY_SCALE;
}

// arch/arm64/include/asm/topology.h : 20

#define arch_scale_freq_tick topology_scale_freq_tick
#define arch_set_freq_scale topology_set_freq_scale
#define arch_scale_freq_capacity topology_get_freq_scale
#define arch_scale_freq_invariant topology_scale_freq_invariant

#define arch_scale_cpu_capacity topology_get_cpu_scale
#define arch_update_cpu_topology topology_update_cpu_topology
```

## 小结

RISC-V Linux 的 CPU 拓扑管理使用 arch_topology 来实现，其为架构提供拓扑和 cache 初始化功能以及 CPU 算力和频率的相关接口，继而满足调度器对 CPU 拓扑、算力、频率的感知需求。

## 参考资料

- [Capacity Aware Scheduling][2]

[1]: https://lore.kernel.org/linux-riscv/20230322061856.2774840-1-suagrfillet@gmail.com/T/#u
[2]: https://www.kernel.org/doc/html/next/scheduler/sched-capacity.html
