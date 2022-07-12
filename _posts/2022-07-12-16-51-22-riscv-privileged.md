---
layout: post
author: Wen Pingbo
title: 'RISC-V 特权指令'
draft: false
album: 'RISC-V Linux'
license: "cc-by-nc-nd-4.0"
permalink: /riscv-privileged/
description: "本文介绍了 RISC-V 特权指令。"
tags:
  - 开源项目
  - Risc-V
categories:
  - 特权指令
  - 机器模式
  - 监管者模式
  - ISA
  - CSR
---

> Author:  Pingbo Wen
> Date:    2022/05/04
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)

## 简介

RISC-V ISA Spec 分为两部分，一个是非特权指令，另外一个就是特权指令。非特权指令主要是用于通用计算，站在操作系统的角度来看，可以理解为用户态（低权限模式）能够运行的指令。而特权指令，是为了能够运行像 Linux/Windows 现代操作系统而设定的。现代操作系统主要强调对资源的管控，这就需要硬件上提供额外的权限管理机制，从而能够限制普通应用代码的行为。

## 特权等级

在 ARM64 中，分为 el0-el3 特权等级。RISC-V 同样有类似的设定，具体定义如下：

特权等级 | 编码 | 名称      | 缩写
---------|------|-----------|------
0        | 00   | 用户模式  | U
1        | 01   | 监管者模式| S
2        | 10   | Reserved  |
3        | 11   | 机器模式  | M

M 模式是权限最高的特权等级，也是 RISC-V Spec 中明确规定必须要实现的特权等级，其他三个特权等级是可选的。芯片厂商可以根据实际应用场景来决定需要实现哪些特权等级。特权等级的实现组合有如下几种：

- M, 简单嵌入式系统(单片机)
- M + U, 安全嵌入式系统(带保护)
- M + S + U, 现代操作系统(Windows/Linux)

其中保留的特权等级 2 是留给虚拟化用的。在 H 扩展(Hypervisor Extension)中，把 S 模式扩展成 HS 模式(Hypervisor-Extended Supervisor mode)，具体可以参考 Spec。

RISC-V 手册中有提到过一个 Debug Mode，可以理解为比 M 权限更高的特权等级，用于支持芯片调试。关于这个模式的资料可参考 [官方手册](https://github.com/riscv/riscv-debug-spec/blob/release/riscv-debug-release.pdf)。

在一个典型 Linux 系统中，用户态应用程序跑在 U 模式，内核跑在 S 模式，而 M 模式一般是 OpenSBI/U-Boot 等 Bootloader 在用。

## 异常处理

有了特权等级，相应的需要提供进入退出特权等级的方法，以及控制机制。和 ARM 类似，RISC-V 也是通过异常切换不同特权等级，这个地方你可以把异常理解成一种中断。严格来讲，中断也只是异常中的一种而已。 以 M 模式处理异常为例，当 U 或者 S 模式发生异常后，处理器会自动做如下处理：

1. 处理器保存异常指令 PC 到 MEPC 中
2. 根据发生的异常类型设置 MCAUSE，并更新 MTVAL 为出错的取指地址、存储/加载地址或者指令码
3. 将 MSTATUS 的中断使能位域 MIE 保存到 MPIE 域中，将 MIE 域的值清零，禁止响应中断
4. 将发生异常之前的权限模式保存到 MSTATUS 的 MPP 域中，切换到机器模式（没有做异常降级响应处理的话）
5. 根据 MTVEC 中的基址和模式，得到异常服务程序入口地址。处理器从异常服务程序的第一条指令处开始执行，进行异常的处理

如果是 S 模式处理异常，相应操作的寄存器就是 SEPC/SCAUSE/STVAL/SIE/SSTATUS 等。而读写这些寄存器主要是通过 CSR 指令，这跟 ARM 中的 MSR/MRS 指令类似。CSR 指令具体定义如下：

CSR 指令 | 格式 | 说明
---------|------|-----
CSRRC | csrrc rd, csr, rs1 | 控制寄存器清零，rd = csr，csr &= ~rs1
CSRRCI | csrrci rd, csr, imm | 控制寄存器立即数清零，rd = csr, csr &= ~imm
CSRRS | csrrs rd, csr, rs1 | 控制寄存器置位，rd = csr, csr \|= rs1
CSRRSI | csrrsi rd, csr, imm | 控制寄存器立即数置位，rd = csr, csr \|= imm
CSRRW | csrrw rd, csr, rs1 | 控制寄存器读写，rd = csr, csr = rs1
CSRRWI | csrrwi rd, csr, imm | 控制寄存器立即数读写，rd = csr, csr = imm

这些 CSR 指令配合 x0 寄存器，就组成了很多我们常见的伪指令：

CSR 伪指令 | 格式 | 说明
---------|------|-----
CSRC | csrc csr, rs | 对应基础指令 csrrc x0, csr, rs
CSRCI | csrci csr, imm | 对应基础指令 csrrci x0, csr, imm
CSRS | csrs csr, rs | 对应基础指令 csrrs x0, csr, rs
CSRSI | csrsi csr, imm | 对应基础指令 csrrsi x0, csr, imm
CSRR | csrr rd, csr | 对应基础指令 csrrs rd, csr, x0
CSRW | csrw csr, rs | 对应基础指令 csrrw x0, csr, rs
CSRWI | csrwi csr, imm | 对应基础指令 csrrw x0, csr, imm

除了硬件上的中断，以及非法指令等异常外，RISC-V 还提供 ECALL/EBREAK 两条指令，让软件可以自己主动产生异常，其中 ECALL 主要用于环境调用，Linux 系统调用就是通过这个指令执行内核系统调用。而 EBREAK 主要是在调试场景下用。

## Linux 系统下的系统调用实现

下面以 Linux 系统 `sys_open` 系统调用为例，我们看一下用户态程序（特权等级 0, U 模式）是怎么陷入到 Linux 内核(特权等级 1, S 模式)中执行系统调用的。

首先用户态通过 `ecall` 指令触发系统调用，使用 `a7` 寄存器传递系统调用编号，`a0-a5` 寄存器来传递参数：

```
   22482:	eb8d               	bnez	a5,224b4 <__libc_open+0x64>
   22484:	03800893          	li	a7,56
   22488:	f9c00513          	li	a0,-100
   2248c:	8622               	mv	a2,s0
   2248e:	00000073           	ecall
```

陷入到内核态后，处理器从 STVEC 寄存器加载异常处理程序入口。在 Linux 内核初始化过程中(arch/riscv/kernel/head.S)，就已经通过 CSR 指令设置好了 STVEC 寄存器，指向 `handle_exception` 函数：

```
setup_trap_vector:
	/* Set trap vector to exception handler */
	la a0, handle_exception
	csrw CSR_TVEC, a0

	/*
	 * Set sup0 scratch register to 0, indicating to exception vector that
	 * we are presently executing in kernel.
	 */
	csrw CSR_SCRATCH, zero
	ret
```

`handle_exception` 最终会跳转到 `handle_syscall`，然后从 a7 寄存器中拿到系统调用编号，从 `sys_call_table` 中索引到最终系统调用处理函数(arch/riscv/kernel/entry.S)：

```
	/* Check to make sure we don't jump to a bogus syscall number. */
	li t0, __NR_syscalls
	la s0, sys_ni_syscall
	/*
	 * Syscall number held in a7.
	 * If syscall number is above allowed value, redirect to ni_syscall.
	 */
	bgeu a7, t0, 1f
	/* Call syscall */
	la s0, sys_call_table
	slli t0, a7, RISCV_LGPTR
	add s0, s0, t0
	REG_L s0, 0(s0)
1:
	jalr s0
```
