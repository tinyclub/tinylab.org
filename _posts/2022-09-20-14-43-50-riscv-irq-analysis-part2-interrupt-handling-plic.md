---
layout: post
author: 'Wu Zhangjin'
title: 'RISC-V 中断子系统分析——PLIC 中断处理'
draft: false
plugin: ''
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-irq-analysis-part2-interrupt-handling-plic/
description: 'RISC-V 中断子系统分析——PLIC 中断处理'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - 中断
  - PLIC
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc1 - [comments]
> Author:  通天塔 985400330@qq.com
> Date:    2022/05/19
> Revisor: Falcon <falcon@tinylab.org>
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor: PLCT Lab, ISCAS


## 前言

上一篇文章对中断的硬件实现以及硬件初始化进行了分析，本篇文章将对中断的申请、产生、处理进行分析。

* [RISC-V 中断子系统分析——硬件及其初始化][001]

本文代码分析基于 Linux-5.17。

## RISC-V Linux 中断申请

中断的注册分析，我们首先找到一个 Linux 驱动，从设备驱动入手进行分析。

```
rtc@101000 {
    interrupts = <0x0b>; // 表明连接到 0x0b 中断线上
    interrupt-parent = <0x09>; // 表明归属于 0x09 中断控制器，经过查找是 plic@c000000。
    reg = <0x00 0x101000 0x00 0x1000>;
    compatible = "google,goldfish-rtc";
};
```

从设备树中可以看到，该 RTC 驱动连接到了中断控制器上，该驱动的文件名为：`rtc-goldfish.c`

驱动与设备匹配成功后，调用以下代码：

```c
// drivers/rtc/rtc-goldfish.c
static int goldfish_rtc_probe(struct platform_device *pdev)
{
···
	err = devm_request_irq(&pdev->dev, rtcdrv->irq,
			       goldfish_rtc_interrupt,
			       0, pdev->name, rtcdrv); // 申请 irq
···
}
```

其中申请 irq 的最终函数调用为 `request_threaded_irq`。

```c
devm_request_irq(&pdev->dev, rtcdrv->irq, goldfish_rtc_interrupt,0, pdev->name, rtcdrv);

——>devm_request_threaded_irq(&pdev->dev,  rtcdrv->irq, goldfish_rtc_interrupt, NULL, 0,pdev->name, dev_id);

————>request_threaded_irq( rtcdrv->irq, goldfish_rtc_interrupt, NULL, 0, pdev->name, dev_id);
```

参数分析如下：

* `rtcdrv->irq`：要分配的中断
* `goldfish_rtc_interrupt`：中断产生时要调用的函数
* `NULL`：中断处理线程要调用的函数
* `0`：中断类型标志位，更多可选设定解释如下
    * `IRQF_SHARED`：共享中断
    * `IRQF_TRIGGER_*`：触发边界或等级
    * `IRQF_ONESHOT`：只触发 1 次
* `pdev->name`：声明设备的 ascii 名称
* `dev_id`：全局唯一的。因为这个值由处理程序接收，所以设备数据结构的地址常用作 dev_id。

`request_threaded_irq` 做的事情：

* 获取 `irq_desc`
* 创建 `irqaction`
* 通过 `__setup_irq` 将 `irqaction` 添加到 IRQ 链表当中

`__setup_irq` 函数有将近 400 行，此处暂不分析，在中断函数处理的时候，我们再分析该函数的作用。

至此，完成中断的申请及注册。

## RISC-V Linux 中断产生

本文以 RTC 为例进行中断处理的分析，现在我们创建一个中断，让系统在运行过程中发出中断，以便后续分析中断的处理流程。

首先通过 menuconfig 配置，将 goldfish-rtc 的驱动编译进内核，将 rtc 设备驱动起来。

应用创建中断的代码如下：

```c
#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/rtc.h>
struct rtc_time time; // 保存时间值
struct rtc_wkalrm alrm; // 保存闹钟值
int main(int argc,char **argv)
{
        int fd=open("/dev/rtc0",O_RDWR); // 2==O_RDWR
        if(fd<0){
                printf("驱动设备文件打开失败!\r\n");
                return 0;
        }
        alrm.enabled=1;
        alrm.pending=0;
        ioctl(fd,RTC_RD_TIME,&time);
        time.tm_sec+=5; // 5 秒后闹钟产生
        alrm.time=time;
        ioctl(fd,RTC_WKALM_SET,&alrm);
        ioctl(fd,RTC_ALM_READ,&time);
        printf("ALM %d-%d-%d %d:%d:%d\r\n",time.tm_year+1900,time.tm_mon+1,time.tm_mday,time.tm_hour,time.tm_min,time.tm_sec);
        while(1){
                ioctl(fd,RTC_RD_TIME,&time);
                printf("now time=%d-%d-%d %d:%d:%d\r\n",time.tm_year+1900,time.tm_mon+1,time.tm_mday,time.tm_hour,time.tm_min,time.tm_sec);
                sleep(1);
        }
}

```

编译命令如下：

```
$ riscv64-linux-gnu-gcc rtc_alarm.c -o rtc_alarm
```

运行命令：

```
$ cp /lib/ld-linux-riscv64-lp64.so.1 /lib/ld-linux-riscv64-lp64d.so.1
$ ./rtc_alarm
```

运行环境：Linux Lab，riscv64 虚拟开发板，内核版本 Linux 5.17。

关于 ld 库为什么要复制一个 lp64d 的库的原因是通过命令 `riscv64-linux-gnu-readelf rtc_alarm -a` 读取到 `[Requesting program interpreter: /lib/ld-linux-riscv64-lp64d.so.1]` 说明要使用的库名称不同，故单独进行复制，否则程序将不能正确运行。

程序运行起来之后，代码追踪打印信息如下：

```
[nfk test] RTC_WKALM_SET
[nfk test] drivers/rtc/dev.c-rtc_dev_ioctl-375
[nfk test] drivers/rtc/interface.c-rtc_set_alarm-464
[nfk test] drivers/rtc/interface.c-rtc_set_alarm-469
[nfk test] drivers/rtc/interface.c-rtc_set_alarm-473
[nfk test] drivers/rtc/interface.c-rtc_set_alarm-477
[nfk test] drivers/rtc/interface.c-rtc_set_alarm-483
[nfk test] drivers/rtc/interface.c-rtc_timer_enqueue-834
[nfk test] drivers/rtc/interface.c-rtc_timer_enqueue-837
[nfk test] drivers/rtc/interface.c-rtc_timer_enqueue-841
[nfk test] drivers/rtc/interface.c-__rtc_set_alarm-416
[nfk test] drivers/rtc/interface.c-__rtc_set_alarm-427
[nfk test] drivers/rtc/interface.c-__rtc_set_alarm-432
[nfk test] goldfish_rtc_set_alarm
[nfk test] goldfish_rtc_set_alarm
[nfk test] drivers/rtc/interface.c-__rtc_set_alarm-454
[nfk test] drivers/rtc/interface.c-rtc_timer_enqueue-845
[nfk test] drivers/rtc/interface.c-rtc_set_alarm-501
[nfk test] get RTC_ALM_READ
ALM 2022-6-24 15:54:35
now time=2022-6-24 15:54:30
...
now time=2022-6-24 15:54:34
[nfk test] goldfish_rtc_interrupt
[nfk test] goldfish_rtc_alarm_irq_enable
now time=2022-6-24 15:54:35
...
now time=2022-6-24 15:54:40

```

代码执行路径：

```c
用户空间：
    main
    	open
    		ioctl
内核空间：
    rtc_dev_ioctl
    	rtc_set_alarm
    		rtc_timer_enqueue
    			__rtc_set_alarm
    				goldfish_rtc_set_alarm
```

通过分析可以知道，闹钟成功地触发了中断，RTC 驱动中的中断函数得到了运行，后面我们进行深入分析，看中断如何从触发到最终执行中断函数的完整流程。

## RISC-V Linux 中断处理

### 中断处理流程

首先在 RTC 驱动的中断处理函数 `goldfish_rtc_interrupt` 中添加函数 `dump_stack` 进行调用栈的回溯，以便找到函数的调用关系。

```
[nfk test] goldfish_rtc_interrupt
CPU: 0 PID: 0 Comm: swapper/0 Not tainted 5.17.0-dirty #85
Hardware name: riscv-virtio,qemu (DT)
Call Trace:
[<ffffffff80004750>] dump_backtrace+0x1c/0x24
[<ffffffff806a1bb8>] show_stack+0x2c/0x38
[<ffffffff806a6da8>] dump_stack_lvl+0x40/0x58
[<ffffffff806a6dd4>] dump_stack+0x14/0x1c
[<ffffffff806ad02c>] goldfish_rtc_interrupt+0x22/0x74
[<ffffffff8004c168>] __handle_irq_event_percpu+0x52/0xe0
[<ffffffff8004c208>] handle_irq_event_percpu+0x12/0x4e
[<ffffffff8004c2a2>] handle_irq_event+0x5e/0x94
[<ffffffff8005013a>] handle_fasteoi_irq+0xac/0x18e
[<ffffffff8004b54a>] generic_handle_domain_irq+0x28/0x3a
[<ffffffff802d67e2>] plic_handle_irq+0x8a/0xec
[<ffffffff8004b54a>] generic_handle_domain_irq+0x28/0x3a
[<ffffffff802d6610>] riscv_intc_irq+0x34/0x5c
[<ffffffff806ae0c8>] generic_handle_arch_irq+0x4a/0x74
[<ffffffff8000302a>] ret_from_exception+0x0/0xc
[<ffffffff8005b0e2>] rcu_idle_enter+0x10/0x18
```

`ret_from_exception` 函数表明 CPU 收到了一个异常，并且已经完成了异常的处理。

架构设计时，就考虑了 CPU 要进行各种各样的异常处理，于是提前定义好了一些异常向量表，在 CPU 执行特殊的指令时，就会触发异常。

本文不对 CPU 如何接收异常和处理异常进行深入分析，这**涉及到 RISC-V 架构相关的汇编指令**的分析，这里先给出参考文档 [Linux 异常处理体系结构][003] ，在下一篇文章中进行重点分析。

本文暂时只对 **CPU 中断控制器 -> PLIC 中断控制器 -> 驱动中的中断处理函数** 这一层面进行分析。

经过查找代码，在 RISC-V 的 entry.S 中的异常处理汇编代码中调用了 `generic_handle_arch_irq` 函数。

汇编代码如下：

```
/* arch/riscv/kernel/entry.S: 113 */
#ifdef CONFIG_CONTEXT_TRACKING
	/* If previous state is in user mode, call context_tracking_user_exit. */
	li   a0, SR_PP
	and a0, s1, a0
	bnez a0, skip_context_tracking
	call context_tracking_user_exit
skip_context_tracking:
#endif

	/*
	 * MSB of cause differentiates between
	 * interrupts and exceptions
	 */
	bge s4, zero, 1f

	la ra, ret_from_exception

	/* Handle interrupts */
	move a0, sp /* pt_regs */
	la a1, generic_handle_arch_irq
	jr a1
```

汇编代码通过寄存器进行传参，将参数传给了函数 `generic_handle_arch_irq`。

```c
// kernel/irq/handle.c
/**
 * generic_handle_arch_irq - root irq handler for architectures which do no
 *                           entry accounting themselves
 * @regs:	Register file coming from the low-level handling code
 */
asmlinkage void noinstr generic_handle_arch_irq(struct pt_regs *regs)
{
	struct pt_regs *old_regs;

	irq_enter();
	old_regs = set_irq_regs(regs);
	handle_arch_irq(regs);
	set_irq_regs(old_regs);
	irq_exit();
}
```

可以看到这个通用接口中并未调用 `riscv_intc_irq` 中断处理函数，但是 dump 出来的 stack 中却看到了中断处理函数。

以下就是原因，可以看到在以下函数中已经配置了对应架构的中断处理函数，该函数被 `riscv_intc_init` 函数调用。

```c
// kernel/irq/handle.c
int __init set_handle_irq(void (*handle_irq)(struct pt_regs *))
{
    if (handle_arch_irq)
        return -EBUSY;
    handle_arch_irq = handle_irq;
    return 0;
}
```

下面开始分析 RISC-V 架构下的中断处理函数是如何调用到 PLIC 中断控制器中的。

```c
// drivers/irqchip/irq-riscv-intc.c
static asmlinkage void riscv_intc_irq(struct pt_regs *regs)
{
	unsigned long cause = regs->cause & ~CAUSE_IRQ_FLAG;

	if (unlikely(cause >= BITS_PER_LONG))
		panic("unexpected interrupt cause");

	switch (cause) {
#ifdef CONFIG_SMP
	case RV_IRQ_SOFT:
		/*
		 * We only use software interrupts to pass IPIs, so if a
		 * non-SMP system gets one, then we don't know what to do.
	         */
		handle_IPI(regs); // 软中断接口
		break;
#endif
	default: // 硬中断接口
		generic_handle_domain_irq(intc_domain, cause);
		break;
	}
}
```

`generic_handle_domain_irq(intc_domain, cause)` 函数的 `intc_domain` 参数是通过 `irq-riscv-intc.c` 驱动的初始化建立的，`cause` 参数是汇编代码中传进来的，`cause` 参数就是中断号，方便进一步的追踪具体调用哪个中断处理函数。

`generic_handle_domain_irq` 代码如下：

```c
// kernel/irq/irqdesc.c
int generic_handle_domain_irq(struct irq_domain *domain, unsigned int hwirq)
{
	WARN_ON_ONCE(!in_irq());
	return handle_irq_desc(irq_resolve_mapping(domain, hwirq));
}
```

可以看到通过两个函数的调用完成进一步的中断处理，第一个是 `irq_resolve_mapping`，通过中断域和硬件中断号得出中断描述符。这到底是如何实现的？下一小节我们将清楚 `domain` 与 `hwirq` 的来龙去脉。

### domain 的来龙去脉

#### 中断描述符（irq_desc）获取

中断描述符通过硬件中断号和中断域获取，中断描述符中存储着一个中断最全的信息，要处理该中断必须获取到这个中断的信息。

通过设备树可知，RTC 的 `hwirq = 0xb`，以下分析都是基于已知 RTC 的 `hwirq` 的情况下添加打印所进行的追踪分析。

```c
// kernel/irq/irqdesc.c
int generic_handle_domain_irq(struct irq_domain *domain, unsigned int hwirq)
{
	WARN_ON_ONCE(!in_irq());
	struct irq_desc *my= irq_resolve_mapping(domain, hwirq);
	if(hwirq==11)
	{
		printk("[nfk test]hwirq=%u\n",hwirq);
		printk("[nfk test] irq =%d,hwirq=%d",my->irq_data.irq,my->irq_data.hwirq);
		printk("[nfk test] name =%s",my->dev_name);
	}
	return handle_irq_desc(irq_resolve_mapping(domain, hwirq));
}
```

追踪 `irq_desc` 的获取函数，

```c
// kernel/irq/irqdomain.c
struct irq_desc *__irq_resolve_mapping(struct irq_domain *domain,
				       irq_hw_number_t hwirq,
				       unsigned int *irq)
{
	struct irq_desc *desc = NULL;
	struct irq_data *data;
...//查找 desc 不是用的以上代码，故省略
	rcu_read_lock();
	/* Check if the hwirq is in the linear revmap. */
	if (hwirq < domain->revmap_size){
		if(hwirq==11)
			printk("hwirq < domain->revmap_size\n"); // 经验证，走的这条路获取到了 irq_data
		data = rcu_dereference(domain->revmap[hwirq]); // 在 RCU 保护机制下，通过 domain->revmap[hwirq] 找到了 irq_data，
	}
	else
		data = radix_tree_lookup(&domain->revmap_tree, hwirq);
	if (likely(data)) {
		if(hwirq==11)
			printk("hwirq is in the linear revmap\n");
		desc = irq_data_to_desc(data); // container_of，已知成员变量地址，求出结构体起始地址
		if (irq)
			*irq = data->irq;
	}
	rcu_read_unlock();
	return desc;
}
```

通过以上函数，我们确认到 `irq_data` 就存在 `domain->revmap` 中，但我们什么时候才将 `irq_data` 放入到 `domain` 中的呢？

#### domain 中的 irq_data 来源

通过查找数组 `domain->revmap` 找到以下函数，可以确认 `irq_data` 就是在这里被添加进去的。

```c
// kernel/irq/irqdomain.c
static void irq_domain_set_mapping(struct irq_domain *domain,
				   irq_hw_number_t hwirq,
				   struct irq_data *irq_data)
{
	if (irq_domain_is_nomap(domain))
		return;
	if(hwirq==11)
	{
		printk("[nfk test] irq_domain_set_mapping,hwirq=%d\n",hwirq);
		dump_stack();
	}

	mutex_lock(&domain->revmap_mutex);
	if (hwirq < domain->revmap_size)
		rcu_assign_pointer(domain->revmap[hwirq], irq_data);
	else
		radix_tree_insert(&domain->revmap_tree, hwirq, irq_data);
	mutex_unlock(&domain->revmap_mutex);
}
```

通过栈回溯得到以下信息：

```
[nfk test] irq_domain_set_mapping,hwirq=11
[<ffffffff80004754>] dump_backtrace+0x1c/0x24
[<ffffffff806b3382>] show_stack+0x2c/0x38
[<ffffffff806b7ece>] dump_stack_lvl+0x40/0x58
[<ffffffff806b7efa>] dump_stack+0x14/0x1c	//栈回溯
[<ffffffff80052c74>] irq_domain_set_mapping+0x84/0x86	//设置映射
[<ffffffff80053b44>] __irq_domain_alloc_irqs+0x1cc/0x25a	//申请中断内存
[<ffffffff80053ef2>] irq_create_fwspec_mapping+0xe6/0x248
[<ffffffff800540a4>] irq_create_of_mapping+0x50/0x6e
[<ffffffff8056ba70>] of_irq_get+0x4c/0x5e
[<ffffffff8056baae>] of_irq_to_resource+0x2c/0xcc	//解析节点的中断，并为其申请资源。
[<ffffffff8056bb80>] of_irq_to_resource_table+0x32/0x4c
[<ffffffff8056719c>] of_device_alloc+0x128/0x292
[<ffffffff8056733c>] of_platform_device_create_pdata+0x36/0x9a //平台设备总线创建设备
[<ffffffff805674d8>] of_platform_bus_create+0x120/0x172
[<ffffffff80567502>] of_platform_bus_create+0x14a/0x172	//平台总线创建
[<ffffffff805675fc>] of_platform_populate+0x36/0x86
[<ffffffff8081fd32>] of_platform_default_populate_init+0xbe/0xcc
[<ffffffff800020ea>] do_one_initcall+0x3e/0x168
[<ffffffff80800ff2>] kernel_init_freeable+0x19e/0x202
[<ffffffff806bf586>] kernel_init+0x1e/0x10a
[<ffffffff8000302a>] ret_from_exception+0x0/0xc
```

以上的整个流程回溯起来篇幅有些大，这里不再深入分析，可以确定的是 `irq_data` 和 `hwirq` 的对应是在平台总线初始化时，进行设备节点的扫描，然后为每个设备都进行了 irq 的映射。

根据代码的追踪，最终确认到 `irq_domain_insert_irq` 调用的 `irq_domain_set_mapping(struct irq_domain *domain,irq_hw_number_t hwirq,struct irq_data *irq_data)`，这时 `irq_data` 在获取时，采用的就是 `irq_desc` 结构体中获取的数据。相关代码如下：

```c
// kernel/irq/irqdomain.c
static void irq_domain_insert_irq(int virq)
{
	struct irq_data *data;

	for (data = irq_get_irq_data(virq); data; data = data->parent_data) {//获取 irq_data
...
	}

	irq_clear_status_flags(virq, IRQ_NOREQUEST);
}
```

那么现在问题就变成了 `irq_desc` 的来源在哪里？

#### irq_desc 的来源

通过以下代码进行栈回溯，可以找到何时进行 `irq_desc` 的创建。

```c
// kernel/irq/irqdesc.c
static void irq_insert_desc(unsigned int irq, struct irq_desc *desc)
{
	if(irq==1)
	{
		printk("irq_insert_desc irq=1\n");
		dump_stack();
	}

	radix_tree_insert(&irq_desc_tree, irq, desc);
}
```

发现流程与 `irq_data` 的来源基本一致，经过确认是在为中断申请资源时，在 `__irq_alloc_descs` 函数中创建的 `irq_desc`。栈回溯打印如下：

```
irq_insert_desc irq=1
...
[<ffffffff80004754>] dump_backtrace+0x1c/0x24
[<ffffffff806b3382>] show_stack+0x2c/0x38
[<ffffffff806b7ece>] dump_stack_lvl+0x40/0x58
[<ffffffff806b7efa>] dump_stack+0x14/0x1c
[<ffffffff806bf864>] __irq_alloc_descs+0x1f2/0x1f4
[<ffffffff80053896>] irq_domain_alloc_descs+0x60/0x80
[<ffffffff80053ace>] __irq_domain_alloc_irqs+0x156/0x25a
[<ffffffff80053ef2>] irq_create_fwspec_mapping+0xe6/0x248
[<ffffffff800540a4>] irq_create_of_mapping+0x50/0x6e
...

```

通过以上小节的分析，可以确认的是，整个中断的信息添加到 `domain` 中的节点，是在平台驱动注册时完成的。

#### 回讲第一节——中断申请

到现在为止，我们搞清楚了 `domain` 的来龙去脉，那么我们现在再思考中断申请到底干了啥？

```c
// drivers/rtc/rtc-goldfish.c
static int goldfish_rtc_probe(struct platform_device *pdev)
{
···
	err = devm_request_irq(&pdev->dev, rtcdrv->irq,
			       goldfish_rtc_interrupt,
			       0, pdev->name, rtcdrv); // 申请 irq
···
}
```

可以看出是为已创建好的 `irq_desc` 添加处理函数，以实现中断触发时，调用对应的中断处理函数。

### 流程续讲

上一小节讲清楚 `domain` 之后，我们继续讲整个中断的处理流程。

```
[<ffffffff80004750>] dump_backtrace+0x1c/0x24
[<ffffffff806a1bb8>] show_stack+0x2c/0x38
[<ffffffff806a6da8>] dump_stack_lvl+0x40/0x58
[<ffffffff806a6dd4>] dump_stack+0x14/0x1c
[<ffffffff806ad02c>] goldfish_rtc_interrupt+0x22/0x74
[<ffffffff8004c168>] __handle_irq_event_percpu+0x52/0xe0
[<ffffffff8004c208>] handle_irq_event_percpu+0x12/0x4e
[<ffffffff8004c2a2>] handle_irq_event+0x5e/0x94
[<ffffffff8005013a>] handle_fasteoi_irq+0xac/0x18e
[<ffffffff8004b54a>] generic_handle_domain_irq+0x28/0x3a     //通过 hwirq = 11，进行查找 rtc 的中断处理程序
[<ffffffff802d67e2>] plic_handle_irq+0x8a/0xec			    //PLIC 中断处理程序
[<ffffffff8004b54a>] generic_handle_domain_irq+0x28/0x3a	//通过 hwirq = 9，进行查找 plic 的中断处理程序
[<ffffffff802d6610>] riscv_intc_irq+0x34/0x5c		        //RISC-V 架构下的中断处理器
[<ffffffff806ae0c8>] generic_handle_arch_irq+0x4a/0x74      //根据架构查找 RISC-V 架构下的中断处理程序
[<ffffffff8000302a>] ret_from_exception+0x0/0xc
[<ffffffff8005b0e2>] rcu_idle_enter+0x10/0x18
```

可以看到栈回溯过程中执行了两次 `generic_handle_domain_irq`，这两次的 `domain` 参数肯定是不同的，一次的 `domain` 是 RISC-V 的 `domain`，另一次是 PLIC 的 `domain`，通过这种级联的结构，使得 CPU 可以扩展更多的中断，并且通过中断控制器完成更加复杂的功能。这种级联结构可以在上一篇的硬件分析中看到图示，[RISC-V 中断子系统分析——硬件及其初始化][001]

通过 PLIC 初始化的相关代码也可以看到，PLIC 的 `domain` 是有 `parent` 的，代码如下：

```c
// drivers/irqchip/irq-sifive-plic.c
static int __init plic_init(struct device_node *node,
		struct device_node *parent)
{
    ...
    /* Find parent domain and register chained handler */
    if (!plic_parent_irq && irq_find_host(parent.np)) {//注册处理函数
        plic_parent_irq = irq_of_parse_and_map(node, i);
        if (plic_parent_irq)
            irq_set_chained_handler(plic_parent_irq,
                                    plic_handle_irq); // 为 parent 设置中断处理函数
        printk("[nfk test]set chained handler\n");
    }
    ...
}
```

也就是说，本质上 PLIC 也会有一个 `irq_desc`，也有自己的中断处理函数。通过设备树和打印信息，确认到 PLIC 的 `hwirq` 和 `irq` 都为 9。

通过命令，我们可以看到 RTC 的中断号为 11，在 CPU0 上触发了中断。

```c
# cat /proc/interrupts
           CPU0       CPU1       CPU2       CPU3
  1:          1          0          0          0  SiFive PLIC  11 Edge      101000.rtc
  2:        315          0          0          0  SiFive PLIC  10 Edge      ttyS0
  3:         11          0          0          0  SiFive PLIC   8 Edge      virtio0
  4:        103          0          0          0  SiFive PLIC   7 Edge      virtio1
  5:      20719      20725      20725      20728  RISC-V INTC   5 Edge      riscv-timer
IPI0:        35         23         26         31  Rescheduling interrupts
IPI1:       763        247        211        683  Function call interrupts
IPI2:         0          0          0          0  CPU stop interrupts
IPI3:         0          0          0          0  IRQ work interrupts
IPI4:         0          0          0          0  Timer broadcast interrupts
```

## 小结

本文讲述了从**中断申请 -> 中断产生 -> 中断处理**的流程。

在中断申请时，并没有对中断申请进行深入的分析，而是在中断处理小节中，再返回来看中断申请，这样就感觉豁然开朗，中断申请的作用就显得非常简单了。

在中断处理小节中，先看了中断的处理流程，但是对于中断处理流程中的 `domain` 又不明白为什么通过 `hwirq` 就可以找到中断处理函数，又针对性的补上了 `domain` 的分析。

至此，已经能够搞清楚一个 IRQ 从产生到处理的 C 语言部分的全部流程。下一篇文章中，将重点针对 IRQ 产生后 CPU 是如何在汇编层面调用到 C 语言这一部分代码进行分析。

## 参考资料

* [articles/20220519-riscv-irq-analysis.md · 泰晓科技/RISCV-Linux - Gitee.com][001]
* [如何分析 Linux 内核 RISC-V 架构相关代码][002]
* [Nuclei_N 级别指令架构手册][005]
* [sifive 中断处理流程][004]
* [Linux Kernel 的中断子系统之（七）：GIC 代码分析 (wowotech.net)][007]
* [Linux 中断子系统 - GIC 驱动源码分析 - 知乎 (zhihu.com)][006]

[001]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220519-riscv-irq-analysis.md
[002]: https://tinylab.org/riscv-linux-quickstart/
[003]: https://www.cnblogs.com/gulan-zmc/p/11604437.html
[004]: https://www.elecfans.com/d/1575408.html
[005]: https://www.rvmcu.com/quickstart-show-id-1.html#38
[006]: https://zhuanlan.zhihu.com/p/363134084
[007]: http://www.wowotech.net/irq_subsystem/gic_driver.html
