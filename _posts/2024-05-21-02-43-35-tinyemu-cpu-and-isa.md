---
layout: post
author: 'yjmstr'
title: '从零开始，徒手写一个 RISC-V 模拟器（2）——RISC-V 指令集与 CPU'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /tinyemu-cpu-and-isa/
description: '从零开始，徒手写一个 RISC-V 模拟器（2）——RISC-V 指令集与 CPU'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - TinyEMU
  - 模拟器
  - 指令集
  - CPU
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces comments]
> Author:    YJMSTR <pyjmstr@gmail.com><br\>
> Date:      2023/01/21
> Revisor:   Bin Meng, Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

在上一篇文章中我们介绍了 TinyEMU 的基本框架。本篇文章将一步步为 TinyEMU 实现 CPU 模块并支持 RV64I 指令集。

## RISC-V 指令集

RISC-V 指令集被划分为若干个模块，每一种 RISC-V 指令集实现都是由基础整数指令集加上其它可选扩展组成的，其中基础整数指令集必须被实现。术语 XLEN 用于描述通用整数寄存器所能存储的数据在二进制表示下的位数，以及地址空间的位数。

基础整数指令集有四种变体，两种常见的变体是 RV32I 与 RV64I，它们的 XLEN 分别为 32 和 64。此外还有 RV32E 与 RV128I。RV32E 是 RV32I 的子集，只提供了 16 个整数寄存器，以支持更小的微控制器。而 RV128I 是为 128 位的地址空间设计的（XLEN=128）。在基础整数指令集中，有符号整数使用二进制补码表示。

基础整数指令集用字母 I 表示，其它扩展模块及缩写分别是：

- M：标准乘法与除法扩展
- A：标准原子指令扩展
- F：标准单精度浮点扩展
- D：标准双精度浮点扩展
- C：标准压缩指令扩展
- Zifencei：FENCE.I 指令扩展
- Zicsr：控制与状态寄存器指令扩展

其它模块此处暂不介绍。I、M、A、F、D、Zifencei、Zicsr 的组合用字母 G 表示。我们将先在 TinyEMU 中实现 RV64I，其它模块之后补充。

在基础整数指令集中，指令被分为了六种类型：

![riscv-instruction-type.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/riscv-instruction-type.png)

每种类型具有固定的格式，我们可以对每种类型分别进行译码。上图中的 imm 表示指令中的立即数，rd 表示目标寄存器编号，rs1 与 rs2 为源寄存器 1 与源寄存器 2 的编号，opcode 为操作码。每种类型的指令中除 imm 外，其它部分如果存在，那么它们的位置都是确定的。因此可以把这些部分先提取出来，再根据指令类型处理 imm。

## RISC-V 通用整数寄存器

在上一篇文章中我们提到过 CPU 结构体：

```c
typedef struct CPU {
    uint64_t regs[32];
    uint64_t pc;
    BUS bus;
    enum CPU_STATE state;
} CPU;
```

其中的 `uint64_t regs[32]` 代表的是 RISC-V 中的 32 个通用整数寄存器。我们选取 RV64I 作为 TinyEMU 的基础整数指令集，因此这些寄存器都是 64 位的。它们由代号 x0，x1，...，x31 表示，其中 x0 恒为 0。

下图中，Register 一栏中 f 开头的为浮点寄存器，这里暂不讨论。在 RISC-V 汇编中，通用寄存器会以 ABI Name 一栏中的名称出现：

![riscv-register-abi.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/riscv-register-abi.png)

## CPU 模块实现

### 访存

为 CPU 添加两个私有访存函数，方便指令执行时进行调用。它们通过总线获得数据。

```c
uint64_t cpu_load(CPU *cpu, uint64_t addr, int length) {
    return mem_load(&cpu->bus.dram, addr, length);
}

void cpu_store(CPU *cpu, uint64_t addr, int length, uint64_t val) {
    mem_store(&cpu->bus.dram, addr, length, val);
}
```

### 初始化

使用 `cpu_init` 函数完成 CPU 的初始化：

```c
void cpu_init(CPU *cpu) {
    cpu->pc = RESET_VECTOR;
    cpu->regs[0] = 0;
    cpu->regs[2] = DRAM_BASE + DRAM_SIZE;
    cpu->state = CPU_RUN;
}
```

### 取指

使用 `inst_fetch` 函数完成 CPU 取指操作：

```c
uint64_t inst_fetch(CPU *cpu) {
    return cpu_load(cpu, cpu->pc, 4);
}
```

注意此处使用 mem_load 而不是 dram_load 进行取指。

### 译码

使用 `decode` 函数完成译码操作，译码结果（指令中各个部分的值，以及指令名称）放入 DECODER 结构体中，并将该结构体作为返回值。

在 `decode` 函数中，首先要判断指令的类型。RISC-V 规范中给出了如下图所示的 opcode 表格（适用于 RV32G 和 RV64G）：

![riscv-g-opcode.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/riscv-g-opcode.png)

以及指令集列表及其对应的译码格式。RV32I 如下所示：

![RV32I.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/RV32I.png)

RV64I 如下所示。这里只给出了相比 RV32I 有所不同的指令：

![RV64I.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_emulator/RV64I.png)

需要注意的是 SLLI 等移位指令在 RV32I 中有同名指令，但 shamt 不同。

我们按照上表中的顺序向 TinyEMU 中添加指令。首先是 RV32I 与 RV64I 共有的部分，然后是 RV64I。向 `enum INST_NAME` 添加这些指令的名称：

```c
enum INST_NAME {
	LUI,
	...
	INST_NUM,
};
```

然后在 `decode` 函数中进行判断。注意到除立即数外，指令中的其它部分如果存在，它们的位置都是固定的，因此可以先将它们提取出来（注意 RV64 中 shamt 比 RV32 中的 shamt 多一位）：

```c
DECODER decode(uint32_t inst) {
    DECODER ret;
    ret.inst_val = inst;
    ret.rd = BITS(inst, 11, 7);
    ret.rs1 = BITS(inst, 19, 15);
    ret.rs2 = BITS(inst, 24, 20);
    ret.shamt = BITS(inst, 25, 20);
    uint32_t funct3 = BITS(inst, 14, 12);
    uint32_t funct7 = BITS(inst, 31, 25);
    uint32_t shamt = BITS(inst, 26, 20);
    uint32_t opcode = BITS(inst, 6, 0);
```

从上文的 opcode 表格中可以看出 U-type 指令的 opcode 是确定的，因此可以首先根据 opcode 可以判断出俩条 U-type 指令：

```c
    switch (opcode) {
        case 0b0110111:
            ret.inst_name = LUI;
            ret.imm = imm_u(inst);
            break;
        case 0b0010111:
            ret.inst_name = AUIPC;
            ret.imm = imm_u(inst);
            break;
```

J-type 的 JAL 与 I-type 的 JALR 指令的 opcode 也是独一条，可以通过 opcode 判断：

```c
        case 0b1101111:
            ret.inst_name = JAL;
            ret.imm = imm_j(inst);
            break;
        case 0b1100111:
            ret.inst_name = JALR;
            ret.imm = imm_i(inst);
```

随后是 opcode = 0b1100011 的情况，这是基础整数指令集中的 B-type 指令，根据 funct3 指令可以进行进一步的判断，此处省略代码。

opcode = 0b0000011 的情况同理，这是加载类型的指令，可以用同样的方法判断。而 opcode = 0b0100011 的情况是 S-type 的指令，也是如此判断。其它指令类似。

需要注意的是，RV64I 中的 SRLIW 等指令的 shamt 与 RV32I 中不带 'W' 后缀的同名指令指令格式一致，但 funct7 的末位为 0，因此 shamt 的值不受影响，可以直接按照 RV64I 的 shamt 进行解码。

### 执行

在添加完对 RV64I 中所有指令的判断后，我们将依次实现每条指令的执行函数，以小写的指令名称作为执行该指令的函数的名称。其中 `FENCE`，`ECALL` 和 `EBREAK` 指令暂不执行操作：

```c
uint64_t MASK(int n) {
    if (n == 64) return -1;
    return (1ull << n) - 1;
}
uint64_t BITS(uint64_t imm, int hi, int lo) {
    return (imm >> lo) & MASK(hi - lo + 1);
}
uint64_t SEXT(uint64_t imm, int n) {
    if ((1 << (n-1)) & imm) {
        return (MASK(64) << n) | imm;
    }
    else return imm;
}
void set_inst_func(enum INST_NAME inst_name, void (*fp)(DECODER)) {
    inst_handle[inst_name] = fp;
}

void lui(DECODER decoder) {
    decoder.cpu->regs[decoder.rd] = decoder.imm << 12;
}

void auipc(DECODER decoder) {
    decoder.cpu->regs[decoder.rd] = decoder.cpu->pc + (decoder.imm << 12);
}

...
```

然后在 `init_inst_func` 函数中通过 `set_inst_func` 设置每条指令对应的函数：

```c
void init_inst_func() {
    set_inst_func(LUI, lui);
    set_inst_func(AUIPC, auipc);
    ...
}
```

最后记得调用初始化函数。

为了让处理器执行完最后一条指令或是运行到不支持的指令时能够退出，在译码器找不到对应指令时将 inst_name 设为 INST_NUM，来表示退出。

## 测试

由于目前暂未实现 Zicsr 模块的支持，暂时无法运行 RISC-V 官方的测例 riscv-test，但我们可以自行编写指令，存放在模拟器的内存中，观察模拟器执行指令后的行为来判断实现是否正确。

以 `auipc t0, 0` 为例，我们可以修改 `dram_init()` 如下：

```c
void dram_init(DRAM *dram) {
    dram->dram = malloc(DRAM_SIZE);
    assert(dram->dram);
    dram_store(0, 4, 0x00000297);// auipc t0, 0
}
```

然后在 monitor 中加入输出寄存器的指令：

```c
void cmd_re() {
    for (int i = 0; i < 32; i++) {
        printf("reg #%d == 0x%08lx\n", i, cpu.regs[i]);
    }
}
```

dram_store 将以小端序把指令存进内存中，随后启动模拟器，直接用 s 指令单步执行，然后输入 re 查看所有寄存器的值，可以看见，reg #5 即 t0 的值为 0x80000000。

## 总结

本文介绍了 RISC-V 指令集和通用寄存器，以及 TinyEMU 中 RV64I 指令集的实现与测试方法。接下来的文章将介绍 Zicsr 模块的实现，以及 riscv-test 测例的使用。

## 参考资料

1. [RISC-V spec][1]

[1]: https://riscv.org/technical/specifications/
