---
layout: post
author: 'Groot'
title: 'RISC-V SBI 规范 2.0-rc1 中文翻译'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /sbi-specification-translation/
description: 'RISC-V SBI 规范 2.0-rc1 中文翻译'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector:        [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc1 - [urls refs]
> Title:            [RISC-V SBI specification](https://github.com/riscv-non-isa/riscv-sbi-doc/releases/download/v2.0-rc1/riscv-sbi.pdf)
> Author:           riscv.org
> Translator:       刘澳 <1219671600@qq.com>
> Date:             2022/07/10
> Revisor:          Falcon <falcon@tinylab.org>, Bin Meng <bmeng@tinylab.org>
> Project:          [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Acknowledgements: 山东大学 山东大学智能创新研究院 [RISC-V SBI-1.0.0 版本 中文][001]
> Sponsor:          PLCT Lab, ISCAS

**当前中文翻译基于 RISC-V SBI Spec 2.0-rc1，2.0 正式版预计很快会正式发布**：

## 前言

本次翻译工作的背景为我正在调研 RISC-V SBI 相关知识，发现 SBI Spec 正在快速更新，目前已经开始更新 2.0 版本。于此同时，我发现国内已经有了 SBI Spec 的翻译工作，不过可能因为某些原因，并没有机构对 SBI Spec 2.0-rc1 进行翻译。我认为这对于我来说是一个很好的了解 SBI Spec 的机会，对于国内想要学习 RISC-V SBI 的研究人员可能也会有些帮助，所以就开始了 SBI Spec 2.0-rc1 的翻译工作。

在这里非常感谢山东大学以及山东大学智能创新研究院，他们之前翻译了 SBI Spec 1.0 版本，我的这次翻译是在他们的基础上完成的。在与原翻译人员通过邮件取得沟通后，他们非常慷慨地同意了我使用他们的翻译成果做为基础来进行我的工作。他们的翻译成果发表在 [RISC-V SBI-1.0.0 版本 中文][001]。

本次翻译相较于前一版本，主要对 SBI Spec 2.0-rc1 版本的新增内容（见“更改日志”一节）进行了翻译，以及对原翻译的格式进行了一些调整，对一些术语进行了统一。

## 更改日志

### 版本 2.0-rc1

- 添加了共享内存物理地址范围参数的通用描述
- 添加了 SBI 调试控制台扩展
- 放宽了 SBI PMU 固件计数器的计数器宽度要求
- 在 SBI PMU 扩展中添加了 `sbi_pmu_counter_fw_read_hi()`
- 为 SBI 实现特定固件事件保留空间
- 添加了 SBI 系统挂起扩展
- 添加了 SBI CPPC 扩展
- 阐明了 SBI 扩展只有在定义发现已实现 SBI 的机制时才能部分实现函数
- 添加了错误代码 SBI_ERR_NO_SHMEM
- 添加了 SBI 嵌套加速扩展
- 添加了虚拟 HART 的通用描述
- 添加了 SBI 隐身时间记帐扩展
- 添加了 SBI PMU 快照扩展

### 版本 1.0.0

- 更新批准版本

### 版本 1.0-rc3

- 更新调用约定
- 修复了 PMU 扩展名中的拼写错误
- 添加缩写表

### 版本 1.0-rc2

- 更新 RISC-V 格式
- 修改介绍部分
- 删除了所有 RV32 引用

### 版本 1.0-rc1

- 错别字修正
  版本 0.3.0

### 版本 0.3.0

- 少量错别字修正
- 文本更新 LICENSE 部分的超链接

### 版本 0.3-rc1

- 改进文档样式和命名约定
- 添加 SBI 系统重置扩展
- 修改 SBI 介绍部分
- 修改 SBI hart 状态管理扩展文档
- 为 SBI hart 状态管理扩展添加挂起
- 添加性能监控单元扩展
- 阐明一个不应局部实现的 SBI 扩展

### 版本 0.2

- 整个 v0.1 SBI 已移动至旧版扩展，现已是可选扩展。

从技术上讲，这是一个向后不兼容的更改，因为遗留扩展是可选的，并且 SBI 的 v0.1 不允许探测，但我们已经尽力了。

## 章节 1. 介绍

本规范描述了 RISC-V Supervisor Binary Interface，简称为 SBI。SBI 允许在所有 RISC-V 实现上，通过定义平台（或虚拟化管理程序）特定功能的抽象，使监督者模式（S 模式或 VS 模式）的软件具备可移植性。SBI 的设计遵循 RISC-V 的一般原则，即核心部分小而精简，同时具备一组可选的模块化扩展功能。
SBI 扩展作为整体是可选的，但不允许部分实现。如果 sbi_probe_extension() 表明某个扩展可用，那么 sbi_get_spec_version() 报告的 SBI 版本中的所有函数必须符合该版本的 SBI 规范。
提供给监管模式软件的更高特权级软件称为 SBI 实现或 Supervisor Execution Environment（SEE）。SBI 实现（或 SEE）可以是在机器模式（M-mode）下执行的平台运行时固件（参见下图 1），也可以是在超级监管模式（HS-mode）下执行的某个虚拟化监管程序（参见下图 2）。

![fig1.jpg](/wp-content/uploads/2022/03/riscv-linux/images/sbi-specification-translation/fig1.jpg)

图 1.无 H 扩展 RISC-V 系统

![fig2.jpg](/wp-content/uploads/2022/03/riscv-linux/images/sbi-specification-translation/fig2.jpg)

图 2.带 H 扩展 RISC-V 系统

SBI 规范不指定硬件发现的任何方法。监督者软件必须依赖其他行业标准的硬件发现方法（例如设备树或 ACPI）来实现。

## 章节 2. 术语和缩写

本规范使用了下列术语及缩写：

| 术语 | 含义                                                            |
| :--- | --------------------------------------------------------------- |
| ACPI | 高级配置和电源接口 (Advanced Configuration and Power Interface) |
| ASID | 地址空间标识符 (Address Space Identifier)                       |
| BMC  | 底板管理控制器 (Baseboard Management Controller)                |
| CPPC | 协处理器性能控制 (Collaborative Processor Performance Control)  |
| EID  | 扩展号 (Extension ID)                                           |
| FID  | 函数号 (Function ID)                                            |
| HSM  | 核心状态管理 (Hart State Management)                            |
| IPI  | 处理器核间中断 (Inter Processor Interrupt)                      |
| PMU  | 性能监控单元 (Performance Monitoring Unit)                      |
| SBI  | 监管二进制接口 (Supervisor Binary Interface)                    |
| SEE  | 监管执行环境 (Supervisor Execution Environment)                 |
| VMID | 虚拟机标识符 (Virtual Machine Identifier)                       |

## 章节 3. 二进制编码

所有的 SBI 函数共享一种二进制编码方式，这有助于混合使用 SBI 扩展功能。SBI 规范遵循以下调用约定。

- 在监督者和 SEE 之间，使用 ECALL 作为控制传输指令。
- a7 编码 SBI 扩展 ID（EID）
- a6 编码 SBI 函数 ID（FID），对于任何在 a7 中编码的 SBI 扩展，其定义在 SBI v0.2 之后。
- 在 SBI 调用期间，除了 a0 和 a1 寄存器外，所有寄存器都必须由被调用方保留。
- SBI 函数必须在 a0 和 a1 中返回一对值，其中 a0 返回错误代码。类似于返回 C 结构体。

```
struct sbiret
{
	long error;
	long value;
};
```

为了保持兼容性，SBI 扩展 ID（EID）和 SBI 函数 ID（FID）被编码为有符号的 32 位整数。当以寄存器形式传递时，遵循上述标准的调用约定规则。
表 1 列出了标准 SBI 错误代码。

_表 1.标准 SBI 错误_

| 错误类型                  | 值 | 描述           |
| :------------------------ | -- | :------------- |
| SBI_SUCCESS               | 0  | 顺利完成       |
| SBI_ERR_FAILED            | -1 | 失败           |
| SBI_ERR_NOT_SUPPORTED     | -2 | 不支持操作     |
| SBI_ERR_INVALID_PARAM     | -3 | 非法参数       |
| SBI_ERR_DENIED            | -4 | 拒绝           |
| SBI_ERR_INVALID_ADDRESS   | -5 | 非法地址       |
| SBI_ERR_ALREADY_AVAILABLE | -6 | （资源）已可用 |
| SBI_ERR_ALREADY_STARTED   | -7 | （操作）已启动 |
| SBI_ERR_ALREADY_STOPPED   | -8 | （操作）已停止 |
| SBI_ERR_NO_SHMEM          | -9 | 共享内存不可用 |

不支持的 SBI 扩展 ID（EID）或 SBI 函数 ID（FID）的 ECALL 必须返回错误代码 SBI_ERR_NOT_SUPPORTED。
每个 SBI 函数应该优先选择无符号长整型 unsigned long 作为数据类型。这使得规范简单且易于适应所有 RISC-V ISA 类型。如果数据被定义为 32 位宽度，则更高权限的软件必须确保只使用 32 位数据。

### 3.1 HART 列表参数

如果 SBI 函数需要将一组 hart 传递给更高权限模式，它必须使用如下所定义的 hart 掩码。这适用于在 v0.2 版本之后定义的任何扩展。
任何需要 hart 掩码的函数需要传递以下两个参数。

- unsigned long hart_mask 是一个包含 hartid 的标量位向量。
- unsigned long hart_mask_base 是计算位向量的起始 hartid。

在单个 SBI 函数调用中，可以设置的最大 hart 数量始终为 XLEN。如果较低特权模式需要传递超过 XLEN 个 hart 的信息，它应该调用多个 SBI 函数调用的实例。hart_mask_base 可以设置为-1，表示可以忽略 hart_mask 并考虑所有可用的 harts。
使用 hart 掩码的任何函数可能返回表 2 中列出的错误值，这些错误值是针对特定函数的错误值的补充。

_表 2. HART 掩码错误_

| 错误代码              | 描述                                                                                           |
| :-------------------- | :--------------------------------------------------------------------------------------------- |
| SBI_ERR_INVALID_PARAM | hart_mask_base 或 hart_mask 中任何一个 hartid 无效，即该 hartid 未被平台启用或对监管程序不可用 |

### 3.2 共享内存物理地址范围参数

如果 SBI 功能需要将共享内存物理地址范围传递给 SBI 实现（或更高特权模式），则该物理内存地址范围必须满足以下要求：

- SBI 实现必须检查监管模式软件是否允许使用请求的访问类型（读和/或写）访问指定的物理内存范围。
- SBI 实现必须使用 PMA 属性访问指定的物理内存范围。

> 注意：如果监督者模式的软件使用与 PMA 不同的内存类型访问相同的物理内存范围，就可能发生一致性丢失或意外的内存排序。调用的软件应遵循 RISC-V Svpbmt 规范中定义的规则和顺序，以防止一致性丢失和内存排序问题的发生。

- 在共享内存中的数据必须遵循小端字节顺序。

建议将传递给 SBI 函数的内存物理地址至少无符号长整形参数，以支持具有大于 XLEN 位的内存物理地址的平台。

## 章节 4. 基本扩展 (EID #0x10)

基本扩展旨在尽可能简洁。因此，它仅包含用于探测可用的 SBI 扩展以及查询 SBI 版本的功能。基本扩展中的所有函数必须由所有 SBI 实现支持，因此没有定义错误返回值。

### 4.1 函数：获取 SBI 规范版本 (FID #0)

```
struct sbiret sbi_get_spec_version(void);
```

返回当前的 SBI 规范版本。此函数必定成功。SBI 规范的次版本号编码在低 24 位中，主版本号编码在接下来的 7 位中。第 31 位必须为 0，保留用于未来扩展。

### 4.2 函数：获取 SBI 实现标识符 (FID #1)

```
struct sbiret sbi_get_impl_id(void);
```

返回当前 SBI 实现的标识符，每个 SBI 实现的标识符都是不同的。这个标识符旨在让软件探测 SBI 实现的特殊问题或特点。

### 4.3 函数：获取 SBI 实现版本 (FID #2)

```
struct sbiret sbi_get_impl_version(void);
```

返回当前 SBI 实现的版本。该版本号的编码是特定于 SBI 实现的。

### 4.4 函数：探测 SBI 扩展功能 (FID #3)

```
struct sbiret sbi_probe_extension(long extension_id);
```

如果给定的 SBI 扩展 ID (EID) 不可用，则返回 0；如果可用，返回值应为 1，或为特定 SBI 实现定义的其他非 0 值。

### 4.5 函数：获取机器供应商标识符 (FID #4)

```
struct sbiret sbi_get_mvendorid(void);
```

返回一个合法的 mvendorid CSR 值，其中 0 总是一个合法的值。mvendorid CSR 是一个用于标识机器供应商的控制状态寄存器，它用于表示底层硬件的供应商或制造商。

### 4.6 函数：获取机器体系结构标识符 (FID #5)

```
struct sbiret sbi_get_marchid(void);
```

返回一个在 marchid CSR 中合法的值，其中 0 总是合法的值。marchid CSR 是 RISC-V 架构中的一个控制状态寄存器，用于标识机器体系结构。

### 4.7 函数：获取机器实现标识符 ID (FID #6)

```
struct sbiret sbi_get_mimpid(void);
```

返回一个在 mimpid CSR 中合法的值，而且对于该 CSR，0 始终是一个合法的值。

### 4.8.函数列表

_表 3.基础函数列表_

| 函数名                   | SBI 版本 | FID | EID  |
| :----------------------- | -------- | --- | ---- |
| sbi_get_sbi_spec_version | 0.2      | 0   | 0x10 |
| sbi_get_sbi_impl_id      | 0.2      | 1   | 0x10 |
| sbi_get_sbi_impl_version | 0.2      | 2   | 0x10 |
| sbi_probe_extension      | 0.2      | 3   | 0x10 |
| sbi_get_mvendorid        | 0.2      | 4   | 0x10 |
| sbi_get_marchid          | 0.2      | 5   | 0x10 |
| sbi_get_mimpid           | 0.2      | 6   | 0x10 |

### 4.9 SBI 实现标识符

_表 4. SBI 实现 IDs_

| SBI 实现 ID | 名称                       |
| :---------- | -------------------------- |
| 0           | Berkeley Boot Loader (BBL) |
| 1           | OpenSBI                    |
| 2           | Xvisor                     |
| 3           | KVM                        |
| 4           | RustSBI                    |
| 5           | Diosix                     |
| 6           | Coffer                     |
| 7           | Xen Project                |

## 章节 5. 旧版扩展 (EIDs #0x00- #0x0F)

传统的 SBI 扩展与 SBI v0.2（或更高版本）规范相比，遵循略微不同的调用约定，其中：

- a6 寄存器中的 SBI 函数 ID 字段被忽略，因为这些被编码为多个 SBI 扩展 ID。
- a1 寄存器中不返回任何值。
- 在 SBI 调用期间，除 a0 寄存器外的所有寄存器都必须由被调用者保留。
- a0 寄存器中返回的值是特定于 SBI 传统扩展的。

SBI 实现在监督者访问内存时发生的页面和访问故障会被重定向回监督者，并且 sepc 寄存器指向故障的 ECALL 指令。

传统 SBI 扩展已被以下扩展所取代。传统的控制台 SBI 函数（sbi_console_getchar() 和 sbi_console_putchar()）预计将被弃用；它们没有替代方案。

### 5.1 扩展：设置时钟 (EID #0x00)

```
long sbi_set_timer(uint64_t stime_value)
```

设置时钟，在 stime_value 时间之后进行下一次事件。此功能还清除待处理的计时器中断位。
如果监管程序希望清除计时器中断但不安排下一个计时器事件，则可以将计时器中断请求设置为无限远（即（uint64_t）-1），或者通过清除 sie.STIE 寄存器位来屏蔽计时器中断。
此 SBI 调用在成功时返回 0，否则返回实现特定的负错误代码。

### 5.2 扩展：控制台字符输出 (EID #0x01)

```
long sbi_console_putchar(int ch)
```

将 **ch** 中的数据写入控制台。
与 sbi_console_getchar() 不同的是，如果仍有任何待传输的字符或接收终端还没有准备好接收字节，则此 SBI 调用将阻塞。但是，如果控制台根本不存在，则字符将被丢弃。
此 SBI 调用在成功时返回 0，否则返回实现特定的负错误代码。

### 5.3 扩展：控制台字符输入 (EID #0x02)

```
long sbi_console_getchar(void)
```

从调试控制台中读一个字符。
此 SBI 调用在成功时返回 0，否则返回实现特定的负错误代码。

### 5.4 扩展：清除 IPI (EID #0x03)

```
long sbi_clear_ipi(void)
```

清除任何挂起的 IPI（处理器核间中断）。这个 SBI 调用只会清除被调用的 hart（硬件线程），其他的 hart 不受影响。
sbi_clear_ipi() 已经被弃用，因为 S 模式代码可以直接清除 sip.SSIP 寄存器位。
如果没有 IPI 被挂起，这个 SBI 调用返回 0；如果有 IPI 被挂起，则返回一个实现特定的正值。

### 5.5 扩展：发送 IPI (EID #0x04)

```
long sbi_send_ipi(const unsigned long *hart_mask)
```

向 hart_mask 指定的所有 hart 发送跨处理器中断。跨处理器中断在接收的 hart 上表现为监督者模式软件中断。
hart_mask 是指向 hart 位向量的虚拟地址。该位向量表示为无符号长整型序列，其长度等于系统中 hart 的数量除以无符号长整型中的位数，向上取整到下一个整数。
此 SBI 调用在成功时返回 0，或返回一个实现特定的负错误代码。

### 5.6 扩展：远程 FENCE.I (EID #0x05)

```
long sbi_remote_fence_i(const unsigned long *hart_mask)
```

该函数用于指示远程处理器执行 FENCE.I 指令。
此 SBI 调用在成功时返回 0，或返回一个实现特定的负错误代码。

### 5.7 扩展：远程 SFENCE.VMA (EID #0x06)

```
long sbi_remote_sfence_vma(const unsigned long *hart_mask,unsigned long start, unsigned long size)
```

指示远程 harts 执行一个或多个 SFENCE.VMA 指令，涵盖从 start 到 size 的虚拟地址范围。其中，hart_mask 参数与 sbi_send_ipi() 函数中描述的一样。
此 SBI 调用在成功时返回 0，或返回一个实现特定的负错误代码。

### 5.8 扩展：远程 SFENCE.VMA（指定地址空间标识符）(EID #0x07)

```
long sbi_remote_sfence_vma_asid(const unsigned long *hart_mask,unsigned long start, unsigned long size, unsigned long asid)
```

指示远程 hart 执行一个或多个 SFENCE.VMA 指令，覆盖 start 和 size 之间的虚拟地址范围。此操作仅涵盖给定的 ASID。
此 SBI 调用在成功时返回 0，或返回一个实现特定的负错误代码。

### 5.9 扩展：系统关闭 (EID #0x08)

```
void sbi_shutdown(void)
```

将所有 hart 从监督者模式的角度置于关闭状态。
此 SBI 调用在成功时返回 0，或返回一个实现特定的负错误代码。

### 5.10 函数列表

_表 5. 旧版函数列表_

| 函数名                     | SBI 版本 | FID | EID       | 替代 EID   |
| :------------------------- | -------- | --- | --------- | ---------- |
| sbi_set_timer              | 0.1      | 0   | 0x00      | 0x54494D45 |
| sbi_console_putchar        | 0.1      | 0   | 0x01      | N/A        |
| sbi_console_getchar        | 0.1      | 0   | 0x02      | N/A        |
| sbi_clear_ipi              | 0.1      | 0   | 0x03      | N/A        |
| sbi_send_ipi               | 0.1      | 0   | 0x04      | 0x735049   |
| sbi_remote_fence_i         | 0.1      | 0   | 0x05      | 0x52464E43 |
| sbi_remote_sfence_vma      | 0.1      | 0   | 0x06      | 0x52464E43 |
| sbi_remote_sfence_vma_asid | 0.1      | 0   | 0x07      | 0x52464E43 |
| sbi_shutdown               | 0.1      | 0   | 0x08      | 0x53525354 |
| 保留                       |          |     | 0x09-0x0F |            |

## 章节 6. 时钟扩展 (EID #0x54494D45 "TIME")

这个替代扩展（EID #0x00）替代了传统的计时器扩展。它遵循在 v0.2 中定义的新的调用约定。

### 6.1 函数：时钟设定 (FID #0)

```
struct sbiret sbi_set_timer(uint64_t stime_value)
```

在 stime_value 时间之后，为下一个事件设置时钟。stime_value 以绝对时间表示。此函数还必须清除挂起的计时器中断位。
如果监督者希望在不安排下一个计时器事件的情况下清除计时器中断，可以请求一个无限远的计时器中断（即 (uint64_t)-1），或者通过清除 sie.STIE 寄存器位来屏蔽计时器中断。

### 6.2 函数列表

_表 6. 时钟函数列表_

| 函数名        | SBI 版本 | FID | EID        |
| :------------ | -------- | --- | ---------- |
| sbi_set_timer | 0.2      | 0   | 0x54494D45 |

## 章节 7. IPI 扩展 (EID #0x735049 "sPI: s-mode IPI")

该扩展替代了传统的扩展 (EID #0x04)。其他与 IPI 相关的传统扩展（0x3）现已不推荐使用。该扩展中的所有函数都遵循二进制编码部分中定义的 hart_mask.

### 7.1 函数：发送 IPI (FID #0)

```
struct sbiret sbi_send_ipi(unsigned long hart_mask,unsigned long hart_mask_base)
```

向 hart_mask 中定义的所有 hart 发送跨处理器中断。接收 hart 上的处理器间中断将在其上表现为监督者软件中断。
sbiret.error 返回的可能错误代码如表 7 所示。

_表 7. IPI 发送错误_

| 错误代码         | 描述                           |
| :--------------- | ------------------------------ |
| SBI_SUCCESS 成功 | IPI 被成功发送至所有目标 harts |

### 7.2 函数列表

_表 8. IPI 函数列表_

| 函数名       | SBI 版本 | FID | EID      |
| :----------- | -------- | --- | -------- |
| sbi_send_ipi | 0.2      | 0   | 0x735049 |

## 章节 8. RFENCE 扩展 (EID #0x52464E43 "RFNC")

该扩展定义了所有与远程屏障相关的函数，并替代了旧的扩展（EID #0x05 - #0x07）。所有的函数都遵循二进制编码部分中定义的 hart_mask。任何希望使用地址范围（即 start_addr 和 size）的函数，必须遵守以下对范围参数的约束条件。
如果以下条件满足，则远程屏障函数充当完全 TLB 刷新的作用：

- start_addr 和 size 都为 0
- size 等于 2^XLEN-1

### 8.1 函数：远程 FENCE.I 指令 (FID #0)

```
struct sbiret sbi_remote_fence_i(unsigned long hart_mask,unsigned long hart_mask_base)
```

远程指示 harts 执行 FENCE.I 指令。
sbiret.error 返回的可能错误代码如表 9 所示。

_表 9. RFENCE 远程 FENCE.I 指令错误_

| 错误代码         | 描述                           |
| :--------------- | ------------------------------ |
| SBI_SUCCESS 成功 | IPI 被成功发送至所有目标 harts |

### 8.2 函数：远程 SFENCE.VMA 指令 (FID #1)

```
struct sbiret sbi_remote_sfence_vma(unsigned long hart_mask,
unsigned long hart_mask_base, unsigned long start_addr, unsigned long size)
```

指示远程 hart 执行一个或多个 SFENCE.VMA 指令，覆盖从 start 到 size 的虚拟地址范围内的地址。
sbiret.error 返回的可能错误代码如表 10 所示。

_表 10. RFENCE 远程 SFENCE.VMA 错误_

| 错误代码                         | 描述                           |
| :------------------------------- | ------------------------------ |
| SBI_SUCCESS 成功                 | IPI 被成功发送至所有目标 harts |
| SBI_ERR_INVALID_ADDRESS 非法地址 | start_addr 或 size 非法        |

### 8.3 函数：远程 SFENCE.VMA 指定 ASID (FID #2)

```
struct sbiret sbi_remote_sfence_vma_asid(unsigned long hart_mask,
unsigned long hart_mask_base, unsigned long start_addr, unsigned long size,
unsigned  long asid)
```

指示远程 hart 执行一个或多个 SFENCE.VMA 指令，覆盖从 start 到 size 的虚拟地址范围内的地址。这仅涵盖给定的 ASID。
sbiret.error 返回的可能错误代码如表 11 所示。

_表 11. RFENCE 远程 SFENCE.VMA 指定 ASID 错误_

| 错误代码                         | 描述                           |
| :------------------------------- | ------------------------------ |
| SBI_SUCCESS 成功                 | IPI 被成功发送至所有目标 harts |
| SBI_ERR_INVALID_ADDRESS 非法地址 | start_addr 或 size 非法        |

### 8.4 函数：远程 HFENCE.GVMA 指定 VMID (FID #3)

```
struct sbiret sbi_remote_hfence_gvma_vmid(unsigned long hart_mask,
unsigned long hart_mask_base, unsigned long start_addr, unsigned long size,
unsigned long vmid)
```

指示远程 hart 执行一个或多个 HFENCE.GVMA 指令，仅覆盖给定 VMID（虚拟机标识符）的 start 到 size 之间的客户机物理地址范围。此函数调用仅适用于实现了虚拟化扩展的 harts。
sbiret.error 返回的可能错误代码如表 12 所示。

_表 12. RFENCE 远程 HFENCE.GVMA 指定 VMID 错误_

| 错误代码                            | 描述                                                           |
| :---------------------------------- | -------------------------------------------------------------- |
| SBI_SUCCESS 成功                    | IPI 被成功发送至所有目标 harts                                 |
| SBI_ERR_NOT_SUPPORTED（操作）不支持 | 由于未被实现或目标 hart 中不错支持虚拟化扩展，则该操作不受支持 |
| SBI_ERR_INVALID_ADDRESS 非法地址    | start_addr 或 size 非法                                        |

### 8.5 函数：远程 HFENCE.GVMA (FID #4)

```
struct sbiret sbi_remote_hfence_gvma(unsigned long hart_mask,
unsigned long hart_mask_base, unsigned long start_addr, unsigned long size)
```

指示远程 harts 执行一个或多个 HFENCE.GVMA 指令，覆盖从 start 到 size 之间的所有客户机的客户机物理地址范围。此函数调用仅适用于实现虚拟化扩展的 harts。
sbiret.error 返回的可能错误代码如表 13 所示。

_表 13. RFENCE 远程 HFENCE.GVMA 错误_

| 错误代码                            | 描述                                                           |
| :---------------------------------- | -------------------------------------------------------------- |
| SBI_SUCCESS 成功                    | IPI 被成功发送至所有目标 harts                                 |
| SBI_ERR_NOT_SUPPORTED（操作）不支持 | 由于未被实现或目标 hart 中不错支持虚拟化扩展，则该操作不受支持 |
| SBI_ERR_INVALID_ADDRESS 非法地址    | start_addr 或 size 非法                                        |

### 8.6 函数：远程 HFENCE.VVMA 指定 ASID (FID #5)

```
struct sbiret sbi_remote_hfence_vvma_asid(unsigned long hart_mask,
unsigned long hart_mask_base, unsigned long start_addr, unsigned long size,
unsigned  long asid)
```

远程指示 harts 执行一个或多个 HFENCE.VVMA 指令，覆盖从 start 至 size 之间，指定的 ASID 与
VMID（hgatp 寄存器）下所有客户机物理地址范围。此函数调用仅适用于实现虚拟化扩展的 harts。
sbiret.error 返回的可能错误代码如表 14 所示。

_表 14. RFENCE 远程 HFENCE.VVMA 指定 ASID 错误_

| 错误代码                            | 描述                                                           |
| :---------------------------------- | -------------------------------------------------------------- |
| SBI_SUCCESS 成功                    | IPI 被成功发送至所有目标 harts                                 |
| SBI_ERR_NOT_SUPPORTED（操作）不支持 | 由于未被实现或目标 hart 中不错支持虚拟化扩展，则该操作不受支持 |
| SBI_ERR_INVALID_ADDRESS 非法地址    | start_addr 或 size 非法                                        |

### 8.7 函数：远程 HFENCE.VVMA (FID #6)

```
struct sbiret sbi_remote_hfence_vvma(unsigned long hart_mask,
unsigned long hart_mask_base, unsigned long start_addr, unsigned long size)
```

指示远程 HART 执行一个或多个 HFENCE.VVMA 指令，覆盖当前调用 HART 的 VMID（在 hgatp 寄存器中）下的 start 和 size 之间的客户虚拟地址范围。此函数调用仅适用于实现了虚拟化扩展的 harts。
sbiret.error 返回的可能错误代码如表 15 所示。

_表 15.RFENCE 远程 HFENCE.VVMA 错误_

| 错误代码                            | 描述                                                           |
| :---------------------------------- | -------------------------------------------------------------- |
| SBI_SUCCESS 成功                    | IPI 被成功发送至所有目标 harts                                 |
| SBI_ERR_NOT_SUPPORTED（操作）不支持 | 由于未被实现或目标 hart 中不错支持虚拟化扩展，则该操作不受支持 |
| SBI_ERR_INVALID_ADDRESS 非法地址    | start_addr 或 size 非法                                        |

### 8.8 函数列表

_表 16. RFENCE 函数列表_

| 函数名                      | SBI 版本 | FID | EID        |
| :-------------------------- | -------- | --- | ---------- |
| sbi_remote_fence_i          | 0.2      | 0   | 0x52464E43 |
| sbi_remote_sfence_vma       | 0.2      | 1   | 0x52464E43 |
| sbi_remote_sfence_vma_asid  | 0.2      | 2   | 0x52464E43 |
| sbi_remote_hfence_gvma_vmid | 0.2      | 3   | 0x52464E43 |
| sbi_remote_hfence_gvma      | 0.2      | 4   | 0x52464E43 |
| sbi_remote_hfence_vvma_asid | 0.2      | 5   | 0x52464E43 |
| sbi_remote_hfence_vvma      | 0.2      | 6   | 0x52464E43 |

## 章节 9. Hart State Management 状态管理扩展 (EID #0x48534D "HSM")

Hart State Management (HSM) 扩展引入了一组 Hart 状态和一组函数，允许监督者模式下的软件请求 Hart 状态变更。
下面的表 17 描述了所有可能的 HSM 状态以及每个状态的唯一 HSM 状态标识符。:

_表 17. HSM Hart 状态_

| 状态 ID | 状态名                     | 描述                                                                                                                            |
| :------ | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| 0       | 启动 (STARTED)             | 该 hart 处于物理上电状态，并正常执行。                                                                                          |
| 1       | 结束 (STOPPED)             | 该 hart 没有在监督者模式或任何更低特权模式下执行。如果底层平台具有关闭 hart 的物理机制，那么它可能被 SBI 实现关闭了电源。       |
| 2       | 等待被启动 (START_PENDING) | 另一个 hart 请求将该 hart 从 STOPPED 状态启动（或上电），而 SBI 实现仍在努力将该 hart 转换为 STARTED 状态。                     |
| 3       | 结束等待 (STOP_PENDING)    | 该 hart 在 STARTED 状态下请求停止（或关机），而 SBI 实现仍在努力将该 hart 转变为 STOPPED 状态。                                 |
| 4       | 挂起 (SUSPENDED)           | 该 hart 处于特定于平台的暂停（或低功耗）状态。                                                                                  |
| 5       | 等待挂起 (SUSPEND_PENDING) | 该 hart 从 STARTED 状态请求将自身置于特定于平台的低功耗状态，并且 SBI 实现正在努力将该 hart 转换为特定于平台的 SUSPENDED 状态。 |
| 6       | 等待恢复 (RESUME_PENDING)  | 中断或特定于平台的硬件事件导致 hart 从 SUSPENDED 状态恢复正常执行，而 SBI 实现正在努力将该 hart 转换为 STARTED 状态。           |

在任何时刻，hart 应该处于上述提到的 hart 状态之一。SBI 实现对 hart 状态的转换应遵循图 3 所示的状态机。

![fig3.jpg](/wp-content/uploads/2022/03/riscv-linux/images/sbi-specification-translation/fig3.jpg)

图 3. SBI HSM 状态机

一个平台可以有多个 hart，这些 hart 被分组成层次拓扑组（如核心、集群、节点等），每个层次组都有独立的平台特定低功耗状态。这些层次拓扑组的平台特定低功耗状态可以表示为一个 hart 的平台特定挂起状态。SBI 实现可以利用较高层次拓扑组的挂起状态，使用以下一种方法之一：

1. **平台协调**: 在这种方法中，当一个 hart 变为空闲时，监督者模式的功耗管理软件将请求该 hart 和较高层次组的最深挂起状态。SBI 实现应选择一个较高层次组的挂起状态，满足以下条件：
   1. 不比指定的挂起状态更深
   2. 唤醒延迟不高于指定挂起状态的唤醒延迟
2. **操作系统发起**: 在这种方法中，监督者模式的功耗管理软件将在最后一个 hart 变为空闲后，直接请求较高层次组的挂起状态。当一个 hart 变为空闲时，监管模式的功耗管理软件总是选择该 hart 的挂起状态，但仅在该 hart 是组内最后一个运行的 hart 时，才为较高层次组选择一个挂起状态。SBI 实现应满足以下条件：
   1. 永远不要选择与指定暂停状态不同的较高层次组的挂起状态
   2. 总是优先选择最近请求的较高层次组的挂起状态。

### 9.1 函数：HART 启动 (FID #0)

```
struct  sbiret  sbi_hart_start(unsigned  long  hartid,
unsigned long start_addr, unsigned long opaque)
```

SBI 实现以特定的寄存器值在指定的 start_addr 地址处启动执行目标 hart 的监督者模式。具体的寄存器值如表 18 所述。

_表 18. HSM Hart 启动的寄存器状态_

| 寄存器名称                   | 寄存器值    |
| :--------------------------- | ----------- |
| satp                         | 0           |
| sstatus.SIE                  | 0           |
| a0                           | hartid      |
| a1                           | opaque 参数 |
| 其他寄存器仍处于未定义状态。 |             |

此调用是异步的，具体来说，sbi_hart_start() 函数可以在目标 hart 开始执行之前返回，只要 SBI 实现能够确保返回的结果准确。如果 SBI 实现是在机器模式（M-mode）下执行的平台运行时固件，则必须在将控制权转移给监督者模式软件之前配置 PMP 和其他 M-mode 状态。
hartid 参数指定要启动的目标 hart。
start_addr 参数指向一个运行时指定的物理地址，该 hart 可以在监督者模式下开始执行。
opaque 参数是一个 XLEN 位的值，当 hart 在 start_addr 处开始执行时 opaque 参数被设置在 a1 寄存器中。
sbiret.error 中可能返回的错误代码在下表 19 中显示。

_表 19. HSM Hart 启动错误_

| 错误代码                          | 描述                                                                             |
| :-------------------------------- | -------------------------------------------------------------------------------- |
| SBI_SUCCESS 成功                  | Hart 之前处于停止状态。它将从 start_addr 开始执行                                |
| SBI_ERR_INVALID_ADDRESS 非法地址  | start_addr 无效，原因可能如下：无效物理地址。该地址被 PMP 禁止在监督者模式下执行 |
| SBI_ERR_INVALID_PARAM 非法参数    | 无效的 Hart，因为其相应的 hart 不能以监督者模式启动                              |
| SBI_ERR_ALREADY_AVAILAB LE 已存在 | 给定 hartid 已启动                                                               |
| SBI_ERR_FAILED 失败               | 未知原因造成的启动失败                                                           |

### 9.2 函数：HART 停止 (FID #1)

```
struct sbiret sbi_hart_stop(void)
```

要求 SBI 实现停止以监督者模式执行调用 hart，并将其所有权返回给 SBI 实现。在正常情况下，不希望此调用返回。sbi_hart_stop() 必须在禁用监督者模式中断时调用。
sbiret.error 可能返回的错误代码如下表 20 所示。

_表 20. HSM Hart 停止错误_

| 错误代码            | 描述                   |
| :------------------ | ---------------------- |
| SBI_ERR_FAILED 失败 | 当前 hart 停止执行失败 |

### 9.3 函数：HART 获取状态 (FID #2)

```
struct sbiret sbi_hart_get_status(unsigned long hartid)
```

通过 sbiret.value 获取给定 hart 的当前状态（或 HSM 状态 ID），或通过 sbiret.error 获取错误信息。
hartid 参数指定需要查询状态的目标 hart。
sbiret.value 中可能返回的状态（或 HSM 状态 ID）值在表 17 中进行了描述。
sbiret.error 可能返回的错误代码如下表 21 所示。

_表 21. HSM Hart 获取状态错误_

| 错误代码                       | 描述               |
| :----------------------------- | ------------------ |
| SBI_ERR_INVALID_PARAM 无效参数 | 给定的 hartid 无效 |

由于任何并发的 sbi_hart_start()、sbi_hart_stop() 或 sbi_hart_suspend() 调用，harts 可能随时转换 HSM 状态，因此该函数的返回值可能不代表返回值验证时 hart 的实际状态。

### 9.4 函数：HART 挂起 (FID #3)

```
struct sbiret sbi_hart_suspend(uint32_t suspend_type,
unsigned long resume_addr, unsigned long opaque)
```

SBI 实现将调用的 hart 置于由 suspend_type 参数指定的平台特定的挂起（或低功耗）状态。当收到中断或平台特定的硬件事件时，hart 将自动退出挂起状态并恢复正常执行。
一个 hart 的平台特定挂起状态可以是保持性的或非保持性的。保持性挂起状态将保留所有特权模式下 hart 的寄存器和 CSR 值，而非保持性挂起状态将不保留 hart 的寄存器和 CSR 值。
从保持性挂起状态恢复是比较简单的，监督者模式的软件将看到 SBI 挂起调用返回而无需任何失败。在保持性挂起期间，resume_addr 参数未使用。
从非保持性挂起状态恢复相对更复杂，需要软件还原各种特权模式下的 hart 寄存器和 CSR。从非保持性挂起状态恢复后，hart 将跳转到由 resume_addr 指定的监督者模式地址，具体寄存器的值在表 22 中描述。

_表 22. HSM Hart 恢复寄存器状态_

| 寄存器名称                 | 寄存器值    |
| :------------------------- | ----------- |
| satp                       | 0           |
| sstatus.SIE                | 0           |
| a0                         | hartid      |
| a1                         | Opaque 参数 |
| 其他寄存器保持未定义状态。 |             |

suspend_type 参数是 32 位宽，可能的值如表 23 所示。

_表 23. HSM Hart 挂起类型_

| 值                      | 描述                 |
| :---------------------- | -------------------- |
| 0x00000000              | 默认保持性挂起       |
| 0x00000001 - 0x0FFFFFFF | 保留供未来使用       |
| 0x10000000 - 0x7FFFFFFF | 平台特定保持性挂起   |
| 0x80000000              | 默认非保持性挂起     |
| 0x80000001 - 0x8FFFFFFF | 保留供未来使用       |
| 0x90000000 - 0xFFFFFFFF | 平台特定非保持性挂起 |
| > 0xFFFFFFFF            | 保留                 |

resume_addr 参数指向一个在非保持性挂起后，hart 可以在监督者模式下恢复执行的运行时指定的物理地址。
opaque 参数是一个 XLEN 位的值，当 hart 在非保留挂起后在 resume_addr 处恢复执行时，会将该值设置在 a1 寄存器中。
sbiret.error 中可能返回的错误代码如表 24 所示。

_表 24. HSM Hart 挂起错误_

| 错误代码                         | 描述                                                                                      |
| :------------------------------- | ----------------------------------------------------------------------------------------- |
| SBI_SUCCESS 成功                 | Hart 已成功地从保持性挂起状态中恢复。                                                     |
| SBI_ERR_INVALID_PARAM 无效参数   | suspend_type 无效                                                                         |
| SBI_ERR_NOT_SUPPORTED 不支持     | suspend_type 有效但未实现。                                                               |
| SBI_ERR_INVALID_ADDRESS 无效地址 | resume_addr 无效，可能是由于以下原因：无效的物理地址或该地址被 PMP 禁止在监督者模式下运行 |
| SBI_ERR_FAILED 失败              | 挂起请求因未知原因而失败。                                                                |

### 9.5 函数列表

_表 25. HSM 函数列表_

| 函数名                       | SBI 版本 | FID | EID      |
| :--------------------------- | -------- | --- | -------- |
| sbi_hart_start 启动          | 0.2      | 0   | 0x48534D |
| sbi_hart_stop 停止           | 0.2      | 1   | 0x48534D |
| sbi_hart_get_status 获取状态 | 0.2      | 2   | 0x48534D |
| sbi_hart_suspend 挂起        | 0.3      | 3   | 0x48534D |

## 章节 10. 系统复位扩展 (EID #0x53525354 "SRST")

系统复位扩展提供了一个函数，允许监督者模式下的软件请求系统级的重启或关闭操作。"系统"指的是监督者模式下的软件的视角，底层的 SBI 实现可以是机器模式 M-mode 固件或虚拟化管理程序。

### 10.1 函数：系统复位 (FID #0)

```
struct sbiret sbi_system_reset(uint32_t reset_type, uint32_t reset_reason)
```

根据提供的类型 reset_type 和原因 reset_reason 重置系统。这是一个同步调用，如果成功将不会返回。
reset_type 参数的宽度为 32 位，其可能的取值在下面的表 26 中列出。

_表 26. SRST 系统复位类型_

| 值                      | 描述                       |
| :---------------------- | -------------------------- |
| 0x00000000              | 关机                       |
| 0x00000001              | 冷启动                     |
| 0x00000002              | 热启动                     |
| 0x00000003 - 0xEFFFFFFF | 保留以便未来使用           |
| 0xF0000000 - 0xFFFFFFFF | 供应商或平台特定的复位类型 |
| > 0xFFFFFFFF            | 保留                       |

reset_reason 是一个可选参数，表示系统复位的原因。该参数是 32 位宽，可能的取值如下所示：

_表 27. SRST 系统复位原因_

| 值                     | 描述                       |
| :--------------------- | -------------------------- |
| 0x00000000             | 没有原因                   |
| 0x00000001             | 系统失败                   |
| 0x00000002 - 0xDFFFFFFF | 保留以便未来使用           |
| 0xE0000000 - 0xEFFFFFFF | SBI 实现特定的复位原因     |
| 0xF0000000 - 0xFFFFFFFF | 供应商或平台特定的复位类型 |
| > 0xFFFFFFFF           | 保留                       |

当监督者下的软件在本地运行时，SBI 实现属于机器模式下的固件。在这种情况下，关机等同于整个系统的物理断电，冷启动等同于整个系统的物理断电循环（并重新上电）。此外，热重启等同于对主处理器和系统的一部分进行断电循环，而不是整个系统。例如，在具有 BMC（主板管理控制器）的服务器级系统上，热重启不会对 BMC 进行断电循环，而冷重启则肯定会对 BMC 进行断电循环。
当监督者模式下的软件在虚拟机内运行时，SBI 实现是一个虚拟化管理器。关机、冷重启和热重启在功能上与本机情况相同，但可能不会导致任何物理电源变化。
sbiret.error 中可能返回的错误代码如表 28 所示。

_表 28. SRST 系统复位错误 s_

| 错误代码                       | 描述                            |
| :----------------------------- | ------------------------------- |
| SBI_ERR_INVALID_PARAM 无效参数 | reset_type 或 reset_reason 无效 |
| SBI_ERR_NOT_SUPPORTED 不支持   | reset_type 有效但未被设定       |
| SBI_ERR_FAILED 失败            | 未知原因的复位请求失败          |

### 10.2 函数列表

_表 29. SRST 函数列表_

| Function Name    | SBI Version | FID | EID        |
| :--------------- | ----------- | --- | ---------- |
| sbi_system_reset | 0.3         | 0   | 0x53525354 |

## 章节 11. 性能监控单元扩展 (EID #0x504D55 "PMU")

RISC-V 硬件性能计数器（如 mcycle、minstret 和 mhpmcounterX CSRs）可以以只读方式从监督者模式使用 cycle、instret 和 hpmcounterX CSRs 进行访问。SBI 性能监控单元（PMU）扩展是一个接口，供监督者模式使用，以便借助机器模式（或虚拟化模式）配置和使用 RISC-V 硬件性能计数器。这些硬件性能计数器只能从机器模式使用 mcountinhibit 和 mhpmeventX CSRs 启动、停止或配置。因此，如果 RISC-V 平台未实现 mhpmcounterX CSR，机器模式的 SBI 实现可能选择禁止 SBI PMU 扩展。
一般情况下，RISC-V 平台支持使用有限数量的硬件性能计数器（最多 64 位）来监控各种硬件事件。此外，SBI 实现还可以提供固件性能计数器，用于监控固件事件，例如不对齐的加载/存储指令数量、RFENCE 数量、IPI 数量等。固件计数器始终为 64 位。
SBI PMU 扩展提供以下功能：

1. 监督者模式软件发现和配置每个 HART 的硬件/固件计数器的接口
2. 具有典型 perf 兼容接口的硬件/固件性能计数器和事件
3. 完全访问微体系结构的原始事件编码

为了定义 SBI PMU 扩展调用，我们首先定义了重要的实体 counter_idx、event_idx 和 event_data。counter_idx 是分配给每个硬件/固件计数器的逻辑编号。event_idx 表示硬件（或固件）事件，而 event_idx 为 64 位宽，表示硬件（或固件）事件的额外配置（或参数）。
event_idx 是一个 20 位宽的数字，编码如下：

```
event_idx[19:16]= type
event_idx[15:0] = code
```

### 11.1 事件：硬件通用事件 (Type #0)

event_idx.type（即事件类型）对于所有硬件通用事件应为 0x0，并且每个硬件通用事件由一个唯一的 event_idx.code（即事件代码）标识，如下所示的表格 30 中所述。

_表 30. PMU 硬件事件_

| 通用事件名称                       | 代码 | 描述                                  |
| :--------------------------------- | ---- | ------------------------------------- |
| SBI_PMU_HW_NO_EVENT                | 0    | 未使用的事件，因为 event_idx 不能为零 |
| SBI_PMU_HW_CPU_CYCLES              | 1    | 每个 CPU 周期的事件                   |
| SBI_PMU_HW_INSTRUCTIONS            | 2    | 每个完成的指令的事件                  |
| SBI_PMU_HW_CACHE_REFERENCES        | 3    | 缓存命中的事件                        |
| SBI_PMU_HW_CACHE_MISSES            | 4    | 缓存未命中的事件                      |
| SBI_PMU_HW_BRANCH_INSTRUCTIONS     | 5    | 分支指令的事件                        |
| SBI_PMU_HW_BRANCH_MISSES           | 6    | 分支预测错误的事件                    |
| SBI_PMU_HW_BUS_CYCLES              | 7    | 每个 BUS 周期的事件                   |
| SBI_PMU_HW_STALLED_CYCLES_FRONTEND | 8    | 微架构前端阻塞周期的事件              |
| SBI_PMU_HW_STALLED_CYCLES_BACKEND  | 9    | 微架构后端阻塞周期的事件              |
| SBI_PMU_HW_REF_CPU_CYCLES          | 10   | 每个参考 CPU 周期的事件               |

> 注意：对于硬件通用事件，event_data（即事件数据）未使用，event_data 的所有非零值都保留供将来使用。

> 注意：当 RISC-V 平台使用 WFI 指令进入 WAIT 状态或使用 SBI HSM HART 挂起调用进入平台特定的挂起状态时，CPU 时钟可能会停止。

> 注意：SBI_PMU_HW_CPU_CYCLES 事件通过 cycle CSR 计数 CPU 时钟周期。这些周期可能是可变频率的周期，在 CPU 时钟停止时不计数。

> 注意：SBI_PMU_HW_REF_CPU_CYCLES 在 CPU 时钟未停止时计数固定频率的时钟周期。计数的固定频率可以是例如时间 CSR 计数的频率。
> 注意：SBI_PMU_HW_BUS_CYCLES 计数固定频率的时钟周期。计数的固定频率可以是例如时间 CSR 计数的频率，或者可以是 HART（及其私有缓存）与系统其他部分之间的时钟边界的频率。

### 11.2 事件：硬件缓存事件 (Type #1)

对于所有硬件缓存事件，event_idx.type（即事件类型）应为 0x1，并且每个硬件缓存事件由唯一的 event_idx.code（即事件代码）标识，其编码如下：

```
event_idx.code[15:3] = cache_id
event_idx.code[2:1] = op_id
event_idx.code[0:0] = result_id
```

下表显示了以下标识符可能的值：event_idx.code.cache_id（即缓存事件 ID），event_idx.code.op_id（即缓存操作 ID）和 event_idx.code.result_id（即缓存结果 ID）。

_表 31. PMU 缓存事件 ID_

| 缓存事件名称          | 事件 ID | 描述              |
| :-------------------- | ------- | ----------------- |
| SBI_PMU_HW_CACHE_L1D  | 0       | 一级数据缓存事件  |
| SBI_PMU_HW_CACHE_L1I  | 1       | 一级指令缓存事件  |
| SBI_PMU_HW_CACHE_LL   | 2       | 最后一级缓存事件  |
| SBI_PMU_HW_CACHE_DTLB | 3       | 数据 TLB 事件     |
| SBI_PMU_HW_CACHE_ITLB | 4       | 指令 TLB 事件     |
| SBI_PMU_HW_CACHE_BPU  | 5       | 分支预测单元事件  |
| SBI_PMU_HW_CACHE_NODE | 6       | NUMA 节点缓存事件 |

_表 32. PMU 缓存操作 ID_

| 缓存操作名称                 | 操作 ID | 描述       |
| :--------------------------- | ------- | ---------- |
| SBI_PMU_HW_CACHE_OP_READ     | 0       | 读取缓存行 |
| SBI_PMU_HW_CACHE_OP_WRITE    | 1       | 写入缓存行 |
| SBI_PMU_HW_CACHE_OP_PREFETCH | 2       | 预取缓存行 |

_表 33. PMU 缓存操作结果 ID_

| 缓存结果名称                   | 结果 ID | 描述       |
| :----------------------------- | ------- | ---------- |
| SBI_PMU_HW_CACHE_RESULT_ACCESS | 0       | 缓存访问   |
| SBI_PMU_HW_CACHE_RESULT_MISS   | 1       | 缓存未命中 |

> 注意：对于硬件缓存事件，event_data（即事件数据）未使用，所有非零值的事件数据均保留用于将来使用。

### 11.3 事件：硬件原始事件 (Type #2)

硬件原始事件类型的 event_idx.type (i.e. event type) 值应为 0x2，而 event_idx.code(i.e. event code) 值应为零。
对于具有 32 位宽度的 mhpmeventX CSRs 的 RISC-V 平台，event_data 配置（或参数）应包含要编程到 mhpmeventX CSR 中的 32 位值。
对于具有 64 位宽度的 mhpmeventX CSRs 的 RISC-V 平台，event_data 配置（或参数）应包含要编程到 mhpmeventX CSR 的低 48 位值，而 SBI 实现将确定要编程到 mhpmeventX CSR 的高 16 位值。

> 注意：RISC-V 平台的硬件实现可能选择定义要写入 mhpmeventX CSR 的硬件事件的预期值。对于硬件常规/缓存事件，为了简化起见，RISC-V 平台的硬件实现可能使用零扩展的 event_idx 作为预期值。

### 11.4 事件：固件事件 (Type #15)

所有固件事件的 event_idx.type（即事件类型）应为 0xf，并且每个固件事件都由唯一的 event_idx.code（即事件代码）标识，其描述如下所示的 表 34 中。

_表 34. PMU 固件事件_

| 固件事件名称                          | 编码 | 描述                                                  |
| :------------------------------------ | ---- | ----------------------------------------------------- |
| SBI_PMU_FW_MISALIGNED_LOAD            | 0    | 对齐错误加载陷入事件                                  |
| SBI_PMU_FW_MISALIGNED_STORE           | 1    | 对齐错误存储陷入事件                                  |
| SBI_PMU_FW_ACCESS_LOAD                | 2    | 加载访问陷入事件                                      |
| SBI_PMU_FW_ACCESS_STORE               | 3    | 存储访问陷入事件                                      |
| SBI_PMU_FW_ILLEGAL_INSN               | 4    | 非法指令陷入事件                                      |
| SBI_PMU_FW_SET_TIMER                  | 5    | 设置定时器事件                                        |
| SBI_PMU_FW_IPI_SENT                   | 6    | 发送 IPI 给其他 HART 事件                             |
| SBI_PMU_FW_IPI_RECEIVED               | 7    | 接收来自其他 HART 的 IPI 事件                         |
| SBI_PMU_FW_FENCE_I_SENT               | 8    | 发送 FENCE.I 请求给其他 HART 事件                     |
| SBI_PMU_FW_FENCE_I_RECEIVED           | 9    | 接收来自其他 HART 的 FENCE.I 请求事件                 |
| SBI_PMU_FW_SFENCE_VMA_SENT            | 10   | 发送 SFENCE.VMA 请求给其他 HART 事件                  |
| SBI_PMU_FW_SFENCE_VMA_RECEIVED        | 11   | 接收来自其他 HART 的 SFENCE.VMA 请求事件              |
| SBI_PMU_FW_SFENCE_VMA_ASID_SENT       | 12   | 发送带有 ASID 的 SFENCE.VMA 请求给其他 HART 事件      |
| SBI_PMU_FW_SFENCE_VMA_ASID_RECEIVE D  | 13   | 接收来自其他 HART 的带有 ASID 的 SFENCE.VMA 请求事件  |
| SBI_PMU_FW_HFENCE_GVMA_SENT           | 14   | 发送 HFENCE.GVMA 请求给其他 HART 事件                 |
| SBI_PMU_FW_HFENCE_GVMA_RECEIVED       | 15   | 接收来自其他 HART 的 HFENCE.GVMA 请求事件             |
| SBI_PMU_FW_HFENCE_GVMA_VMID_SENT      | 16   | 发送带有 VMID 的 HFENCE.GVMA 请求给其他 HART 事件     |
| SBI_PMU_FW_HFENCE_GVMA_VMID_RECEI VED | 17   | 接收来自其他 HART 的带有 VMID 的 HFENCE.GVMA 请求事件 |
| SBI_PMU_FW_HFENCE_VVMA_SENT           | 18   | 发送 HFENCE.VVMA 请求给其他 HART 事件                 |
| SBI_PMU_FW_HFENCE_VVMA_RECEIVED       | 19   | 接收来自其他 HART 的 HFENCE.VVMA 请求事件             |
| SBI_PMU_FW_HFENCE_VVMA_ASID_SENT      | 20   | 向其他 HART 发送带有 ASID 的 HFENCE.VVMA 请求事件     |
| SBI_PMU_FW_HFENCE_VVMA_ASID_RECEIV ED | 21   | R 从其他 HART 接收带有 ASID 的 HFENCE.VVMA 请求事件   |

> 注意：对于固件事件，event_data（即事件数据）未使用，所有非零的 event_data 值都保留供将来使用。

### 11.5 函数：获取可用计数器的数量 (FID #0)

```
struct sbiret sbi_pmu_num_counters()
```

**返回**可用计数器的数量到 sbiret.value 中，并始终在 sbiret.error 中返回 SBI_SUCCESS。

### 11.6 函数：获取特定计数器的详细信息 (FID #1)

```
struct sbiret sbi_pmu_counter_get_info(unsigned long counter_idx)
```

获取有关指定计数器的详细信息，例如底层 CSR 编号、计数器的宽度、计数器的类型（硬件/固件）等。
此 SBI 调用返回的 counter_info 信息编码如下：

```
counter_info[11:0] = CSR (12bit CSR number)
counter_info[17:12] = Width (One less than number of bits in CSR)
counter_info[XLEN-2:18] = Reserved for future use counter_info[XLEN-1] = Type (0 = hardware and 1 = firmware)
```

若 counter_info.type == 1，那么 counter_info.csr 与 counter_info.width 应该被忽略。
在 sbiret.value 中返回上述描述的 counter_info。
sbiret.error 中可能返回的错误代码如下表 35 所示。

_表 35. PMU 计数器获取信息错误_

| 错误代码              | 描述                         |
| :-------------------- | ---------------------------- |
| SBI_SUCCESS           | 成功读取 counter_info        |
| SBI_ERR_INVALID_PARAM | counter_idx 指向无效的计数器 |

### 11.7 函数：查找并配置匹配计数器 (FID #2)

```
struct sbiret sbi_pmu_counter_config_matching(unsigned long counter_idx_base,
unsigned long counter_idx_mask, unsigned long config_flags, unsigned long  event_idx, uint64_t event_data)
```

在一组计数器中查找并配置一个尚未启动（或已启用）且可以监视指定事件的计数器。其中，counter_idx_base 和 counter_idx_mask 参数表示计数器集合，event_idx 表示要监视的事件，event_data 表示任何附加事件配置。
config_flags 参数表示额外的计数器配置和过滤标志。config_flags 参数的位定义如下所示：

_表 36. PMU 计数器配置匹配标志_

| 标志名称                     | 位         | 描述                                 |
| :--------------------------- | ---------- | ------------------------------------ |
| SBI_PMU_CFG_FLAG_SKIP_MATCH  | 0:0        | 跳过计数器匹配                       |
| SBI_PMU_CFG_FLAG_CLEAR_VALUE | 1:1        | 在计数器配置中清零（或置零）计数器值 |
| SBI_PMU_CFG_FLAG_AUTO_START  | 2:2        | 配置匹配计数器后自动启动计数器       |
| SBI_PMU_CFG_FLAG_SET_VUINH   | 3:3        | VU 模式下禁止事件计数                |
| SBI_PMU_CFG_FLAG_SET_VSINH   | 4:4        | VS 模式下禁止事件计数                |
| SBI_PMU_CFG_FLAG_SET_UINH    | 5:5        | U 模式下禁止事件计数                 |
| SBI_PMU_CFG_FLAG_SET_SINH    | 6:6        | S 模式下禁止事件计数                 |
| SBI_PMU_CFG_FLAG_SET_MINH    | 7:7        | M 模式下禁止事件计数                 |
| RESERVED                     | 8:(XLEN-1) | 所有非零值保留供将来使用             |

> 注意：当在 config_flags 中设置了 SBI_PMU_CFG_FLAG_SKIP_MATCH 标志时，SBI 实现将无条件地从由 counter_idx_base 和 counter_idx_mask 指定的计数器集合中选择第一个计数器。

> 注意：config_flags 中的 SBI_PMU_CFG_FLAG_AUTO_START 标志对计数器值没有影响。

> 注意：config_flags[3:7] 位是事件过滤提示，因此在安全性方面或由于底层 RISC-V 平台缺乏事件过滤支持时，SBI 实现可能会忽略或覆盖这些提示。
> 成功时，在 sbiret.value 中返回 counter_idx。
> 如果操作失败，在 sbiret.error 中可能返回的错误代码如下表 37 所示：

_表 37. PMU 计数器配置匹配错误_

| 错误代码              | 描述                             |
| :-------------------- | -------------------------------- |
| SBI_SUCCESS           | 计数器已成功找到并配置           |
| SBI_ERR_INVALID_PARAM | 计数器集合中存在无效的计数器     |
| SBI_ERR_NOT_SUPPORTED | 没有任何计数器能够监视指定的事件 |

### 11.8 函数：启动一组计数器 (FID #3)

```
struct sbiret sbi_pmu_counter_start(unsigned long counter_idx_base, unsigned long counter_idx_mask,
unsigned long start_flags, uint64_t initial_value)
```

启动或启用一组计数器，并设置指定的初始值。counter_idx_base 和 counter_idx_mask 参数表示计数器集合，initial_value 参数指定计数器的初始值。
start_flags 参数的位定义如下表 38 所示：

_表 38. PMU 计数器启动标志_

| 标志名称                     | 位         | 描述                                            |
| :--------------------------- | ---------- | ----------------------------------------------- |
| SBI_PMU_START_SET_INIT_VALUE | 0:0        | parameter 根据 initial_value 参数设置计数器的值 |
| RESERVED                     | 1:(XLEN-1) | 所有非零值保留供将来使用                        |

> 注意：当 start_flags 中未设置 SBI_PMU_START_SET_INIT_VALUE 时，计数器值不会被修改，并且事件计数将从当前计数器值开始。
> sbiret.error 中可能返回的错误代码在下表表 39 中列出。

_表 39. PMU 计数器启动错误_

| 错误代码                | 描述                           |
| :---------------------- | ------------------------------ |
| SBI_SUCCESS             | 计数器启动成功                 |
| SBI_ERR_INVALID_PARAM   | 参数中指定的一些计数器无效     |
| SBI_ERR_ALREADY_STARTED | 参数中指定的一些计数器已被启动 |

### 11.9 函数：停止或禁用一组计数器 (FID #4)

```
struct sbiret sbi_pmu_counter_stop(unsigned long counter_idx_base,
unsigned long counter_idx_mask, unsigned long stop_flags)
```

停止或禁用调用 HART 上的一组计数器。counter_idx_base 和 counter_idx_mask 参数表示计数器的集合。stop_flags 参数的位定义如下表 40 所示。

_表 40. PMU 计数器停止禁用标志_

| 标志名称                | 位         | 描述                       |
| :---------------------- | ---------- | -------------------------- |
| SBI_PMU_STOP_FLAG_RESET | 0:0        | 重置计数器到事件的映射关系 |
| RESERVED                | 1:(XLEN-1) | 所有非零值都保留供将来使用 |

返回在 sbiret.error 中可能出现的错误代码如下表 41 所示。

_表 41. PMU 计数器停止禁用错误_

| 错误代码                | 描述                     |
| :---------------------- | ------------------------ |
| SBI_SUCCESS             | 计数器禁用成功           |
| SBI_ERR_INVALID_PARAM   | 指定的某些计数器无效     |
| SBI_ERR_ALREADY_STOPPED | 指定的某些计数器已经停止 |

### 11.10 函数：读取固件计数器 (FID #5)

```
struct sbiret sbi_pmu_counter_fw_read(unsigned long counter_idx)
```

在 sbiret.value 中提供固件计数器的当前值。
sbiret.error 中返回的可能错误代码如下表 42 所示。

_表 42. PMU 读取固件计数错误_

| 错误代码              | 描述                                           |
| :-------------------- | ---------------------------------------------- |
| SBI_SUCCESS           | 成功读取固件计数器的值。                       |
| SBI_ERR_INVALID_PARAM | counter_idx 指向一个硬件计数器或无效的计数器。 |

### 11.11 函数：读取固件计数器的高位 (FID #6)

```
struct sbiret sbi_pmu_counter_fw_read_hi(unsigned long counter_idx)
```

在 sbiret.value 中提供当前固件计数器值的前 32 位。对于 RV64（或更高）系统，此函数在 sbiret.value 中总是返回 0。

在 sbiret.error 中返回的可能的错误代码显示在下面的表 43 中。

*表 43. PMU 计数器固件读高错误*

| 错误代码              | 描述                                             |
| :-------------------- | :----------------------------------------------- |
| SBI_SUCCESS           | 固件计数器读取成功                               |
| SBI_ERR_INVALID_PARAM | counter_idx 指向一个硬件计数器或一个无效的计数器 |

### 11.12 函数：启用 PMU 快照功能 (FID #7)

```
struct sbiret sbi_pmu_snapshot_set_shmem(unsigned long shmem_phys_lo,   unsigned long shmem_phys_hi)
```

为 PMU 状态快照设置共享内存区域。shmem_phys_lo 指定共享内存物理地址的低 XLEN 位，shmem_phys_hi 指定共享内存物理地址的高 XLEN 位。shmem_phys_lo 必须是 4096 字节（即页面）对齐。共享内存的大小必须是 4096 字节。共享内存的布局在表 44 中描述。

*表 44. SBI PMU 快照共享内存布局*

| 名称                    | 偏移量 | 大小 | 描述                                                                                     |
| :---------------------- | :----- | :--- | :--------------------------------------------------------------------------------------- |
| counter_overflow_bitmap | 0x0000 | 8    | 一个所有逻辑溢出计数器的位图。只有在 Sscofpmf ISA 扩展可用时，它才有效。否则，它必须为零 |
| counter_values          | 0x0008 | 512  | 一个 64 位逻辑计数器的数组，每个索引代表与硬件/固件相关的每个逻辑计数器的值              |
| Reserved                | 0x0208 | 3576 | 保留给未来使用                                                                           |

今后对这一结构的任何修订都应以向后兼容的方式进行，并将与 SBI 的一个版本相关。

这个函数应该在启动时每个 Hart 只被调用一次。一旦配置好，当 sbi_pmu_counter_stop 被调用并设置了 SBI_PMU_STOP_FLAG_TAKE_SNAPSHOT 标志时，SBI 实现可以对共享内存进行读/写访问。当 sbi_pmu_counter_start 被调用并设置了 SBI_PMU_START_FLAG_INIT_SNAPSHOT 标记时，SBI 实现有只读访问权。SBI 实现不得在其他时间访问该内存。

在 sbiret.error 中返回的可能的错误代码如下表 45 所示。

*表 45. PMU 设置快照区的错误*

| 错误代码                | 描述                                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------------ |
| SBI_SUCCESS             | 固件计数器读取成功                                                                         |
| SBI_ERR_INVALID_ADDRESS | shmem_phys_lo 和 shmem_phys_hi 参数所指向的共享内存是不可写的，或者不满足 3.2 节的其他要求 |

### 11.13 函数列表

_表 46. PMU 函数列表_

| 函数名                          | SBI 版本 | FID | EID      |
| :------------------------------ | -------- | --- | -------- |
| sbi_pmu_num_counters            | 0.3      | 0   | 0x504D55 |
| sbi_pmu_counter_get_info        | 0.3      | 1   | 0x504D55 |
| sbi_pmu_counter_config_matching | 0.3      | 2   | 0x504D55 |
| sbi_pmu_counter_start           | 0.3      | 3   | 0x504D55 |
| sbi_pmu_counter_stop            | 0.3      | 4   | 0x504D55 |
| sbi_pmu_counter_fw_read         | 0.3      | 5   | 0x504D55 |
| sbi_pmu_counter_fw_read_hi      | 2.0      | 6   | 0x504D55 |
| sbi_pmu_snapshot_set_shmem      | 2.0      | 7   | 0x504D55 |

## 章节 12. 调试控制台扩展 (EID #0x4442434E "DBCN")

调试控制台扩展定义了一种通用机制，用于在监管模式软件中进行调试以及引导过程中的早期打印输出。

这个扩展取代了传统的控制台 putchar（EID #0x01）和控制台 getchar（EID #0x02）扩展。调试控制台扩展允许监督者模式的软件在一次 SBI 调用中写入或读取多个字节。

如果底层物理控制台有额外的位用于错误检查（或纠正），那么这些额外的位应该由 SBI 实现来处理。

> 注意：建议使用调试控制台扩展发送/接收的字节遵循 UTF-8 字符编码。

### 12.1 函数：控制台写入 (FID #0)

```
struct sbiret sbi_debug_console_write(unsigned long num_bytes,   unsigned long base_addr_lo,   unsigned long base_addr_hi)
```

从输入存储器向调试控制台写入字节。

num_bytes 参数指定了输入存储器中的字节数。输入存储器的物理基址由两个 XLEN 位宽的参数表示。base_addr_lo 参数指定输入存储器物理基址的低 XLEN 位，base_addr_hi 参数指定输入存储器的高 XLEN 位。

这是一个非阻塞的 SBI 调用，如果调试台不能接受更多的字节，它可能会做部分/不写。

写入的字节数在 sbiret.value 中返回，可能的错误代码在 sbiret.error 中返回，如下表 47 所示。

*表 47. 调试控制台写入错误*

| 错误代码              | 描述                                                                                |
| :-------------------- | :---------------------------------------------------------------------------------- |
| SBI_SUCCESS           | 成功写入的字节数                                                                    |
| SBI_ERR_INVALID_PARAM | num_bytes、base_addr_lo 和 base_addr_hi 参数所指向的内存不满足第 3.2 节中描述的要求 |
| SBI_ERR_FAILED        | 由于 I/O 错误，写入失败                                                             |

### 12.2 函数：控制台读取 (FID #1)

```
struct sbiret sbi_debug_console_read(unsigned long num_bytes,   unsigned long base_addr_lo,   unsigned long base_addr_hi)
```

从调试控制台读取字节到一个输出存储器。

num_bytes 参数规定了可以写入输出存储器的最大字节数。输出存储器的物理基址由两个 XLEN 位宽的参数表示。base_addr_lo 参数指定输出存储器物理基址的低 XLEN 位，base_addr_hi 参数指定输出存储器的高 XLEN 位。

这是一个非阻塞的 SBI 调用，如果在调试控制台上没有要读的字节，它就不会向输出内存写任何东西。

读取的字节数在 sbiret.value 中返回，可能的错误代码在 sbiret.error 中返回，如下表 48 所示。

*表 48. 调试控制台读取错误*

| 错误代码              | 描述                                                                                |
| :-------------------- | :---------------------------------------------------------------------------------- |
| SBI_SUCCESS           | 成功读取的字节数                                                                    |
| SBI_ERR_INVALID_PARAM | num_bytes、base_addr_lo 和 base_addr_hi 参数所指向的内存不满足第 3.2 节中描述的要求 |
| SBI_ERR_FAILED        | 由于 I/O 错误，读取失败                                                             |

### 12.3 函数：控制台写字节 (FID #2)

```
struct sbiret sbi_debug_console_write_byte(uint8_t byte)
```

写一个单字节到调试控制台。

这是一个阻塞的 SBI 调用，它只在将指定的字节写入调试控制台后返回。如果有 I/O 错误，它也会以 SBI_ERR_FAILED 返回。

sbiret.value 被设置为 0，在 sbiret.error 中返回的可能的错误代码如下表 49 所示。

*表 49. 调试控制台写入字节的错误*

| 错误代码       | 描述                      |
| :------------- | ------------------------- |
| SBI_SUCCESS    | 字节写入成功              |
| SBI_ERR_FAILED | 由于 I/O 错误，写字节失败 |

### 12.4 函数列表

*表 50. DBCN 事件列表*

| 函数名                       | SBI 版本 | FID | EID        |
| :--------------------------- | :------- | :-- | :--------- |
| sbi_debug_console_write      | 2.0      | 0   | 0x4442434E |
| sbi_debug_console_read       | 2.0      | 1   | 0x4442434E |
| sbi_debug_console_write_byte | 2.0      | 2   | 0x4442434E |

## 章节 13. 系统挂起扩展 (EID #0x53555350 "SUSP")

系统挂起扩展定义了一组系统级睡眠状态和一个允许监督者模式软件请求系统过渡到睡眠状态的功能。睡眠状态由 32 位宽的标识符（sleep_type）来识别。这些标识符的可能值如表 51 所示。

术语 "系统 "指的是监督者软件的世界观。底层的 SBI 实现可以由机器模式的固件或管理程序提供。

系统挂起扩展没有为支持的睡眠类型提供任何探测方法。平台应该在其硬件描述中指定其支持的系统睡眠类型和每个类型的唤醒设备。SUSPEND_TO_RAM 睡眠类型是一个例外，它的存在是通过扩展来暗示的。

*表 51. SUSP 系统睡眠类型*

| 类型                  | 名字           | 描述                                                                                                                                                                     |
| :-------------------- | :------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0                     | SUSPEND_TO_RAM | 这是一个 "休眠到内存 "的睡眠类型，类似于 ACPI 的 S2 或 S3。进入时要求除了调用的 hart 以外的所有 hart 都处于 HSM STOPPED 状态，并且所有 hart 寄存器和 CSR 都保存在 RAM 中 |
| 0x00000001 - 0x7fffffff |                | 保留给未来使用                                                                                                                                                           |
| 0x80000000 - 0xffffffff |                | 平台特有的系统睡眠类型                                                                                                                                                   |
| > 0xffffffff          |                | 保留                                                                                                                                                                     |

### 13.1 函数：系统挂起 (FID #0)

```
struct sbiret sbi_system_suspend(uint32_t sleep_type,   unsigned long resume_addr,   unsigned long opaque)
```

sbi_system_suspend() 调用的返回意味着一个错误，表 53 中的错误代码将出现在 sbiret.error 中。一个成功的挂起和唤醒，会导致启动挂起的 hart 从 STOPPED 状态恢复。为了恢复，hart 将跳转到监督者模式，地址由 resume_addr 指定，具体寄存器值见表 52。

*表 52. SUSP 系统恢复寄存器状态*

| 寄存器名称                             | 寄存器值         |
| :------------------------------------- | :--------------- |
| satp                                   | 0                |
| sstatus.SIE                            | 0                |
| a0                                     | hartid           |
| a1                                     | opaque parameter |
| 所有其他的寄存器仍然处于未定义的状态。 |                  |

> 注意：一个无符号的长参数对 resume_addr 来说就足够了，因为在 MMU 关闭的情况下，hart 将以监督者模式恢复执行，因此 resume_addr 必须小于 XLEN 位宽。

resume_addr 参数指向一个运行时指定的物理地址，hart 可以在系统暂停后以监督者模式恢复执行。

参数 opaque 是一个 XLEN 位的值，当系统暂停后，hart 在 resume_addr 恢复执行时，这个值将被设置在 a1 寄存器中。

除了确保所选睡眠类型的所有进入标准得到满足，例如确保其他 harts 处于 STOPPED 状态，调用者必须确保所有电源单元和域处于与所选睡眠类型兼容的状态。用于从系统睡眠状态恢复的电源单元、电源域和唤醒设备的准备工作是平台特定的，超出了本规范的范围。

当主管软件在虚拟机内运行时，SBI 的实现是由管理程序提供的。系统暂停在功能上的表现与本地情况相同，但可能不会导致任何物理功率的变化。

sbiret.error 中可能返回的错误代码见表 53。

*表 53. SUSP 系统挂起的错误*

| 错误代码                | 描述                                                                                                                                               |
| :---------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------- |
| SBI_SUCCESS             | 系统已暂停并成功恢复                                                                                                                               |
| SBI_ERR_INVALID_PARAM   | sleep_type 是保留的，或者是平台特定的，未实现的                                                                                                    |
| SBI_ERR_NOT_SUPPORTED   | sleep_type 没有被保留，并且已经实现，但由于一个或多个依赖项缺失，平台不支持它                                                                      |
| SBI_ERR_INVALID_ADDRESS | resume_addr 是无效的，可能是由于以下原因：1. 它不是一个有效的物理地址。2. 对该地址的可执行访问被物理内存保护机制或监督者模式的 H-扩展 G-阶段所禁止 |
| SBI_ERR_FAILED          | 暂停请求因未指明或未知的其他原因而失败                                                                                                             |

### 13.2 函数列表

*表 54. SUSP 事件列表*

| 函数名             | SBI 版本 | FID | EID        |
| :----------------- | :------- | :-- | :--------- |
| sbi_system_suspend | 2.0      | 0   | 0x53555350 |

## 章节 14. CPPC 扩展 (EID #0x43505043 "CPPC")

ACPI 定义了协作处理器性能控制（CPPC）机制，这是一个抽象而灵活的机制，用于监督者模式的电源管理软件与平台中的实体协作，管理处理器的性能。

SBI CPPC 扩展提供了一个抽象，通过 SBI 调用访问 CPPC 寄存器。CPPC 寄存器可以是与一个单独的平台实体（如 BMC）共享的内存位置。即使 CPPC 被定义在 ACPI 规范中，也可能实现一个基于 Device Tree 的 CPPC 驱动。

表 55 定义了由 SBI CPPC 功能使用的所有 CPPC 寄存器的 32 位标识。32 位寄存器空间的前半部分与 ACPI 规范所定义的寄存器相对应。后半部分提供了 ACPI 规范中没有定义的信息，但也是监督者模式电源管理软件额外需要的。

*表 55. CPPC 寄存器*

| 寄存器 ID               | 寄存去                                | 位宽    | 属性                     | 描述                                               |
| :---------------------- | :------------------------------------ | :------ | :----------------------- | -------------------------------------------------- |
| 0x00000000              | HighestPerformance                    | 32      | Read-only                | ACPI Spec 6.5: 8.4.6.1.1.1                         |
| 0x00000001              | NominalPerformance                    | 32      | Read-only                | ACPI Spec 6.5: 8.4.6.1.1.2                         |
| 0x00000002              | LowestNonlinearPerformance            | 32      | Read-only                | ACPI Spec 6.5: 8.4.6.1.1.4                         |
| 0x00000003              | LowestPerformance                     | 32      | Read-only                | ACPI Spec 6.5: 8.4.6.1.1.5                         |
| 0x00000004              | GuaranteedPerformanceRegister         | 32      | Read-only                | ACPI Spec 6.5: 8.4.6.1.1.6                         |
| 0x00000005              | DesiredPerformanceRegister            | 32      | Read / Write             | ACPI Spec 6.5: 8.4.6.1.2.3                         |
| 0x00000006              | MinimumPerformanceRegister            | 32      | Read / Write             | ACPI Spec 6.5: 8.4.6.1.2.2                         |
| 0x00000007              | MaximumPerformanceRegister            | 32      | Read / WriteRead / Write | ACPI Spec 6.5: 8.4.6.1.2.1                         |
| 0x00000008              | PerformanceReductionToleranceRegister | 32      | Read / Write             | ACPI Spec 6.5: 8.4.6.1.2.4                         |
| 0x00000009              | TimeWindowRegister                    | 32      | Read / Write             | ACPI Spec 6.5: 8.4.6.1.2.5                         |
| 0x0000000A              | CounterWraparoundTime                 | 32 / 64 | Read-only                | ACPI Spec 6.5: 8.4.6.1.3.1                         |
| 0x0000000B              | ReferencePerformanceCounterRegister   | 32 / 64 | Read-only                | ACPI Spec 6.5: 8.4.6.1.3.1                         |
| 0x0000000C              | DeliveredPerformanceCounterRegister   | 32 / 64 | Read-only                | ACPI Spec 6.5: 8.4.6.1.3.1                         |
| 0x0000000D              | PerformanceLimitedRegister            | 32      | Read / Write             | ACPI Spec 6.5: 8.4.6.1.3.2                         |
| 0x0000000E              | CPPCEnableRegister                    | 32      | Read / Write             | ACPI Spec 6.5: 8.4.6.1.4                           |
| 0x0000000F              | AutonomousSelectionEnable             | 32      | Read / Write             | ACPI Spec 6.5: 8.4.6.1.5                           |
| 0x00000010              | AutonomousActivityWindowRegister      | 32      | Read / Write             | ACPI Spec 6.5: 8.4.6.1.6                           |
| 0x00000011              | EnergyPerformancePreferenceRegister   | 32      | Read / Write             | ACPI Spec 6.5: 8.4.6.1.7                           |
| 0x00000012              | ReferencePerformance                  | 32      | Read-only                | ACPI Spec 6.5: 8.4.6.1.1.3                         |
| 0x00000013              | LowestFrequency                       | 32      | Read-only                | ACPI Spec 6.5: 8.4.6.1.1.7                         |
| 0x00000014              | NominalFrequency                      | 32      | Read-only                | ACPI Spec 6.5: 8.4.6.1.1.7                         |
| 0x00000015 - 0x7FFFFFFF |                                       | 32      |                          | 保留给未来使用                                     |
| 0x80000000              | TransitionLatency                     | 32      | Read-only                | 提供以纳秒为单位的最大（最坏情况）性能状态转换延迟 |
| 0x80000001 - 0xFFFFFFFF |                                       | 32      |                          | 保留给未来使用                                     |

### 14.1. 函数：探测 CPPC 寄存器 (FID #0)

```
struct sbiret sbi_cppc_probe(uint32_t cppc_reg_id)
```

探测由 cppc_reg_id 参数指定的 CPPC 寄存器是否被平台实现。

如果寄存器被实现，sbiret.value 将包含寄存器的宽度。如果寄存器没有实现，sbiret.value 将被设置为 0。

在 sbiret.error 中返回的可能的错误代码如表 56 所示。

*表 56. CPPC 探测错误*

| 错误代码              | 描述                                     |
| :-------------------- | :--------------------------------------- |
| SBI_SUCCESS           | 探测成功完成                             |
| SBI_ERR_INVALID_PARAM | cppc_reg_id 被保留                       |
| SBI_ERR_FAILED        | 探测请求因未指明的或未知的其他原因而失败 |

### 14.2 函数：读 CPPC 寄存器 (FID #1)

```
struct sbiret sbi_cppc_read(uint32_t cppc_reg_id)
```

读取 cppc_reg_id 参数中指定的寄存器，并在 sbiret.value 中返回数值。当监督者模式 XLEN 为 32 时，sbiret.value 将只包含 CPPC 寄存器值的低 32 位。

sbiret.error 中可能返回的错误代码见表 57。

*表 57. CPPC 读错误*

| 错误代码              | 描述                                     |
| :-------------------- | :--------------------------------------- |
| SBI_SUCCESS           | 读取已成功完成                           |
| SBI_ERR_INVALID_PARAM | cppc_reg_id 被保留                       |
| SBI_ERR_NOT_SUPPORTED | cppc_reg_id 没有被平台实现               |
| SBI_ERR_DENIED        | cppc_reg_id 是一个只写的寄存器           |
| SBI_ERR_FAILED        | 读取请求因未指定的或未知的其他原因而失败 |

### 14.3 函数：读取 CPPC 寄存器高位 (FID #2)

```
struct sbiret sbi_cppc_read_hi(uint32_t cppc_reg_id)
```

读取参数 cppc_reg_id 中指定的寄存器的高 32 位的值，并在 sbiret.value 中返回该值。当主管模式 XLEN 为 64 或更高时，该函数在 sbiret.value 中总是返回 0。

sbiret.error 中可能返回的错误代码见表 58。

*表 58. CPPC 读高位错误*

| 错误代码              | 描述                                     |
| :-------------------- | :--------------------------------------- |
| SBI_SUCCESS           | 读取已成功完成                           |
| SBI_ERR_INVALID_PARAM | cppc_reg_id 被保留                       |
| SBI_ERR_NOT_SUPPORTED | cppc_reg_id 没有被平台实现               |
| SBI_ERR_DENIED        | cppc_reg_id 是一个只写的寄存器           |
| SBI_ERR_FAILED        | 读取请求因未指定的或未知的其他原因而失败 |

### 14.4 函数：写 CPPC 寄存器 (FID #3)

```
struct sbiret sbi_cppc_write(uint32_t cppc_reg_id, uint64_t val)
```

将参数 val 中传递的值写到 cppc_reg_id 参数指定的寄存器中。

sbiret.error 中可能返回的错误代码见表 59。

*表 59. CPPC 写错误*

| 错误代码              | 描述                                     |
| :-------------------- | :--------------------------------------- |
| SBI_SUCCESS           | 写入已成功完成                           |
| SBI_ERR_INVALID_PARAM | cppc_reg_id 被保留                       |
| SBI_ERR_NOT_SUPPORTED | cppc_reg_id 没有被平台实现               |
| SBI_ERR_DENIED        | cppc_reg_id 是一个只读的寄存器           |
| SBI_ERR_FAILED        | 读取请求因未指定的或未知的其他原因而失败 |

### 14.5 函数列表

*表 60. CPPC 函数列表*

| 函数名           | SBI 版本 | FID | EID        |
| :--------------- | :------- | :-- | :--------- |
| sbi_cppc_probe   | 2.0      | 0   | 0x43505043 |
| sbi_cppc_read    | 2.0      | 1   | 0x43505043 |
| sbi_cppc_read_hi | 2.0      | 2   | 0x43505043 |
| sbi_cppc_write   | 2.0      | 3   | 0x43505043 |

## 章节 15. 嵌套加速扩展 (EID #0x4E41434C "NACL")

嵌套虚拟化是指一个虚拟化监控程序能够作为宿主客户机来运行另一个虚拟化监控程序的能力。RISC-V 嵌套虚拟化需要一个 L0 虚拟化监控程序（以虚拟化监控模式运行）来捕获并模拟 RISC-V H 扩展功能（如 CSR 访问、HFENCE 指令、HLV/HSV 指令等），以供 L1 虚拟化监控程序（以虚拟化监督者模式运行）使用。

SBI 嵌套加速扩展定义了 SBI 实现（或 L0 虚拟化监控程序）与监督者模式软件（或 L1 虚拟化监控程序）之间基于共享内存的接口，可以让两者协作减少 L0 虚拟化监控程序用于模拟 RISC-V H 扩展功能的陷入。嵌套加速共享内存允许 L1 虚拟化监控程序批量处理多个 RISC-V H 扩展 CSR 访问和 HFENCE 请求，然后通过显式同步的 SBI 调用由 L0 虚拟化监控程序进行模拟。

> 注意：如果底层平台已经在硬件中实现了 RISC-V H 扩展，M 模式固件不应该实现 SBI 嵌套加速扩展。

该 SBI 扩展定义了一些可选的特性，必须由监督者模式软件（或 L1 虚拟化监控程序）在使用相应的 SBI 函数之前进行发现。每个嵌套加速的特性都被分配一个唯一的 ID，该 ID 是一个无符号 32 位整数。下面的表 61 列出了所有的嵌套加速特性。

*表 61. 嵌套加速功能*

| 特性 ID     | 特性名称                   | 描述           |
| :---------- | :------------------------- | :------------- |
| 0x00000000  | SBI_NACL_FEAT_SYNC_CSR     | 同步 CSR       |
| 0x00000001  | SBI_NACL_FEAT_SYNC_HFENCE  | 同步 HFENCE    |
| 0x00000002  | SBI_NACL_FEAT_SYNC_SRET    | 同步 SRET      |
| 0x00000003  | SBI_NACL_FEAT_AUTOSWAP_CSR | 自动交换 CSR   |
| >0x00000003 | RESERVED                   | 保留给未来使用 |

为了使用 SBI 嵌套加速扩展，监督者模式软件（或 L1 虚拟化监控程序）在启动时必须为每个虚拟 hart 设置嵌套加速共享内存的物理地址。嵌套加速共享内存的物理基地址必须是 4096 字节（即一页）对齐，而嵌套加速共享内存的大小假设为 4096 + (1024 * (XLEN / 8)) 字节。下面的表 62 展示了嵌套加速共享内存的布局。

*表 62. 嵌套加速的共享内存布局*

| 名称          | 偏移量     | 大小（byte） | 描述                                                                                                                       |
| :------------ | :--------- | ------------ | :------------------------------------------------------------------------------------------------------------------------- |
| Scratch space | 0x00000000 | 4096         | 嵌套加速特性的具体数据                                                                                                     |
| CSR space     | 0x00001000 | XLEN * 128   | 一个由 1024 个 XLEN 位字组成的数组，每个字对应于 RISC-V 特权规范表 2.1 中定义的可能的 RISC-V H-extension CSR |

上面表格 62 中所示的暂存空间的内容对于每个嵌套加速特性是单独定义的。

上面表格 62 中 CSR 空间的内容是 RISC-V H 扩展 CSR 值的数组，其中 CSR 寄存器 `<x>` 在索引 `<i>` = ((`<x>` & 0xc00) >> 2) | (`<x>` & 0xff) 处。除非某些嵌套加速特性定义了不同的行为，否则 SBI 实现（或 L0 虚拟化监控程序）在任何 RISC-V H 扩展 CSR 状态改变时必须更新 CSR 空间。下面的表格 63 显示了所有可能的 1024 个 RISC-V H 扩展 CSR 的 CSR 空间索引范围。

*表 63. 嵌套加速 H-扩展 CSR 指数范围*

<table>
	<tbody>
		<tr>
			<td colspan="4">H-extension CSR address</td>
			<td colspan="1">SBI NACL CSR space index</td>
		</tr>
		<tr>
			<td>[11:10]</td>
			<td>[9:8]</td>
			<td>[7:4]</td>
			<td>Hex Range</td>
			<td>Hex Range</td>
		</tr>
		<tr>
			<td>00</td>
			<td>10</td>
			<td>xxxx</td>
			<td>0x200 - 0x2ff</td>
			<td>0x000 - 0x0ff</td>
		</tr>
		<tr>
			<td>01</td>
			<td>10</td>
			<td>0xxx</td>
			<td>0x600 - 0x67f</td>
			<td>0x100 - 0x17f</td>
		</tr>
		<tr>
			<td>01</td>
			<td>10</td>
			<td>10xx</td>
			<td>0x680 - 0x6bf</td>
			<td>0x180 - 0x1bf</td>
		</tr>
		<tr>
			<td>01</td>
			<td>10</td>
			<td>11xx</td>
			<td>0x6c0 - 0x6ff</td>
			<td>0x1c0 - 0x1ff</td>
		</tr>
		<tr>
			<td>10</td>
			<td>10</td>
			<td>0xxx</td>
			<td>0xa00 - 0xa7f</td>
			<td>0x200 - 0x27f</td>
		</tr>
		<tr>
			<td>10</td>
			<td>10</td>
			<td>10xx</td>
			<td>0xa80 - 0xabf</td>
			<td>0x280 - 0x2bf</td>
		</tr>
		<tr>
			<td>10</td>
			<td>10</td>
			<td>11xx</td>
			<td>0xac0 - 0xaff</td>
			<td>0x2c0 - 0x2ff</td>
		</tr>
		<tr>
			<td>11</td>
			<td>10</td>
			<td>0xxx</td>
			<td>0xe00 - 0xe7f</td>
			<td>0x300 - 0x37f</td>
		</tr>
		<tr>
			<td>11</td>
			<td>10</td>
			<td>10xx</td>
			<td>0xe80 - 0xebf</td>
			<td>0x380 - 0x3bf</td>
		</tr>
		<tr>
			<td>11</td>
			<td>10</td>
			<td>11xx</td>
			<td>0xec0 - 0xeff</td>
			<td>0x3c0 - 0x3ff</td>
		</tr>
	</tbody>
</table>

### 15.1 特性：同步 CSR (ID #0)

同步 CSR 特性描述的是 SBI 实现（或 L0 虚拟化监控程序）允许监督者模式软件（或 L1 虚拟化监控程序）使用 CSR 空间来编写 RISC-V H 扩展 CSR 的能力。

嵌套加速特性将范围为 0x0F80 - 0x0FFF（128 字节）的空闲空间定义为嵌套 CSR 脏位图。嵌套 CSR 脏位图为每个可能的 RISC-V H 扩展 CSR 包含了 1 位。

要在嵌套加速共享内存中写入 CSR，监督者模式软件（或 L1 虚拟化监控程序）必须执行以下操作：

1. 计算 `<i>` = ((`<x>` & 0xc00) >> 2) | (`<x>` & 0xff)
2. 在 CSR 空间中的索引为 `<i>` 的字位置写入新的 CSR 值。
3. 设置嵌套 CSR 脏位图中的第 `<i>` 位。

要同步 CSR `<x>`，SBI 实现（或 L0 虚拟化监控程序）必须执行以下操作：

1. 计算 `<i>` = ((`<x>` & 0xc00) >> 2) | (`<x>` & 0xff)
2. 如果嵌套 CSR 脏位图中的第 `<i>` 位未被设置，则跳转到步骤 5。
3. 使用 CSR 空间中索引为 `<i>` 的字中的新 CSR 值，来模拟写入 CSR `<x>`。
4. 在嵌套的 CSR 脏位图中清除 `<i>` 位。
5. 将 CSR `<x>` 的最新值写回到 CSR 空间中索引为 `<i>` 的单词中。

在同步多个 CSR 时，如果 CSR `<y>` 的值取决于其他 CSR `<x>` 的值，则 SBI 实现（或 L0 虚拟化监视程序）必须在 CSR `<y>` 之前同步 CSR `<x>`。例如，CSR hip 的值取决于 CSR hvip 的值，这意味着首先模拟和写入 hvip，然后再写入 hip。

### 15.2 特性：同步 HFENCE (ID #1)

对于 synchronize HFENCE 特性的描述，它说明了 SBI 实现（或 L0 虚拟化监控程序）允许监督者软件（或 L1 虚拟化监控程序）通过临时空间发出 HFENCE 指令的能力。

该嵌套加速特性将临时空间偏移范围 0x0800 - 0x0F7F（1920 字节）定义为嵌套 HFENCE 条目的数组。嵌套 HFENCE 条目的总数为 3840 / XLEN，其中每个嵌套 HFENCE 条目由四个 XLEN 位的字组成。

嵌套的 HFENCE 条目相当于在一定范围的客户机地址上进行的 HFENCE 操作。下表 64 显示了嵌套 HFENCE 条目的格式，而下表 65 提供了嵌套 HFENCE 条目类型的列表。在监督者软件（或 L1 虚拟化监控程序）显式发出同步 HFENCE 请求时，SBI 实现（或 L0 虚拟化监控程序）将处理具有 Config.Pending 位设置的嵌套 HFENCE 条目。在处理挂起的嵌套 HFENCE 条目后，SBI 实现（或 L0 虚拟化监控程序）将清除这些条目的 Config.Pending 位。

*表 64. 嵌套的 HFENCE 条目格式*

| 字 | 名称        | 编码                                                                                                                                                                                                                                                                                                                                                                                                                               |
| :- | :---------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0  | Config      | 关于嵌套 HFENCE 条目的配置信息<br />BIT[XLEN-1:XLEN-1] - 待定<br />BIT[XLEN-2:XLEN-4] - 保留，必须为零<br />BIT[XLEN-5:XLEN-8] - 类型<br />BIT[XLEN-9:XLEN-9] - 保留，必须为零<br />BIT[XLEN-10:XLEN-16] - 顺序<br />if XLEN == 32 then<br />    BIT[15:9] - VMID<br />    BIT[8:0] - ASID<br />else<br />    BIT[29:16] - VMID<br />    BIT[15:0] - ASID<br /><br />假设失效的页面大小为 1 << (Config.Order + 12) 字节 |
| 1  | Page_Number | 页地址右移 Config.Order + 12 位                                                                                                                                                                                                                                                                                                                                                                                                    |
| 2  | Reserved    | 保留用于将来使用，必须为零                                                                                                                                                                                                                                                                                                                                                                                                         |
| 3  | Page_Count  | 需要使无效的页面数量                                                                                                                                                                                                                                                                                                                                                                                                               |

*表 65. 嵌套的 HFENCE 条目类型*

| 类型 | 名称          | 描述                                                                                                                                            |
| :--- | :------------ | :---------------------------------------------------------------------------------------------------------------------------------------------- |
| 0    | GVMA          | 在所有 VMID 中使一个客户机物理地址范围失效。配置字的 VMID 和 ASID 字段将被忽略且必须为零                                                        |
| 1    | GVMA_ALL      | 使所有 VMID 中的所有客户机物理地址失效。配置字的 Order、VMID 和 ASID 字段将被忽略且必须为零。Page_Number 和 Page_Count 两个字将被忽略且必须为零 |
| 2    | GVMA_VMID     | 使特定 VMID 的客户机物理地址范围失效。配置字的 ASID 字段将被忽略且必须为零                                                                      |
| 3    | GVMA_VMID_ALL | 使特定 VMID 的所有客户机物理地址失效。配置字的 Order 和 ASID 字段将被忽略且必须为零。Page_Number 和 Page_Count 两个字将被忽略且必须为零         |
| 4    | VVMA          | 使特定 VMID 的客户机虚拟地址范围失效。配置字的 ASID 字段将被忽略且必须为零                                                                      |
| 5    | VVMA_ALL      | 使特定 VMID 的所有客户机虚拟地址失效。配置字的 Order 和 ASID 字段将被忽略且必须为零。Page_Number 和 Page_Count 两个字将被忽略且必须为零         |
| 6    | VVMA_ASID     | 使特定 VMID 和 ASID 的客户机虚拟地址范围失效                                                                                                    |
| 7    | VVMA_ASID_ALL | 使特定 VMID 和 ASID 的所有客户机虚拟地址失效。配置字的 Order 字段将被忽略且必须为零。Page_Number 和 Page_Count 两个字将被忽略且必须为零         |
| >7   | Reserved      | 保留以备将来使用                                                                                                                              |

要添加一个嵌套的 HFENCE 条目，监督者软件（或 L1 虚拟化监控程序）必须执行以下操作：

1. 找到一个未使用的嵌套 HFENCE 条目，其中 Config.Pending == 0。
2. 更新嵌套的 HFENCE 条目中的 Page_Number 和 Page_Count 两个字。
3. 更新嵌套 HFENCE 条目中的配置字，以设置 Config.Pending 位。

若要同步一个嵌套的 HFENCE 条目，SBI 实现（或 L0 虚拟化监控程序）必须执行以下操作：

1. 如果 Config.Pending == 0，则不执行任何操作并跳过下面的步骤。
2. 根据嵌套 HFENCE 条目中的详细信息处理 HFENCE。
3. 清除嵌套 HFENCE 条目中的 Config.Pending 位。

### 15.3 特性：同步 SRET (ID #2)

同步 SRET 特性描述了 SBI 实现（或 L0 虚拟化监控程序）在嵌套加速共享内存中对监督者软件（或 L1 虚拟化监控程序）进行 CSR 和 HFENCE 同步，并进行 SRET 模拟的能力。

这个嵌套加速特性将临时空间的偏移范围定义为 0x0000 - 0x01FF（512 个字节），用作嵌套的 SRET 上下文。下表 66 展示了嵌套 SRET 上下文的内容。

*表 66. 嵌套的 SRET 上下文*

| 偏移            | 名称     | 编码                       |
| :-------------- | :------- | :------------------------- |
| 0 * (XLEN / 8)  | Reserved | 保留以备将来使用，必须为零 |
| 1 * (XLEN / 8)  | X1       | 在 GPR X1 中要恢复的值     |
| 2 * (XLEN / 8)  | X2       | 在 GPR X2 中要恢复的值     |
| 3 * (XLEN / 8)  | X3       | 在 GPR X3 中要恢复的值     |
| 4 * (XLEN / 8)  | X4       | 在 GPR X4 中要恢复的值     |
| 5 * (XLEN / 8)  | X5       | 在 GPR X5 中要恢复的值     |
| 6 * (XLEN / 8)  | X6       | 在 GPR X6 中要恢复的值     |
| 7 * (XLEN / 8)  | X7       | 在 GPR X7 中要恢复的值     |
| 8 * (XLEN / 8)  | X8       | 在 GPR X8 中要恢复的值     |
| 9 * (XLEN / 8)  | X9       | 在 GPR X9 中要恢复的值     |
| 10 * (XLEN / 8) | X10      | 在 GPR X10 中要恢复的值    |
| 11 * (XLEN / 8) | X11      | 在 GPR X11 中要恢复的值    |
| 12 * (XLEN / 8) | X12      | 在 GPR X12 中要恢复的值    |
| 13 * (XLEN / 8) | X13      | 在 GPR X13 中要恢复的值    |
| 14 * (XLEN / 8) | X14      | 在 GPR X14 中要恢复的值    |
| 15 * (XLEN / 8) | X15      | 在 GPR X15 中要恢复的值    |
| 16 * (XLEN / 8) | X16      | 在 GPR X16 中要恢复的值    |
| 17 * (XLEN / 8) | X17      | 在 GPR X17 中要恢复的值    |
| 18 * (XLEN / 8) | X18      | 在 GPR X18 中要恢复的值    |
| 19 * (XLEN / 8) | X19      | 在 GPR X19 中要恢复的值    |
| 20 * (XLEN / 8) | X20      | 在 GPR X20 中要恢复的值    |
| 21 * (XLEN / 8) | X21      | 在 GPR X21 中要恢复的值    |
| 22 * (XLEN / 8) | X22      | 在 GPR X22 中要恢复的值    |
| 23 * (XLEN / 8) | X23      | 在 GPR X23 中要恢复的值    |
| 24 * (XLEN / 8) | X24      | 在 GPR X24 中要恢复的值    |
| 25 * (XLEN / 8) | X25      | 在 GPR X25 中要恢复的值    |
| 26 * (XLEN / 8) | X26      | 在 GPR X26 中要恢复的值    |
| 27 * (XLEN / 8) | X27      | 在 GPR X27 中要恢复的值    |
| 28 * (XLEN / 8) | X28      | 在 GPR X28 中要恢复的值    |
| 29 * (XLEN / 8) | X29      | 在 GPR X29 中要恢复的值    |
| 30 * (XLEN / 8) | X30      | 在 GPR X10 中要恢复的值    |
| 31 * (XLEN / 8) | X31      | 在 GPR X31 中要恢复的值    |
| 32 * (XLEN / 8) | 保存     | 保留以后使用               |

在发送同步 SRET 请求给 SBI 实现（或 L0 虚拟化监控程序）之前，监督者软件（或 L1 虚拟化监控程序）必须将要在嵌套 SRET 上下文的偏移量 `<i>` * (XLEN / 8) 处恢复的 GPR X `<i>` 值写入。

当监督者软件（或 L1 虚拟化监控程序）发出同步 SRET 请求时，SBI 实现（或 L0 虚拟化监控程序）必须执行以下操作：

1. 如果 SBI_NACL_FEAT_SYNC_CSR 特性可用，则
   1. 所有由 SBI 实现（或 L0 虚拟化监控程序）实现的 RISC-V H 扩展 CSR 按照第 15.1 节所描述的方式进行同步。这相当于调用 SBI 的 sbi_nacl_sync_csr(-1UL) 函数。
2. 如果 SBI_NACL_FEAT_SYNC_HFENCE 特性可用，则
   1. 所有嵌套的 HFENCE 条目按照第 15.2 节所描述的方式进行同步。这相当于调用 SBI 的 sbi_nacl_sync_hfence(-1UL) 函数。
3. 从嵌套的 SRET 上下文中恢复通用寄存器 X `<i>` 的值。
4. 按照 RISC-V 特权规范 [priv_v1.12] 中定义的内容，模拟执行 SRET 指令。

### 15.4 特性：自动交换 CSR (ID #3)

自动交换 CSR 特性描述了 SBI 实现（或 L0 虚拟化监控程序）在以下情况下自动交换特定的 RISC-V H 扩展 CSR 值，这些 CSR 值位于嵌套的加速共享内存中：

- 在为来自监督者软件（或 L1 虚拟化监控程序）的同步的 SRET 请求模拟执行 SRET 指令之前。
- 在监督者（或 L1）虚拟化状态从 ON 变为 OFF 之后。

> 注意：监督者软件（或 L1 虚拟化监控程序）应该将 autoswap CSR 特性与同步 SRET 特性结合使用。

这个嵌套加速特性将 0x0200 - 0x027F（128 字节）的空间偏移范围定义为嵌套的自动交换上下文。下面的表格 67 展示了嵌套的自动交换上下文的内容。

*表 67. 嵌套的自动交换上下文*

| 偏移量                | 名称           | 编码                                                                                   |
| :-------------------- | :------------- | :------------------------------------------------------------------------------------- |
| 0 * (XLEN / 8)        | Autoswap_Flags | 动交换标志位<br /> BIT[XLEN-1:1] - 保留用于将来使用，必须为零<br /> BIT[0:0] - HSTATUS |
| 1 * (XLEN / 8)        | HSTATUS        | 要与 HSTATUS CSR 交换的值                                                              |
| 2 * (XLEN / 8) - 0x7F | Reserved       | 保留以供将来使用                                                                       |

要启用从嵌套的自动交换上下文中自动交换 CSRs，监督者软件（或 L1 虚拟化监控程序）必须执行以下操作：

1. 在嵌套的自动交换上下文中写入 HSTATUS 交换值。
2. 在嵌套的自动交换上下文中设置 Autoswap_Flags.HSTATUS 位。

要从嵌套的自动交换上下文中交换 CSRs，SBI 实现（或 L0 虚拟化监控程序）必须执行以下操作：

1. 如果在嵌套的自动交换上下文中设置了 Autoswap_Flags.HSTATUS 位，则将监督者的 HSTATUS CSR 值与嵌套的自动交换上下文中的 HSTATUS 值进行交换。

### 15.5 函数：探头嵌套加速功能 (FID #0)

```
struct sbiret sbi_nacl_probe_feature(uint32_t feature_id)
```

探测一个嵌套加速特性。这是 SBI 嵌套加速扩展的一个必须函数。feature_id 参数指定要探测的嵌套加速特性。表格 61 提供了可能的特性 ID 列表。该函数在 sbiret.error 中始终返回 SBI_SUCCESS。如果给定的 feature_id 不可用，则在 sbiret.value 中返回 0，如果可用，则返回 1。

### 15.6 函数：设置嵌套加速的共享内存 (FID #1)

```
struct sbiret sbi_nacl_set_shmem(unsigned long shmem_phys_lo,
				 unsigned long shmem_phys_hi,
				 unsigned long flags)
```

在调用的 hart 上设置并启用嵌套加速的共享内存。这是 SBI 嵌套加速扩展的强制功能。

如果 shmem_phys_lo 和 shmem_phys_hi 两个参数的位无法组成全 1，则 shmem_phys_lo 指定了共享内存物理基址的低 XLEN 位，而 shmem_phys_hi 指定了共享内存物理基址的高 XLEN 位。shmem_phys_lo 必须是 4096 字节（即一页）对齐，而共享内存的大小假定为 4096+(XLEN * 128) 字节。

如果 shmem_phys_lo 和 shmem_phys_hi 两个参数的位全部为 1，则嵌套加速功能被禁用。

flags 参数保留供将来使用，必须为零。

在 sbiret.error 中返回的可能错误代码在表 68 中显示。

*表 68. NACL 设置共享内存错误*

| 错误代码                | 描述                                                                            |
| :---------------------- | :------------------------------------------------------------------------------ |
| SBI_SUCCESS             | 共享内存被成功地设置或清除                                                      |
| SBI_ERR_INVALID_PARAM   | flags 参数不为零，或者 shmem_phys_lo 参数不是 4096 字节对齐的                   |
| SBI_ERR_INVALID_ADDRESS | 由 shmem_phys_lo 和 shmem_phys_hi 参数指定的共享内存不符合第 3.2 节中描述的要求 |

### 15.7 函数：同步共享内存 CSR (FID #2)

```
struct sbiret sbi_nacl_sync_csr(unsigned long csr_num)
```

在嵌套加速共享内存中同步 CSR 寄存器。这是一个可选功能，仅在支持 SBI_NACL_FEAT_SYNC_CSR 功能时可用。参数 csr_num 指定要同步的 RISC-V H 扩展 CSR 寄存器集合。

如果 csr_num 的位全部为 1，则根据第 15.1 节的描述，同步 SBI 实现（或 L0 虚拟化监控程序）实现的所有 RISC-V H 扩展 CSR 寄存器。

如果 (csr_num & 0x300) == 0x200 并且 csr_num < 0x1000，则根据第 15.1 节的描述，仅同步由 csr_num 参数指定的单个 RISC-V H 扩展 CSR 寄存器。

在 sbiret.error 中返回的可能错误代码在表 69 中显示。

*表 69. NACL 同步 CSR 错误*

| 错误代码              | 描述                                                                                                                                |
| :-------------------- | :---------------------------------------------------------------------------------------------------------------------------------- |
| SBI_SUCCESS           | CSRs 同步成功                                                                                                                       |
| SBI_ERR_NOT_SUPPORTED | SBI_NACL_FEAT_SYNC_CSR 特性不可用                                                                                                   |
| SBI_ERR_INVALID_PARAM | csr_num 不是全部的位数，并且要么：<br /> * (csr_num & 0x300) != 0x200 或 <br />* csr_num >= 0x1000 或 <br />* csr_num 未被 SBI 实现 |
| SBI_ERR_NO_SHMEM      | 嵌套加速共享内存不可用                                                                                                              |

### 15.8 函数：同步共享内存 HFENCEs (FID #3)

```
struct sbiret sbi_nacl_sync_hfence(unsigned long entry_index)
```

在嵌套加速共享内存中同步 HFENCE 指令。这是一个可选功能，仅在支持 SBI_NACL_FEAT_SYNC_HFENCE 功能时可用。参数 entry_index 指定要同步的嵌套 HFENCE 指令集合。

如果 entry_index 的位全部为 1，根据第 15.2 节的描述，将同步所有嵌套 HFENCE 指令。

如果 entry_index < (3840 / XLEN)，则根据第 15.2 节的描述，仅同步由 entry_index 参数指定的单个嵌套 HFENCE 指令。

在 sbiret.error 中返回的可能错误代码在表 70 中显示。

*表 70. NACL 同步 HFENCE 错误*

| 错误代码              | 描述                                                           |
| :-------------------- | :------------------------------------------------------------- |
| SBI_SUCCESS           | HFENCEs 同步成功                                               |
| SBI_ERR_NOT_SUPPORTED | SBI_NACL_FEAT_SYNC_HFENCE 特性不可用                           |
| SBI_ERR_INVALID_PARAM | entry_index 不是全 1 位比特，并且 entry_index >= (3840 / XLEN) |
| SBI_ERR_NO_SHMEM      | 嵌套加速共享内存不可用                                         |

### 15.9 函数：同步共享内存并模拟 SRET 指令 (FID #4)

```
struct sbiret sbi_nacl_sync_sret(void)
```

同步嵌套加速共享内存中的 CSR 寄存器和 HFENCE 指令，并模拟 SRET 指令。这是一个可选功能，仅在支持 SBI_NACL_FEAT_SYNC_SRET 特性时可用。

监督者软件（或 L1 虚拟化监控程序）使用此函数进行同步 SRET 请求，并且 SBI 实现（或 L0 虚拟化监控程序）必须按第 15.3 节中的描述进行处理。

该函数在成功时不返回任何值，而在失败时 sbiret.error 可能会返回表 71 中所示的错误代码。

*表 71. NACL 同步 SRET 错误*

| 错误代码              | 描述                               |
| :-------------------- | :--------------------------------- |
| SBI_ERR_NOT_SUPPORTED | SBI_NACL_FEAT_SYNC_SRET 特性不可用 |
| SBI_ERR_NO_SHMEM      | 嵌套加速共享内存不可用             |

### 15.10 函数列表

*表 72. NACL 函数列表*

| 函数名                 | SBI 版本 | FID | EID        |
| :--------------------- | :------- | :-- | :--------- |
| sbi_nacl_probe_feature | 2.0      | 0   | 0x4E41434C |
| sbi_nacl_set_shmem     | 2.0      | 1   | 0x4E41434C |
| sbi_nacl_sync_csr      | 2.0      | 2   | 0x4E41434C |
| sbi_nacl_sync_hfence   | 2.0      | 3   | 0x4E41434C |
| sbi_nacl_sync_sret     | 2.0      | 4   | 0x4E41434C |

## 章节 16. 偷窃时间的核算扩展 (EID #0x535441 "STA")

SBI 实现可能会遇到虚拟 HART 准备就绪但无法运行的情况。例如，当多个 SBI 领域共享处理器，或者 SBI 实现是一个虚拟机监视器，客户环境和其他客户环境或主机任务共享处理器时，可能会出现这些情况。当虚拟 HART 有时无法运行时，虚拟 HART 上下文中的观察者可能需要一种方式来解释比预期少的进展。虚拟 HART 准备好但必须等待的时间称为“被窃取的时间”，并且对其进行跟踪被称为窃取时间核算。窃取时间核算（STA）扩展定义了一种机制，使得 SBI 实现能够为每个虚拟 HART 向监督模式软件提供窃取时间和抢占信息。

### 16.1 函数 设置窃取时间共享内存地址

```
struct sbiret sbi_steal_time_set_shmem(unsigned long shmem_phys_lo,   unsigned long shmem_phys_hi,   uint32_t flags)
```

设置共享内存物理基址，用于调用虚拟 HART 的窃取时间核算，并启用 SBI 实现的窃取时间信息报告。

如果 shmem_phys_lo 和 shmem_phys_hi 不是全一的位数，那么 shmem_phys_lo 指定共享内存物理基址的低 XLEN 位，shmem_phys_hi 指定共享内存物理基址的高 XLEN 位。shmem_phys_lo 必须是 64 字节对齐的。共享内存的大小被假定为至少 64 字节。在从 SBI 调用返回之前，所有字节必须被 SBI 实现设置为零。

如果 shmem_phys_lo 和 shmem_phys_hi 是全一的位数，SBI 实现将停止报告虚拟 HART 的偷窃时间信息。

flags 必须被设置为零。

当共享内存被用于窃取时间核算时，预计共享内存不会被监督者模式的软件写入。然而，如果监督者模式软件的写入发生，SBI 实现必须不会表现失常，然而，在这种情况下，它可能会使共享内存充满不一致的数据。

SBI 实现必须在系统复位时停止对共享内存的写入。

共享内存布局的定义见表 73。

*表 73. STA 共享内存结构*

| 名称      | 偏移量 | 大小 | 描述                                                                                                                                                                                                                                                                                                                                   |
| :-------- | :----- | :--- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| sequence  | 0      | 4    | SBI 实现必须在写入窃取字段之前将该字段递增为奇数值，并在写入窃取后再次递增为偶数值（即，奇数序列号表示正在进行的更新）。SBI 实现应确保序列字段只在很短的时间内保持奇数。主管模式软件必须在读取窃取字段之前和之后检查这个字段，如果它是不同的或奇数的，则重复读取。这个序列字段使在 32 位环境下执行的监督者模式软件能够读取窃取字段的值 |
| flags     | 4      | 4    | 始终为零。未来对 SBI 调用的扩展可能允许监督者模式的软件写到共享内存的一些字段。只要 SBI 调用的 flags 参数使用零值，这种扩展就不会被启用                                                                                                                                                                                                |
| steal     | 8      | 8    | 该虚拟 HART 没有空闲和安排外出的时间，单位是纳秒。虚拟 HART 空闲的时间将不被报告为偷窃时间                                                                                                                                                                                                                                             |
| preempted | 16     | 1    | 一个指示标志，指示注册了此结构的虚拟 HART 是否正在运行或停止。如果虚拟 HART 被抢占（即窃取字段在增加），SBI 实现可能会写入非零值，而在虚拟 HART 重新开始运行之前，必须写入零值。例如，监督模式软件可以使用这个标志来检查锁的持有者是否已被抢占，并在这种情况下禁用 optimistic spinning                                                 |
| pad       | 17     | 47   | 用零填充到 64 字节的边界                                                                                                                                                                                                                                                                                                               |

sbiret.value 被设置为 0，在 sbiret.error 中可能返回的错误代码如下表 74 所示。

*表 74. STA 设置窃取时间共享内存地址错误*

| 错误代码                | 描述                                                                                       |
| :---------------------- | :----------------------------------------------------------------------------------------- |
| SBI_SUCCESS             | 偷取时间共享内存物理基址被成功设置或清除                                                   |
| SBI_ERR_INVALID_PARAM   | flags 参数不为零或 shmem_phys_lo 不是 64 字节对齐的                                        |
| SBI_ERR_INVALID_ADDRESS | shmem_phys_lo 和 shmem_phys_hi 参数所指向的共享内存是不可写的，或者不满足 3.2 节的其他要求 |
| SBI_ERR_FAILED          | 该请求因未指明的或未知的其他原因而失败                                                     |

### 16.2 函数列表

*表 75. STA 函数列表*

| 函数名                   | SBI 版本 | FID | EID      |
| :----------------------- | :------- | :-- | :------- |
| sbi_steal_time_set_shmem | 2.0      | 0   | 0x535441 |

## 章节 17. 实验性 SBI 扩展空间 (EIDs #0x08000000 - #0x08FFFFFF)

未安排。

## 章节 18. 供应商特定 SBI 扩展空间 (EIDs #0x09000000 - #0x09FFFFFF)

从 mvendorid 开始的低位。

## 章节 19. 固件特定 SBI 扩展空间 (EIDs #0x0A000000 - #0x0AFFFFFF)

低位是 SBI 实现的 ID。固件特定的 SBI 扩展适用于 SBI 实现。它提供了在外部固件规范中定义的特定固件的 SBI 功能。

## 参考资料

- [RISC-V SBI-1.0.0版本 中文][001]
- [The RISC-V Instruction Set Manual, Volume II: Privileged Architecture, Document Version 20211203][002]

[001]: https://zhuanlan.zhihu.com/p/634337322
[002]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/github.com/riscv/riscv-isa-manual/releases/tag/Priv-v1.12
