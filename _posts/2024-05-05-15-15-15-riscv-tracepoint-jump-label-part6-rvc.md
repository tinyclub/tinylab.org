---
layout: post
author: 'Wu Zhangjin'
title: 'RISC-V jump_label 详解，第 6 部分：分析 RVC 支持'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-tracepoint-jump-label-part6-rvc/
description: 'RISC-V jump_label 详解，第 6 部分：分析 RVC 支持'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - RVC
  - C 扩展
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces header toc urls autocorrect]
> Author:    Falcon <falcon@tinylab.org>
> Date:      2023/02/02
> Revisor:   Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 背景简介

该系列已经连载 5 篇文章，旨在分析 RISC-V 架构上的 jump_label 实现。前面 5 篇已经系统地分析了其原理和实现并结合 RISC-V 架构介绍了实际使用 jump_label 的优化案例。

前段观察到，在 RISC-V Linux 邮件列表中，有一位名叫 Guo Ren 的内核开发者提交了 1 笔针对 RVC 的 Static Branch 优化补丁，本文直接基于相关 [patch][003] 进行介绍（注：该代码到目前为止并未合入）。

如果没有特别说明，本文以 Linux v6.1 为例。

## RVC - RISC-V C 扩展

RISC-V 作为一种采用精简指令集的处理器架构，其特征是围绕核心指令集 RV32I/RV64I，通过一系列扩展来增强处理器的功能，不同厂家可以根据自身需要选择是否实现这些扩展。

其中，“C” 扩展通过为常见操作添加 16 位指令编码来减少静态和动态代码空间占用：

> reduces static and dynamic code size by adding short 16-bit instruction encodings for common operations. The C extension can be added to any of the base ISAs (RV32, RV64, RV128), and we use the generic term “RVC” to cover any of these. Typically, 50%–60% of the RISC-V instructions in a program can be replaced with RVC instructions, resulting in a 25%–30% code-size reduction.

以上内容摘录自 [riscv-spec-20191213.pdf][001] 的 "Chapter 16“C”Standard Extension for Compressed Instructions, Version 2.0"。

如果想在编译时启用 RVC 指令，需要开启如下选项：

```
Symbol: RISCV_ISA_C [=y]
Type  : bool
Defined at arch/riscv/Kconfig:385
  Prompt: Emit compressed instructions when building Linux
  Location:
    -> Platform type
(1)   -> Emit compressed instructions when building Linux (RISCV_ISA_C [=y])
Selected by [y]:
  - EFI [=y] && OF [=y] && !XIP_KERNEL [=n] && MMU [=y]
```

## RVC 指令长度

在 RISC-V Spec Chapter 16 的 “16.1 Overview” 一节讲到：

> RVC uses a simple compression scheme that offers shorter 16-bit versions of common 32-bit RISC-V
> instructions when:
>
> • the immediate or address offset is small, or
> • one of the registers is the zero register (x0), the ABI link register (x1), or the ABI stack
> pointer (x2), or
> • the destination register and the first source register are identical, or
> • the registers used are the 8 most popular ones.
>
> The C extension is compatible with all other standard instruction extensions. The C extension
> allows 16-bit instructions to be freely intermixed with 32-bit instructions, with the latter now able
> to start on any 16-bit boundary, i.e., IALIGN=16. With the addition of the C extension, no
> instructions can raise instruction-address-misaligned exceptions.

因此，RVC 指令长度为 16 位，即 2 个字节。

所以，该 patch 需要追加如下定义：

```
// arch/riscv/include/asm/jump_label.h

+#ifdef CONFIG_RISCV_ISA_C
+#define JUMP_LABEL_NOP_SIZE 2
+#else
 #define JUMP_LABEL_NOP_SIZE 4
+#endif
```

## RVC 指令编码

之前有介绍过如何编码 NOP 和 JAL/J offset，类似地，这里需要针对 RVC 的 C.NOP 和 C.JAL/C.J offset 进行编码。

### C.NOP

在 RISC-V Spec Chapter 16 的 “16.5 Integer Computational Instructions” 一节可知，C.NOP 同样复用 C.ADDI 编码：

    15 - 13 |  1  2    | 11 - 7  | 6  -  2    | 1  -   0 | Bits
    --------|----------|---------|------------|----------|------------
    funct3  | imm[5]   | rd/rs1  | imm[4:0]   | opcode   | CI-Type Instruction
    C.ADDI  | nzimm[5] | dest̸=0  | nzimm[4:0] | C1       | C.ADDI

> C.ADDI adds the non-zero sign-extended 6-bit immediate to the value in register rd then writes the result to rd. C.ADDI expands into addi rd, rd, nzimm[5:0]. C.ADDI is only valid when rd̸=x0 and nzimm̸=0. The code points with rd=x0 encode the C.NOP instruction

    15 - 13 |  12      | 11 - 7  | 6  -  2    | 1  -   0 | Bits
    --------|----------|---------|------------|----------|------------
    funct3  | imm[5]   | rd/rs1  | imm[4:0]   | opcode   | CI-Type Instruction
    C.NOP   |    0     |    0    |    0       | C1       | C.NOP

> C.NOP is a CI-format instruction that does not change any user-visible state, except for advancing the pc and incrementing any applicable performance counters. C.NOP expands to nop. C.NOP is only valid when imm=0

然后在 16.8 节的 “RVC Instruction Set Listings” 表中，可以找到 C.NOP 的最终编码：

    15 - 13 |  12      | 11 - 7  | 6  -  2    | 1  -   0 | Bits
    --------|----------|---------|------------|----------|------------
    funct3  | imm[5]   | rd/rs1  | imm[4:0]   | opcode   | CI-Type Instruction
    000     |    0     |    0    |    0       | 01       | C.NOP

因此，C.NOP 可以编码为 0x01，该 Patch 中的对应定义为：

```
#define RISCV_INSN_NOP 0x0001U
```

### C.JAL/C.J offset

在 RISC-V Spec Chapter 16 的 “16.4 Control Transfer Instructions” 一节中讲到：

    15 - 13 |  12         -            2    | 1  -   0 | Bits
    --------|-------------------------------|----------|------------
    funct3  |            imm                | opcode   | CJ-Type Instruction
    C.J     |    imm[11|4|9:8|10|6|7|3:1|5] | C1       | C.J

> C.J performs an unconditional control transfer. The offset is sign-extended and added to the pc to form the jump target address. C.J can therefore target a ±2 KiB range. C.J expands to jal x0, offset[11:1].
>
> C.JAL is an RV32C-only instruction that performs the same operation as C.J, but additionally writes the address of the instruction following the jump (pc+2) to the link register, x1. C.JAL expands to jal x1, offset[11:1].

需要注意的是，不同于 non RVC 的情况，这里的 C.JAL 只面向 RV32C，而 C.J 更通用，另外，其 offset 编码仅剩 12 位，跳转范围缩减到 ±2K。

然后在 16.8 节的 “RVC Instruction Set Listings” 表中，可以找到 C.J 的最终编码：

    15 - 13 |  12         -            2    | 1  -   0 | Bits
    --------|-------------------------------|----------|------------
    funct3  |            imm                | opcode   | CJ-Type Instruction
    101     |    imm[11|4|9:8|10|6|7|3:1|5] | 01       | C.J

因此，该 Patch 中的对应定义为：

```
#define RISCV_INSN_C_J 0xa001U
```

### C.NOP 和 C.J 完整定义

结合上面的编码过程，汇总后，该 Patch 针对 RVC 的指令编码如下：

```
// arch/riscv/kernel/jump_label.c

+#ifdef CONFIG_RISCV_ISA_C
+#define RISCV_INSN_NOP 0x0001U
+#define RISCV_INSN_C_J 0xa001U
+#else
 #define RISCV_INSN_NOP 0x00000013U
 #define RISCV_INSN_JAL 0x0000006fU
+#endif
```

## RVC Static Branch 实现

接下来，就是去实现针对 RVC 的 Jump Label 核心架构相关代码。

### 静态部分

首先是汇编部分，针对 RVC，需要把原有的 nop 和 jal 替换为 c.nop 和 c.j。

```
// arch/riscv/include/asm/jump_label.h

 static __always_inline bool arch_static_branch(struct static_key * const key,
 					       const bool branch)
 {
 	asm_volatile_goto(
-		"	.align		2			\n\t"
 		"	.option push				\n\t"
 		"	.option norelax				\n\t"
-		"	.option norvc				\n\t"
+#ifdef CONFIG_RISCV_ISA_C
+		"1:	c.nop					\n\t"
+#else
 		"1:	nop					\n\t"
+#endif
 		"	.option pop				\n\t"
 		"	.pushsection	__jump_table, \"aw\"	\n\t"
 		"	.align		" RISCV_LGPTR "		\n\t"
@@ -40,11 +46,13 @@ static __always_inline bool arch_static_branch_jump(struct static_key * const ke
 						    const bool branch)
 {
 	asm_volatile_goto(
-		"	.align		2			\n\t"
 		"	.option push				\n\t"
 		"	.option norelax				\n\t"
-		"	.option norvc				\n\t"
+#ifdef CONFIG_RISCV_ISA_C
+		"1:	c.j		%l[label]		\n\t"
+#else
 		"1:	jal		zero, %l[label]		\n\t"
+#endif
 		"	.option pop				\n\t"
 		"	.pushsection	__jump_table, \"aw\"	\n\t"
 		"	.align		" RISCV_LGPTR "		\n\t"
```

更简洁的写法其实可以定义另外的宏，例如：

```
#ifdef CONFIG_RISCV_ISA_C
#define RISCV_INSN_C_NOP_NAME "c.nop"
#define RISCV_INSN_C_J_NAME   "c.j"
#else
#define RISCV_INSN_C_NOP_NAME "nop"
#define RISCV_INSN_C_J_NAME   "j"
#endif
```

然后在代码中直接使用宏替换原有的 “nop” 和 “jal zero, ”，这样可以提升代码可读性。

需要特别讨论的是，在这个 Patch 中，删除了 “.align 2” 和 “.option norvc” 两行代码：

- 第二个比较容易理解，即启用 RVC 以后，不应该继续禁用 RVC，反之，那意味着原来的 “.option norvc” 针对未启用 RVC 的情况不是必须的，也就是压根不会用到 RVC 指令，所以没必要加 “.option norvc”。
- 而为什么要删除 “.align 2” 呢？这行代码实际上在 v6.1 中都还不存在，而是跟该 Patch 一同发出来，这行代码是配合 “.option norvc” 使用的，强制对齐到 4 字节（32bit），以避免在某些情况下出现动态写入 NOP 和 JAL 各一半的情况，详细解释请参考 [riscv: jump_label: Fixup unaligned arch_static_branch function][002]。
- 如果要考虑这块的完整兼容，这里简单删除 “.align 2” 似乎跟原有逻辑并不一致，也许需要针对 RVC 添加独立的 `arch_static_branch_jump()`，有待进一步确认。

### 动态部分

接下来是 C 语言部分的实现，即动态替换时需要编码 C.NOP 和 C.J 并做范围判断的更新。该 Patch 的实现如下：

```
 void arch_jump_label_transform(struct jump_entry *entry,
 			       enum jump_label_type type)
 {
 	void *addr = (void *)jump_entry_code(entry);
+#ifdef CONFIG_RISCV_ISA_C
+	u16 insn;
+#else
 	u32 insn;
+#endif

 	if (type == JUMP_LABEL_JMP) {
 		long offset = jump_entry_target(entry) - jump_entry_code(entry);
-
-		if (WARN_ON(offset & 1 || offset < -524288 || offset >= 524288))
+		if (WARN_ON(offset & 1 || offset < -2048 || offset >= 2048))
 			return;

+#ifdef CONFIG_RISCV_ISA_C
+		/*
+		 * 001 | imm[11|4|9:8|10|6|7|3:1|5] 01 - C.J
+		 */
+		insn = RISCV_INSN_C_J |
+			(((u16)offset & GENMASK(5, 5)) >> (5 - 2)) |
+			(((u16)offset & GENMASK(3, 1)) << (3 - 1)) |
+			(((u16)offset & GENMASK(7, 7)) >> (7 - 6)) |
+			(((u16)offset & GENMASK(6, 6)) << (7 - 6)) |
+			(((u16)offset & GENMASK(10, 10)) >> (10 - 8)) |
+			(((u16)offset & GENMASK(9, 8)) << (9 - 8)) |
+			(((u16)offset & GENMASK(4, 4)) << (11 - 4)) |
+			(((u16)offset & GENMASK(11, 11)) << (12 - 11));
+#else
+		/*
+		 * imm[20|10:1|11|19:12] | rd | 1101111 - JAL
+		 */
 		insn = RISCV_INSN_JAL |
 			(((u32)offset & GENMASK(19, 12)) << (12 - 12)) |
 			(((u32)offset & GENMASK(11, 11)) << (20 - 11)) |
 			(((u32)offset & GENMASK(10,  1)) << (21 -  1)) |
 			(((u32)offset & GENMASK(20, 20)) << (31 - 20));
+#endif
 	} else {
 		insn = RISCV_INSN_NOP;
 	}
```

同样地，为了减少条件编译，提升代码的可读性，可以增加针对 RVC 的独立 `arch_jump_label_transform()` 实现。

需要补充的是，该 Patch 把 offset 的范围从 1M 改到了 4KB，这个是符合 RISC-V Spec 针对 C.J 的 “±2 KiB range” 跳转约定，但实际上，针对 non RVC 的情况，保留原有的更大跳转范围（±1 MiB range）似乎更为合理。当然，原有的 offset 范围判断也有误，需要修改代码，从 ±524288 改为 ±1048576。

## 小结

本文简单分析了针对 RVC 的 Jump Label Patch，该 Patch 可以进一步减少 Jump Label 在启用 RISC-V “C” 扩展后的内核代码空间占用。

经过分析，该 Patch 在代码阅读性和兼容性方面存在进一步优化的空间。

## 参考资料

* [riscv: jump_label: Optimize the code size with compressed instruction][003]
* [riscv-spec-20191213.pdf][001]

[001]: https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf
[002]: https://lore.kernel.org/linux-riscv/20230126170607.1489141-2-guoren@kernel.org/
[003]: https://lore.kernel.org/linux-riscv/20230126170607.1489141-3-guoren@kernel.org/
