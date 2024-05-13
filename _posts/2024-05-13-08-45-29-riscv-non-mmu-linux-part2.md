---
layout: post
author: 'Zhangjin Wu'
title: 'RISC-V Non-MMU Linux (2): 从 M/S/U 到 M/U 的层级转变'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-non-mmu-linux-part2/
description: 'RISC-V Non-MMU Linux (2): 从 M/S/U 到 M/U 的层级转变'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - MMU
  - Non-MMU
  - 特权等级
  - Machine
  - Supervisor
  - User
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces urls]
> Author:    Falcon <falcon@tinylab.org>
> Date:      2023/03/09
> Revisor:   Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 简介

上一篇，我们已经从内核到应用跑通了 RISC-V Non-MMU 的实验，为后续的分析打下了非常好的基础。另外，那篇文章还提到 Non-MMU 内核工作在 Machine Mode，然后整个软件架构从原有的 M/S/U 三
层权限级别转变为更为扁平的 M/U 两层权限级别。

这种转变引起了我们对 RISC-V 软硬件协同工作的思考，即 RISC-V 硬件从开机上电、引导加载、内核启动到应用程序执行的整个过程中，这些权限级别是如何设定与切换的。

本文将分别讨论在 MMU On 和 MMU Off 的情况下，各种权限级别在整个 RISC-V 软硬件生命周期中的演进与变化。

### RISC-V 特权等级

类似于其他的处理器架构，RISC-V 也提供了多种层级的权限模式：Machine/Supervisor/User。更复杂地，实际还有 Debug, Hypervisor。

有了这种层级的划分以后，在系统安全、设备调试、功能扩展等方面就变得更简单一些。

不同层级之间有专门的 Entry 和 Exit 的机制。层级越高，权限越大，比如，某些寄存器与外设，低权限层级是不能直接访问的，需要通过专门的 Entry 机制调用更高层级的服务来实现，这个相当于在硬件上实现了隔离，这种调用机制软件上称为 ABI（User Mode 调用 Supervisor Mode）、SBI（Supervisor Mode 调用 Machine Mode）等。

关于硬件这块的约定这里不做展开，感兴趣的朋友可以直接看 RISC-V 的特权手册：<https://riscv.org/technical/specifications/>

### 本文讨论范围

本文将讨论，在整个 RISC-V 运行过程中，这种权限的级别是如何演变的。

#### MMU On

MMU On 的情况下，仅关注 Machine/Supervisor/User 这三级，简写为 M/S/U。

         [ User Mode ]
            |      ^
            |      |
          ecall   sret
    ABI     |      |
            v      |
       [ Supervisor Mode ]
            |      ^
            |      |
          ecall    mret
    SBI     |      |
            v      |
        [ Machine Mode ]

#### MMU Off

MMU Off 的情况下，仅关注 Machine/User 这两级，简写为 M/U。

         [ User Mode ]
            |      ^
            |      |
          ecall   mret
    ABI     |      |
            v      |
        [ Machine Mode ]

本文主要结合 QEMU, OpenSBI, Linux 来做介绍，完整的启动过程可以查看：[QEMU 启动方式分析（1）：QEMU 及 RISC-V 启动流程简介][002]。

接下来以 QEMU riscv64/virt 这款虚拟硬件板子为例来介绍，具体代码在这里：<https://github.com/qemu/qemu/blob/master/hw/riscv/virt.c>

同样地，如果没有特别说明，本文以 v6.2 作为演示内核版本（v6.3 有衰退），以 [Linux Lab](https://tinylab.org/linux-lab) 或 [Linux Lab Disk](https://tinylab.org/linux-lab-disk) 为实验环境。

## 从开机上电到执行应用

整个 RISC-V 的上电运行过程，一开始是从高权限模式（Machine Mode）往低权限模式（User Mode）演变的。

### BootRom 阶段：Machine Mode

首先是 BootRom，上电或硬件 Reset 以后会进入到 0x00001000 这个地址（相对应地，Debug 的入口地址在 0x0），这里是 Machine Mode。

QEMU 首先会 load bootrom，这个对应开机上电时执行的代码。

```
/* boot rom */

memory_region_init_rom(mask_rom, NULL, "riscv_virt_board.mrom",
memmap[VIRT_MROM].size, &error_fatal);
```

### Firmware 阶段：Machine Mode

#### MMU On

BootRom 之后接着走到 Firmware，比如 OpenSBI，此时还是在 Machine Mode。

如果没指定 BIOS，QEMU 会默认加载一个内置的 Firmware，否则会加载用户指定的 Firmware。

BootRom 执行后会跳到 Firmware，这里主要是为即将运行在 Supervisor Mode 的内核提供一些服务，这些服务只有在 Machine Mode 才能做，当然，具体的服务范围的约定其实一直在变，比如 timer，比如 console。RISC-V Firmware，即 Supervisor Binary Interface (SBI) 的 Spec 版本和硬件实现也在不断演进，本文撰写时 SBI 已经演进到 [v2.0-rc1][001]。

Firmware 的加载地址是 0x80000000，BootROM 执行完来到这里：

```
firmware_end_addr = riscv_find_and_load_firmware(machine, firmware_name, start_addr, NULL);
```

Firmware 的经典实现有 OpenSBI, RustSBI 等。

#### MMU Off

在 Non-MMU 的情况下，Linux 内核本身运行在 Machine Mode，它自身还“承担”了 Firmware 的角色，所以需要通过 `-bios none` 来禁止 QEMU 加载默认的 Firmware。

### Linux 阶段

#### MMU On

然后是内核部分，这时 Firmware 会跳到内核（如果有 U-Boot，会先跳到 U-Boot，U-Boot 承担 BootLoader 的角色），并且会切换到 Supervisor Mode。

内核一般是由 QEMU 的 `-kernel` 指定，rv64 默认加载地址一般是 0x80200000，而 rv32 是 0x80400000，具体可以看内核 head.S 的 Image header。

如果用 U-Boot 的话，`-kernel` 指定的就是 U-Boot，Kernel 部分再从其他地方加载，比如从 Flash 或根文件系统加载，也可以直接让 QEMU 通过 `-device loader,file=/path/to/Image,addr=0x84000000` 放到内存某个位置，dtb 也是一样，之后让 U-Boot 直接从内存转运到 Image header 中指定的 entry point。

QEMU 中加载 Linux 内核：

```
kernel_entry = riscv_load_kernel(machine, &s->soc[0], kernel_start_addr, true, NULL);
```

此时还会 load fdt，即 Device Tree：

```
riscv_load_fdt(fdt_load_addr, machine->fdt);
```

那具体是如何从 Machine Mode 切换到 Supervisor Mode 的呢？需要看 Firmware 的代码，这里以 OpenSBI 为例：

```
firmware/fw_jump.S:

    fw_next_mode:
        li	a0, PRV_S
        ret

    fw_next_addr:
        lla     a0, _jump_addr
        REG_L   a0, (a0)
        ret

lib/sbi/sbi_hart.c:
    sbi_hart_switch_mode:
        val = csr_read(CSR_MSTATUS);
        val = INSERT_FIELD(val, MSTATUS_MPP, next_mode);
        val = INSERT_FIELD(val, MSTATUS_MPIE, 0);
        csr_write(CSR_MSTATUS, val);
        csr_write(CSR_MEPC, next_addr);

        if (next_mode == PRV_S) {
                csr_write(CSR_STVEC, next_addr);
                csr_write(CSR_SSCRATCH, 0);
                csr_write(CSR_SIE, 0);
                csr_write(CSR_SATP, 0);
        }

        register unsigned long a0 asm("a0") = arg0;
        register unsigned long a1 asm("a1") = arg1;
        __asm__ __volatile__("mret" : : "r"(a0), "r"(a1));
        __builtin_unreachable();
```

Mode 切换的关键代码如上：

* 主要是设置 `MSTATUS` 这个寄存器，其中的 `MPP` 位域需要改为 `next_mode`
* MEPC 改为接下来要执行的地址 `next_addr`
* arg0 和 arg1 分别为 hart id 和 fdt addr
* 另外，还要关中断（SIE 和 MPIE 都设置为 0）
* 刚进入 Supervisor Mode 时还要关 MMU（SATP 初始化为 0，刚开始可以直接访问物理地址，跟 Firmware 一样）
* 用户态的异常入口也通过设定 STVEC 初始化成了 `next_addr`

配置完 `MSTATUS` 和 `MEPC` 以后，就是执行 `mret` 进入到 Supervisor Mode。

从 `mret` 指令的名字来看，是返回指令，所以起到的效果，则是从 Machine Mode 返回到之前的 Mode，通常是权限级别更低的模式。反之，要从 Supervisor Mode 进入 Machine Mode 的话，则需要 ecall 指令，这个是统一的（早期是单独的，每一级一个带特权级别名的指令，比如 scall）。

所以前面提到的 Entry 和 Exit 机制从低到高对应的是 ecall 和 Xret，从高到低是反过来对应的是 Xret 和 ecall。

ecall 和 Xret 的时候，对应的地址则分别是 CSR_xTVEC 和 CSR_xEPC。xTVEC 用于设定 ecall 时的入口地址，xEPC 用于设定 Xret 返回更低权限层级时的入口地址。

这个设计其实非常清晰。ecall 这里是 environment call 的缩写，实际上，内核也好，Firmware 也好，却是当 exception/trap call 处理的，感觉就是有点让人困扰，按早期的 scall（虽然对应 system call），理解成 service call 可能更贴切一些，ecall 本身是调用更高特权级服务的一种方式。

这里简单绘制了一个示意图：

                 [ User Mode ]   <-------+
                    |      ^             |
         STVEC      |      |     SEPC    |
        +-------  ecall   sret ----------+
    ABI |           |      |
        |           v      |
        +----> [ Supervisor Mode ] <-----+
                    |      ^             |
         MTVEC      |      |     MEPC    |
        +-------  ecall   mret  ---------+   arg0=hardid, arg1=fdtaddr, SIE=0, MPIE=0, SATP=0 (MMU off)
    SBI |           |      |
        |           v      |
        +--->   [ Machine Mode ]

#### MMU Off

在 Non-MMU 的情况下，QEMU 在传递 `-bios none` 后，`-kernel` 会直接把内核加载在 Firmware 的地址 0x80000000，把 Linux 当 Firmware 执行。

如果不需要指定 `-append` 参数，实际上可以直接用 `-bios /path/to/kernel/image` 来加载内核。

这里并没有发生特权级别的切换，所以不做进一步讨论。

这里简单绘制了一个示意图：

               [ User Mode ]    <------+
                  |      ^             |
         MTVEC    |      |     MEPC    |
        +------- ecall  mret ----------+
    ABI |         |      |
        |         v      |
        +---> [ Machine Mode ]

**说明**：这两种方式在 QEMU v6.0.0 都正常，但是在 v8.0.0 似乎有一些衰退，只能用 `-bios` 的方式，而且无法正常关机。

### 应用阶段：User Mode

进入到内核，做完一系列的设备初始化、模块加载等动作以后，内核会启动第一个用户态进程，即 init。

如果开启了 MMU，此时完成从 Supervisor Mode 往 User Mode 的切换。

如果没有开启 MMU 的话，那么内核是必须工作在 Machine Mode 的，也就是说，内核实际上也为自己提供了类似 OpenSBI Firmware 提供的服务，看到的内存就是物理内存，地址可以直接写，不需要做转换，所以，Non-MMU 下，执行应用的时候是从 Machine Mode 直接往 User Mode 切换，而不需要经过 Supervisor Mode 这个中间环节。

这部分在泰晓社区的这篇文章中有所涉及：[RISC-V 架构下内核线程返回函数探究][005]。

```
// arch/riscv/kernel/process.c : 160

int copy_thread(struct task_struct *p, const struct kernel_clone_args *args)
{
        unsigned long clone_flags = args->flags;
        unsigned long usp = args->stack;
        unsigned long tls = args->tls;
        struct pt_regs *childregs = task_pt_regs(p);

        memset(&p->thread.s, 0, sizeof(p->thread.s));

        /* p->thread holds context to be restored by __switch_to() */
        if (unlikely(args->fn)) {
                /* Kernel thread */
                memset(childregs, 0, sizeof(struct pt_regs));
                childregs->gp = gp_in_global;
                /* Supervisor/Machine, irqs on: */
                childregs->status = SR_PP | SR_PIE;

                p->thread.ra = (unsigned long)ret_from_kernel_thread;
                p->thread.s[0] = (unsigned long)args->fn;
                p->thread.s[1] = (unsigned long)args->fn_arg;
        } else {
                *childregs = *(current_pt_regs());
                if (usp) /* User fork */
                        childregs->sp = usp;
                if (clone_flags & CLONE_SETTLS)
                        childregs->tp = tls;
                childregs->a0 = 0; /* Return value of fork() */
                p->thread.ra = (unsigned long)ret_from_fork;
        }
        p->thread.sp = (unsigned long)childregs; /* kernel sp */
        return 0;
}
```

这个 `SR_PP` 定义在这里：

```
arch/riscv/include/asm/csr.h: 300

#ifdef CONFIG_RISCV_M_MODE
# define CSR_STATUS     CSR_MSTATUS
# define CSR_IE         CSR_MIE
# define CSR_TVEC       CSR_MTVEC
# define CSR_SCRATCH    CSR_MSCRATCH
# define CSR_EPC        CSR_MEPC
# define CSR_CAUSE      CSR_MCAUSE
# define CSR_TVAL       CSR_MTVAL
# define CSR_IP         CSR_MIP

# define SR_IE          SR_MIE
# define SR_PIE         SR_MPIE
# define SR_PP          SR_MPP

# define RV_IRQ_SOFT            IRQ_M_SOFT
# define RV_IRQ_TIMER   IRQ_M_TIMER
# define RV_IRQ_EXT             IRQ_M_EXT
#else /* CONFIG_RISCV_M_MODE */
# define CSR_STATUS     CSR_SSTATUS
# define CSR_IE         CSR_SIE
# define CSR_TVEC       CSR_STVEC
# define CSR_SCRATCH    CSR_SSCRATCH
# define CSR_EPC        CSR_SEPC
# define CSR_CAUSE      CSR_SCAUSE
# define CSR_TVAL       CSR_STVAL
# define CSR_IP         CSR_SIP

# define SR_IE          SR_SIE
# define SR_PIE         SR_SPIE
# define SR_PP          SR_SPP
...
#endif
```

在 MMU On 和 MMU Off 的时候分别定义为 SPP 和 MPP，这个其实分别对应上面 SSTATUS 和 MSTATUS 寄存器中的 SPP 和 MPP 位域，用于设定 next mode，具体的设定在这里：

```
arch/riscv/kernel/entry.S: 286

restore_all:
    REG_L a0, PT_STATUS(sp)
    REG_L  a2, PT_EPC(sp)
    REG_SC x0, a2, PT_EPC(sp)
    csrw CSR_STATUS, a0                     // SSTATUS or MSTATUS
    csrw CSR_EPC, a2                        // MEPC or SEPC
#ifdef CONFIG_RISCV_M_MODE
    mret
#else
    sret
#endif
```

从 RISC-V 的特权手册可以看到 User Mode 的编码是 0，所以无论是从哪个模式切换，因为 `memset()` 是把整个 childregs 初始化成了 0，所以对应的这个 a0，写入到的 `CSR_STATUS` 都是对应 User Mode。

从 OpenSBI 也可以看到，这个 PRV_U 是定义成 0 的：

```
./include/sbi/riscv_encoding.h:

#define PRV_U				_UL(0)
```

从上述代码也能看到，在 MMU On 和 MMU Off 下，分别通过 sret 和 mret 返回上一权限级别，并且在这之前，也设定好了对应的 CSR_SEPC 和 CSR_MEPC。关于 EPC 的设定比较复杂，建议查看 [RISC-V 架构下内核线程返回函数探究][005] 的分析，其由 `rest_init()` 触发，并最终通过 `start_thread()` 来设定 elf_entry 的。

## 从应用到内核服务

最后，反过来，进入 User Space 后，应用需要访问外设等硬件资源的话，必须调用内核提供的服务，这个时候就需要通过 ecall 指令来实现。

ecall 指令执行以后，会进入到下一层级的服务入口，这个服务入口是通过 STVEC 或 MTVEC 寄存器来设定的。

### 内核部分的异常服务地址设定

```
arch/riscv/kernel/head.S: 175

.align 2
setup_trap_vector:
        /* Set trap vector to exception handler */
        la a0, handle_exception
        csrw CSR_TVEC, a0

arch/riscv/kernel/entry.S: 21

ENTRY(handle_exception)
```

对于 MMU On 和 MMU Off 的情况，分别对应 `CSR_STVEC` 和 `CSR_MTVEC`，具体定义见 `arch/riscv/include/asm/csr.h`。

更具体地，内核的服务接口是 Syscall，由 ABI 规范约定，其内核侧接口提供主要在 `arch/riscv/kernel/entry.S` 和 `arch/riscv/kernel/syscall_table.c`。

实际上，除了 ecall 指令主动触发的服务，内核侧还提供了其他服务，比如异常处理，比如中断服务，分别在 `arch/riscv/kernel/traps.c` 和 `arch/riscv/kernel/irq.c`。

* 关于 RISC-V 系统调用，可以查看：[RISC-V Syscall 系列 2：Syscall 过程分析][006]
* 关于 RISC-V 中断服务，可以查看：[RISC-V 中断子系统分析——CPU 中断处理][003]
* 关于异常处理这部分，可以查看：[RISC-V 异常处理流程介绍][004]，更详细的等后续文章系统地介绍。

### OpenSBI Firmware 的异常服务地址设定

```
./firmware/fw_base.S: 475

        /* Setup trap handler */
        lla     a4, _trap_handler
#if __riscv_xlen == 32
        csrr    a5, CSR_MISA
        srli    a5, a5, ('H' - 'A')
        andi    a5, a5, 0x1
        beq     a5, zero, _skip_trap_handler_rv32_hyp
        lla     a4, _trap_handler_rv32_hyp
_skip_trap_handler_rv32_hyp:
#endif
        csrw    CSR_MTVEC, a4

./firmware/fw_base.S:
	call	sbi_trap_handler

./lib/sbi/sbi_trap.c:

struct sbi_trap_regs *sbi_trap_handler(struct sbi_trap_regs *regs)
```

更具体地，Firmware 的服务接口是 SBICall，由 SBI 规范约定，这部分我们后面通过专门的文章再做详细介绍。

* 在 MMU On 的情况下，SBI Call 从内核发起，由独立的 Firmware 提供。内核侧的 SBI 调用接口在 `arch/riscv/kernel/sbi.c` 和 `arch/riscv/include/asm/sbi.h` 中实现。
* 在 MMU Off 的情况下，由内核自己来使用并实现这部分功能。

## 总结

本文结合代码，详细地分析了 MMU On 和 Off 两种情况下，RISC-V 整个运行时的特权层级的演进，从开机上电、Firmware 加载、内核引导到应用执行，然后反过来，再从应用空间访问内核空间，从内核空间访问 Firmware 服务的情况。

在 MMU On 的情况下，有三种层级：

                 [ User Mode ]   <-------+
                    |      ^             |
         STVEC      |      |     SEPC    |
        +-------  ecall  sret -----------+
    ABI |           |      |
        |           v      |
        +----> [ Supervisor Mode ] <-----+
                    |      ^             |
         MTVEC      |      |     MEPC    |
        +-------  ecall  mret  ----------+   arg0=hardid, arg1=fdtaddr, SIE=0, MPIE=0, SATP=0 (MMU off)
    SBI |           |      |
        |           v      |
        +--->   [ Machine Mode ]

在 MMU Off 的情况下，只有两种层级：

                [ User Mode ]    <-----+
                  |      ^             |
         MTVEC    |      |     MEPC    |
        +------- ecall  mret ----------+
    ABI |         |      |
        |         v      |
        +---> [ Machine Mode ]

在未来将讨论到的 Unikernel 设计中，将只有一个完全扁平的 Machine Mode 层级，应用程序也运行在 Machine Mode。

## 参考资料

* [QEMU 启动方式分析（1）：QEMU 及 RISC-V 启动流程简介][002]
* [RISC-V 异常处理流程介绍][004]
* [RISC-V 中断子系统分析——CPU 中断处理][003]
* [RISC-V Syscall 系列 2：Syscall 过程分析][006]
* [RISC-V Supervisor Binary Interface Specification][001]

[001]: https://github.com/riscv-non-isa/riscv-sbi-doc/blob/master/riscv-sbi.adoc
[002]: https://tinylab.org/introduction-to-qemu-and-riscv-upstream-boot-flow/
[003]: https://tinylab.org/riscv-irq-analysis-part3-interrupt-handling-cpu/
[004]: https://tinylab.org/riscv-irq-pipeline-introduction/
[005]: https://tinylab.org/riscv-kthread-ret/
[006]: https://tinylab.org/riscv-syscall-part2-procedure/
