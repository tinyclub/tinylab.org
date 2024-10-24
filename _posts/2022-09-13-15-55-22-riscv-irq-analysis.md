---
layout: post
author: 'Wu Zhangjin'
title: 'RISC-V 中断子系统分析——硬件及其初始化'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-irq-analysis/
description: 'RISC-V 中断子系统分析——硬件及其初始化'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - 中断
---

> Author:  通天塔 985400330@qq.com
> Date:    2022/05/19
> Revisor: Falcon <falcon@tinylab.org>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor: PLCT Lab, ISCAS


## 前言

中断子系统是 CPU 对设备进行管理的一种有效手段，设备可以通过中断来向 CPU 发出请求，进行数据的处理。这些设备有的在片上例如 SPI 控制器、I2C 控制器、UART 等内部设备，外部设备例如键盘、鼠标等。RISC-V 架构下的 CPU 是如何对外部中断进行响应的，本文将进行分析。

## RISC-V 中断硬件实现

### CM32M433R MCU 实现

参考手册：[Nuclei_N级别指令架构手册](https://www.rvmcu.com/quickstart-show-id-1.html#38)

这是 RISC-V 中文社区中，CM32M433R 芯片中的中断实现，外部信号进入芯片后，通过中断控制器中的“使能+信号+优先级+仲裁”等逻辑，最终输出到 MCU。

中断控制器内部逻辑如下图所示：

![image-20220519234513284](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220519234513284.png)

ECLIC 中断控制器内部逻辑有一些可以通过寄存器进行配置，从而实现中断是否接入 MCU 的控制，uCORE 通过接收中断控制器的信号，确定是否产生中断，从而触发中断处理函数。

![image-20220519234540201](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220519234540201.png)

### 蜂鸟E203 MCU实现

[sifive中断处理流程](https://www.elecfans.com/d/1575408.html)

![image-20220526234133423](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220526234133423.png)

蜂鸟 203 实现方法

![image-20220610000250720](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220610000250720.png)

### 全志 D1 芯片实现

全志 D1 芯片使用 PLIC 进行中断的管理。

![image-20220612175448894](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220612175448894.png)

## RISC-V Linux 中断子系统软件实现

### 中断处理流程

![image-20220612180146138](/wp-content/uploads/2022/03/riscv-linux/images/riscv-irq-analysis/image-20220612180146138.png)

### RISC-V CPU 中断控制器初始化

上一小节是从网上找到的一款 RISC-V MCU 的中断控制器的硬件实现，我们要分析的是 RISC-V 架构下的 Linux 的软件实现。

首先从设备树入手，设备树下共 4 个 CPU 核，每个节点下边有一个中断控制器，中断控制器匹配的中断代码是：

```c
                cpu@0 {
                        phandle = <0x07>;
                        device_type = "cpu";
                        reg = <0x00>;
                        status = "okay";
                        compatible = "riscv";
                        riscv,isa = "rv64imafdcsu";
                        mmu-type = "riscv,sv48";

                        interrupt-controller {
                                #interrupt-cells = <0x01>;
                                interrupt-controller;
                                compatible = "riscv,cpu-intc";
                                phandle = <0x08>;
                        };
                };

```

在 [ Linux 启动时序 ](https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220515-riscv-linux-startup-process-analysis.md) 这篇文章中 `init_IRQ` 函数会进行设备树的匹配与遍历，从而触发对应驱动的 `init` 函数。

根据设备树找到对应的驱动 `irq-riscv-intc.c`，驱动首先调用 `init` 函数，`init` 函数省略部分代码如下：

```c
static int __init riscv_intc_init(struct device_node *node,
                                  struct device_node *parent)
{
...
        intc_domain = irq_domain_add_linear(node, BITS_PER_LONG,
                                            &riscv_intc_domain_ops, NULL);//线性映射中断，产生 irq_domain
...
        rc = set_handle_irq(&riscv_intc_irq);//设置中断处理函数
        if (rc) {
                pr_err("failed to set irq handler\n");
                return rc;
        }
...
        pr_info("%d local interrupts mapped\n", BITS_PER_LONG);
...
}

```



使用 `irq_domain_add_linear` 进行了中断的线性映射 ，通过 HW interrupt ID 作为 index，进行查表可以获取对应的 IRQ number，对应的 IRQ number 可以找到相应的软件中断处理函数。这一部分是架构无关的代码。

但是在设备树中，未找到对应的 interrupt-parent 是 CPU 下属的中断控制器的设备，设备树中的设备都是挂在 PLIC 中断控制器上的，下面我们分析 PLIC 中断控制器。

### PLIC 中断控制器初始化

以 RTC 为例，确定 RTC 的中断是如何触发的。设备节点匹配到的驱动为：`rtc-goldfish.c`

```c
                rtc@101000 {
                        interrupts = <0x0b>;//表明连接到0x0b中断线上
                        interrupt-parent = <0x09>;//表明归属于0x09中断控制器，经过查找是plic@c000000。
                        reg = <0x00 0x101000 0x00 0x1000>;
                        compatible = "google,goldfish-rtc";
                };


```

rtc 设备中断连接到了 `plic@c000000` 设备上。

该设备的设备节点如下：

```c
                plic@c000000 {
                        phandle = <0x09>;
                        riscv,ndev = <0x35>;
                        reg = <0x00 0xc000000 0x00 0x210000>;
                        interrupts-extended = <0x08 0x0b 0x08 0x09 0x06 0x0b 0x06 0x09 0x04 0x0b 0x04 0x09 0x02 0x0b 0x02 0x09>;
                        interrupt-controller;
                        compatible = "riscv,plic0";
                        #interrupt-cells = <0x01>;
                        #address-cells = <0x00>;
                };

```

该设备节点匹配到的驱动为：`irqchip/irq-sifive-plic.c`

通过以下宏定义可知：

```c
IRQCHIP_DECLARE(sifive_plic, "sifive,plic-1.0.0", plic_init);
IRQCHIP_DECLARE(riscv_plic0, "riscv,plic0", plic_init); /* for legacy systems */
IRQCHIP_DECLARE(thead_c900_plic, "thead,c900-plic", plic_init); /* for firmware driver */
```

调用设备初始化函数：`static int __init plic_init(struct device_node *node,struct device_node *parent)`

```c
static int __init plic_init(struct device_node *node,
                struct device_node *parent)
{
        int error = 0, nr_contexts, nr_handlers = 0, i;
        u32 nr_irqs;
        struct plic_priv *priv;
        struct plic_handler *handler;

        priv = kzalloc(sizeof(*priv), GFP_KERNEL);
        if (!priv)
                return -ENOMEM;

        priv->regs = of_iomap(node, 0);//对PLIC寄存器映射
        if (WARN_ON(!priv->regs)) {
                error = -EIO;
                goto out_free_priv;
        }

        error = -EINVAL;
        of_property_read_u32(node, "riscv,ndev", &nr_irqs);//读取属性
        if (WARN_ON(!nr_irqs))
                goto out_iounmap;

        nr_contexts = of_irq_count(node);//统计该节点的irq数量
        printk("[nfk test] nr_contexts=%d\n",nr_contexts);//得到数量8个
        if (WARN_ON(!nr_contexts))
                goto out_iounmap;

        error = -ENOMEM;
        priv->irqdomain = irq_domain_add_linear(node, nr_irqs + 1,
                        &plic_irqdomain_ops, priv);//创建IRQ域，建立线性映射
        if (WARN_ON(!priv->irqdomain))
                goto out_iounmap;
...

```

接下来分析以下 `nr_contexts = 8` 打印信息的由来：

```c
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=0
[    0.000000] of_irq_parse_raw:  /cpus/cpu@0/interrupt-controller:ffffffff
[    0.000000] irq.np->fullname=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=1
[    0.000000] of_irq_parse_raw:  /cpus/cpu@0/interrupt-controller:00000009
[    0.000000] irq.np->fullname=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=2
[    0.000000] of_irq_parse_raw:  /cpus/cpu@1/interrupt-controller:ffffffff
[    0.000000] irq.np->fullname=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=3
[    0.000000] of_irq_parse_raw:  /cpus/cpu@1/interrupt-controller:00000009
[    0.000000] irq.np->fullname=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=4
[    0.000000] of_irq_parse_raw:  /cpus/cpu@2/interrupt-controller:ffffffff
[    0.000000] irq.np->fullname=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=5
[    0.000000] of_irq_parse_raw:  /cpus/cpu@2/interrupt-controller:00000009
[    0.000000] irq.np->fullname=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=6
[    0.000000] of_irq_parse_raw:  /cpus/cpu@3/interrupt-controller:ffffffff
[    0.000000] irq.np->fullname=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=7
[    0.000000] of_irq_parse_raw:  /cpus/cpu@3/interrupt-controller:00000009
[    0.000000] irq.np->fullname=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=8
[    0.000000] [nfk test] nr_contexts=8

```

通过分析 `of_irq_count` 函数，可知，这个函数通过 `#interrupt-cells` 获取一个中断描述所需要的参数，可以得出 `interrupts-extended` 的 16 个参数描述了 8 个中断。

```
interrupts-extended = <0x08 0x0b 0x08 0x09 0x06 0x0b 0x06 0x09 0x04 0x0b 0x04 0x09 0x02 0x0b 0x02 0x09>;
```

由于反编译的设备树，丢失了一些信息，正常的话，应该是长这个样子：

```
interrupts-extended = <&pic 0xA 8>, <&gic 0xda>;...
```

以上函数追踪过程中尝试把挂载在 plic 下的设备节点名称打出来，尝试了很多种方法未能打出，打出来的名称一直是 `interrupt-controller`，有点疑惑，没搞懂。

函数的前半部分，主要进行了一系列的初始化，读取数据，以及中断域的建立。后半部分则针对于中断进行解析和配置。

```c
        for (i = 0; i < nr_contexts; i++) {
                struct of_phandle_args parent;
                irq_hw_number_t hwirq;
                int cpu, hartid;

                if (of_irq_parse_one(node, i, &parent)) {//解析irq
                        pr_err("failed to parse parent for context %d.\n", i);
                        continue;
                }
                else
                {
                        printk("parent.np->full_name=%s\n",parent.np->full_name);
                }

                /*
                 * Skip contexts other than external interrupts for our
                 * privilege level.
                 */
                if (parent.args[0] != RV_IRQ_EXT)//判断是不是RV_IRQ_EXT
                        continue;
                else
                        printk("is RV_IRQ_EXT\n");//共4个nr_handlers


                hartid = riscv_of_parent_hartid(parent.np);//获取hartid
                if (hartid < 0) {
                        pr_warn("failed to parse hart ID for context %d.\n", i);
                        continue;
                }

                cpu = riscv_hartid_to_cpuid(hartid);//获取cpu id
                if (cpu < 0) {
                        pr_warn("Invalid cpuid for context %d\n", i);
                        continue;
                }

                /* Find parent domain and register chained handler */
                if (!plic_parent_irq && irq_find_host(parent.np)) {//注册处理函数
                        plic_parent_irq = irq_of_parse_and_map(node, i);
                        if (plic_parent_irq)
                                irq_set_chained_handler(plic_parent_irq,
                                                        plic_handle_irq);
                        printk("[nfk test]set chained handler\n");
                }

                /*
                 * When running in M-mode we need to ignore the S-mode handler.
                 * Here we assume it always comes later, but that might be a
                 * little fragile.
                 */
                handler = per_cpu_ptr(&plic_handlers, cpu);
                if (handler->present) {
                        pr_warn("handler already present for context %d.\n", i);
                        plic_set_threshold(handler, PLIC_DISABLE_THRESHOLD);
                        goto done;
                }//处理函数已经设置则直接done

                cpumask_set_cpu(cpu, &priv->lmask);
                handler->present = true;
                handler->hart_base =
                        priv->regs + CONTEXT_BASE + i * CONTEXT_PER_HART;
                raw_spin_lock_init(&handler->enable_lock);
                handler->enable_base =
                        priv->regs + ENABLE_BASE + i * ENABLE_PER_HART;
                handler->priv = priv;
done:
                for (hwirq = 1; hwirq <= nr_irqs; hwirq++)
                        plic_toggle(handler, hwirq, 0);//写寄存器，清零掩码寄存器
                nr_handlers++;
        }

        /*
         * We can have multiple PLIC instances so setup cpuhp state only
         * when context handler for current/boot CPU is present.
         */
        handler = this_cpu_ptr(&plic_handlers);//热插拔相关设置
        if (handler->present && !plic_cpuhp_setup_done) {
                cpuhp_setup_state(CPUHP_AP_IRQ_SIFIVE_PLIC_STARTING,
                                  "irqchip/sifive/plic:starting",
                                  plic_starting_cpu, plic_dying_cpu);
                plic_cpuhp_setup_done = true;
        }

        pr_info("%pOFP: mapped %d interrupts with %d handlers for"
                " %d contexts.\n", node, nr_irqs, nr_handlers, nr_contexts);
        return 0;

out_iounmap:
        iounmap(priv->regs);
out_free_priv:
        kfree(priv);
        return error;
}
```

一共 4 个 handler，打印如下：

```c
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=0
[    0.000000] of_irq_parse_raw:  /cpus/cpu@0/interrupt-controller:ffffffff
[    0.000000] parent.np->full_name=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=1
[    0.000000] of_irq_parse_raw:  /cpus/cpu@0/interrupt-controller:00000009
[    0.000000] parent.np->full_name=interrupt-controller
[    0.000000] is RV_IRQ_EXT
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=1
[    0.000000] of_irq_parse_raw:  /cpus/cpu@0/interrupt-controller:00000009
[    0.000000] [nfk test]set chained handler
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=2
[    0.000000] of_irq_parse_raw:  /cpus/cpu@1/interrupt-controller:ffffffff
[    0.000000] parent.np->full_name=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=3
[    0.000000] of_irq_parse_raw:  /cpus/cpu@1/interrupt-controller:00000009
[    0.000000] parent.np->full_name=interrupt-controller
[    0.000000] is RV_IRQ_EXT
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=4
[    0.000000] of_irq_parse_raw:  /cpus/cpu@2/interrupt-controller:ffffffff
[    0.000000] parent.np->full_name=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=5
[    0.000000] of_irq_parse_raw:  /cpus/cpu@2/interrupt-controller:00000009
[    0.000000] parent.np->full_name=interrupt-controller
[    0.000000] is RV_IRQ_EXT
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=6
[    0.000000] of_irq_parse_raw:  /cpus/cpu@3/interrupt-controller:ffffffff
[    0.000000] parent.np->full_name=interrupt-controller
[    0.000000] of_irq_parse_one: dev=/soc/plic@c000000, index=7
[    0.000000] of_irq_parse_raw:  /cpus/cpu@3/interrupt-controller:00000009
[    0.000000] parent.np->full_name=interrupt-controller
[    0.000000] is RV_IRQ_EXT
```

### CLINT 中断控制器初始化

clint 也是 RISC-V 架构下的中断控制器，clint 只负责软件中断和定时器中断，属于内部中断。

```
clint@2000000 {
interrupts-extended = <0x08 0x03 0x08 0x07 0x06 0x03 0x06 0x07 0x04 0x03 0x04 0x07 0x02 0x03 0x02 0x07>;
reg = <0x00 0x2000000 0x00 0x10000>;
compatible = "riscv,clint0";
};
```

驱动匹配到 `clocksource/timer-clint.c`

初始化函数为 `clint_timer_init_dt`

函数所做的工作基本与 PLIC 中断控制器一样，主要做的工作有：

1. 统计中断数量
2. 进行 IO 映射
3. 注册中断函数
4. 热插拔配置


## 小结

本文对 RISC-V 架构下的中断控制器进行了简单的分析，主要从硬件的角度和软件初始化的角度展开，后续会进一步分析其他驱动对中断的触发与处理流程。

## 参考资料

* [如何分析 Linux 内核 RISC-V 架构相关代码](https://tinylab.org/riscv-linux-quickstart/)
* [Nuclei_N级别指令架构手册](https://www.rvmcu.com/quickstart-show-id-1.html#38)
* [sifive中断处理流程](https://www.elecfans.com/d/1575408.html)
