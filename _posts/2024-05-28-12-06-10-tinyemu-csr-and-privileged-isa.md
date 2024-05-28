---
layout: post
author: 'yjmstr'
title: '从零开始，徒手写一个 RISC-V 模拟器（3）—— CSR 与特权级 ISA'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /tinyemu-csr-and-privileged-isa/
description: '从零开始，徒手写一个 RISC-V 模拟器（3）—— CSR 与特权级 ISA'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - TinyEMU
  - 模拟器
  - 特权级
  - CSR
  - ISA
  - Machine Mode
  - Supervisor Mode
  - User Mode
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces images urls autocorrect]
> Author:    YJMSTR <pyjmstr@gmail.com><br\>
> Date:      2023/02/06
> Revisor:   Bin Meng, Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

在之前的文章中我们介绍了 TinyEMU 的基本架构、RISC-V 非特权级指令集以及 TinyEMU 中 RV64I 指令集的实现。本篇文章中将介绍 RISC-V 中的控制与状态寄存器 CSR，Zicsr 扩展在 TinyEMU 中的实现，并介绍特权级 ISA，为之后实现中断和异常处理做准备。

## CSR

RISC-V 预留了 12 位的地址空间给至多 4096 个控制与状态寄存器（CSR）。但 RISC-V 规范只使用了其中一部分，我们可以利用剩余的地址空间添加自定义 CSR。

RISC-V 规范中已分配地址的 CSR 如下，非特权级 CSR：

![unprivileged CSR](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/unprivileged_csr.png)

supervisor-level CSR：

![supervisor_csr](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/supervisor_csr.png)

hypervisor and VS CSR:

![hypervisor and VS CSR](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/hypervisor_and_vs_csr.png)

machine-level CSR:

![machine level csr](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/machine_csr.png)

RISC-V 规范中分配了地址的 CSR 并不都是必须实现的，我们只需要根据需求实现其中的一部分即可。目前 TinyEMU 中先不实现 hypervisor 相关的 CSR 以及 RV32 only 的 CSR。

有关这些 CSR 的具体功能，我们将在使用到这些 CSR 时进行介绍。CSR 的不同字段可能有不同的可读写性，手册中会用以下名词标识它们的读写性：

- WPRI：写时保护保留值，读时忽略值。这些字段是保留给未来使用的，软件在读取该 CSR 时需要忽略这些字段，并在写入该寄存器其它字段时保留 WPRI 字段中的值。
- WLRL：只读写合法值。这些可读写 CSR 字段规定：除合法值外，不能向其写入其它内容。且仅当上一次向该字段写入的是合法值时，才能保证从该字段中读取到的是合法值。
- WARL：写任意值，读合法值。这些可读写 CSR 字段定义了一些合法值。WARL 可以写入任意值，但保证任意时刻读取到的都是合法值。

下面向 TinyEMU 中添加 CSR。首先加入如下的 CSR 结构体：

```c
typedef struct CSR {
    uint64_t csr[4096];
} CSR;
```

并修改 CPU 结构体：

```c
typedef struct CPU {
    uint64_t regs[32];
    uint64_t pc;
    BUS bus;
    enum CPU_STATE state;
    CSR csr;
} CPU;
```

然后用 enum 为 CSR 分配地址：

```c
enum CSR_ADDR {
    cycle = 0xC00,
    ...
};
```

## Zicsr 扩展

SYSTEM major opcode 用于编码所有的特权级指令，即当 opcode = 0b1110011 时，说明当前指令为特权级指令。其可以分为两部分：Zicsr 扩展中的指令和所有其它的特权级指令。

Zicsr 扩展定义了 CSR 指令来对 CSR 进行原子性的 `读-修改-写` 操作。CSR 指令分为两类：寄存器指令（CSRRW，CSRRS，CSRRC）和立即数指令（CSRRWI，CSRRSI，CSRRCI）。

CSR 指令格式如下：

![csr.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/csr.png)

各 CSR 指令编码如下：

![csrcode.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/csrcode.png)

其中 CSR 指令的立即数位于 rs1 字段，扩展方式为零扩展。opcode 均为 1110011。

如果 rd 寄存器是 x0，指令将不会读取 CSR，以避免读取 CSR 产生的副作用。类似地，若 rs1 寄存器为 x0 或立即数为 0，也不会进行 CSR 写操作。所有 CSR 指令何时进行读/写操作的表格如下：

![CSR_rw.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/CSR_rw.png)

CSRRW 指令原子性地交换指定的 CSR 和整数寄存器中的值，它读出 CSR 中的值后将其进行零拓展至 XLEN 位，再写回 rd 寄存器中。而 rs1 寄存器中的值将被写入指定的 CSR 里。

CSRRS 指令原子性地读取并置位 CSR，将值零扩展至 XLEN 位后写入 rd。rs1 中的初始值将作为 CSR 的位掩码，即：若寄存器 rs1 中为 1 的位在 CSR 中是可写入的位，那么 CSR 中的该位会被置 1，其它位会保持不变。

CSRRC 指令原子性地读 CSR 值，零扩展至 XLEN 位后写入 rd。rs1 中为 1 的位若在 CSR 中是可写入的位，那么 CSR 中的该位会被置 0，其它位保持不变。

CSRRWI，CSRRSI 和 CSRRCI 指令的行为与之前三条指令的行为一致，但 rs1 被换为了零扩展的立即数。

下面向 TinyEMU 中添加 Zicsr 指令，在 `enum INST_NAME` 中添加相应指令名称后，修改译码函数，加入对 Zicsr 指令的支持。

接着添加指令对应的执行函数。以 `csrrw(DECODER *decoder)` 为例，其它 CSR 函数类似：

```c
void csrrw(DECODER *decoder) {
    uint64_t csrval;
    if (decoder->rd != 0)
        csrval = decoder->cpu->csr.csr[decoder->csr_addr];
    else csrval = 0;
    uint64_t rs1val = decoder->cpu->regs[decoder->rs1];
    decoder->cpu->regs[decoder->rd] = csrval;
    decoder->cpu->csr.csr[decoder->csr_addr] = rs1val;
}
```

需要注意的是，CSR 指令中的高 12 位提取出来后是零扩展，而 i 型立即数虽然也是这些位，但是是符号位扩展，因此不能复用提取 i 型立即数的 imm_i 函数。

## 其它特权指令

前文曾经提到过，opcode = 0b1110011 用于编码所有的特权指令，本小节将介绍除 Zicsr 扩展外的其它特权指令，但不会给出它们的实现。

### 特权等级

任一时刻，一个 RISC-V 硬件线程（hart）总是运行在某一特权等级上。目前 RISC-V 特权级规范中定义了如下的特权等级：

![privilege_level.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/privilege_level.png)

U 模式通常是用于运行传统的应用程序，S 模式通常用于运行操作系统，M 模式拥有最高的权限，所有的 RISC-V 系统都必须要实现 M 模式。

每个特权模式有属于自己特权等级的 CSR，能够使用的特权指令也有所不同。M 模式可以访问所有模式的 CSR，S 模式只能访问 S 模式和 U 模式的 CSR，U 模式只能访问 U 模式的 CSR，并且没有专属于 U 模式的特权指令。在 RISC-V 的虚拟化扩展（hypervisor extension）中还将 S 模式扩展为了 HS 与 VS 模式。此外还有用于调试的 D（Debug）模式，关于这些模式的详细介绍可以查阅 RISC-V 规范。

下面向 TinyEMU 中加入特权等级。在 cpu.h 中对特权等级进行编码：

```c
enum CPU_PRI_LEVEL {
    U = 0b00,
    S = 0b01,
    M = 0b11,
};
```

然后在 `struct CPU` 中加入 `enum CPU_PRI_LEVEL pri_level;` 用于标识当前 CPU 所处的特权等级。并在 `cpu_init` 函数中将初始的特权等级设为 `M`。

### M-mode

机器模式可用的特权指令包括环境调用与断点（Environment Call and Breakpoint），自陷返回指令（Trap-Return Instructions），等待中断（Wait for Interrupt）与自定义系统指令。

环境调用与断点指令包括 `ecall` 指令与 `ebreak` 指令。这两条指令在之前介绍 RV64I 的文章中已经实现了译码，但没有添加指令实现的函数。这两条指令的编码格式如下：

![ecall_and_ebreak.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/ecall_and_ebreak.png)

RISC-V 中的中断和异常都会引起 trap。一个 hart 通常运行在 U 模式，直到自陷（trap）发生，该 hart 会切换到自陷处理程序（通常运行在更高特权模式），使得当前 hart 原先执行的程序中 trap 发生之后的指令暂停执行，直到 hart 从 trap 返回后才会继续执行。提高当前 hart 运行的特权等级的 trap 被称为垂直 trap，而不改变特权等级的 trap 被称为水平 trap。

M 模式下和 trap 相关的 CSR 寄存器有：

- mtvec：用于保存 M 模式下 trap 时处理器需要跳转到的地址。
- mepc：用于记录 M 模式触发 trap 时的 pc 值。
- mcause：指示发生 trap 的原因。最高位为 1 表示当前 trap 为 interrupt，否则为 exception；其它位用于编码不同的 exception。
- mie：指出处理器目前能处理和必须忽略的中断。
- mip：指出处理器目前正准备处理的中断。
- mtval：用于保存异常发生时的附加信息：比如地址异常时的地址，非法指令异常的指令本身，对于其它异常它的值为 0。
- mscratch：暂时存放一个字大小的数据。
- mstatus：保存全局中断使能等状态。

`ecall` 指令是 RISC-V 中的自陷指令，在不同的特权等级下，该指令会产生对应的环境调用异常，触发 trap。

`ebreak` 由调试器使用，该指令会将系统的控制权转交给调试环境，产生断点异常。异常和中断处理我们在之后的文章中再实现，因此此处仅先将这两条指令实现为 `nop`。

![trap_return_instruction.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/trap_return_instruction.png)

自陷-返回指令包括 `mret` 和 `sret` 这两条指令，用于在处理完自陷（trap）后从自陷状态返回。它们会对 mstatus 寄存器进行操作（sstatus 是 mstatus 的子集）。RV64 中的 mstatus 寄存器如下所示：

![mstatus.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/mstatus.png)

mstatus 寄存器中分别为 M 模式和 S 模式提供了全局中断使能位 MIE 和 SIE（注意和 mie 与 sie 寄存器进行区分）。这些位主要用于保证当前特权等级下中断处理程序的原子性。若当前 hart 在特权模式 $x$ 下执行，则 $x$IE=1 表示全局中断启用，$x$IE=0 表示全局中断禁用。更低特权等级 $w$ ($w<x$) 的中断总是全局禁用，无论 $w$IE 的值是多少；更高特权等级 $h$ ($h>x$) 的中断总是全局启用，无论 $h$IE 的值是多少。

`mret` 和 `sret` 指令分别用于从 M 模式和 S 模式的 trap 中返回，它们会根据 mstatus 寄存器的信息恢复 trap 之前的中断标志位和特权等级，并分别跳转回 mepc 和 sepc 中所存储的地址。

等待中断（Wait for Interrupt）指令 `wfi`，用于将当前 hart 挂起。该指令在任何特权模式下均可用，并且在 U 模式下是可选的。这条指令是 RISC-V 架构中的休眠指令，可以让处理器进入平台特定的低功耗状态，直到中断到来。

### S-mode

S 模式可用的特权指令除了之前提到的 `sret` 外，还有 `sfence.vma` 指令：

![sfence_vma.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/sfence_vma.png)

这条指令用于同步更新内存中与内存管理有关的数据结构（比如页表），还能用于弃置地址转译缓存（TLB，Translation Lookaside Buffer）中的条目，具体细节我们将在实现 TinyEMU 的虚拟内存系统时再进行介绍。

### U-mode

在 RISC-V 特权级规范 v20211203 版本中，没有给出介绍 U-mode 特权指令的章节。但在 U-mode 下，我们可以通过 `ecall` 指令主动触发 trap，来切换到更高的特权模式，并通过 `mret/sret` 指令切换回 U-mode。

如果你想要了解 U-mode 下如何处理中断，可以查阅 RISC-V N 扩展的相关资料。

## 总结

本文简要介绍了 RISC-V 中的特权指令，并提供了 CSR 以及 Zicsr 扩展在 TinyEMU 中的实现。在之后的文章中我们将进一步实现 trap 的处理，并完善相关指令的实现。

## 参考资料

- [RISC-V spec][1]
- [RISC-V Reader 中文版][2]

[1]: https://riscv.org/technical/specifications/
[2]: http://www.riscvbook.com/chinese/
