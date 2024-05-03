---
layout: post
author: 'panxiakai'
title: 'RISC-V 异常处理在 KVM 中的实现'
draft: false
plugin: 'mermaid'
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-kvm-excp-impl/
description: 'RISC-V 异常处理在 KVM 中的实现'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - KVM
  - 异常处理
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [tounix spaces toc comments tables images urls epw]
> Author: XiakaiPan <13212017962@163.com>
> Date: 2022/10/21
> Revisor: walimis, Falcon
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V 虚拟化技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I5E4VB)
> Sponsor: PLCT Lab, ISCAS


## 前言

Trap 处理是 RISC-V 虚拟化实现中的重要部分，包括异常和中断两个部分。当前 KVM 是 RISC-V 虚拟化扩展在软件层面较为可靠的实现，本文将结合 RISC-V 特权指令集手册的规定，分析 KVM 中有关异常处理的实现，中断部分由于涉及较多驱动层面的内容，故将在之后的文章中结合 MMIO，timer 等做具体探讨。

## 软件版本

| Software     | commit ID or version No.                 | Link                               |
| ------------ | ---------------------------------------- | ---------------------------------- |
| Linux Kernel | v6.0                                     | https://www.kernel.org/            |
| kvmtool      | 6a1f699108e5c2a280d7cd1f1ae4816b8250a29f | https://github.com/kvmtool/kvmtool |

## KVM 异常处理

### 异常处理入口

在 KVM 对 RISC-V H 扩展的实现中，与异常处理相关的函数调用关系如下图所示。目前的实现中，KVM 能够处理三类异常。即虚拟机内的 page fault、虚拟指令异常和系统调用，三种不同的异常处理分别对应了不同的实现。

<pre><div class="mermaid">

flowchart LR

subgraph arch/riscv/kvm/vcpu.c

run

end

subgraph arch/riscv/kvm/vcpu_exit.c

exit
gpf

end

subgraph arch/riscv/kvm/vcpu_insn.c

virt_insn

end

subgraph arch/riscv/kvm/vcpu_sbi.c

ecall

end

run[kvm_arch_vcpu_ioctl_run]-->exit[kvm_riscv_vcpu_exit]

exit-->virt_insn[kvm_riscv_vcpu_virtual_insn]
exit-->gpf[gstage_page_fault]
exit-->ecall[kvm_riscv_vcpu_sbi_ecall]
</div></pre>

（[下载由 Mermaid 生成的 PNG 图片][004]）

### 异常分类及其定义

`kvm_arch_vcpu_ioctl_run` 函数用于实现 vCPU 的运行。其调用 `kvm_riscv_vcpu_enter_exit` 函数进入 vCPU 的运行，此时 Guest 进入运行状态，CPU 处于 VS 或者 VU 模式。当 Guest 发生无法处理的异常时，Guest 退出，CPU 进入 HS 模式，随后 KVM 调用 `kvm_riscv_vcpu_exit` 来实现对异常的处理。

`kvm_riscv_vcpu_exit` 函数内部包含三个部分，分别对应三种异常的处理，代码如下：

```cpp
// arch/riscv/kvm/vcpu_exit.c: line 188
/*
 * Return > 0 to return to guest, < 0 on error, 0 (and set exit_reason) on
 * proper exit to userspace.
 */
int kvm_riscv_vcpu_exit(struct kvm_vcpu *vcpu, struct kvm_run *run,
			struct kvm_cpu_trap *trap)
{
	int ret;

	/* 仅处理 guest 内部的 trap */
	/* If we got host interrupt then do nothing */
	if (trap->scause & CAUSE_IRQ_FLAG)
		return 1;

	/* 处理 guest 中断：KVM 使得 Linux 内核成为了 hypervisor，故 KVM 内部实现了对来自 guest/VM 和 hypervisor 的 trap 处理，此处仅处理 Guest 内部的 trap */
	/* Handle guest traps */
	ret = -EFAULT;
	run->exit_reason = KVM_EXIT_UNKNOWN;
	switch (trap->scause) {
	/* 虚拟指令异常 */
	case EXC_VIRTUAL_INST_FAULT:    // 22, Virtual instruction
		if (vcpu->arch.guest_context.hstatus & HSTATUS_SPV)
			ret = kvm_riscv_vcpu_virtual_insn(vcpu, run, trap);
		break;
	/* 虚拟机内页缺陷异常 */
	case EXC_INST_GUEST_PAGE_FAULT: // 20, Instruction guest-page fault
	case EXC_LOAD_GUEST_PAGE_FAULT: // 21, Load guest-page fault
	case EXC_STORE_GUEST_PAGE_FAULT:// 23, Store/AMO guest-page fault
		if (vcpu->arch.guest_context.hstatus & HSTATUS_SPV)
			ret = gstage_page_fault(vcpu, run, trap);
		break;
	/* 虚拟机内系统调用 */
	case EXC_SUPERVISOR_SYSCALL:    // 10, Environment call from VS-mode
		if (vcpu->arch.guest_context.hstatus & HSTATUS_SPV)
			ret = kvm_riscv_vcpu_sbi_ecall(vcpu, run);
		break;
	default:
		break;
	}

	/* 若异常未能被顺利处理（ret > 0），则输出当前状态（sepc, sstatus, hstatus）和对应的异常信息（scause, stval, htval, htinst）*/
	/* Print details in-case of error */
	if (ret < 0) {
		kvm_err("VCPU exit error %d\n", ret);
		kvm_err("SEPC=0x%lx SSTATUS=0x%lx HSTATUS=0x%lx\n",
			vcpu->arch.guest_context.sepc,
			vcpu->arch.guest_context.sstatus,
			vcpu->arch.guest_context.hstatus);
		kvm_err("SCAUSE=0x%lx STVAL=0x%lx HTVAL=0x%lx HTINST=0x%lx\n",
			trap->scause, trap->stval, trap->htval, trap->htinst);
	}

	return ret;
}
```

如上所示，KVM 的实现中包含了三类异常：

- 虚拟指令异常；
- Guest page fault；
- SBI 系统调用。

[特权指令集手册][1] 中规定了每种异常对应的编码（即 `scause` 的可能的值），在进行异常处理时，可依据据 `scause` 的具体值确定其处理方式，如下表所示。

![cause code](/wp-content/uploads/2022/03/riscv-linux/images/riscv-kvm/excp-impl/scause-code.png)

在 KVM 中，其对应宏的定义如下：

```cpp
// arch/riscv/include/asm/csr.h: line 66
/* Exception causes */
#define EXC_INST_MISALIGNED	0               // Instruction address misaligned
#define EXC_INST_ACCESS		1               // Instruction access fault
#define EXC_INST_ILLEGAL	2               // Illegal instruction
#define EXC_BREAKPOINT		3               // Breakpoint
#define EXC_LOAD_ACCESS		5               // Load access fault
#define EXC_STORE_ACCESS	7               // Store/AMO access fault
#define EXC_SYSCALL		8		// Environment call from U-mode or VU-mode
#define EXC_HYPERVISOR_SYSCALL	9	        // Environment call from HS-mode
#define EXC_SUPERVISOR_SYSCALL	10		// Environment call from VS-mode
#define EXC_INST_PAGE_FAULT	12		// Instruction page fault
#define EXC_LOAD_PAGE_FAULT	13		// Load page fault
#define EXC_STORE_PAGE_FAULT	15		// Store/AMO page fault
#define EXC_INST_GUEST_PAGE_FAULT	20      // Instruction guest-page fault
#define EXC_LOAD_GUEST_PAGE_FAULT	21      // Load guest-page fault
#define EXC_VIRTUAL_INST_FAULT		22      // Virtual instruction
#define EXC_STORE_GUEST_PAGE_FAULT	23      // Store/AMO guest-page fault
```

### 虚拟指令异常

其中，`EXC_VIRTUAL_INST_FAULT` 即 virtual instruction exception 对应如下情况：

- 在 VS-Mode 或 VU-Mode 下访问特定 CSR 的特定位；
- 在 VS-Mode 或 VU-Mode 下执行无权限的指令如 `HFENCE`, `HLV`, `HSV` 等。

KVM 中 virtual instruction 异常的处理如下：

```cpp
// arch/riscv/kvm/vcpu_insn.c: line 397
/**
 * kvm_riscv_vcpu_virtual_insn -- Handle virtual instruction trap
 *
 * @vcpu: The VCPU pointer
 * @run:  The VCPU run struct containing the mmio data
 * @trap: Trap details
 *
 * Returns > 0 to continue run-loop
 * Returns   0 to exit run-loop and handle in user-space.
 * Returns < 0 to report failure and exit run-loop
 */
int kvm_riscv_vcpu_virtual_insn(struct kvm_vcpu *vcpu, struct kvm_run *run,
				struct kvm_cpu_trap *trap)
{
	unsigned long insn = trap->stval;   // 获取导致 trap 的指令
	struct kvm_cpu_trap utrap = { 0 };
	struct kvm_cpu_context *ct;

	/* 判断是否为 16-bit 的压缩指令（[1:0]=2，非压缩指令 [1:0]=3），如果是压缩指令，则作如下处理 */
	if (unlikely(INSN_IS_16BIT(insn))) {
		if (insn == 0) {    // Illegal instruction 非法指令（参见特权指令集手册的表 16.5）
			ct = &vcpu->arch.guest_context;
			insn = kvm_riscv_vcpu_unpriv_read(vcpu, true,
							  ct->sepc,
							  &utrap);  // 从 Guest 内存中读取指定地址的内存
			if (utrap.scause) {
				utrap.sepc = ct->sepc;
				kvm_riscv_vcpu_trap_redirect(vcpu, &utrap); // 重定向 trap 到 Guest 中
				return 1;
			}
		}
		if (INSN_IS_16BIT(insn))
			return truly_illegal_insn(vcpu, run, insn);     // 将当前指令直接重定向到 Guest 中
	}

	/* 对于非压缩指令，根据当前指令的类型（[6:2] opcode）进行处理：*/
	switch ((insn & INSN_OPCODE_MASK) >> INSN_OPCODE_SHIFT) {
	case INSN_OPCODE_SYSTEM:    // SYSTEM 类型的指令（ecall, ebreak, CSR 读写指令）
		return system_opcode_insn(vcpu, run, insn);
	default:    // 正常长度且非 SYSTEM 类型的指令，将当前指令直接重定向到 Guest 中进行处理
		return truly_illegal_insn(vcpu, run, insn);
	}
}

// arch/riscv/kvm/vcpu_insn.c: line 70-72
#define INSN_16BIT_MASK		0x3
#define INSN_IS_16BIT(insn)	(((insn) & INSN_16BIT_MASK) != INSN_16BIT_MASK)
```

其中用于处理具体指令的函数其原型或定义如下：

处理非法压缩指令时，用于从 Guest 获取合法指令的 `kvm_riscv_vcpu_unpriv_read` 函数：

```cpp
// arch/riscv/kvm/vcpu_exit.c: line 50
/**
 * kvm_riscv_vcpu_unpriv_read -- Read machine word from Guest memory
 *
 * @vcpu: The VCPU pointer
 * @read_insn: Flag representing whether we are reading instruction
 * @guest_addr: Guest address to read
 * @trap: Output pointer to trap details
 */
unsigned long kvm_riscv_vcpu_unpriv_read(struct kvm_vcpu *vcpu,
					 bool read_insn,
					 unsigned long guest_addr,
					 struct kvm_cpu_trap *trap);
```

从 Hypervisor 重定向到 Guest 的函数 `kvm_riscv_vcpu_trap_redirect`：

```cpp
// arch/riscv/kvm/vcpu_exit.c: line 152
/**
 * kvm_riscv_vcpu_trap_redirect -- Redirect trap to Guest
 *
 * @vcpu: The VCPU pointer
 * @trap: Trap details
 */
void kvm_riscv_vcpu_trap_redirect(struct kvm_vcpu *vcpu,
				  struct kvm_cpu_trap *trap);
```

对合法的压缩指令以及非 SYSTEM 类型的非压缩指令，不进行额外处理，直接调用 `truly_illegal_insn` 函数处理，保存当前 trap 的具体信息，将 Guest PC 设置为 Guest 中对应的异常向量， 然后返回到到 Guest 中对异常进行处理：

```cpp
// arch/riscv/kvm/vcpu_insn.c: line 151
static int truly_illegal_insn(struct kvm_vcpu *vcpu, struct kvm_run *run,
			      ulong insn)
{
	struct kvm_cpu_trap utrap = { 0 };

	/* Redirect trap to Guest VCPU */
	utrap.sepc = vcpu->arch.guest_context.sepc;
	utrap.scause = EXC_INST_ILLEGAL;
	utrap.stval = insn;
	utrap.htval = 0;
	utrap.htinst = 0;
	kvm_riscv_vcpu_trap_redirect(vcpu, &utrap);

	return 1;
}
```

对 SYSTEM 类型进行特别操作的函数 `system_opcode_insn`：

```cpp
// arch/riscv/kvm/vcpu_insn.c: line 368
static int system_opcode_insn(struct kvm_vcpu *vcpu, struct kvm_run *run,
			      ulong insn)
{
	int i, rc = KVM_INSN_ILLEGAL_TRAP;
	const struct insn_func *ifn;

	for (i = 0; i < ARRAY_SIZE(system_opcode_funcs); i++) {
		ifn = &system_opcode_funcs[i];
		if ((insn & ifn->mask) == ifn->match) {
			rc = ifn->func(vcpu, run, insn);
			break;
		}
	}

	switch (rc) {
	case KVM_INSN_ILLEGAL_TRAP:         // 非法指令异常，设置 scause 为对应编码后重定向到 Guest

		return truly_illegal_insn(vcpu, run, insn);
	case KVM_INSN_VIRTUAL_TRAP:         // 虚拟指令异常，设置 scause 为对应编码后重定向到 Guest
		return truly_virtual_insn(vcpu, run, insn);
	case KVM_INSN_CONTINUE_NEXT_SEPC:   // 执行下一条指令
		vcpu->arch.guest_context.sepc += INSN_LEN(insn);
		break;
	default:
		break;
	}

	return (rc <= 0) ? rc : 1;
}
```

虚拟指令的处理函数 `truly_virtual_insn`：

```cpp
// arch/riscv/kvm/vcpu_insn.c: line 167
static int truly_virtual_insn(struct kvm_vcpu *vcpu, struct kvm_run *run,
			      ulong insn)
{
	struct kvm_cpu_trap utrap = { 0 };

	/* Redirect trap to Guest VCPU */
	utrap.sepc = vcpu->arch.guest_context.sepc;
	utrap.scause = EXC_VIRTUAL_INST_FAULT;
	utrap.stval = insn;
	utrap.htval = 0;
	utrap.htinst = 0;
	kvm_riscv_vcpu_trap_redirect(vcpu, &utrap);

	return 1;
}
```

其调用关系如下图所示：

<pre><div class="mermaid">
flowchart LR

subgraph arch/riscv/kvm/vcpu_insn.c
vvi[kvm_riscv_vcpu_virtual_insn]
tii[truly_illegal_insn]
tvi[truly_virtual_insn]
soi[system_opcode_insn]
end

subgraph arch/riscv/kvm/vcpu_exit.c
rd[kvm_riscv_vcpu_unpriv_read]
rdrct[kvm_riscv_vcpu_trap_redirect]
end

vvi--Illegal Compressed-->rd
vvi--Illegal Compressed-->rdrct
vvi--Legal Compressed-->tii
vvi--SYSTEM-->soi
vvi-->tii

tii-->rdrct

soi-->tii
soi-->tvi

</div></pre>

（[下载由 Mermaid 生成的 PNG 图片][005]）

### Guest page fault

参见 [上篇][2] 关于 gstage page fault 处理函数的分析，调用关系如下图所示：

<pre><div class="mermaid">
flowchart LR

subgraph arch/riscv/kvm/vcpu.c
run[kvm_arch_vcpu_ioctl_run]
end

subgraph arch/riscv/kvm/vcpu_exit.c
gpgft[gstage_page_fault]
exit[kvm_riscv_vcpu_exit]
end

subgraph arch/riscv/kvm/vcpu_insn.c
ld[kvm_riscv_vcpu_mmio_load]
st[kvm_riscv_vcpu_mmio_store]
end

subgraph arch/riscv/kvm/mmu.c
mp[kvm_riscv_gstage_map]
end

run-->exit-->gpgft

gpgft--error hva or store fault-->ld
gpgft--error hva or store fault-->st

gpgft-->mp
</div></pre>

（[下载由 Mermaid 生成的 PNG 图片][006]）

### SBI 系统调用

系统调用的处理通过调用 `kvm_riscv_vcpu_sbi_ecall` 函数实现，如下方代码块所示：

[SBI（Supervisor Binary Interface）][3] 是直接运行在 Machine Mode 下的，为上层 OS 提供统一接口的程序，具有最高权限。而 Guest 访问 SBI 系统调用，是在 KVM 中模拟实现，不是实际访问 Machine Mode 中的 SBI firmware。KVM 通过直接访问和设置寄存器（`cp->a7`, `cp->a0`, `cp->a0` 等）的值来实现对 SBI 系统调用的处理。

```cpp
int kvm_riscv_vcpu_sbi_ecall(struct kvm_vcpu *vcpu, struct kvm_run *run)
{
	int ret = 1;
	bool next_sepc = true;
	bool userspace_exit = false;
	struct kvm_cpu_context *cp = &vcpu->arch.guest_context;
	const struct kvm_vcpu_sbi_extension *sbi_ext;
	struct kvm_cpu_trap utrap = { 0 };
	unsigned long out_val = 0;
	bool ext_is_v01 = false;

	/* 根据当前参数（a7）确定对应 SBI 中被调用的扩展（ext）及其 handler，获得返回值 ret；否则设置 ret 的值为不支持 SBI */
	sbi_ext = kvm_vcpu_sbi_find_ext(cp->a7);
	if (sbi_ext && sbi_ext->handler) {
#ifdef CONFIG_RISCV_SBI_V01
		if (cp->a7 >= SBI_EXT_0_1_SET_TIMER &&
		    cp->a7 <= SBI_EXT_0_1_SHUTDOWN)
			ext_is_v01 = true;
#endif
		ret = sbi_ext->handler(vcpu, run, &out_val, &utrap, &userspace_exit);
	} else {
		/* Return error for unsupported SBI calls */
		cp->a0 = SBI_ERR_NOT_SUPPORTED;
		goto ecall_done;
	}

	/* 依据经由 SBI ext handler 处理之后返回的 utrap 判断是否为需要进一步处理的 trap 等 */
	/* Handle special error cases i.e trap, exit or userspace forward */
	if (utrap.scause) {
		/* No need to increment sepc or exit ioctl loop */
		ret = 1;
		utrap.sepc = cp->sepc;
		kvm_riscv_vcpu_trap_redirect(vcpu, &utrap);
		next_sepc = false;
		goto ecall_done;
	}

	/* 依据 SBI 返回结果判断是否需要停止运行，或直接向 Guest 返回特定错误代码 */
	/* Exit ioctl loop or Propagate the error code the guest */
	if (userspace_exit) {
		next_sepc = false;
		ret = 0;
	} else {
		/**
		 * SBI extension handler always returns an Linux error code. Convert
		 * it to the SBI specific error code that can be propagated the SBI
		 * caller.
		 */
		ret = kvm_linux_err_map_sbi(ret);
		cp->a0 = ret;
		ret = 1;
	}
/* 设置全局 pc 以及返回值 */
ecall_done:
	if (next_sepc)
		cp->sepc += 4;
	if (!ext_is_v01)
		cp->a1 = out_val;

	return ret;
}
```

对应的函数调用关系如下图：

<pre><div class="mermaid">
flowchart LR

subgraph arch/riscv/kvm/vcpu.c
run[kvm_arch_vcpu_ioctl_run]
end

subgraph arch/riscv/kvm/vcpu_sbi.c
ecall[kvm_riscv_vcpu_sbi_ecall]
fe[kvm_vcpu_sbi_find_ext]
err[kvm_linux_err_map_sbi]
end

subgraph arch/riscv/kvm/vcpu_exit.c
exit[kvm_riscv_vcpu_exit]
rdrct[kvm_riscv_vcpu_trap_redirect]
end

run-->exit-->ecall-->fe
ecall-->rdrct
ecall-->err
</div></pre>

（[下载由 Mermaid 生成的 PNG 图片][007]）

## 总结

本文结合 KVM 中有关异常处理的实现，讨论了在添加 H 扩展之后的虚拟指令异常、guest page fault 以及来自 guest 的系统调用的处理。

## 参考资料

- [RISC-V 特权指令集手册][1]
- [RISC-V Linux][8]

[1]: https://riscv.org/technical/specifications/privileged-isa/
[2]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20221011-riscv-kvm-mem-virt-impl.md#g-stage-page-fault
[3]: https://github.com/riscv-non-isa/riscv-sbi-doc
[004]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/riscv-kvm/excp-impl/mermaid-riscv-kvm-excp-impl-1.png
[005]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/riscv-kvm/excp-impl/mermaid-riscv-kvm-excp-impl-2.png
[006]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/riscv-kvm/excp-impl/mermaid-riscv-kvm-excp-impl-3.png
[007]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/riscv-kvm/excp-impl/mermaid-riscv-kvm-excp-impl-4.png
[8]: https://gitee.com/tinylab/riscv-linux
