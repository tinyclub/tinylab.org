---
layout: post
author: 'yjmstr'
title: '从零开始，徒手写一个 RISC-V 模拟器（1）——简介与基本框架'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /tinyemu-introduction/
description: '从零开始，徒手写一个 RISC-V 模拟器（1）——简介与基本框架'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - 模拟器
  - TinyEMU
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces]
> Author:    YJMSTR <pyjmstr@gmail.com><br\>
> Date:      2023/01/19
> Revisor:   Bin Meng, Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

之前 [翻译了一篇博客][1]，博主受到 [RVEMU 项目][2] 的启发，尝试通过用 C 语言写一个 RISC-V emulator，来学习 RISC-V 与计算机体系结构。但该博主在实现了 RISC-V 的整数、乘法和 Zicsr 模块之后便没有后续了。

本项目旨在延续该博主的工作，开发一个简单的教学用途 RISC-V 模拟器 —— TinyEMU，与此同时学习 RISC-V、计算机系统架构相关的知识。

## 模拟器与仿真器

在《计算机科学技术名词》（第三版）中，simulation 被译为模拟，emulation 被译为仿真，simulator 与 emulator 也相应地被分别译为模拟器与仿真器。在计算机领域中，模拟器和仿真器这两个概念常被混淆。之前在翻译 [这篇博客][1] 时，我也将 emulator 译为了模拟器，下面简单地对这两个概念进行区分：

仿真器（emulator）是使一个计算机系统（称为 host）表现得像另一个计算机系统（称为 guest）的硬件或软件，常用于调试，其使得 host 能够运行或使用为 guest 设计的软件或外设。仿真器不仅仿真了软件的运行环境，还仿真了底层硬件。仿真器和被仿真的对象期望有相同的输出。在某些情况下，仿真器可以代替其仿真的对象。计算机领域常见的仿真器有 QEMU 等。

而模拟器（simulator）注重模拟对象的行为，其内部原理需要与模拟目标一致。它可以用于模拟目标的运行原理，但不追求能够替代目标系统。常见的模拟器有 Spike，gem5，前者模拟 RISC-V ISA，后者倾向于模拟处理器的内部结构。

正如 TinyEMU 的名字（Tiny Emulator）所示，它是一个 RISC-V 仿真器，但为了方便起见，之后我们将 emulator 和 simulator 均称为模拟器。

## 指令执行方式

目前模拟器 [执行指令的方式][4] 主要有以 Spike 为主的解释型，和以 QEMU 为主的翻译型。

解释型直接用高级语言模拟指令的行为，比如 RISC-V ISA 中的 `add rd, rs1, rs2` 指令，它的含义是将 rs1 和 rs2 寄存器中的值相加后存入寄存器 rd 中，在解释型的模拟器里可以直接进行模拟：

```c
decode_result = decode(inst);	//译码
switch (decode_result) {
    case ADD: {R(rd) = R(rs1) + R(rs2); pc += 4; break;}	//执行
    ...;
}
```

解释型的优点是方便分析，缺点是性能较低。

翻译型的模拟器会将指令翻译成本机可以直接执行的指令序列，每次会翻译若干条指令，并一次性执行。其优点是运行速度快，可以结合编译技术对翻译过程进行优化，缺点是分析较为困难。

TinyEMU 采用的指令执行方式是解释型。

## 基本框架

要想运行模拟器，至少要实现本小节中包含的内容（监视器、内存、总线、CPU）。

TinyEMU 的根目录结构如下：

- TinyEmu/
  - src/
  - includes/
  - main.c
  - Makefile

### 监视器

监视器为 TinyEMU 提供与用户进行交互的命令行。监视器有一个主循环不断监听键盘输入，并根据键盘的输入执行对应的操作，我们将在 main.c 中实现它。

监视器还提供调试器，用于调试在 TinyEMU 中运行的客户程序。

要想实现和常见的命令行程序相同的基本功能，比如命令补全，快速输入历史命令等功能，可以使用 GNU Readline 库。如果想简单些也可以直接使用 scanf 读入命令进行处理。

监视器还要负责读入 guest 程序的路径。Guest 程序以二进制文件（.bin）的形式传入，存放于模拟器的内存中。

目前我们先为监视器实现如下基本功能：

- q：退出
- c：执行程序
- r：读入程序
- h：输出帮助文本

main.c 中的主循环如下：

```c
    while (1) {
        scanf("%s", opt);
        switch (opt[0]) {
            case 'q':
                return 0;
            case 'c':
                cmd_c();
                break;
            case 'h':
                cmd_h();
                break;
            case 'r':
                cmd_r();
                break;
            default:
                puts("invalid command");
                puts("input \'h\' for help");
                break;
        }
    }
```

其中 cmd_r() 的代码如下，它负责读入模拟器要执行的程序：

```c
void cmd_r() {
    scanf("%s", img_path);
    FILE *fp = fopen(img_path, "rb");
    assert(fp);
    fseek(fp, 0, SEEK_END);
    long size = ftell(fp);
    printf("Read %ld byte from file.\n", size);
    fseek(fp, 0, SEEK_SET);
    fread(cpu.bus.dram.dram + RESET_VECTOR_OFFSET, size, 1, fp);
    fclose(fp);
}
```

### 内存

DRAM 是系统内存，其中存放有指令和数据。此外，还需要为内存映射 IO（MMIO）留出足够的地址空间，以方便后续添加外设。

这里以 QEMU RISC-V 'virt' 平台作为参考，DRAM 的起始地址为 0x80000000，更低的地址留给外设。RESET_VECTOR 的地址默认为 DRAM 起始地址：

```c
#define DRAM_SIZE 1024*1024*128ull   //128 MiB
#define DRAM_BASE 0x80000000ull
#ifndef RESET_VECTOR_OFFSET
#define RESET_VECTOR_OFFSET 0
#endif
#define RESET_VECTOR DRAM_BASE + RESET_VECTOR_OFFSET
```

如果之后要运行 xv6 等特定程序，需要对内存大小进行对应修改。

DRAM 结构体如下所示：

```c
typedef struct DRAM {
    uint8_t *dram;
} DRAM;
```

初始化时调用 dram_init 函数，按照定义的 DRAM_SIZE 分配空间：

```c
void dram_init(DRAM *dram) {
    dram->dram = malloc(DRAM_SIZE);
    assert(dram->dram);
}
```

访存函数实现如下：

```c
void dram_store(DRAM *dram, uint64_t addr, int length, uint64_t val) {
    printf("dram store 0x%lx\n", addr);
    assert (length == 1 || length == 2 || length == 4 || length == 8);
    assert(addr >= 0 && addr < DRAM_SIZE);
    switch (length) {
        case 1:
            dram->dram[addr] = val & 0xff;
            return;
        case 2:
            dram->dram[addr] = val & 0xff;
            dram->dram[addr + 1] = (val & 0xff00) >> 8;
            return;
        case 4:
            dram->dram[addr] = val & 0xff;
            dram->dram[addr + 1] = (val & 0xff00) >> 8;
            dram->dram[addr + 2] = (val & 0xff0000) >> 16;
            dram->dram[addr + 3] = (val & 0xff000000) >> 24;
            return;
        case 8:
            dram_store(dram, addr, 4, val & 0xffff);
            dram_store(dram, addr + 4, 4, (val & 0xffff0000) >> 32);
            return;
    }
}

uint64_t dram_load(DRAM *dram, uint64_t addr, int length) {
    assert (length == 1 || length == 2 || length == 4 || length == 8);
    assert(addr >= 0 && addr < DRAM_SIZE);
    switch (length) {
        case 1:
            return dram->dram[addr];
        case 2:
            return (dram->dram[addr + 1] << 8) | dram->dram[addr];
        case 4:
            return (dram->dram[addr + 3] << 24) | (dram->dram[addr + 2] << 16) | (dram->dram[addr + 1] << 8) | (dram->dram[addr]);
        case 8:
            return (dram_load(dram, addr + 4, 4) << 32) | dram_load(dram, addr, 4);
    }
    return 0;
}
```

这里使用 `mem_load` 等辅助函数将 guest 程序的内存地址映射到 TinyEMU 的内存数组的下标中：

```c
uint64_t mem_load(DRAM *dram, uint64_t addr, int length) {
    printf("mem load addr = 0x%08lx\n", addr);
    return dram_load(dram, addr - DRAM_BASE, length);
}

void mem_store(DRAM *dram, uint64_t addr, int length, uint64_t val) {
    dram_store(dram, addr - DRAM_BASE, length, val);
}
```

### 总线

总线是计算机各个模块之间的数据通路。由于目前我们没有实现外设，只需要在总线中连接内存模块即可，即在总线结构体中添加一个 DRAM 成员。总线的实例将在 CPU 结构体中声明，因此此处不需要将 CPU 加进来。

总线结构体如下所示：

```c
typedef struct BUS {
    DRAM dram;
} BUS;
```

### CPU

CPU 需要实现取指、译码、执行这几个步骤：

- 取指：根据 PC 寄存器中的值在指令内存中取得数据。RISC-V 使用小端序存储数据，低地址存放低字节。
- 译码：根据机器码判断是哪种类型的哪一条指令，并根据指令类型提取指令中的寄存器编号、立即数等信息。译码结果存放在 `DECODER` 结构体中。
- 执行：直接用 C 代码模拟指令的行为。

CPU 结构体如下：

```c
typedef struct CPU {
    uint64_t regs[32];
    uint64_t pc;
    BUS bus;
    enum CPU_STATE state;
} CPU;
```

其中 CPU_STATE 用于表示目前 CPU 的状态，它有 CPU_STOP 和 CPU_RUN 两种取值。CPU 的执行函数每次执行时会检测 CPU 状态，如果处于 CPU_STOP 态将会停止执行。

指令的译码结果被存储在 DECODER 结构体中，供模拟该指令行为的函数使用。

CPU 执行函数代码如下：

```c
void exec_once(CPU *cpu) {
    uint32_t inst = inst_fetch(cpu);
    DECODER decoder = decode(inst);
    if (decoder.inst_name == INST_NUM) {
        cpu->state = CPU_STOP;
        printf("Unsupported instruction or EOF\n");
        printf("TinyEMU STOP\n");
        printf("PC = 0x%08lx inst=0x%08x inst_name = %d\n", cpu->pc, inst, decoder.inst_name);
        return;
    }
    decoder.dnpc = decoder.snpc = cpu->pc + 4;
    decoder.cpu = cpu;
    inst_handle[decoder.inst_name](https://gitee.com/tinylab/riscv-linux/blob/master/articles/&decoder);
    cpu->pc = decoder.dnpc;
}
```

其中 `inst_handle` 是存放函数指针的数组，`inst_handle[decoder->inst_name](https://gitee.com/tinylab/riscv-linux/blob/master/articles/&decoder)` 是执行指令的函数，`DECODER decoder` 作为该函数的参数。执行函数会对 `decoder` 进行修改，最终处理器根据执行结果对 PC 进行更新。当检测到空指令或是不支持的指令时，CPU 将停止运行，并输出相关信息。

## 总结

本文介绍了模拟器与仿真器的区别，模拟器的指令执行方式以及 TinyEMU 的基本框架，主要包括监视器、内存、总线、CPU 几大模块。其中监视器负责提供和用户进行交互的命令行，以及提供调试客户程序的功能；内存是一个大数组，存放有要执行的指令；总线是各个模块之间数据传输的通路；CPU 负责处理指令并执行对应的操作。

下一篇文章将进一步介绍 RISC-V 指令集与 CPU 模块、并在模拟器上运行程序。

## 参考资料

1. [用纯 C 语言写一个简单的 RISC-V 模拟器（支持基础整数指令集，乘法指令集与 CSR 指令）][1]
2. [RVEMU][2]
3. [RVEMU 开发教程][3]
4. [【余子濠】NEMU：一个效率接近 QEMU 的高性能解释器 - 第一届 RISC-V 中国峰会][4]
5. [NEMU][5]

[1]: https://tinylab.org/writing-a-simple-riscv-emulator-in-plain-c/
[2]: https://github.com/d0iasm/rvemu
[3]: https://book.rvemu.app/
[4]: https://www.bilibili.com/video/BV1Zb4y1k7RJ
[5]: https://github.com/NJU-ProjectN/nemu
