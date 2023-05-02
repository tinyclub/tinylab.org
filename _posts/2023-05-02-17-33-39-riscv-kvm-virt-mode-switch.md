---
layout: post
author: 'Liming Wang'
title: 'RISC-V 虚拟化模式切换简析'
draft: false
plugin: 'mermaid'
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-kvm-virt-mode-switch/
description: 'RISC-V 虚拟化模式切换简析'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [codeinline tables epw]
> Author:   潘夏凯 <13212017962@163.com>
> Date:     2022/07/25
> Revisor:  Falcon <falcon@tinylab.org>
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V 虚拟化技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I5E4VB)
> Sponsor:  PLCT Lab, ISCAS


## 前言

本文简要介绍了 RISC-V 虚拟化的实现方式、特权级划分以及基于 trap 实现的虚拟化模式切换机制，并分析了当前主流的 RISC-V 模拟器中与模式切换相关的代码实现，尝试理清基于 KVM 的虚拟机系统其 Host 和 Guest 的切换机制。

## 软件版本信息

| 软件         | 版本                                     |
|--------------|------------------------------------------|
| Linux Kernel | Linux 5.19-rc5                           |
| Spike        | ac466a21df442c59962589ba296c702631e041b5 |
| QEMU         | a74c66b1b933b37248dd4a3f70a14f779f8825ba |

## RISC-V 虚拟化

### RISC-V 如何实现虚拟化？

RISC-V 通过引入虚拟化指令集扩展（Hypervisor extension，后简称 H 扩展）实现了在 S 扩展基础上的虚拟化。

#### 何为 H 扩展

1. 非虚拟化的系统架构（Supervisor-Level Architecture）

   通俗地说，S 级架构指的是由硬件、操作系统、应用（Application）三层结构构建的计算机系统，OS 运行在 S-mode 下，处理虚拟地址和物理地址的转换等任务。对应的，硬件运行在 M-mode(Machine Mode)，应用程序则运行在 U-mode(User Mode)。

2. 支持虚拟化的系统架构（Hypervisor-Level Architecture）

   相较于上述非虚拟化系统架构，虚拟化要求在 OS 与硬件之间添加一个可统筹管理 OS 的 hypervisor，此时的 OS 被称为客户操作系统（Guest OS），后续简称为 Guest。这样一来，在同一个硬件上就可以同时运行多个互相独立的 Guest，每个 Guest 都认为自己是一台独立的机器，这便实现了所谓的虚拟化。此时，硬件仍旧运行在 M-mode，supervisor 则运行在 HS-mode(Hypervisor-extended Supervisor mode)，对应的原来分别运行于 S-mode 和 U-mode 的 OS 和应用程序则在此处被标记为 VS-mode(Virtual Supervisor) 和 VU-mode(Virtual User mode)。

3. RISC-V 对虚拟化的支持

   RISC-V 指令集中添加了 H 扩展，规定了支持 hypervisor 在 H-mode 下需要执行的所有操作对应的指令（instructions）和控制状态寄存器（CSRs）。在具体的设计（处理器架构、模拟器等）中，通过添加、修改对应 CSR 及增加对应指令的操作的支持，可以实现系统的虚拟化。

#### H 扩展的实现

1. 系统分层与各层间通讯

   对于 S 级架构而言，系统包含硬件、OS、App 三层，各类 App 通过 OS 提供的各类 API 完成与系统的交互，这里对此不作讨论。RISC-V ISA 中，OS 与物理硬件的通信仅给出了机制的定义而非具体的实现，以期实现对干净的虚拟化（clean virtualization）的支持，如对 timer 的请求、处理器间中断请求等处理，在某些系统中是以 SBI (supervisor binary interface) 的形式实现了一个 SEE (supervisor execution environment) 来支持的，在其它系统中则是对于这类请求直接进行了具体的实现。上述关于 S-mode 下硬件与 OS 的通信的论述，参考自 RISC-V 特权指令级（20211203）规范的第四章前言（Page63）。

   而对于 H 级架构而言，系统包含了硬件、supervisor、OSs、Apps 四层，硬件与 supervisor 之间的通信与 S 级架构下硬件与 OS 的通信类似，可以使用相同的 SBI；但 supervisor 与 Guest 之间的通信则需要额外的实现。

   值得一提的是，hypervisor 除了可以是单独实现的管理器之外，还可以是具备管理多个 Guest 的能力的 OS。

<pre><div class="mermaid">
graph BT
subgraph 系统分层与层间通信

M1[hardware]--SBI---H[hypervisor]--SBI to be implemented---Guest1[Guest OS 1]--OS API---Apps1[Apps on Guest1]

H-.SBI to be implemented-.-Guests[Guest 2, 3, ...]-.OS API-.-Apps[Other Apps]

M2[harware]--SBI----S[Supervisor OS]--OS API---Apps2[Apps]
end
</div></pre>

   （[下载由 Mermaid 生成的 PNG 图片][004]）

2. 寄存器数目要求

   该扩展要求 32 的整数倍个寄存器，因此依赖于 `RV32I` 或 `RV64I` 指令集，`RV32E` 仅有 16 个寄存器，无法支持 H 扩展。

3. 地址转换机制要求

   依赖的基础指令集必须支持标准的基于页的地址转换机制，即 `Sv32 for RV32` 或 `minimum Sv39 for RV64`

4. CSR 规定

   `mtval` 不能是 x0 寄存器；
   规定 H 扩展通过设置 `misa` 的第七位开启，对应字母 H；
   推荐不对 `misa[7]` 使用硬连线（hardwired）从而保证该扩展可以被关闭。

### RISC-V 如何区分虚拟化？

指令集中约定用虚拟化模式 V (_virtualization mode_) 来标记当前是否是在 Guest 系统中运行。V=1 表示当前确实运行在 Guest 系统中，V=0 则表示不运行在 Guest 中。具体如下表所示：

| V | 虚拟化（H-Level Arch.）| V | 虚拟化特例 | 名义特权级 |
|---|------------------------|---|------------|------------|
| 1 | VU-mode                | 0 | U-mode     | U-0        |
| 1 | VS-mode                |   |            | S-1        |
| 0 | HS-mode                | 0 | HS-mode    | S-1        |
| 0 | M-mode                 | 0 | M-mode     | M-3        |

在上述表格中，虚拟化特例指 hart 所指示的应用程序以 U-mode 直接运行在一个运行于 HS-mode 的 OS 上。

名义特权级（Nominal Privilege）是在 S-mode 基础上的特权级约定，分为 U, S, M 三级，分别用 0，1，3 表示，各类指令集模拟器均以此标准实现。

### RISC-V 如何处理虚拟化？

#### 相关 CSR 简介

##### mstatus

参考：riscv-privileged-20211203, 3.1.6.1

`mstatus` CSR 分区如下图所示：

![mstatus](/wp-content/uploads/2022/03/riscv-linux/images/20220723-virt-mode/mstatus.png)

`mstatus` 具备全局中断使能栈机制：

该 CSR 中，`MIE`, `SIE` 分别用于 M/S-mode 下的中断使能，另有 `MPIE`, `SPIE` 用于记录 trap 之前 `mstatus` 的中断使能状态，还有 `SPP, MPP` 记录 trap 之前的特权级（SPP 一位：0,1; MPP 两位：0, 1, 2, 3），由此实现了一个支持嵌套 trap 的两级栈。

基于中断使能栈的 trap 返回机制：

trap 处理完成后从 M-mode 或 S-mode 返回需要调用 `mret` 或 `sret` 指令，`mstatus` 需做如下对应修改。假设执行 $xRET$ 指令，$xPP=y$：$xIE = xPIE$；当前特权级设置为 $y$，$xPIE=1$；$xPP$ 设置为支持的最小特权级（若支持 U-mode 则设置为 0，否则为 3 即 M-mode）；若$xPP \not ={M}$, $MPRV=0$。

上述修改可在 QEMU、Spike 的 `sret` 及 `mret` 中找到实现，分析见 [返回指令与虚拟化](#返回指令与虚拟化) 部分。

`TSR` (Trap SRet) 支持拦截 supervisor 异常返回指令 `sret`：

- TSR=1，在 S-mode 下尝试执行 `sret` 将会导致 `illegal instruction exception`；
- TSR=0，则允许在 S-mode 下执行 `sret`。若不支持 S-mode，TSR 为只读 0。

##### hstatus

参考：riscv-privileged-20211203, 8.2.1

![hstatus](/wp-content/uploads/2022/03/riscv-linux/images/20220723-virt-mode/hstatus.png)

`hstatus` 寄存器提供了类似于 `mstatus` 的特性用于追踪和控制一个 VS-mode 下的 Guest 的异常的行为。

- `SPV` (Supervisor Previous Virtualization)

  trap 到 HS-mode 就会涉及写入：`sstatus.SPP` 在 trap 时会被设置为 trap 对应的名义特权级，此时 `hstatus.SPV` 就会被设置为 trap 时的 V 值；当 V=0 时执行 `sret` 指令，`SPV` 置为 V。

- `SPVP` (Supervisor Previous Virtual Privilege)

  V=1 时，行为与 `sstatus.SPP` 相同，即置为 trap 时的名义特权级；V=0 时，保持不变。

- `GVA` (Guest Virtual Address)

  trap 到 HS-mode 时写入：对于写虚拟地址到 `stval` 的寄存器的 trap(breakpoint, address misaligned, access fault, page fault, or guest-page fault)，`hstatus.GVA` 置 1，对于其他 trap 置 0。

##### sstatus

参考：riscv-privileged-20211203, 4.1.1

![sstatus](/wp-content/uploads/2022/03/riscv-linux/images/20220723-virt-mode/sstatus.png)

`sstatus` 用于追踪处理器当前的运行状态，`sstatus` 是 `mstatus` 的一个子集。

- `SPP` (Supervisor Previous Privilige)

  用于标识 trap 进入 S-mode 之前 hart 所在的特权级：来自 U-mode 则置 0，否则为 1。

- `SIE`, `SPIE` (Supervisor Previous Interrupt Enable)
- trap 处理过程中 `sstatus` 的行为

  trap to S-mode: `SPIE=SIE`, `SIE=0`
  `sret`: `SIE=SPIE`, `SPIE=1`

##### vsstatus

V=1 时，`vsstatus` 用于替代 `sstatus`，所以通常针对 `sstatus` 的操作会替换为 `vsstatus`。

#### Trap 引起虚拟化模式切换

##### RISC-V 术语

- _hart_

  RISC-V ISA 中将包含一个独立的取值单元的组件定义为 _core_，一个兼容 RISC-V 的 _core_ 可以通过多线程的方式支持多个兼容 RISC-V 的硬件线程，这样的一个硬件线程定义为一个 _hart_(**har**dware **t**hread)。(riscv-spec-20191213, 1.1 **RISC-V Hardware Platform Terminology**, p2)

- _SEE_, _EEI_ and _hart_

  SEE (Software Execution Environment) 决定了一个 RISC-V 程序的具体行为，SEE 是通过具体的 EEI (Execution Environment Interface) 来定义的，而一个 EEI 应该定义一个程序的初始状态、访存与 IO、执行环境应包含的 hart 的类型、数量、特权级、合法指令的行为，如 ABI (Linux Application Binary Interface), SBI (RISC-V Supervisor Binary Interface)。

  在裸机硬件平台，hart 是由物理处理器线程直接实现的，其 EE 在硬件加电重置时就被定义；对于一个 RISC-V 平台的操作系统来说，其通过控制虚拟地址的访问和将用户级的 hart 分配到可用的物理处理器的线程上，为应用提供了多个用户级的 EE；对于 RISC-V supervisor 而言，其为 Guest OS 提供 Supervisor-level EE 的方式视 hypervisor 的实现方式而异，与 OS 相同的是，它也包含了多个可用的 hart。

  综上所述，不论是硬件、OS 还是 supervisor，都可以视为其内部基于不同等级的 hart 为更高一级提供了运行环境。因此，某一时刻的一个 RISC-V 程序必然对应着一个特定等级的 hart。故而本文所指的运行在某一模式，均可以视为某一程序对应的 hart 处于特定等级：

  | hart 等级                            | 运行模式 |
  |--------------------------------------|----------|
  | User-Level                           | U        |
  | Supervisor-Level                     | S        |
  | Hypervisor-Extended Supervisor-Level | S        |
  | Machine-Level                        | M        |

  因此，H-mode 下的虚拟模式切换，其具体行为与 S-mode 具有诸多相同之处。

##### RISC-V 中的 Trap

|             | 定义                                                         |
|-------------|------------------------------------------------------------|
| _exception_ | 当前 hart **内部**与某条指令相关的运行时中出现了异常的条件   |
| _interrupt_ | 可能导致 hart 控制转移的**外部**异步事件                     |
| _trap_      | 异常或中断导致的从原 hart 到特定 trap handler 的**控制转移** |

由上述定义可得，在 RISC-V 中，trap 是控制转移的总称。控制转移意味着 hart 的等级可能发生变化，即在一个虚拟化的系统中，trap 可能导致虚拟化模式切换。

##### Trap 处理概览

一个 trap 意味着 hart 的控制转移，导致 trap 的程序对应的 hart 有可能从一个特权级 $x$ 跳转到另一个特权级 $y$ ($x \leq y$)。

当 trap 在 $y$ 特权级下被处理完成后，hart 需要返回原来的特权级$x$，可以通过 `sret` 和 `mret` 分别实现从 S-mode 和 M-mode 返回。

上述两个操作的具体细节详见 [Trap 与虚拟化](#trap-与虚拟化) 和 [返回指令与虚拟化](#返回指令与虚拟化) 两节。

### 总结

下面对本节做一个小结：

首先，RISC-V ISA 借助 HS (hypervisor-extended supervisor) 指令集扩展实现了对虚拟化的支持。RISC-V hypervosir 指令集扩展将 S（supervisor）级架构进行虚拟化，从而使之支持 Guest OS 在 Hypervisor 上的运行。

其次，相较于 S 扩展，从指令集需要的功能和对应的修改两个方面的对应关系来解读，H 扩展改动如下：

| 功能                                                                 | ISA 改动（相较于 S 扩展）                                                 |
|----------------------------------------------------------------------|---------------------------------------------------------------------------|
| 地址转换：GPA (guest physical address) $\to$ SA (supervisor address) | 用于支持 guest OS 运行在 VS-mode (Virtual Supervisor mode) 的指令以及 CSR |
| hypervisor 运行                                                      | 用于控制地址转换新阶段的指令以及 CSR                                      |

第三，可以运行在 S-mode 的 OS 均可以无需修改就可在 HS-mode 和 VS-mode 下运行。

## Trap 与虚拟化

Trap 将导致 hart 的控制转移、模式切换及 CSR 修改。

### 控制转移

RISC-V 中，trap 可能导致的控制转移及模式切换如下图所示：

<pre><div class="mermaid">
graph BT
M[M-mode/MRET]---HS[HS-mode/SRET]-----VS[VS-mode/SRET]----VU[VU-mode]

HS-------U[U-mode]
U-.trap-.->M

HS-.trap-.->M
HS==trap by medeleg or mideleg==>HS

VS-.trap-.->M
VU-.trap-.->M

VS==trap by medeleg or mideleg==>HS
VU==trap by hedeleg or hideleg==>VS

</div></pre>

（[下载由 Mermaid 生成的 PNG 图片][005]）

从上图可知，正常情况下 trap 都会导致 hart 的控制转移至 M-mode，处理之后通过 `mret` 指令返回到原来的模式。

特殊情况下 trap 会经由 `mdeleg` 或 `mideleg` 委派从 HS-mode 或 VS-mode 转移至 HS-mode，或再经由 `hedeleg` 或 `hideleg` 委派从 VU-mode 转移至 VS-mode。

被委派至 HS-mode 和 VS-mode 的 trap 在处理完毕后，将通过 `sret` 指令返回至 trap 之前的模式。

### 虚拟模式和特权级切换、CSR 修改

虚拟化模式及特权级的切换对应上述控制转移图，具体对于 CSR 的修改包含如下情况：

trap 到 **M-mode**, V=0, **`msatatus`**'s fields MPV (Machine Previous Virtualization), MPP (Machine Previous Previlige) 依据下表设置：

| Previous Mode | msatatus.MPV | msatatus.MPP |
|---------------|--------------|--------------|
| U-mode        | 0            | 0            |
| HS-mode       | 0            | 1            |
| M-Mode        | 0            | 3            |
| VU-mode       | 1            | 0            |
| VS-mode       | 1            | 1            |

并修改 `mstatus` 的 GVA, MIE, MPIE 位，修改 CSR `mepc`, `mcause`, `mtval`, `mtval2`, `mtinst`.

trap 到 **HS-mode**, V=0, **`hstatus`** 的 MPV 和 MPP 位调整如下：

| Previous Mode | hstatus.SPV | hstatus.SPP |
|---------------|-------------|-------------|
| U-mode        | 0           | 0           |
| HS-mode       | 0           | 1           |
| VU-mode       | 1           | 0           |
| VS-mode       | 1           | 1           |

若 trap 前 V=1，`hstatus.SPVP = sstatus.SPP`；若 trap 前 V=0，保持不变。

trap 到 HS-mode 要求写 `hstatus.GVA`, `sstatus.SIE`, `sstatus.SPIE` 和 CSR `sepc`, `scause`, `stval`, `htval`, `htinst`。

trap 到 **VS-mode**，`vsstatus.SPP` 依照下表设置：

| Previous Mode | vsstatus.SPP |
|---------------|--------------|
| VU-mode       | 0            |
| VS-mode       | 1            |

`hstatus`, `sstatus` 不修改，V=1；写 `vsstatus.PIE`, `vsstatus.SPIE` 和 CSR `vsepc`, `vscause`, `vstval`。

## 返回指令与虚拟化

### 相关指令及其作用

`mret`, `sret` 两条指令分别用于 trap 从 M-mode 和 S-mode 返回，这两条指令的执行也对应着特定 CSR 的修改，与 trap 陷入时的 CSR 修改行为有所区别，相关的主要的 CSR 修改参见 [Trap 相关 CSR](#相关-csr-简介) 一节。

### QEMU 中的实现

```C{.line-numbers}
// qemu/target/riscv/op_helper.c
target_ulong helper_sret(CPURISCVState *env)
{
    uint64_t mstatus;
    target_ulong prev_priv, prev_virt;

    // exception handling
    ...

    mstatus = env->mstatus;

    // with H-mode support and it is diabled
    if (riscv_has_ext(env, RVH) && !riscv_cpu_virt_enabled(env)) {
        /* We support Hypervisor extensions and virtulisation is disabled */
        target_ulong hstatus = env->hstatus;

        prev_priv = get_field(mstatus, MSTATUS_SPP);
        prev_virt = get_field(hstatus, HSTATUS_SPV);

        // set mstatus and hstatus of env
        hstatus = set_field(hstatus, HSTATUS_SPV, 0);
        mstatus = set_field(mstatus, MSTATUS_SPP, 0);
        mstatus = set_field(mstatus, SSTATUS_SIE,
                            get_field(mstatus, SSTATUS_SPIE));
        mstatus = set_field(mstatus, SSTATUS_SPIE, 1);

        env->mstatus = mstatus;
        env->hstatus = hstatus;

        // check whether to swap vs, s, hs CSR values
        if (prev_virt) {
            riscv_cpu_swap_hypervisor_regs(env);
        }

        // set VIRT_ONOFF to prev_virt
        riscv_cpu_set_virt_enabled(env, prev_virt);
    } else {
        prev_priv = get_field(mstatus, MSTATUS_SPP);

        mstatus = set_field(mstatus, MSTATUS_SPP, PRV_U);
        mstatus = set_field(mstatus, MSTATUS_SIE,
                            get_field(mstatus, MSTATUS_SPIE));
        mstatus = set_field(mstatus, MSTATUS_SPIE, 1);
        env->mstatus = mstatus;
    }

    // set env virt mode to prev_virt
    riscv_cpu_set_mode(env, prev_priv);

    return retpc;
}
```

在上述的 `if...else...` 中有公共的关于 `mstatus` 的代码块：

```C{.line-numbers}{.line-numbers}
mstatus = set_field(mstatus, MSTATUS_SPP, PRV_U);
mstatus = set_field(mstatus, MSTATUS_SIE,
                    get_field(mstatus, MSTATUS_SPIE));
mstatus = set_field(mstatus, MSTATUS_SPIE, 1);
env->mstatus = mstatus;
```

他们被用于在执行 `sret` 时设置 `mstatus` 的 `SPP`, `SIE`, `SPIE` 区域，对应 [`mstatus` CSR](#mstatus) 部分。

每当 trap 被引入 HS-mode，`hstatus.SPV` 就会被写入 trap 时的 V 值。此处代码中，若当前系统支持 H 指令集扩展且当前虚拟化未开启，将通过代码 `hstatus = set_field(hstatus, HSTATUS_SPV, 0);` 将 `hstatus` 的 `SPV` (Supervisor Previous Virtualization) 置零，然后依据 trap 之前的虚拟模式 `prev_virt` 判断是否要修改 VS/S/HS 模式的 CSR 的值，如下方代码所示：

```C{.line-numbers}
// qemu/target/riscv/cpu_helper.c: line 465-525
void riscv_cpu_swap_hypervisor_regs(CPURISCVState *env)
{
    uint64_t mstatus_mask = MSTATUS_MXR | MSTATUS_SUM |
                            MSTATUS_SPP | MSTATUS_SPIE | MSTATUS_SIE |
                            MSTATUS64_UXL | MSTATUS_VS;

    if (riscv_has_ext(env, RVF)) {
        mstatus_mask |= MSTATUS_FS;
    }
    // true if H-extension is supported and virt_ONOFF is 1
    bool current_virt = riscv_cpu_virt_enabled(env);

    g_assert(riscv_has_ext(env, RVH));

    if (current_virt) {
        /* Current V=1 and we are about to change to V=0 */
        env->vsstatus = env->mstatus & mstatus_mask;
        env->mstatus &= ~mstatus_mask;
        env->mstatus |= env->mstatus_hs;

        env->vstvec = env->stvec;
        env->stvec = env->stvec_hs;

        ...
    } else {
        /* Current V=0 and we are about to change to V=1 */
        env->mstatus_hs = env->mstatus & mstatus_mask;
        env->mstatus &= ~mstatus_mask;
        env->mstatus |= env->vsstatus;

        env->stvec_hs = env->stvec;
        env->stvec = env->vstvec;

        ...
    }
}
```

`riscv_cpu_swap_hypervisor_regs` 函数实现了如下图所示的寄存器内容交换：

<pre><div class="mermaid">
graph BT

subgraph From V=1 to V=0

S[S CSRs]--1--->VS1[VS CSRs]
HS1[HS CSRs]--2--->S

end

subgraph From V=0 to V=1

S--1--->HS2[HS CSRs]
VS2[VS CSRs]--2--->S

end

</div></pre>

（[下载由 Mermaid 生成的 PNG 图片][006]）

```C{.line-numbers}
// qemu/target/riscv/cpu_helper.c: line 558-583
void riscv_cpu_set_virt_enabled(CPURISCVState *env, bool enable)
{
    if (!riscv_has_ext(env, RVH)) {
        return;
    }

    /* Flush the TLB on all virt mode changes. */
    if (get_field(env->virt, VIRT_ONOFF) != enable) {
        tlb_flush(env_cpu(env));
    }

    env->virt = set_field(env->virt, VIRT_ONOFF, enable);

    if (enable) {
        /*
         * The guest external interrupts from an interrupt controller are
         * delivered only when the Guest/VM is running (i.e. V=1). This means
         * any guest external interrupt which is triggered while the Guest/VM
         * is not running (i.e. V=0) will be missed on QEMU resulting in guest
         * with sluggish response to serial console input and other I/O events.
         *
         * To solve this, we check and inject interrupt after setting V=1.
         */
        riscv_cpu_update_mip(env_archcpu(env), 0, 0);
    }
}
```

### Spike 中的实现

```C{.line-numbers}
// riscv-isa-sim/riscv/insns/sret.h
require_extension('S');
reg_t prev_hstatus = STATE.hstatus->read();
if (STATE.v) {
  if (STATE.prv == PRV_U || get_field(prev_hstatus, HSTATUS_VTSR))
    // if (unlikely(STATE.v)) throw trap_virtual_instruction(insn.bits())
    require_novirt();
} else {
  // decide M-mode or S-mode to handle trap
  require_privilege(get_field(STATE.mstatus->read(), MSTATUS_TSR) ? PRV_M : PRV_S);
}
reg_t next_pc = p->get_state()->sepc->read();
set_pc_and_serialize(next_pc);
reg_t s = STATE.sstatus->read();
reg_t prev_prv = get_field(s, MSTATUS_SPP);
s = set_field(s, MSTATUS_SIE, get_field(s, MSTATUS_SPIE));
s = set_field(s, MSTATUS_SPIE, 1);
s = set_field(s, MSTATUS_SPP, PRV_U);
STATE.sstatus->write(s);
p->set_privilege(prev_prv);
if (!STATE.v) {
  if (p->extension_enabled('H')) {
    reg_t prev_virt = get_field(prev_hstatus, HSTATUS_SPV);
    p->set_virt(prev_virt);
    reg_t new_hstatus = set_field(prev_hstatus, HSTATUS_SPV, 0);
    STATE.hstatus->write(new_hstatus);
  }

  STATE.mstatus->write(set_field(STATE.mstatus->read(), MSTATUS_MPRV, 0));
}
```

相较于 QEMU 的处理逻辑（两种情况：支持 H 扩展且未开启虚拟化和其他），Spike 的处理逻辑有所不同：

1. 先判断是否已经开启虚拟化，若已经开启且支持 trap (U-mode 或 H-mode 下 hstatus.vtsr=1) 则通过 `require_novirt()` 处理 trap，若当前为非虚拟化模式，则通过 `require_privilege()` 请求对应的处理 trap 的特权级，其中 `mstatus.TSR` 表示是否允许在 M-mode 下执行 trap 返回指令。
2. 设置 trap 返回的 PC 值：`set_pc_and_serialize(next_pc)`
3. 修改并保存 `sstatus` 的 `SPP`, `SIE`, `SPIE` 位
4. 根据系统对 H 扩展的支持情况和当前所在的虚拟模式设置 `hstatus` 和 `mstatus` 的值
   1. 如已经处于虚拟模式（V=1），无操作
   2. 若 V=0，`mstatus.MPRV` 置为 0，如果支持 H 扩展，修改 `hstatus.SPV` 为 0，恢复 trap 之前的虚拟模式。

### Linux Kernel KVM 中模式切换的实现

KVM 可以帮助 Linux Kernel 完成管理 Guest 等归属于 supervisor 的任务，下面将结合 Linux 内核源码中关于 KVM 如何创建一个虚拟 CPU 并管理 Host/Guest 切换的代码实现，分析虚拟化模式的切换机制。

创建一个 vCPU，初始化其指令集、CSR (`sstatus`, `hstatus`):

```C{.line-numbers}
// linux/arch/riscv/kvm/vcpu.c: line 97-130
int kvm_arch_vcpu_create(struct kvm_vcpu *vcpu)
{
 struct kvm_cpu_context *cntx;
 struct kvm_vcpu_csr *reset_csr = &vcpu->arch.guest_reset_csr;

 /* Mark this VCPU never ran */
 vcpu->arch.ran_atleast_once = false;
 vcpu->arch.mmu_page_cache.gfp_zero = __GFP_ZERO;

 /* Setup ISA features available to VCPU */
 vcpu->arch.isa = riscv_isa_extension_base(NULL) & KVM_RISCV_ISA_ALLOWED;

 /* Setup VCPU hfence queue */
 spin_lock_init(&vcpu->arch.hfence_lock);

 /* Setup reset state of shadow SSTATUS and HSTATUS CSRs */
 cntx = &vcpu->arch.guest_reset_context;
        // 按位与即为分别设置 sstatus、hstatus 各位
 cntx->sstatus = SR_SPP | SR_SPIE;
 cntx->hstatus = 0;
 cntx->hstatus |= HSTATUS_VTW;
 cntx->hstatus |= HSTATUS_SPVP;
 cntx->hstatus |= HSTATUS_SPV;

 /* By default, make CY, TM, and IR counters accessible in VU mode */
 reset_csr->scounteren = 0x7;

 /* Setup VCPU timer */
 kvm_riscv_vcpu_timer_init(vcpu);

 /* Reset VCPU */
 kvm_riscv_reset_vcpu(vcpu);

 return 0;
}
```

trap 时，通过如下代码实现 Host 和 Guest 的寄存器替换：

```C{.line-numbers}{.line-numbers}
// arch/riscv/kvm/vcpu_switch.S: line 9-211
ENTRY(__kvm_riscv_switch_to)
 /* Save Host GPRs (except A0 and T0-T6) */
 REG_S ra, (KVM_ARCH_HOST_RA)(a0)
 REG_S sp, (KVM_ARCH_HOST_SP)(a0)
        // ... ra-s11

 /* Load Guest CSR values */
 REG_L t0, (KVM_ARCH_GUEST_SSTATUS)(a0)
 REG_L t1, (KVM_ARCH_GUEST_HSTATUS)(a0)
 REG_L t2, (KVM_ARCH_GUEST_SCOUNTEREN)(a0)
 la t4, __kvm_switch_return
 REG_L t5, (KVM_ARCH_GUEST_SEPC)(a0)

 /* Save Host and Restore Guest SSTATUS */
 csrrw t0, CSR_SSTATUS, t0

 /* Save Host and Restore Guest HSTATUS */
 csrrw t1, CSR_HSTATUS, t1

 /* Save Host and Restore Guest SCOUNTEREN */
 csrrw t2, CSR_SCOUNTEREN, t2

 /* Save Host STVEC and change it to return path */
 csrrw t4, CSR_STVEC, t4

 /* Save Host SSCRATCH and change it to struct kvm_vcpu_arch pointer */
 csrrw t3, CSR_SSCRATCH, a0

 /* Restore Guest SEPC */
 csrw CSR_SEPC, t5

 /* Store Host CSR values */
 REG_S t0, (KVM_ARCH_HOST_SSTATUS)(a0)
 REG_S t1, (KVM_ARCH_HOST_HSTATUS)(a0)
 // ... t0-t4

 /* Restore Guest GPRs (except A0) */
 REG_L ra, (KVM_ARCH_GUEST_RA)(a0)
 REG_L sp, (KVM_ARCH_GUEST_SP)(a0)
 // ... ra-s11, t3-t6

 /* Restore Guest A0 */
 REG_L a0, (KVM_ARCH_GUEST_A0)(a0)

 /* Resume Guest */
 sret

 /* Back to Host */
 .align 2
__kvm_switch_return:
 /* Swap Guest A0 with SSCRATCH */
 csrrw a0, CSR_SSCRATCH, a0

 /* Save Guest GPRs (except A0) */
 REG_S ra, (KVM_ARCH_GUEST_RA)(a0)
 REG_S sp, (KVM_ARCH_GUEST_SP)(a0)
 // ... ra-s11, t3-t6

 /* Load Host CSR values */
 REG_L t1, (KVM_ARCH_HOST_STVEC)(a0)
 REG_L t2, (KVM_ARCH_HOST_SSCRATCH)(a0)
 REG_L t3, (KVM_ARCH_HOST_SCOUNTEREN)(a0)
 REG_L t4, (KVM_ARCH_HOST_HSTATUS)(a0)
 REG_L t5, (KVM_ARCH_HOST_SSTATUS)(a0)

 /* Save Guest SEPC */
 csrr t0, CSR_SEPC

 /* Save Guest A0 and Restore Host SSCRATCH */
 csrrw t2, CSR_SSCRATCH, t2

 /* Restore Host STVEC */
 csrw CSR_STVEC, t1

 /* Save Guest and Restore Host SCOUNTEREN */
 csrrw t3, CSR_SCOUNTEREN, t3

 /* Save Guest and Restore Host HSTATUS */
 csrrw t4, CSR_HSTATUS, t4

 /* Save Guest and Restore Host SSTATUS */
 csrrw t5, CSR_SSTATUS, t5

 /* Store Guest CSR values */
 REG_S t0, (KVM_ARCH_GUEST_SEPC)(a0)
 REG_S t2, (KVM_ARCH_GUEST_A0)(a0)
 // t0, t2-t5

 /* Restore Host GPRs (except A0 and T0-T6) */
 REG_L ra, (KVM_ARCH_HOST_RA)(a0)
 REG_L sp, (KVM_ARCH_HOST_SP)(a0)
 // ra-s11

 /* Return to C code */
 ret
ENDPROC(__kvm_riscv_switch_to)
```

以上代码所实现的 Host 与 Guest 替换的过程可以整理为如下表格。第一列表示保存 Host 并加载 Guest 到硬件，第二列表示保存 trap 处理完毕的 Guest 并重新加载 Host 到硬件。

| Save Host From and Load Guest to Machine                                                         | Save Guest from and Load Host to Machine                                         |
|--------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------|
| 1.1 Save Host GPR                                                                                | 2.1 Save Guest GPRs                                                              |
| 1.2 Load Guest CSR to `t0-t2`, `t4-t5`                                                           | 2.2 Load Host CSRs to `t1-t5`                                                    |
| 1.3 Swap Physical CSR with `t0-t2`, `t4` to pre-store Host CSR and restore Guest CSR             | 2.3 Swap Physical CSR with `t2-t5` to pre-store Guest CSRs and restore Host CSRs |
| 1.4 Save SSCRATCH of Host and change it to save Host A0 (`csrrw t3, CSR_SSCRATCH, a0`)           | 2.4 Restore Host STVEC (`csrw CSR_STVEC, t1`)                                    |
| 1.5 Restore Guest SEPC (`csrw CSR_SEPC, t5`)                                                     | 2.5 Save Guest SEPC (`csrr t0, CSR_SEPC`);                                       |
| 1.6 Store Host CSRs (`t0-t4`)                                                                    | 2.6 Store Guest CSRs (`t0`, `t2-t5`)                                             |
| 1.7 Restore Guest GPRs and A0                                                                    | 2.7 Restore Host GPRs                                                            |
| Resume Guest: `sret`                                                                             | Return to C code (ret)                                                           |
| Swap a0 and SSCRATCH-let SSCRATCH has Guest a0 and a0 has Host a0 (`csrrw a0, CSR_SSCRATCH, a0`) |                                                                                  |

单独考虑保存 Host 并加载 Guest 到硬件的过程，其细节如下图所示：

<pre><div class="mermaid">
graph LR

A0[a0]
Gs[GPRs]
Cs[CSRs]
Ts[t0, t1, ...]
HG[Host GPRs]
HC[Host CSRs]
HA0[Host a0]
GG[Guest GPRs]
GC[Guest CSRs]
GA0[Guest a0]

subgraph Physical Registers
A0
Gs
Cs
Ts
end

subgraph Host Virtual Registers
HA0[Host a0]
HG
HC
end

subgraph Guest Virtual Regsiters
GA0[Guest a0]
GG
GC
end

Gs--1.1 save host GPR-->HG
GC--1.2 load gust CSR-->Ts

Ts--1.3 csrrw to restore guest CSR-->Cs
Cs--1.3 csrrw to pre-store host CSR-->Ts

Cs--1.4 csrrw to save host SSCRATCH in t3-->Ts
Ts--1.4 csrrw to save host a0 in SSCRATCH-->Cs
HC-.1.4 t3 = sscratch-.-Ts
HA0-.1.4 sscratch = a0-.-Cs

Ts--1.5 csrw to restore guest SEPC-->Cs
Ts--1.6 store host CSR-->HC

GG--1.7 restore guest GPR-->Gs
GA0--1.7 restore gust A0-->A0

</div></pre>

（[下载由 Mermaid 生成的 PNG 图片][007]）

## 结语

本文结合 QEMU、Spike、KVM 源码及特权指令级手册对于 RISC-V 虚拟化的实现、特权级（虚拟化模式 V）切换机制及其实现进行了简要分析，明确了模式切换的各类条件以及处理方式。

不足之处在于，当前对模式切换过程中涉及的诸多寄存器修改细节并不足够明确，例如，在 Spike 和 QEMU 中，都有对 `sret` 指令的实现，但是目前无法理解为什么两者对于 `mstatus`, `hstatus`, `sstatus`, `vsstatus` 等 CSR 的修改行为不同。这部分有待后续深入分析，或者向社区开发者咨询澄清。

## 参考资料

- [RISC-V 特权指令集手册][003]
- [Cloud Lab][001]
- [Linux Lab][002]
- [RISC-V Linux][002]

[001]: https://gitee.com/tinylab/cloud-lab
[002]: https://gitee.com/tinylab/linux-lab
[003]: https://github.com/riscv/riscv-isa-manual/releases/download/Priv-v1.12/riscv-privileged-20211203.pdf
[004]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/20220723-virt-mode/mermaid-virt-mode-1.png
[005]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/20220723-virt-mode/mermaid-virt-mode-2.png
[006]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/20220723-virt-mode/mermaid-virt-mode-3.png
[007]: https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/20220723-virt-mode/mermaid-virt-mode-4.png
