---
layout: post
author: 'XiaKai Pan'
title: 'RISC-V 架构 H 扩展中的 Trap 处理'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-kvm-virt-trap/
description: 'RISC-V 架构 H 扩展中的 Trap 处理'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - 虚拟化
  - H 扩展
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [spaces header]
> Author:   潘夏凯 <13212017962@163.com>
> Date:     2022/09/27
> Revisor:  Falcon <falcon@tinylab.org>;Walimis <walimis@walimis.org>
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V 虚拟化技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I5E4VB)
> Sponsor:  PLCT Lab, ISCAS


## 前言

本文基于 RISC-V 特权指令集手册中关于 trap 处理的规范，结合 Spike、QEMU 两个常用的硬件模拟器的实现，分析了 RISC-V 中添加了 S 扩展和 H 扩展的 trap 处理机制。

## 软件版本信息

| 软件         | 版本                                     |
| ------------ | ---------------------------------------- |
| Linux Kernel | Linux 5.19-rc5                           |
| Spike        | ac466a21df442c59962589ba296c702631e041b5 |
| QEMU         | a74c66b1b933b37248dd4a3f70a14f779f8825ba |

## RISC-V Trap 处理总览

### Trap, Exception, Interrupt

参见 [此文][5] 对指令集手册的解读，Exception 用于指同步的异常，Interrupt 用于指异步的中断，二者在 RISC-V 中统称为 Trap。

### Trap 从何而来

RISC-V 的中断分为软件（Software）中断、计时器（Timer）中断、外部（External）中断和调试（Debug）中断。此处仅详细讨论软件中断和计时器中断。

#### 软件中断

程序内部可以直接规定 trap 处理程序及其所在位置，在程序执行过程中，如果满足了程序中设定的处理程序的触发条件，那么后续就会进入该程序。[下一节][11] 将会以 [riscv-tests][6] 为例，分析一个具体的来自于程序内部的中断处理流程。软件中断通过向内存映射的寄存器中写数来触发，通常用于一个 hart 中断另一个 hart（这在其他架构中被称为处理器间中断机制，即 IPI）。

#### 计时器中断

硬件本身是由时钟信号驱动的，而运行在硬件上的操作系统也同样需要以时间为基准对于任务进行调度。时钟中断就是上述处理的基础。

关于时钟相关的寄存器的介绍，以及 Linux 中如何实现 RISC-V 的 timer，参见 [这篇文章][7]。

#### 外部中断

外部中断指来自于诸如 GPIO，SPI，UART 等位于处理器外部的中断请求。

### Trap 处理

一个基本的软件中断（Software Interrupt）的处理流程可以概括如下：程序执行过程中 **触发** 特定条件，首先保存当前运行状态（各个 GPR 即通用寄存器的值），依据 xydeleg (x-Mode y delegation, y 可以为 interrupt 或 exception，记为 i 或 e) CSR 确定处理当前 trap 所需的特权级，然后跳转到指定的 trap 处理函数所在位置（由 mtvec 的值确定），设置包括 epc (exception program counter), cause, tval (trap value), tinst (trap instruction) 等 CSR 的值供针对具体的 trap 情况进行 **处理**。处理完成之后，调用 `mret` 或 `sret` 指令 **返回**，恢复 trap 触发之前的状态。

其中，一个典型的软件中断触发 trap 处理的流程已在 riscv-test 程序的分析过了，trap 的返回将在下一节进行介绍，本节将介绍这一流程中涉及的与所在特权级相关的一些 CSR 及对应机制。

#### 跳转至处理程序：mtvec

RISC-V trap 处理有向量化和非向量化两种模式可选，通过 `mtvec` CSR 来实现，该 CSR 表示 Machine Trap-Vector，用于指示 trap 处理程序所在的位置，由两部分构成：BASE，MODE，如下图所示。

![mtvec](/wp-content/uploads/2022/03/riscv-linux/images/riscv-kvm/trap/mtvec.png)

RISC-V 指令集出于灵活性考虑，支持两种类型的 trap 处理，即直接（Direct）处理和向量化（Vectored）处理，对于低端设备来说，可以采用直接处理的模式，无需考虑实现对应诸多 trap 类型的状态处理功能，对于较大的计算机系统而言，则可以采用向量化模式。在具体的 trap 处理过程中，采用哪一种模式将由 `mtvec.MODE` 位来确定，如下表所示。

![mtvec.MODE](/wp-content/uploads/2022/03/riscv-linux/images/riscv-kvm/trap/mtvec-mode.png)

如果 MODE=0，即采用直接模式，对于所有的异常（exception）来说，程序计数器（pc）将会被设置为特定值（mtvec.BASE），即跳转到 BASE 指示的位置处，执行 trap 处理的程序。但如果 MODE=1，即采用的是向量模式，那么将要跳转到的地址将与具体的 trap 类型有关：

1. 对于所有被交由在 M-Mode 处理的同步异常，处理方式与直接模式相同，pc:=mtvec.BASE。
2. 对于外部中断（interrupt），$pc:=mtvec.BASE+4\times cause$，其中 cause 是 interrupt 编码。

#### 保存 trap 前的状态

除了用栈保存通用寄存器（GPR）的值，以供 trap 处理完成返回之后使用，诸如 trap 触发时的中断使能、特权级等信息也需要有栈结构进行保存，以供返回之后的运行环境恢复。`xstatus` (x = m, h, s) CSR 即承担了这样的功能，如 [此文][4] 所述，其 `xIE, xPIE, xPP` 共同构成了一个可以保存 trap 前的中断使能（Interrupt Enable）、特权级（Privilege）情况的栈。对照 [此文][9] 所述的集中从低特权级到不高于原特权级的 trap 处理机制，可以看到栈的深度决定了 RISC-V 当前并不支持硬件层面的 trap 嵌套，但是可以通过软件方式保存现场、开启中断使能来实现。

此外值得一提的是，如果是在 S-Mode 下处理 trap 的话（HS，VS），使用 `sstatus` 作为栈结构与使用 `mstatus` 是等价的，因为 `sstatus` 本身就可以视作 `mstatus` 的一个部分拷贝，与 trap 处理栈相关的结构完全相同。例如在 QEMU 中统一使用 mstatus，而在 Spike 中则仅在 trap 到 M-Mode 时才使用 mstatus，其余情况均使用 sstatus。在特定的硬件设计中只需保持内部统一即可。

对于添加了 H 扩展之后的 trap 处理，其栈结构还需要 `hstatus` 来辅助保存额外关于 Guest 的信息。

#### 中断使能，中断等待：ie, ip

##### mie, mip

mie, mip 是与 mstatus 中的中断使能栈相配合的两个 CSR，表示 Machine Interrupt Enable/Pending。其 [15:0] 位与 mcause 的值相对应。

仅在同时满足如下条件时，trap 才可以在 M-Mode 处理：

1. 当前特权级为 M，且 mstatus.MIE=1，或当前特权级比 M 更低；
2. mip, mie CSR 均被设置为 mcause 的值；
3. 若 mideleg CSR 存在则其未被修改为 mcause 的值。

mip 和 mie 的布局如下所示，在 mip 和 mie 中分别记录了 Machine 和 Supervisor 的 External、Timer、Software Interrupts 的使能以及挂起情况，处理优先级为 MEI, MSI, MTI, SEI, SSI, STI。

![mie-mip](/wp-content/uploads/2022/03/riscv-linux/images/riscv-kvm/trap/mie-mip.png)

##### xie, xip

除了 M-Mode 之外，其他特权模式也都有对应的中断使能和等待 CSR，如下表所示，其结构与 mie, mip 相似，如下表所示。

| Privilege | xie  | xip       | hgeip | hgeie |
| --------- | ---- | --------- | ----- | ----- |
| S         | sie  | sip       |
| HS        | hie  | hip, hvip | hgeip | hgeie |
| VS        | vsie | vsip      |

对于 HS-Mode 而言，特权指令集还规定了 hgeie 和 hgeip（hypervisor guest external interrupt enable/pending）两个 CSR。hgeip 为只读寄存器，用于表示对于当前硬件线程是否挂起其 guest 外部中断。hgeie 可以读写，包含 guest 外部中断的使能位。

#### 中断信息保存：epc, cause, tval, tinst, status

##### epc

mepc, sepc 分别用于在 M-Mode 和 S-Mode 下处理 trap 时记录原程序发生 trap 时的地址；vsepc 则是用于 Guest 内部的中断处理的，其功能与仅支持 S 扩展时的 sepc 几乎相同。

##### cause

###### mcause

mcause 表示 Machine Cause，用于记录当 trap 被交由 M-Mode 处理时该 trap 的具体类型。该 CSR 包含 Interrupt 和 Exception Code 两个部分，前者用于记录本次处理的 trap 是否为 Interrupt，是则置 1，否则置 0，后者用于记录上一次处理的 trap 的具体编码。具体情况如下表所示。

![mcause](/wp-content/uploads/2022/03/riscv-linux/images/riscv-kvm/trap/mcause.png)

在 trap 处理完成之后，Exception Code 的值将会被修改为本次 trap 的类型编码，这个值来自于程序本身，如果是页错误（page fault）等需要保存额外信息的异常，mtval 将会被修改，参见 [下一小节][4]。

如果一条指令将会导致多个同步异常，那么异常的处理优先级将遵循下表的次序。

![exception priority](/wp-content/uploads/2022/03/riscv-linux/images/riscv-kvm/trap/mcause-excp-priority.png)

###### xcause

scause, vscause 与 epc 同理，前者用于协助 S-Mode 下的 trap 处理，记录 trap（interrupt 和 exception）的编码，后者则在 Guest 内部发挥着与 scause 相同的作用。

##### tval

###### mtval

mtval 表示 Machine Trap Value，用于辅助软件进行 trap 处理。当 trap 被交由 M-Mode 处理时，mtval 的值要么是 0 要么被写入异常相关的特定信息。如果硬件指定了所有异常都不会导致 mtval 被写入非 0 值，那么该寄存器将始终是只读的 0。

mtval 被写入非 0 值大致包含以下情况，即异常类型为断点（breakpoint）、地址错位（address-misaligned）、访问错误（access-fault）和页错误（page-fault），此时 mtval 将会被写入出错的虚拟地址，即便是对物理内存的访问出错也是如此。这样的设计对于大多数的实现来说可以大大减少数据通路的访问代价。尤其是需要进行 page-table walk 的实现。

对于 access-fault 和 page-fault 异常而言，mepc（Machine Exception Program Counter）CSR 将会被用于保存导致异常的指令地址，而 mtval 则用于保存导致上述异常的指令访问的虚拟地址。

###### xtval

stval, vstval 与上述 scause, vscause 对应关系基本一致。

##### mtinst, htinst

mtinst 会在 trap 发生后并进入 M-Mode 时，写入一个发生 trap 的指令值，或者直接置 0，该信息将用于协助软件处理 trap。htinst 则协助处理 HS-Mode 的 trap。二者都会被自动写入。它们的值在 [特权指令手册][1] 中 8.6.3 规定如下：

- 0；
- 导致发生 trap 的指令的转换结果；
- 非标准的导致 trap 的指令的指定值；
- 特殊的伪指令。

#### status

`mstatus` 的构造及其作用参见 [此文][4]。`sstatus` 可以视为 `mstatus` 的部分拷贝，`hstatus` 则是为了满足添加了 H 扩展之后的额外 trap 处理需求而做的功能补充，`vsstatus` 则完全可以视作专用于 Guest 的 `sstatus` 翻版。

### Trap 返回：xret

参见 [出栈机制解读][3] 及 [对应代码实现][10]。

### Trap 处理实例

本节将以 [riscv-tests][6] 为例，分析程序中实际的 trap 处理流程。示例程序中除了源代码、Makefile 之外，还包括链接文件（.ld 等）和一个 crt\*.S 文件。

在此之前先补充一些背景信息。程序源文件经过编译将会生成多个目标文件（.obj, .o），这些目标文件需要通过链接器依照对应的链接文件进行处理，合并为一个二进制文件（.elf），在 riscv-test 中，`riscv-tests/benchmarks/common/test.ld` 即为链接文件。

而 `riscv-tests/benchmarks/common/crt.S` 文件则是以汇编语言写成的、包含了 CPU 初始化、启动判断和 trap 处理程序的 C 运行时（RunTime）文件，该文件经过编译之后生成对应目标文件，在链接时会被与源代码文件生成的诸多目标文件一起处理。

汇编对应的 `riscv-tests/benchmarks/Makefile` 中的如下语句：

```Makefile
# benchmarks/Makefile: line 49
define compile_template
$(1).riscv: $(wildcard $(src_dir)/$(1)/*) $(wildcard $(src_dir)/common/*)
	$$(RISCV_GCC) $$(incs) $$(RISCV_GCC_OPTS) -o $$@ $(wildcard $(src_dir)/$(1)/*.c) $(wildcard $(src_dir)/common/*.c) $(wildcard $(src_dir)/common/*.S) $$(RISCV_LINK_OPTS)
endef

$(foreach bmark,$(bmarks),$(eval $(call compile_template,$(bmark))))
```

在矩阵乘法的测试程序中用到了 `crt.S` 程序，如下所示：

```Makefile
# mt/Makefile: line 111
$(bmarks_riscv_vvadd_bin): %.riscv: %.o mt-vvadd.o syscalls.o crt.o
	$(RISCV_LINK) $< mt-vvadd.o syscalls.o crt.o $(RISCV_LINK_OPTS) -o $@

$(bmarks_riscv_matmul_bin): %.riscv: %.o mt-matmul.o syscalls.o crt.o
	$(RISCV_LINK) $< mt-matmul.o syscalls.o crt.o $(RISCV_LINK_OPTS) -o $@
```

查看 crt.S 的源码，`trap_entry` 的地址被赋值给 `mtvec`，作为 trap 处理的入口；trap_entry 中定义了一个完整的 trap 处理过程：申请栈保存当前 GPR 的值，调用处理函数 handle_trap 初始化对应硬件线程的一个 trap_handler 进行处理，完成之后在 M-Mode 出栈恢复 trap 之前的寄存器值，最后调用 `mret` 返回。

```S
# benchmarks/common/crt.S: line 109
# initialize trap vector
  la t0, trap_entry # 加载 trap_entry 的地址到 t0
  csrw mtvec, t0    # 将 t0 的值写入 mtvec，即 mtvec 保存了 trap 的处理程序入口位置

# benchmarks/common/crt.S: line 139
trap_entry:
  addi sp, sp, -272 # 申请栈空间

  # 保存当前寄存器的值
  SREG x1, 1*REGBYTES(sp)
  # ...
  SREG x31, 31*REGBYTES(sp)

  # get arguments of handle_trap (store them in a0, a1, a2)
  # 为 handle_trap 的参数赋值，调用该函数
  csrr a0, mcause
  csrr a1, mepc
  mv a2, sp
  jal handle_trap
  csrw mepc, a0  # 将 a0 中的返回值写回 mepc

  # Remain in M-mode after eret
  # 将 mstatus.MPP (Machine Previous Privilege) 写回到 mstatus 中
  li t0, MSTATUS_MPP
  csrs mstatus, t0

  # 恢复所有寄存器的值
  LREG x1, 1*REGBYTES(sp)
  # ...
  LREG x31, 31*REGBYTES(sp)

  # 栈销毁，mret 从 trap 处理返回原执行状态
  addi sp, sp, 272
  mret
```

```c
// debug/programs/init.c: line 20
void handle_trap(unsigned int mcause, void *mepc, void *sp)
{
    unsigned hartid = read_csr(mhartid);
    if (trap_handler[hartid]) {
        trap_handler[hartid](hartid, mcause, mepc, sp);
        return;
    }

    while (1)
        ;
}

// debug/programs/init.h: line 7
typedef void* (*trap_handler_t)(unsigned hartid, unsigned mcause, void *mepc,
        void *sp);
```

## S/H 扩展支持下的 Trap 处理

### S 扩展支持下的 Trap 处理

参考 [rcore 讲义][2]，仅具有 S 扩展，实现了内核态和用户态分隔的中断处理涉及的 CSR 以及指令可以归纳如下：

| 中断触发 |                   | 触发中断时要修改的 CSR |                                                                                                                                                  | 协助处理中断的 CSR |                                                                                                                                                                                                                                                                      | 中断处理后的返回 |                        |
| -------- | ----------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- | ---------------------- |
| ecall    | Environment Call  | sepc                   | Exception Program Counter，用来记录触发中断的指令的地址                                                                                          | stvec              | 设置内核态中断处理流程的入口地址。存储了一个基址 BASE 和模式 MODE：MODE 为 0 表示 Direct 模式，即遇到中断便跳转至 BASE 进行执行；MODE 为 1 表示 Vectored 模式，此时 BASE 应当指向一个向量，存有不同处理流程的地址，遇到中断会跳转至 BASE + 4 \* cause 进行处理流程。 | sret             | 从 S-Mode 做中断返回。 |
| ebreak   | Environment Break | scause                 | 记录中断是否是硬件中断，以及具体的中断原因。                                                                                                     | sstatus            | 具有许多状态位，控制全局中断使能等。                                                                                                                                                                                                                                 | mret             | 从 M-Mode 做中断返回。 |
|          |                   | stval                  | scause 不足以存下中断所有的必须信息。例如缺页异常，就会将 stval 设置成需要访问但是不在内存中的地址，以便于操作系统将这个地址所在的页面加载进来。 | sie                | 即 Supervisor Interrupt Enable，用来控制具体类型中断的使能，例如其中的 STIE 控制时钟中断使能。                                                                                                                                                                       |
|          |                   |                        |                                                                                                                                                  | sip                | 即 Supervisor Interrupt Pending，和 sie 相对应，记录每种中断是否被触发。仅当 sie 和 sip 的对应位都为 1 时，意味着中断打开且已发生中断，这时中断最终触发。                                                                                                            |

### H 扩展支持下的 Trap 处理扩充

如上所述，H 扩展在不改变 S 扩展的特权分级的前提下，引入了 HS 和 VS 两种特权模式，这也带来了额外的 trap 处理需求，由此引入了一些专用于 HS-Mode 的 trap 处理 CSR（`hstatus`, `htinst`, `hvip`, `hip`, `hie`, `hgeie`, `hgeip`），同时也引入了在 Guest 内部用于 trap 处理的 S 扩展 CSR 的拷贝版本（`vsepc`, `vscause`, `vstval` 等）。

## Trap 处理的模拟器实现

### Spike

在 Spike 的 `riscv/processor.cc` 文件中，`take_trap` 函数负责对 trap 进行处理，该函数接收 trap 类型和对应的 `epc` (Exception Program Counter) 作为参数，依据当前所在的特权级以及特定 CSR 的内容，确定 trap 应当在哪个特权级做处理。

其中 `trap_t` 定义如下：

```cpp
class trap_t
{
 public:
  trap_t(reg_t which) : which(which) {}
  virtual bool has_gva() { return false; }
  virtual bool has_tval() { return false; }
  virtual reg_t get_tval() { return 0; }
  virtual bool has_tval2() { return false; }
  virtual reg_t get_tval2() { return 0; }
  virtual bool has_tinst() { return false; }
  virtual reg_t get_tinst() { return 0; }
  reg_t cause() { return which; }

  virtual const char* name()
  {
    const char* fmt = uint8_t(which) == which ? "trap #%u" : "interrupt #%u";
    sprintf(_name, fmt, uint8_t(which));
    return _name;
  }

 private:
  char _name[16];
  reg_t which;
};

class insn_trap_t : public trap_t
{
 public:
  insn_trap_t(reg_t which, bool gva, reg_t tval)
    : trap_t(which), gva(gva), tval(tval) {}
  bool has_gva() override { return gva; }
  bool has_tval() override { return true; }
  reg_t get_tval() override { return tval; }
 private:
  bool gva;
  reg_t tval;
};

class mem_trap_t : public trap_t
{
 public:
  mem_trap_t(reg_t which, bool gva, reg_t tval, reg_t tval2, reg_t tinst)
    : trap_t(which), gva(gva), tval(tval), tval2(tval2), tinst(tinst) {}
  bool has_gva() override { return gva; }
  bool has_tval() override { return true; }
  reg_t get_tval() override { return tval; }
  bool has_tval2() override { return true; }
  reg_t get_tval2() override { return tval2; }
  bool has_tinst() override { return true; }
  reg_t get_tinst() override { return tinst; }
 private:
  bool gva;
  reg_t tval, tval2, tinst;
};
```

`trap_t` 类包含了一个 trap 可能需要包含的信息，如 GVA (Guest Virtual Address), tval, tval2 (trap value) 和 tinst (trap instruction)。处理 trap 时，先根据 trap 的具体内容设置程序计数器，以及进行处理时所在特权级对应的 CSR（如 epc, cause, tval, tinst 等），以保证下一步以正确的方式运行 trap 处理程序。此外还需对 sstatus 以及 当前特权级进行设置，如 `take_trap` 函数所示，定义如下：

```cpp
// riscv/processor.cc: line 793
void processor_t::take_trap(trap_t& t, reg_t epc)
{
  unsigned max_xlen = isa->get_max_xlen();

  // 格式化输出当前信息：processor id, trap 名称，epc/tval 值
  if (debug) {
    std::stringstream s; // first put everything in a string, later send it to output
    s << "core " << std::dec << std::setfill(' ') << std::setw(3) << id
      << ": exception " << t.name() << ", epc 0x"
      << std::hex << std::setfill('0') << std::setw(max_xlen/4) << zext(epc, max_xlen) << std::endl;
    if (t.has_tval())
       s << "core " << std::dec << std::setfill(' ') << std::setw(3) << id
         << ":           tval 0x" << std::hex << std::setfill('0') << std::setw(max_xlen / 4)
         << zext(t.get_tval(), max_xlen) << std::endl;
    debug_output_log(&s);
  }

  // 依据 trap 类型修改 pc 值，即 trap 处理程序：如果为断点调试，设置 pc 为 DEBUG_ROM_ENTRY，否则为 tvec
  if (state.debug_mode) {
    if (t.cause() == CAUSE_BREAKPOINT) {
      state.pc = DEBUG_ROM_ENTRY;
    } else {
      state.pc = DEBUG_ROM_TVEC;
    }
    return;
  }

  // 默认情况下会在 M-Mode 处理 trap，除非通过 xdeleg CSR 委托给 HS 或 VS 模式
  // By default, trap to M-mode, unless delegated to HS-mode or VS-mode
  reg_t vsdeleg, hsdeleg;
  reg_t bit = t.cause();
  bool curr_virt = state.v;
  bool interrupt = (bit & ((reg_t)1 << (max_xlen - 1))) != 0;
  // 依据 trap 的类别（interrupt，exception）确定：interrupt 只与高一级特权模式的 deleg CSR 有关，而 exception 与所有特权级更高的 deleg CSR 有关
  if (interrupt) {
    vsdeleg = (curr_virt && state.prv <= PRV_S) ? state.hideleg->read() : 0;
    hsdeleg = (state.prv <= PRV_S) ? state.mideleg->read() : 0;
    bit &= ~((reg_t)1 << (max_xlen - 1));
  } else {
    vsdeleg = (curr_virt && state.prv <= PRV_S) ? (state.medeleg->read() & state.hedeleg->read()) : 0;
    hsdeleg = (state.prv <= PRV_S) ? state.medeleg->read() : 0;
  }
  if (state.prv <= PRV_S && bit < max_xlen && ((vsdeleg >> bit) & 1)) {
    // Handle the trap in VS-mode

    // 修改 pc 以及对应 CSR
    reg_t vector = (state.vstvec->read() & 1) && interrupt ? 4 * bit : 0;
    state.pc = (state.vstvec->read() & ~(reg_t)1) + vector;
    state.vscause->write((interrupt) ? (t.cause() - 1) : t.cause());
    state.vsepc->write(epc);
    state.vstval->write(t.get_tval());

    // 设置 sstatus 用于保存当前运行状态；设置当前特权级
    reg_t s = state.sstatus->read();
    s = set_field(s, MSTATUS_SPIE, get_field(s, MSTATUS_SIE));
    s = set_field(s, MSTATUS_SPP, state.prv);
    s = set_field(s, MSTATUS_SIE, 0);
    state.sstatus->write(s);
    set_privilege(PRV_S);
  } else if (state.prv <= PRV_S && bit < max_xlen && ((hsdeleg >> bit) & 1)) {
    // Handle the trap in HS-mode
    set_virt(false);
    reg_t vector = (state.stvec->read() & 1) && interrupt ? 4 * bit : 0;
    state.pc = (state.stvec->read() & ~(reg_t)1) + vector;
    state.scause->write(t.cause());
    state.sepc->write(epc);
    state.stval->write(t.get_tval());
    state.htval->write(t.get_tval2());
    state.htinst->write(t.get_tinst());

    reg_t s = state.sstatus->read();
    s = set_field(s, MSTATUS_SPIE, get_field(s, MSTATUS_SIE));
    s = set_field(s, MSTATUS_SPP, state.prv);
    s = set_field(s, MSTATUS_SIE, 0);
    state.sstatus->write(s);
    if (extension_enabled('H')) {
      s = state.hstatus->read();
      if (curr_virt)
        s = set_field(s, HSTATUS_SPVP, state.prv);
      s = set_field(s, HSTATUS_SPV, curr_virt);
      s = set_field(s, HSTATUS_GVA, t.has_gva());
      state.hstatus->write(s);
    }
    set_privilege(PRV_S);
  } else {
    // Handle the trap in M-mode
    set_virt(false);
    reg_t vector = (state.mtvec->read() & 1) && interrupt ? 4 * bit : 0;
    state.pc = (state.mtvec->read() & ~(reg_t)1) + vector;
    state.mepc->write(epc);
    state.mcause->write(t.cause());
    state.mtval->write(t.get_tval());
    state.mtval2->write(t.get_tval2());
    state.mtinst->write(t.get_tinst());

    reg_t s = state.mstatus->read();
    s = set_field(s, MSTATUS_MPIE, get_field(s, MSTATUS_MIE));
    s = set_field(s, MSTATUS_MPP, state.prv);
    s = set_field(s, MSTATUS_MIE, 0);
    s = set_field(s, MSTATUS_MPV, curr_virt);
    s = set_field(s, MSTATUS_GVA, t.has_gva());
    state.mstatus->write(s);
    if (state.mstatush) state.mstatush->write(s >> 32);  // log mstatush change
    set_privilege(PRV_M);
  }
}
```

### QEMU

QEMU 中的 trap 处理实现与 Spike 类似，不同之处在于对当前状态（中断使能，特权级）的保存是通过修改 `mstatus` 而非 `sstatus` 来完成的。

```cpp
// target/riscv/cpu_helper.c: line 1325
/*
 * Handle Traps
 *
 * Adapted from Spike's processor_t::take_trap.
 *
 */
void riscv_cpu_do_interrupt(CPUState *cs)
{
#if !defined(CONFIG_USER_ONLY)

    RISCVCPU *cpu = RISCV_CPU(cs);
    CPURISCVState *env = &cpu->env;
    bool write_gva = false;
    uint64_t s;

    /* cs->exception is 32-bits wide unlike mcause which is XLEN-bits wide
     * so we mask off the MSB and separate into trap type and cause.
     */
    bool async = !!(cs->exception_index & RISCV_EXCP_INT_FLAG);
    target_ulong cause = cs->exception_index & RISCV_EXCP_INT_MASK;
    uint64_t deleg = async ? env->mideleg : env->medeleg;
    target_ulong tval = 0;
    target_ulong htval = 0;
    target_ulong mtval2 = 0;

    if  (cause == RISCV_EXCP_SEMIHOST) {
        if (env->priv >= PRV_S) {
            do_common_semihosting(cs);
            env->pc += 4;
            return;
        }
        cause = RISCV_EXCP_BREAKPOINT;
    }

    if (!async) {
        /* set tval to badaddr for traps with address information */
        switch (cause) {
        case RISCV_EXCP_INST_GUEST_PAGE_FAULT:
        case RISCV_EXCP_LOAD_GUEST_ACCESS_FAULT:
        case RISCV_EXCP_STORE_GUEST_AMO_ACCESS_FAULT:
        case RISCV_EXCP_INST_ADDR_MIS:
        case RISCV_EXCP_INST_ACCESS_FAULT:
        case RISCV_EXCP_LOAD_ADDR_MIS:
        case RISCV_EXCP_STORE_AMO_ADDR_MIS:
        case RISCV_EXCP_LOAD_ACCESS_FAULT:
        case RISCV_EXCP_STORE_AMO_ACCESS_FAULT:
        case RISCV_EXCP_INST_PAGE_FAULT:
        case RISCV_EXCP_LOAD_PAGE_FAULT:
        case RISCV_EXCP_STORE_PAGE_FAULT:
            write_gva = env->two_stage_lookup;
            tval = env->badaddr;
            break;
        case RISCV_EXCP_ILLEGAL_INST:
        case RISCV_EXCP_VIRT_INSTRUCTION_FAULT:
            tval = env->bins;
            break;
        default:
            break;
        }
        /* ecall is dispatched as one cause so translate based on mode */
        if (cause == RISCV_EXCP_U_ECALL) {
            assert(env->priv <= 3);

            if (env->priv == PRV_M) {
                cause = RISCV_EXCP_M_ECALL;
            } else if (env->priv == PRV_S && riscv_cpu_virt_enabled(env)) {
                cause = RISCV_EXCP_VS_ECALL;
            } else if (env->priv == PRV_S && !riscv_cpu_virt_enabled(env)) {
                cause = RISCV_EXCP_S_ECALL;
            } else if (env->priv == PRV_U) {
                cause = RISCV_EXCP_U_ECALL;
            }
        }
    }

    trace_riscv_trap(env->mhartid, async, cause, env->pc, tval,
                     riscv_cpu_get_trap_name(cause, async));

    qemu_log_mask(CPU_LOG_INT,
                  "%s: hart:"TARGET_FMT_ld", async:%d, cause:"TARGET_FMT_lx", "
                  "epc:0x"TARGET_FMT_lx", tval:0x"TARGET_FMT_lx", desc=%s\n",
                  __func__, env->mhartid, async, cause, env->pc, tval,
                  riscv_cpu_get_trap_name(cause, async));

    if (env->priv <= PRV_S &&
            cause < TARGET_LONG_BITS && ((deleg >> cause) & 1)) {
        /* handle the trap in S-mode */
        if (riscv_has_ext(env, RVH)) {
            uint64_t hdeleg = async ? env->hideleg : env->hedeleg;

            if (riscv_cpu_virt_enabled(env) && ((hdeleg >> cause) & 1)) {
                /* Trap to VS mode */
                /*
                 * See if we need to adjust cause. Yes if its VS mode interrupt
                 * no if hypervisor has delegated one of hs mode's interrupt
                 */
                if (cause == IRQ_VS_TIMER || cause == IRQ_VS_SOFT ||
                    cause == IRQ_VS_EXT) {
                    cause = cause - 1;
                }
                write_gva = false;
            } else if (riscv_cpu_virt_enabled(env)) {
                /* Trap into HS mode, from virt */
                riscv_cpu_swap_hypervisor_regs(env);
                env->hstatus = set_field(env->hstatus, HSTATUS_SPVP,
                                         env->priv);
                env->hstatus = set_field(env->hstatus, HSTATUS_SPV,
                                         riscv_cpu_virt_enabled(env));

                htval = env->guest_phys_fault_addr;

                riscv_cpu_set_virt_enabled(env, 0);
            } else {
                /* Trap into HS mode */
                env->hstatus = set_field(env->hstatus, HSTATUS_SPV, false);
                htval = env->guest_phys_fault_addr;
            }
            env->hstatus = set_field(env->hstatus, HSTATUS_GVA, write_gva);
        }

        s = env->mstatus;
        s = set_field(s, MSTATUS_SPIE, get_field(s, MSTATUS_SIE));
        s = set_field(s, MSTATUS_SPP, env->priv);
        s = set_field(s, MSTATUS_SIE, 0);
        env->mstatus = s;
        env->scause = cause | ((target_ulong)async << (TARGET_LONG_BITS - 1));
        env->sepc = env->pc;
        env->stval = tval;
        env->htval = htval;
        env->pc = (env->stvec >> 2 << 2) +
            ((async && (env->stvec & 3) == 1) ? cause * 4 : 0);
        riscv_cpu_set_mode(env, PRV_S);
    } else {
        /* handle the trap in M-mode */
        if (riscv_has_ext(env, RVH)) {
            if (riscv_cpu_virt_enabled(env)) {
                riscv_cpu_swap_hypervisor_regs(env);
            }
            env->mstatus = set_field(env->mstatus, MSTATUS_MPV,
                                     riscv_cpu_virt_enabled(env));
            if (riscv_cpu_virt_enabled(env) && tval) {
                env->mstatus = set_field(env->mstatus, MSTATUS_GVA, 1);
            }

            mtval2 = env->guest_phys_fault_addr;

            /* Trapping to M mode, virt is disabled */
            riscv_cpu_set_virt_enabled(env, 0);
        }

        s = env->mstatus;
        s = set_field(s, MSTATUS_MPIE, get_field(s, MSTATUS_MIE));
        s = set_field(s, MSTATUS_MPP, env->priv);
        s = set_field(s, MSTATUS_MIE, 0);
        env->mstatus = s;
        env->mcause = cause | ~(((target_ulong)-1) >> async);
        env->mepc = env->pc;
        env->mtval = tval;
        env->mtval2 = mtval2;
        env->pc = (env->mtvec >> 2 << 2) +
            ((async && (env->mtvec & 3) == 1) ? cause * 4 : 0);
        riscv_cpu_set_mode(env, PRV_M);
    }

    /* NOTE: it is not necessary to yield load reservations here. It is only
     * necessary for an SC from "another hart" to cause a load reservation
     * to be yielded. Refer to the memory consistency model section of the
     * RISC-V ISA Specification.
     */

    env->two_stage_lookup = false;
#endif
    cs->exception_index = RISCV_EXCP_NONE; /* mark handled to qemu */
}
```

## 总结

添加 H 扩展之后，RISC-V ISA 中与 trap 相关的 CSR 列表如下。需要注意的是，在进行 trap 处理时，需要如上节所分析的那样，确定在什么特权级下使用哪些 CSR 进行处理。

| Function                            | Machine             | Supervisor | Hypervisor       | Virtual Supervisor |
| ----------------------------------- | ------------------- | ---------- | ---------------- | ------------------ |
| **_Trap_**                          |
| Trap Vector Base Address            | mtvec               | stvec      |                  | vstvec             |
| Trap Delegation                     | medeleg and mideleg |            | hedeleg, hideleg |
| Interrupt                           | mip, mie            | sip, sie   | hvip, hip, hie   | vsip, vsie         |
| Hypervisor Guest External Interrupt |                     |            | hgeip, hgeie     |
| Exception Program Counter           | mepc                | sepc       |                  | vsepc              |
| Cause                               | mcause              | scause     |                  | vscause            |
| Trap Value                          | mtval               | stval      | htval            | vstval             |
| Trap Instruction                    | mtinst              |            | htinst           |
| Status                              | mstatus, mstatush   | sstatus    | hstatus          | vsstatus           |

## 参考资料

- [RISC-V 特权指令集手册][1]
- [RCore Tutorial][2]
- [RISC-V 虚拟模式][3]
- [riscv-tests][6]

[1]: https://riscv.org/technical/specifications/privileged-isa/
[2]: http://rcore-os.cn/rCore-Tutorial-deploy/docs/lab-1/guide/part-2.html
[3]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220724-riscv-kvm-virt-mode-switch.md#mstatus
[4]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220724-riscv-kvm-virt-mode-switch.md#mstatus
[5]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220724-riscv-kvm-virt-mode-switch.md#risc-v-中的-trap
[6]: https://github.com/riscv-software-src/riscv-tests
[7]: https://tinylab.org/riscv-timer/#kvm-vcpu_timerc
[8]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220724-riscv-kvm-virt-mode-switch.md#risc-v-中的-trap
[9]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220724-riscv-kvm-virt-mode-switch.md#控制转移
[10]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220724-riscv-kvm-virt-mode-switch.md#返回指令与虚拟化
[11]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220905-riscv-kvm-virt-trap.md#trap-处理实例
