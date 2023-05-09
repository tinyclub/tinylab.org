---
layout: post
author: 'XiaKai Pan'
title: 'RISC-V KVM 虚拟化：用户态程序'
draft: false
plugin: 'mermaid'
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-kvm-user-app/
description: 'RISC-V KVM 虚拟化：用户态程序'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - KVM
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [codeinline images urls]
> Author:   潘夏凯 <13212017962@163.com>
> Date:     2022/08/02
> Revisor:  Falcon, taotieren, Bin Meng, tjytimi, walimis
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V 虚拟化技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I5E4VB)
> Sponsor:  PLCT Lab, ISCAS


## 概览

本文以 kvm-hello-world, kvmtool 和 QEMU 为例，分析了基于 KVM API 的虚拟化实现中所用到的用户态程序的结构。包括虚拟机、vCPU 的创建、初始化和运行。

## 软件版本

| 软件            | 提交 ID 或版本号                         | 仓库链接                               |
| --------------- | ---------------------------------------- | -------------------------------------- |
| Linux Kernel    | 5.19-rc5                                 | https://www.kernel.org/                |
| kvm-hello-world | e9ab0f26e892fa3794f2f991144be7fa45ddd082 | https://github.com/dpw/kvm-hello-world |
| kvmtool         | 6a1f699108e5c2a280d7cd1f1ae4816b8250a29f | https://github.com/kvmtool/kvmtool     |
| QEMU            | a74c66b1b933b37248dd4a3f70a14f779f8825ba | https://www.qemu.org/                  |

## KVM 虚拟化术语

| 层次              | 名称                                            | 功能                                  |
| ----------------- | ----------------------------------------------- | ------------------------------------- |
| Virtualized Layer | Guest Applications                              | 运行在 Guest 中的应用程序             |
| Virtualized Layer | VM (Virtual Machine)                            | 虚拟机                                |
| User Layer        | User Application                                | 调用 KVM API 创建 VM                  |
| Kernel Layer      | Include KVM module in Linux Kernel (hypervisor) | 用于支持管理的功能抽象                |
| Hardware Layer    | Host Machine                                    | 由 CPU, Memory, Disk 等硬件构成的系统 |

## KVM 简介

RedHat 网站的一篇 [博文][1] 对 KVM 做了简要介绍，现整理摘录如下：

- Hypervisor 应提供什么功能？

  作为运行在宿主机的 Hypervisor，它应该提供一些操作系统级组件，例如内存管理器，进程调度进程，输入/输出（I / O）堆栈，设备驱动进程，安全管理器，网络堆栈等，以运行虚拟机。

- KVM 如何工作？

  KVM 是内置于 Linux 内核中的模块，它重用了内核中描述的上述组件，并为 VM 提供专用的虚拟硬件如网卡、GPU、CPU、内存和磁盘。每个 VM 都作为常规 Linux 进程实现，它由虚拟机管理进程中的标准 Linux 调度器进行调度。

## kvm-hello-world

kvm-hello-world 是一个使用 KVM API 管理 VM 的精简示例。我们将从此应用开始，演示如何使用 KVM 创建虚拟机的简单方法。该示例基于 x86 架构的 CPU，x86 架构的虚拟化功能有两种主流实现，即英特尔的 VT-x 或 AMD 的 AMD-V。

该示例的主体就是代码文件 `kvm-hello-world.c`。

### VM（虚拟机）和 vCPU（虚拟处理器）的创建

下表对比了 VM 和 vCPU 的创建过程：

| 项目                         | VM（虚拟机）的创建         | vCPU 的创建                 |
| ---------------------------- | -------------------------- | --------------------------- |
| 初始化函数                   | vm_init                    | vcpu_init                   |
| 挂载 /dev/kvm 设备           | open(/dev/kvm)             |
| `ioctl()` 检查 KVM 软件版本  | KVM_GET_API_VERSION        |
| `ioctl()` 创建 VM 或 vCPU    | KVM_CREATE_VM              | KVM_CREATE_VCPU             |
| `mmap()` 申请虚拟机内存      | vm->mem, mem_size          | vm->kvm_run, vcpu_mmap_size |
| 额外设置                     | `madvise`                  |
|                              | `memreg` initiation        |
| `ioctl()` 初始化申请到的内存 | KVM_SET_USER_MEMORY_REGION |

接下来，对照代码进行详细分析：

```C
// kvm-hello-world/kvm-hello-world.c: line 66

struct vm
{
	int sys_fd;
	int fd;
	char *mem;
};

void vm_init(struct vm *vm, size_t mem_size)
{
	int api_ver;
	struct kvm_userspace_memory_region memreg;

	/* 打开设备 /dev/kvm，检查 KVM 版本 */
	/* Open /dev/kvm and checks the version. */
	vm->sys_fd = open("/dev/kvm", O_RDWR);
	// ...
	api_ver = ioctl(vm->sys_fd, KVM_GET_API_VERSION, 0);
	// ...

	/* 调用 KVM_CREATE_VM 创建虚拟机 */
	/* Makes a KVM_CREATE_VM call to creates a VM. */
	vm->fd = ioctl(vm->sys_fd, KVM_CREATE_VM, 0);       	// ...

	/* 调用 mmap() 函数为虚拟机申请内存 */
	/* Uses mmap to allocate some memory for the VM. */
	vm->mem = mmap(NULL, mem_size, ..., -1, 0);				// ...

	/* 调用 KVM_SET_USER_MEMORY_REGION 初始化申请到的内存区域 */
	/* Make a KVM_SET_USER_MEMORY_REGION call to set memory */
	if (ioctl(vm->fd, KVM_SET_USER_MEMORY_REGION, &memreg) < 0)
	/* ... */
}
```

`vcpu_init()` 创建 vCPU：

```C
// kvm-hello-world/kvm-hello-world.c: line 134

struct vcpu
{
	int fd;
	struct kvm_run *kvm_run;
};

void vcpu_init(struct vm *vm, struct vcpu *vcpu)
{
	int vcpu_mmap_size;

	/* 调用 KVM_CREATE_VCPU 为已创建的虚拟机创建虚拟 CPU，调用 mmap() 函数将 VCPU 映射到指定内存区域 */
	/* Makes a KVM_CREATE_VCPU call to creates a VCPU within the VM, and mmap its control area. */
	vcpu->fd = ioctl(vm->fd, KVM_CREATE_VCPU, 0);
	/* ... */

	vcpu_mmap_size = ioctl(vm->sys_fd, KVM_GET_VCPU_MMAP_SIZE, 0);
	if (vcpu_mmap_size <= 0)
	{
		perror("KVM_GET_VCPU_MMAP_SIZE");
		exit(1);
	}

	vcpu->kvm_run = mmap(NULL, vcpu_mmap_size, PROT_READ | PROT_WRITE,
						 MAP_SHARED, vcpu->fd, 0);
	if (vcpu->kvm_run == MAP_FAILED)
	{
		perror("mmap kvm_run");
		exit(1);
	}
}
```

### VM 运行前准备

在创建 VM 和 vCPU 并为它们分配内存后，在正式运行 VM 之前，还需要做一些准备工作。这些准备工作在函数 `run_xxx_mode()` 中进行，在 `run_kvm()` 被调用之前完成，细节如下表所示：

| 项目        | 运行实模式                                           | 运行其他模式     |
| ----------- | ---------------------------------------------------- | ---------------- |
| definition  | `sregs`, `regs`                                      |                  |
| test sregs  | KVM_GET_SREGS                                        |
| setup sregs | `sregs.cs.selector = 0; sregs.cs.base = 0;`          | `setup_xxx_mode` |
| set sregs   | KVM_SET_SREGS                                        |
| setup regs  | KVM_SET_REGS                                         |
| set regs    | `memcpy(vm->mem, guestX, guestX_end - guestX);` X=16 | X=32, 64, 64     |
| return      | run_kvm: `ioctl(vcpu->fd, KVM_RUN, 0)`               |

总体来看，准备工作可以分为三个步骤：`KVM_GET_SREGS` 测试，`sregs` 的初始化与传入 VM，`regs` 的初始化与传入 VM。

下方代码是 x86 准备运行保护模式的代码实现。

```C
// kvm-hello-world/kvm-hello-world.c: line 228

extern const unsigned char guest32[], guest32_end[];

int run_protected_mode(struct vm *vm, struct vcpu *vcpu)
{
	struct kvm_sregs sregs;
	struct kvm_regs regs;

	// 测试是否能成功获取 VM 的非通用寄存器
	// test sregs
	printf("Testing protected mode\n");
	if (ioctl(vcpu->fd, KVM_GET_SREGS, &sregs) < 0) {
		// ...
	}
	// 初始化非通用寄存器
	// setup & set sregs
	setup_protected_mode(&sregs);
	if (ioctl(vcpu->fd, KVM_SET_SREGS, &sregs) < 0) {
		// ...
	}

	// 初始化通用寄存器
	// setup & set regs
	memset(&regs, 0, sizeof(regs));
	regs.rflags = 2;
	regs.rip = 0;
	if (ioctl(vcpu->fd, KVM_SET_REGS, &regs) < 0) {
		// ...
	}

	// 初始化 VM 的内存区域
	memcpy(vm->mem, guest32, guest32_end - guest32);

	return run_vm(vm, vcpu, 4);
}

```

如下代码是保护模式下 `sregs` 初始化函数 `setup_protected_mode` 的实现，`sregs` 和 `regs` 在 `/usr/include/x86_64-linux-gnu/asm/kvm.h` 中定义。`kvm_sregs` 用于表示不同架构 vCPU 的特殊寄存器。

```C
// kvm-hello-world/kvm-hello-world.c: line 247

/* 特定模式（此处为 x86 保护模式）下非通用寄存器的赋值 */
/* mode setup: assign values to sregs */
static void setup_protected_mode(struct kvm_sregs *sregs)
{
	struct kvm_segment seg = {
		.base = 0,
		.limit = 0xffffffff,
		.selector = 1 << 3,
		.present = 1,
		.type = 11, /* Code: execute, read, accessed */
		.dpl = 0,
		.db = 1,
		.s = 1, /* Code/data */
		.l = 0,
		.g = 1, /* 4KB granularity */
	};

	sregs->cr0 |= CR0_PE; /* enter protected mode */

	sregs->cs = seg;

	seg.type = 3; /* Data: read/write, accessed */
	seg.selector = 2 << 3;
	sregs->ds = sregs->es = sregs->fs = sregs->gs = sregs->ss = seg;
}
```

在 x86 架构中，`kvm_regs` 定义如下，它们作为 vCPU 的通用寄存器，将在后续运行中用来保存 vCPU 的状态。

```C
// /usr/include/x86_64-linux-gnu/asm/kvm.h: line 148

/* for KVM_GET_SREGS and KVM_SET_SREGS */
struct kvm_sregs {
	/* out (KVM_GET_SREGS) / in (KVM_SET_SREGS) */
	struct kvm_segment cs, ds, es, fs, gs, ss;
	struct kvm_segment tr, ldt;
	struct kvm_dtable gdt, idt;
	__u64 cr0, cr2, cr3, cr4, cr8;
	__u64 efer;
	__u64 apic_base;
	__u64 interrupt_bitmap[(KVM_NR_INTERRUPTS + 63) / 64];
};

// /usr/include/x86_64-linux-gnu/asm/kvm.h: line 115

/* for KVM_GET_REGS and KVM_SET_REGS */
struct kvm_regs {
	/* out (KVM_GET_REGS) / in (KVM_SET_REGS) */
	__u64 rax, rbx, rcx, rdx;
	__u64 rsi, rdi, rsp, rbp;
	__u64 r8,  r9,  r10, r11;
	__u64 r12, r13, r14, r15;
	__u64 rip, rflags;
};
```

### 在指定模式下运行 VM

通过命令行参数确定了虚拟机将运行在什么模式之下，即确定了 `run_xxx_mode()` 中的 `xxx` 的值，并完成上一节的准备工作之后，最后一步就是调用 `run_kvm()` 来运行 VM。

`run_kvm()` 函数包含一个无限循环，实现两个功能：一个是通过 `ioctl(vcpu->fd, KVM_RUN, 0)` 运行 vCPU，另一个是判断退出 VM 的原因（如 `HLT` 指令，IO）并作出对应处理。对应代码如下：

```C
// kvm-hello-world/kvm-hello-world.c: line 156

int run_vm(struct vm *vm, struct vcpu *vcpu, size_t sz)
{
	struct kvm_regs regs;
	uint64_t memval = 0;

	// 无限循环，执行 KVM_RUN
	// an infinite loop for KVM_RUN
	for (;;)
	{
		if (ioctl(vcpu->fd, KVM_RUN, 0) < 0)
		{
			perror("KVM_RUN");
			exit(1);
		}

	// VM 退出处理：HLT（halt）或者有 Input/Output 中断请求
	// exit reason handling (HLT, IO)
	switch (vcpu->kvm_run->exit_reason)
	{
	case KVM_EXIT_HLT:
		goto check;

	case KVM_EXIT_IO:
		/* ... */

	default:
		/* ... */
	}
	}
}
```

### 小结

综上所述，kvm-hello-world 的实现是较为清晰的，可以分为如下步骤：

1. 打开 `/dev/kvm`，检查 KVM API 版本。
2. 用 `KVM_CREATE_VM` 创建虚拟机，使用 `mmap` 为虚拟机申请内存。
3. 用 `KVM_CREATE_VCPU` 创建虚拟机 CPU，使用 `mmap` 为 CPU 申请内存区域（存储寄存器等信息）。
4. 设置 CPU 寄存器和虚拟机内存初始值。
5. 调用 `KVM_RUN` 执行 CPU。

为方便查阅，整个过程汇总成下表：

| step | related data structure        | purpose              | execution result                                                  |
| ---- | ----------------------------- | -------------------- | ----------------------------------------------------------------- |
| 1    | `vm->sys_fd`                  | mount                | `vm->sys_fd = open("/dev/kvm", O_RDWR);`                          |
| 1    | `vm->sys_fd`                  | check version        | `api_ver = ioctl(vm->sys_fd, KVM_GET_API_VERSION, 0);`            |
| 2    | from `sys_fd` to `fd` of `vm` | create VM            | `vm->fd = ioctl(vm->sys_fd, KVM_CREATE_VM, 0);`                   |
| 2    | `vm->mem`                     | allocate VM memory   | `vm->mem = mmap(NULL, mem_size, ..., -1, 0);`                     |
| 3    | `vcpu->vm_fd`                 | create vcpu          | `vcpu->fd = ioctl(vm->fd, KVM_CREATE_VCPU, 0);`                   |
| 3    | `vcpu->kvm_run`               | allocate vcpu memory | `vcpu->kvm_run = mmap(NULL, vcpu_mmap_size, ..., vcpu->fd, 0);`   |
| 4    | `vcpu->vm_fd`                 | set sregs of vcpu    | `ioctl(vcpu->fd, KVM_SET_SREGS, &sregs)`                          |
| 4    | `vcpu->vm_fd`                 | set regs of vcpu     | `ioctl(vcpu->fd, KVM_SET_REGS, &regs)`                            |
| 4    | `vm->mem`                     | set VM memory        | `memcpy(vm->mem, guestX, guestX_end - guestX);` X depends on mode |
| 5    | `vcpu->fd`                    | execute vCPU         | `ioctl(vcpu->fd, KVM_RUN, 0)`                                     |

<pre><div class="mermaid">
graph LR

vmsz[vcpu_mmap_size]

subgraph kernel
kvm[`/dev/kvm`]
km[memory]
end

subgraph struct vm
kvm-- 1. open -->msfd[vm->sys_fd]
msfd-- 2. KVM_CREATE_VM-->mfd[vm->fd]
km-- 2. mmap -->mm[vm->mem]
end

subgraph struct vcpu
mfd-- 3. KVM_CREATE_VCPU--->ufd[vcpu->fd]
ur[vcpu->kvm_run]
km-- 3. mmap-->ur
end

msfd-- 3. KVM_GET_VCPU_MMAP_SIZE-->vmsz
vmsz-- 3. mmap -->ur

ufd-- 4. KVM_SET_xREGS-->ufd
mm-- 4. memcpy--->mm

ufd-- 5. execute --->ufd

</div></pre>

（[下载由 Mermaid 生成的 PNG 图片][006]）

主函数调用上述函数实现，从命令行读入参数，创建并运行虚拟机：

```C
// kvm-hello-world/kvm-hello-world.c: line 440
int main(int argc, char **argv)
{
	struct vm vm;
	struct vcpu vcpu;
	enum
	{
		REAL_MODE,
		PROTECTED_MODE,
		PAGED_32BIT_MODE,
		LONG_MODE,
	} mode = REAL_MODE;

	// 处理命令行参数以判断 VM 以什么模式运行
	// parse cmd arg to verify running mode (real, protected, ...)
	while ((opt = getopt(argc, argv, "rspl")) != -1)
	{
		switch (opt) {...}
	}

	// VM 和 vCPU 的初始化
	// VM and vCPU init
	vm_init(&vm, 0x200000);
	vcpu_init(&vm, &vcpu);

	// run vm
	switch (mode)
	{
	case REAL_MODE:
		return !run_real_mode(&vm, &vcpu);
	case ...
	}

	return 1;
}
```

## kvmtool

[kvmtool][4] 是一个支持多架构的用户态程序的实现，而 kvm-hello-world 当前实现仅支持 x86 架构，此节将结合上述对于用户态程序架构的分析考察 kvmtool 的实现，尤其是 RISC-V 架构不同于 x86 架构的 vCPU 的初始化。

### VM 的创建

```C
// kvm.c: line 436
int kvm__init(struct kvm *kvm)
{
	int ret;

	if (!kvm__arch_cpu_supports_vm()) {
		pr_err("Your CPU does not support hardware virtualization");
		ret = -ENOSYS;
		goto err;
	}

	/* 挂载设备 /dev/kvm */
	/* mount and validate whether it succeed */
	kvm->sys_fd = open(kvm->cfg.dev, O_RDWR);   // ...

	/* 检查 KVM SPI 版本 */
	/* KVM API version check */
	ret = ioctl(kvm->sys_fd, KVM_GET_API_VERSION, 0);   // ...

	/* 创建 VM */
	/* Create VM and validate the result */
	kvm->vm_fd = ioctl(kvm->sys_fd, KVM_CREATE_VM, kvm__get_vm_type(kvm));  // ...

	/* 检查 KVM 与架构相关的扩展 */
	/* check kvm extension related to architecture */
	if (kvm__check_extensions(kvm)) { /* ... */ }

	/* 申请 VM 内存 */
	/* Allocate guest memory */
	kvm__arch_init(kvm);

	/* 初始化申请到的 VM 内存 */
	/* Initialize memory */
	INIT_LIST_HEAD(&kvm->mem_banks);
	kvm__init_ram(kvm);

	/* 加载内核镜像文件 */
	/* load guest kernel image (load firmware/BIOS if necessary for guest) */
	if (!kvm->cfg.firmware_filename) { /* ... */}
	if (kvm->cfg.firmware_filename) { /* ... */ }

	return 0;
}
core_init(kvm__init);
```

### vCPU 的创建

vCPU 的创建是通过 `kvm-cpu.c` 文件中调用不同架构的 vCPU 创建函数来实现的。不同架构的 vCPU 实现在 `kvmtool/{arch}` 文件夹下，如 `kvmtool/riscv/`。

#### 创建 vCPU 的统一接口

`kvm_cpu__init` 用于创建指定数目的 vCPU，之后每个特定架构的 vCPU 的创建均通过调用 `kvmtool/{arch}/kvm-cpu.c` 中的函数来实现。

kvmtool 总的 vCPU 创建函数如下：

```C
// kvm-cpu.c: line 260
int kvm_cpu__init(struct kvm *kvm)
{
	int max_cpus, recommended_cpus, i;

	max_cpus = kvm__max_cpus(kvm);
	recommended_cpus = kvm__recommended_cpus(kvm);

	if (kvm->cfg.nrcpus > max_cpus) {
		printf("  # Limit the number of CPUs to %d\n", max_cpus);
		kvm->cfg.nrcpus = max_cpus;
	} else if (kvm->cfg.nrcpus > recommended_cpus) {
		printf("  # Warning: The maximum recommended amount of VCPUs"
			" is %d\n", recommended_cpus);
	}

	kvm->nrcpus = kvm->cfg.nrcpus;

	task_eventfd = eventfd(0, 0);
	if (task_eventfd < 0) {
		pr_warning("Couldn't create task_eventfd");
		return task_eventfd;
	}

	kvm->cpus = calloc(kvm->nrcpus + 1, sizeof(void *));
	if (!kvm->cpus) {
		pr_warning("Couldn't allocate array for %d CPUs", kvm->nrcpus);
		return -ENOMEM;
	}

	for (i = 0; i < kvm->nrcpus; i++) {
		kvm->cpus[i] = kvm_cpu__arch_init(kvm, i);
		if (!kvm->cpus[i]) {
			pr_warning("unable to initialize KVM VCPU");
			goto fail_alloc;
		}
	}

	return 0;

fail_alloc:
	for (i = 0; i < kvm->nrcpus; i++)
		free(kvm->cpus[i]);
	return -ENOMEM;
}
base_init(kvm_cpu__init);
```

#### RISC-V vCPU 的创建

在 kvmtool 中，一个 RISC-V 架构的 vCPU 的创建通过如下函数实现：

```C
// {arch}/kvm-cpu.c: riscv/kvm-cpu.c, line 48
struct kvm_cpu *kvm_cpu__arch_init(struct kvm *kvm, unsigned long cpu_id)
{
	struct kvm_cpu *vcpu;
	u64 timebase = 0;
	unsigned long isa = 0;
	int coalesced_offset, mmap_size;
	struct kvm_one_reg reg;

	vcpu = calloc(1, sizeof(struct kvm_cpu));	// ...

	vcpu->vcpu_fd = ioctl(kvm->vm_fd, KVM_CREATE_VCPU, cpu_id);	// ...

	// ...

	mmap_size = ioctl(kvm->sys_fd, KVM_GET_VCPU_MMAP_SIZE, 0);	// ...

	vcpu->kvm_run = mmap(NULL, mmap_size, PROT_RW, MAP_SHARED, vcpu->vcpu_fd, 0);

	// ...

	/* 设置对应的 ISA */
	/* set isa, test KVM_SET_ONE_REG */
	reg.id = RISCV_CONFIG_REG(isa);
	reg.addr = (unsigned long)&isa;

	// ...

	/* 设置 vCPU 参数 */
	/* Populate the vcpu structure. */
	vcpu->kvm		= kvm;
	vcpu->cpu_id		= cpu_id;
	vcpu->riscv_isa		= isa;
	vcpu->riscv_xlen	= __riscv_xlen;
	vcpu->riscv_timebase	= timebase;
	vcpu->is_running	= true;

	return vcpu;
}
```

此函数主要完成如下功能：调用 `KVM_CREATE_VCPU` 创建 vCPU 并设置 `kvm`, `cpu_id`, `isa`, `xlen` 等属性。

### vCPU 的运行

上述创建过程并未完成 vCPU 的寄存器初始化工作，vCPU 的初始化将在运行前完成，如本小结所示。在 kvmtool 中，`main.c` 中的 `main()` 函数获取命令行参数并进行参数解析，之后通过如下调用过程实现 vCPU 的运行：

<pre><div class="mermaid">
graph

subgraph main.c
M[main]--->hkc[handle_kvm_command]
end

hkc--->hc

subgraph kvm-cmd.c
cs(struct cmd_struct kvm_commands)
hc[handle_command]-.-cs-.-kgc[kvm_get_command]-.->p===cs

end

subgraph builtin-command.c

subgraph builtin-run.c
kcrun[kvm_cmd_run]--->kvm_cmd_run_work--->kvm_cpu_thread
end
kcr[kvm_cmd_resume]
others[...]
end

cs-.->kcrun
cs-.->kcr
cs-.->others

kvm_cpu_thread--->start

subgraph kvm-cpu.c
base_init==>init
init[kvm_cpu__init]
start[kvm_cpu__start]
end

start--->kvm_cpu__reset_vcpu
init--->kvm_cpu__arch_init
subgraph riscv/kvm-cpu.c
kvm_cpu__reset_vcpu
kvm_cpu__arch_init
end

</div></pre>

（[下载由 Mermaid 生成的 PNG 图片][007]）

## QEMU

### VM, vCPU 的创建与初始化

在 QEMU 中，KVM 是作为虚拟化加速器而存在的，其代码实现在 `qemu/accel/` 文件夹下，VM 和 vCPU 的创建、初始化和运行的通用代码都在 `qemu/accel/kvm/kvm-all.c` 中实现，而后 `qemu/accel/kvm/kvm-accel-ops.c` 统一对其进行调用实现虚拟机加速的功能，如 vCPU 线程创建函数 `kvm_vcpu_thread_fn` 通过调用 `qemu/accel/kvm/kvm-all.c` 中的 `kvm_init_vcpu` 函数初始化一个 vCPU，通过调用 `kvm_destroy_vcpu` 函数销毁 vCPU：

```C
// accel/kvm/kvm-accel-ops.c: line 27
static void *kvm_vcpu_thread_fn(void *arg)
{
	CPUState *cpu = arg;
	int r;
	// ...
	r = kvm_init_vcpu(cpu, &error_fatal);
	// ...
	kvm_destroy_vcpu(cpu);
	// ...
	return NULL;
}
```

VM 通过 `kvm_init` 函数创建，该函数在 `accel/kvm/kvm-all.c` 中实现：

```c
// qemu/accel/kvm/kvm-all.c: line 2318
static int kvm_init(MachineState *ms) {
	// ...
	KVMState *s;
	// ...
	s->fd = qemu_open_old("/dev/kvm", O_RDWR);      /* ... */
	ret = kvm_ioctl(s, KVM_GET_API_VERSION, 0);     /* ... */
	// ...
	do {
	    ret = kvm_ioctl(s, KVM_CREATE_VM, type);
	} while (ret == -EINTR);
}
```

vCPU 在函数 `kvm_init_vcpu` 中实现，代码如下：

```c
// qemu/accel/kvm/kvm-all.c: line 443
static int kvm_get_vcpu(KVMState *s, unsigned long vcpu_id)
{
    // ...

	/* 调用 KVM_CREATE_VCPU 创建 vCPU */
    /* create vcpu from KVM_CREATE_VCPU */
    return kvm_vm_ioctl(s, KVM_CREATE_VCPU, (void *)vcpu_id);
}

// qemu/accel/kvm/kvm-all.c: line 461
int kvm_init_vcpu(CPUState *cpu, Error **errp)
{
	/* 调用 kvm_get_vcpu() 创建 vCPU */
	/* create vcpu from kvm_get_vcpu() */
	ret = kvm_get_vcpu(s, kvm_arch_vcpu_id(cpu));
	// ...
	/* 为 vCPU 申请内存 */
	/* allocate vcpu memory */
	mmap_size = kvm_ioctl(s, KVM_GET_VCPU_MMAP_SIZE, 0);    // ...
	cpu->kvm_run = mmap(NULL, mmap_size, PROT_READ | PROT_WRITE, MAP_SHARED,
	                    cpu->kvm_fd, 0);                    // ...
	/* 初始化 vCPU */
	/* init vcpu, implemented in /qemu/target/riscv/kvm.c */
	ret = kvm_arch_init_vcpu(cpu);
	// ...
}
```

特定架构的 vCPU 具有不同的初始化方式，RISC-V vCPU 的初始化函数如下：
其中 `kvm_riscv_reg_id` 根据传入的 config 确定位宽（32 或 64），之后 `kvm_get_one_reg` 函数取寄存器组中指示 ISA 的寄存器的值并返回。

```c
// target/riscv/kvm.c: line 397
int kvm_arch_init_vcpu(CPUState *cs)
{
	int ret = 0;
	target_ulong isa;
	RISCVCPU *cpu = RISCV_CPU(cs);
	CPURISCVState *env = &cpu->env;
	uint64_t id;
	qemu_add_vm_change_state_handler(kvm_riscv_vm_state_change, cs);
	/* 配置寄存器映射为类型 1 */
	/* Config registers are mapped as type 1 */
	// #define KVM_REG_RISCV_CONFIG		(0x01 << KVM_REG_RISCV_TYPE_SHIFT)
	// #define KVM_REG_RISCV_CONFIG_REG(name)	\
	//	(offsetof(struct kvm_riscv_config, name) / sizeof(unsigned long))
	id = kvm_riscv_reg_id(env, KVM_REG_RISCV_CONFIG,
	                      KVM_REG_RISCV_CONFIG_REG(isa));
	ret = kvm_get_one_reg(cs, id, &isa);
	if (ret) {
	    return ret;
	}
	env->misa_ext = isa;
	return ret;
}
```

## 总结

### 用户态程序的结构

用户态程序依据是否架构相关可以分为两部分，一部分是通用的、架构无关的代码，其功能包括 VM、vCPU 等的创建、虚拟内存的申请，另一部分是架构相关的代码，具体包括 vCPU 的寄存器组的初始化。

结合 kvm-hello-world, kvmtool, QEMU 中创建 KVM 虚拟机的源码分析，我们可以得知，不同架构虚拟机的创建过程中，主要的不同来自于虚拟机 CPU 的架构不同，如 x86, RISC-V, ARM。所有的用户态程序为了支持特定架构的虚拟机，均需要针对其目标架构做单独处理。如 kvmtool 中的 x86, riscv, powerpc 等文件夹下的 `kvm.c`, `kvm-cpu.c` 就是针对这些架构的特别实现，类似的还有 QEMU 中 `target/riscv/kvm.c` 的实现。

### 架构在用户态程序里的体现

综上可知，在用户态程序的实现中，需要对不同的架构做出不同的处理，具体而言则是 vCPU 创建之后的寄存器初始化各有不同，所以需要各自单独处理。对于 RISC-V vCPU 的初始化而言，相较于 x86 架构需要分别针对实模式、保护模式对段寄存器等分别进行不同的初始化，RISC-V vCPU 的初始化较为简单，仅需依据 vCPU 的 `config` 针对 `pc`, `a0`, `a1` 进行设置。

下面将参考用户态程序中架构相关的代码实现，结合特定架构的指令集标准，分析 KVM 中 CPU 虚拟化的具体机制。

## 参考资料

- [What is KVM?][1]
- [Linux Kernel][2]
- [kvm-hello-world][3]
- [kvmtool][4]
- [QEMU][5]

[1]: https://www.redhat.com/en/topics/virtualization/what-is-KVM#%E7%BA%A2%E5%B8%BDkvm%E8%99%9A%E6%8B%9F%E5%8C%96
[2]: https://www.kernel.org/
[3]: https://github.com/dpw/kvm-hello-world
[4]: https://github.com/kvmtool/kvmtool
[5]: https://www.qemu.org/
[006]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/riscv-kvm_user_app/mermaid-kvm-user-app-1.png
[007]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/riscv-kvm_user_app/mermaid-kvm-user-app-2.png
