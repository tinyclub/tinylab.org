---
layout: post
author: 'BossWangST'
title: 'RISC-V CPU 设计（6）： RV64I CPU 控制器模块设计思路与实现'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /cpu-design-riscv-cpu-controller-module-design/
description: 'RISC-V CPU 设计（6）： RV64I CPU 控制器模块设计思路与实现'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - CPU 设计
  - 指令集
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [spaces newline header]
> Author:   Fajie.WangNiXi <YuHaoW1226@163.com>
> Date:     2022/08/16
> Revisor:  Falcon <falcon@tinylab.org>
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V CPU Design](https://gitee.com/tinylab/riscv-linux/issues/I5EIOA)
> Sponsor:  PLCT Lab, ISCAS


## 前言

在 CPU 设计的主要模块中，**控制器**的作用至关重要，控制器的输入是**取指令模块**的 32 位 RV64I 指令，输出是各个控制信号。本文将对 RV64I CPU 的控制器模块设计思路以及实现步骤进行介绍。

## 控制器的设计思路

既然控制器的输入端是指令，输出端是控制信号。那么设计控制器的出发点就在于研读 RISC-V 指令集手册中对指令编码的规定，寻找其中的规律，从而将二进制指令译码获取控制信号。

### RV64I 指令格式

在 [系列的第一篇文章][1] 中已经详细介绍了 RV32I 指令集，而在 RV64I 指令集中，其格式与 RV32I 基本相同。两者的差异在于 RV64I 增加了许多将结果截断成 32 位的指令，即编码会更多。RV64I 的指令格式仍然是以下 6 种：

![RV-inst-format](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/RV-inst-format.png)

从图中可以看出，RISC-V 指令译码阶段时的优势：表示寄存器编号的位置恒定，从而可以边译码边读取寄存器。同时，所有指令格式的末 7 位（inst[6:0]）固定为 `opcode` 字段，保证控制器可以直接区分不同指令所要进行的操作。

由此，控制器的大体框架就可以设计出来，首先将各个指令格式中的字段进行提取，接着根据 `opcode` 对指令功能进行分类，若有更细一步的划分（如 `funct3` 和 `funct7` 字段）则继续在类内区分，最后进行控制信号的赋值操作。于是可以写出如下的框架代码：

```scala
val funct7 = io.instruction(31 downto 25)
val rs2 = io.instruction(24 downto 20)
val rs1 = io.instruction(19 downto 15)
val funct3 = io.instruction(14 downto 12)
val rd = io.instruction(11 downto 7)
val opcode = io.instruction(6 downto 0)
// for I-type
val immediate = UInt(64 bits)
immediate := U(io.instruction(31), 52 bits) @@ io.instruction(31 downto 20)
// for S-type
val store_immediate = io.instruction(31 downto 25) @@ io.instruction(11 downto 7)
// for LUI & AUIPC
val U_immediate = io.instruction(31 downto 12)

switch(opcode) {
	default {
		// 控制信号赋值
	}
	is(...) {
	}
  is(...){
  }
}
```

### opcode 字段译码

从上面的介绍中可以看出，`opcode` 字段是区分指令格式的重要字段，而查阅 RISC-V 手册，`opcode` 字段定义如下：

![opcode-map](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/opcode-map.png)

图中是 RV64G 的主要 `opcode` 映射表。这里对 RV64G 进行说明：

* 对于 RISC-V 项目而言，其目标之一就是可以成为稳定的软件开发目标平台。为此 RISC-V 定义了一个组合指令集架构：基本 ISA（RV32I 或 RV64I）外加上标准扩展模块（IMAFD，Zicsr，Zifencei），作为一个通用目标的 ISA，所以这里使用了缩写 G 表示这一包含了 3 个标准扩展模块的 ISA
* RV64G 的各个扩展功能如下
	* M - 整数乘法和除法
	* A - 原子指令
	* F - 单精度浮点
	* D - 双精度浮点
	* Zicsr - CSRs 原子 RMW 操作扩展
	* Zifencei - fence.i 内存访问指令

* Zicsr：
	* 此扩展模块要求实现原子性的 CSR 寄存器读写指令，也是实现 RISC-V 特权指令集的基本扩展模块

* Zifencei：
	* 此扩展模块定义了 fence 相关指令，其作用是对外部可见的访存请求，如设备 I/O 访问，内存访问等进行串行化。外部可见是指对处理器的其他核心、线程，外部设备或协处理器可见
	* 目前 Zifencei 扩展仅包括了 FENCE.I 指令，该指令提供了同一个 hart 中写指令内存空间和读指令内存空间之间的显式同步，具体来说就是**读取的指令总是最新写入的指令**
	* 该指令目前是确保指令内存存储和读取都对 hart 可见的唯一标准机制

根据表中的内容，结合手册就可以确定 RV64I 每一个 `opcode` 字段所对应的指令格式，从而对上一小节框架中 switch 结构进行完善，得到如下的代码：

```scala
switch(opcode) {
	default {
		// 控制信号赋值
	}
	is(U"00_000_11") {
		// LOAD

	is(U"00_100_11") {
		// OP-IMM
  }
	is(U"00_110_11") {
		// OP-IMM-32
  }
	is(U"01_000_11") {
		// STORE
  }
	is(U"01_100_11") {
		// OP
	}
	is(U"01_101_11") {
		// LUI
	}
	is(U"00_101_11") {
		// AUIPC
  }
	is(U"01_110_11") {
		// OP-32
	}
	is(U"11_000_11") {
		// BRANCH
  }
	is(U"11_001_11") {
		// JALR
  }
	is(U"11_011_11") {
		// JAL
  }
}
```

### 结合指令执行流程确定基本控制信号

在控制器的框架搭建完毕后，下一步就是确定究竟要输出哪些控制信号。这时候就需要关注每条指令的执行流程，根据指令执行中经过的模块，确定控制信号的选取。在此过程中，我们可以根据不同指令格式对控制信号进行确定。

#### R 型指令

下面以一条 ADD 指令为例进行说明：

首先考虑 ADD 指令的功能，其将 rs1 寄存器中的值和 rs2 寄存器中的值相加，结果送至 rd 寄存器中。从描述中，可以得到以下的结论：

* 若要执行加法操作，则必须从**寄存器堆**中读取 2 个寄存器的值
* 加法操作是在 **ALU** 中完成
* 加法的结果将写入**寄存器堆**

所以，ADD 指令执行过程中，涉及的主要模块就是寄存器堆和 ALU。接下来考虑两个模块所需的控制信号：

* 寄存器堆：寄存器堆模块在设计时便要求有一个**写入使能**信号，而对于读取操作则是没有任何限制。所以，加法的结果写入寄存器堆时，需要将**写入使能**信号置位
* ALU：ALU 的功能是算术逻辑运算，在 ADD 指令中，ALU 的主要功能就是加法运算，故需要给 ALU **加法运算的信号**；同时，考虑到 **I 型指令**中，送入 ALU 的 2 个值分别是寄存器的值和立即数的值，所以在送入 ALU 模块操作数之前还需要添加一个 **2 选 1 数据选择器**，对立即数和寄存器值进行选择，故控制器还需要给出选择器的**选择信号**

这里需要牢记，如果一条指令不涉及内存相关的操作，必须要将**内存写入使能**信号清零，防止意外的向内存中写入非法数据。

经过这一系列的考量，一条 ADD 指令就要求控制器至少给出如下的信号：

* 寄存器写入使能信号（置位）
* ALU 运算操作信号（加法操作）
* ALU 数据选择信号（选寄存器值）
* 内存写入使能信号（清零）

#### I 型指令

I 型指令主要考虑 LOAD 相关指令（包括了 LB、LH、LW、LD 共 4 个不同宽度的内存读取操作）：

LOAD 指令的功能是先计算 rs1 寄存器中的值与给出的立即数（即偏移量）之和，得到内存地址后从内存中读取对应的字节、半字、字、双字数据，并写入 rd 寄存器中。所以整个流程会涉及以下操作：

* 从**寄存器堆**中读取 rs1 寄存器的值
* 在 **ALU** 中完成偏移量相加的计算
* 根据地址从**内存**中读取数据
* 将读取的数据写入**寄存器堆**

则根据不同子模块的设计，可以推断出 LOAD 相关的指令，需要额外给出如下的信号：

* 寄存器写入使能信号（置位）
* ALU 运算操作信号（加法操作）
* ALU 数据选择信号（选立即数）
* 内存写入使能信号（置位）

对 **S 型指令**的分析与 I 型指令类似，最终需要的控制信号类型与 LOAD 相关指令相同。由于 LOAD 相关和 STORE 相关指令都有 4 种不同宽度的指令，所以各自需要 3 位控制信号（分别表示 4 种宽度和非内存读写指令）。

#### B 型指令与 J 型指令

对于这两类指令格式，其对应的指令分别是条件转移指令和无条件转移指令。所以可以一并考虑：转移指令的基本流程都是先计算出目标转移地址，再通知 PC 使其调整。故涉及以下操作：

* 从**寄存器堆**中读取寄存器的值（B 型指令比较值的大小，JALR 指令读取基址）
* 在 **ALU** 中计算转移目标地址或比较大小
* 通知 **PC** 更改下一条指令地址
* 向**寄存器堆**写入返回地址（JALR 指令操作）

同样的，可以推断出需要如下的控制信号：

* 寄存器写入使能（仅 JALR 时置位，其他情况下清零）
* PC 通知信号（B 型和 J 型指令需要做出区分）
* ALU 运算操作信号（加法操作、减法操作）
* ALU 数据选择信号（选择寄存器值）
* 内存写入使能信号（清零）

这里有一个技巧，由于 JAL 和 JALR 指令都需要记录下返回地址（即当前 PC + 4）至寄存器中，所以这里的加法运算可以不在庞大的 ALU 中完成，而改为放在数据通路中直接相加得到。此时，控制器就需要另行发出一个控制信号让写入寄存器的值，通过一个 **2 选 1 数据选择器**在 ALU 输出结果和 PC + 4 之间选择。

B 型指令中共有 4 种比较 rs1 寄存器值与 rs2 寄存器值大小的方式：

* 相等（BEQ）
* 不等（BNE）
* 小于（BLT）
* 大于等于（BGE）

所以 B 型指令还需要 3 位的控制信号（注意，此处还有不跳转的情况，共 5 种可能，至少 3 位信号进行选择）。

#### 特殊控制信号

在讨论过上述基本控制信号之后，还需要关注一些特殊控制信号：

* 对于**移位**指令，根据手册描述，移位的数量为立即数的**低 5 位**，所以需要额外输出一个控制信号，要求立即数进入 ALU 前截取低 5 位
* 在 RV64I 指令集中，为了兼容 RV32I 的部分运算操作，在 `opcode` 字段新增了 OP-IMM-32 这一表述，代表此 RV64I 指令不论运算结果如何，都需要首先将**运算数截取低 32 位**进行运算，之后再让运算结果**符号扩展至 64 位**后写入内存或寄存器。故此处即需要一个额外的控制信号，要求 ALU 截断输出的结果
* 对于 **LUI** 指令，其作用是将指令中的高 20 位置入 rd 寄存器中（在 RV64I 中是置入 reg[31:12]），其余位清零。所以，此处还需要一个控制信号，决定写入寄存器的值
* 对于 **AUIPC** 指令，和 LUI 指令类似，区别在于 AUIPC 要求将高 20 位数据后面拼接 12 位的 0，构成一个 32 位偏移量后加上当前 PC 值，最终的和写入 rd 寄存器中。故 AUIPC 需要一个额外的控制信号

至此，控制器模块的总体输入输出端口都已确定，可以得到如下的代码：

```scala
class Controller extends Component {
	val io = new Bundle {
		val instruction = in UInt (32 bits)
		// ALU
		val aluCtr = out UInt (4 bits) // 4 bits signal for ALU
		val aluSrc = out Bool() // select data2 for ALU, True => from register, False => immediate
		val shiftCtr = out Bool() // if instruction is shifting, then data2 should be lower 5 bits of immediate
		val strip32 = out Bool() // for some RV64I instructions, requiring the result to be lower 32 bits
		val exRes = out UInt (2 bits) // 2 bits signal to choose execution part result
		// exRes => 00 -- ALU result  01 -- PC+4  10 -- LUI  11 -- AUIPC
		// Register_file
		val regWriteEnable = out Bool() // register write operation enable signal
		// PC
		val branch = out UInt (3 bits)
		// branch => 000 -- DO NOT BRANCH  001 -- BEQ  010 -- BNE  011 -- BLT  100 -- BGE
		val jump = out Bool()
		val jalr = out Bool() // if JALR, then jump address is True => ALU result, else False => immediate
		// Memory
		val load = out UInt (3 bits) // load data from memory to register, 000 => write_data is ALU result, 001 => LB, 010 => LH, 011 => LW, 100 => LD
		val store = out UInt (3 bits) // same as load
		val memWriteEnable = out Bool() // memory write operation enable signal
		// Register Index
		val rs1 = out UInt (5 bits)
		val rs2 = out UInt (5 bits)
		val rd = out UInt (5 bits)
	}
	noIoPrefix()
}
```

## 控制器的具体实现

在总体设计结束后，就需要根据每条指令分别给不同的控制信号赋值，下面从各个 `opcode` 出发，对控制信号进行赋值。

* 首先需要确定各个控制信号的初始值，默认均清零：

```scala
default {
	io.rs2 := 0
	io.rs1 := 0
	io.rd := 0

	io.aluCtr := aluADD
	io.aluSrc := False
	io.shiftCtr := False
	io.strip32 := False
	io.exRes := aluRes

	io.regWriteEnable := False

	io.branch := noBranch
	io.jump := False
	io.jalr := False

	io.load := noLoad
	io.store := noStore
	io.memWriteEnable := False
}
```

* LOAD 类型

正如上一小节所讨论，根据 `funct3` 字段确定宽度，需要注意的是清零内存写入使能。同时为了让代码更加可读，可以在 switch 选择语句之前定义好一系列的 `val` 常量：

```scala
val noLoad = U"000"
val LoadByte = U"001"
val LoadHalfWord = U"010"
val LoadWord = U"011"
val LoadDoubleWord = U"100"
```

这样在 `is` 语句中可以一定程度避免混淆信号值的问题出现：

```scala
is(U"00_000_11") {
	// LOAD

	// disable memory write enable signal
	io.memWriteEnable := False
	// disable branch & jump signal
	io.jump := False
	io.branch := noBranch
	// ALU = ADD
	io.aluSrc := False
	io.aluCtr := aluADD
	io.shiftCtr := False
	io.exRes := aluRes
	// Register, write memory data to rd
	io.regWriteEnable := True
	switch(funct3) {
		is(U"000") {
			// LB
			io.load := LoadByte
		}
		is(U"001") {
			// LH
			io.load := LoadHalfWord
		}
		is(U"010") {
			// LW
			io.load := LoadWord
		}
		is(U"011") {
			// LD
			io.load := LoadDoubleWord
		}
	}
}
```

* STORE 类型

与 LOAD 类型类似，需要清零寄存器写入使能。同样首先定义常量部分：

```scala
val noStore = U"000"
val StoreByte = U"001"
val StoreHalfWord = U"010"
val StoreWord = U"011"
val StoreDoubleWord = U"100"
```

`is` 语句部分的可读性也可以增加：

```scala
is(U"01_000_11") {
	// STORE

	// disable register write enable signal
	io.regWriteEnable := False
	// disable branch & jump signal
	io.jump := False
	io.branch := noBranch
	// ALU = ADD
	io.aluSrc := False
	io.shiftCtr := False
	io.aluCtr := aluADD
	io.exRes := aluRes
	// Memory, write
	io.memWriteEnable := True
	switch(funct3) {
		is(U"000") {
			// SB
			io.store := StoreByte
		}
		is(U"001") {
			// SH
			io.store := StoreHalfWord
		}
		is(U"010") {
			// SW
			io.store := StoreWord
		}
		is(U"011") {
			// SD
			io.store := StoreDoubleWord
		}
	}
}
```

* BRANCH 类型

注意，当指令没有写入操作时，必须要清零所有写入使能，定义常量如下：

```scala
val noBranch = U"000"
val BEQ = U"001"
val BNE = U"010"
val BGE = U"100"
val BLT = U"101"
```

控制信号变量赋值：

```scala
is(U"11_000_11") {
	// BRANCH

	// disable write enable signals
	io.regWriteEnable := False
	io.memWriteEnable := False
	// branch
	io.exRes := aluRes
	// ALU
	io.aluCtr := aluSUB
	io.aluSrc := True
	io.shiftCtr := False
	switch(funct3) {
		is(U"000") {
			// BEQ
			io.branch := BEQ
		}
		is(U"001") {
			// BNE
			io.branch := BNE
		}
		is(U"100") {
			// BLT
			io.branch := BLT
		}
		is(U"101") {
			// BGE
			io.branch := BGE
		}
	}
}
```

* JALR 类型

JALR 指令需要将返回地址（即当前 PC + 4）写入 rd 指定的寄存器中。由于此处引入了写入寄存器的新选择项，所以定义控制信号常量值如下：

```scala
	val aluRes = U"00" // 写入 ALU 结果
	val pc_plus_4 = U"01" // 写入 pc + 4
	val LUI = U"10" // 写入 upper immediate
	val AUIPC = U"11" // 写入 pc + upper immediate
```

JALR 指令类型控制信号赋值如下：

```scala
is(U"11_001_11") {
	// JALR

	// disable memory write enable signal
	io.memWriteEnable := False
	// Register, store pc+4 into rd
	io.regWriteEnable := True
	io.rs1 := rs1
	io.rd := rd
	io.aluSrc := True
	io.aluCtr := aluADD
	io.shiftCtr := False
	// JALR
	io.jump := True
	io.branch := noBranch
	io.exRes := pc_plus_4
	io.load := noLoad
	io.jalr := True
}
```

* JAL 类型

```scala
is(U"11_011_11") {
	// JAL

	// disable memory write enable signal
	io.memWriteEnable := False
	// Register, store pc+4 into rd
	io.regWriteEnable := True
	// JAL
	io.jump := True
	io.branch := noBranch
	io.exRes := pc_plus_4
	io.load := noLoad
	io.jalr := False
}
```

* OP-IMM 类型

在 OP-IMM 类型指令中，还需要区分 `funct3` 和 `funct7` 字段值以确认 ALU 需要完成的运算。为了区分各 ALU 运算指令，使用常量对其命名：

```scala
val aluADD = U"0000"
val aluSLT = U"0001"
val aluSLTU = U"0010"
val aluAND = U"0011"
val aluOR = U"0100"
val aluXOR = U"0101"
val aluSLL = U"0110"
val aluSRL = U"0111"
val aluSUB = U"1000"
val aluSRA = U"1001"
```

则 OP-IMM 指令类型控制信号如下：

```scala
is(U"00_100_11") {
	// OP-IMM

	//write enable signal
	io.memWriteEnable := False
	io.regWriteEnable := True
	// disable branch & jump signal
	io.jump := False
	io.branch := noBranch
	// ALU data2 must be immediate
	io.aluSrc := False
	io.strip32 := False
	io.exRes := aluRes
	io.load := noLoad
	io.shiftCtr := False
	switch(funct3) {
		is(U"000") {
			// ADDI
			io.aluCtr := aluADD
		}
		is(U"010") {
			// SLTI
			io.aluCtr := aluSLT
		}
		is(U"011") {
			// SLTIU
			io.aluCtr := aluSLTU
		}
		is(U"111") {
			// ANDI
			io.aluCtr := aluAND
		}
		is(U"110") {
			// ORI
			io.aluCtr := aluOR
		}
		is(U"100") {
			// XORI
			io.aluCtr := aluXOR
		}
		is(U"001") {
			// SLLI
			io.aluCtr := aluSLL
			io.shiftCtr := True
		}
		is(U"101") {
			// SRLI SRAI
			io.shiftCtr := True
			switch(funct7) {
				is(U"0000000") {
					// SRLI
					io.aluCtr := aluSRL
				}
				is(U"0100000") {
					// SRAI
					io.aluCtr := aluSRA
				}
			}
		}
	}
}
```

* OP 类型

OP 类型和 OP-IMM 类型相似，依然是需要进一步区分 `funct3` 和 `funct7`：

```scala
is(U"01_100_11") {
	// OP

	//write enable signal
	io.memWriteEnable := False
	io.regWriteEnable := True
	// disable branch & jump signal
	io.jump := False
	io.branch := noBranch

	io.aluSrc := True
	io.strip32 := False
	io.exRes := aluRes
	io.load := noLoad
	io.shiftCtr := False
	switch(funct3) {
		is(U"000") {
			// ADD SUB
			switch(funct7) {
				is(U"0000000") {
					// ADD
					io.aluCtr := aluADD
				}
				is(U"0100000") {
					// SUB
					io.aluCtr := aluSUB
				}
			}
		}
		is(U"010") {
			// SLT
			io.aluCtr := aluSLT
		}
		is(U"011") {
			// SLTU
			io.aluCtr := aluSLTU
		}
		is(U"111") {
			// AND
			io.aluCtr := aluAND
		}
		is(U"110") {
			// OR
			io.aluCtr := aluOR
		}
		is(U"100") {
			// XOR
			io.aluCtr := aluXOR
		}
		is(U"001") {
			// SLL
			io.aluCtr := aluSLL
			io.shiftCtr := True
		}
		is(U"101") {
			// SRL SRA
			io.shiftCtr := True
			switch(funct7) {
				is(U"0000000") {
					// SRL
					io.aluCtr := aluSRL
				}
				is(U"0100000") {
					// SRA
					io.aluCtr := aluSRA
				}
			}
		}
	}
}
```

* OP-IMM-32 类型

和 OP 类型在除 ALU 外的主要模块控制信号相同，区别在于需要发出截取低 32 位的控制信号：

```scala
is(U"00_110_11") {
	// OP-IMM-32

	// write enable signal
	io.memWriteEnable := False
	io.regWriteEnable := True
	// disable branch & jump signal
	io.jump := False
	io.branch := noBranch

	io.aluSrc := False
	io.strip32 := True
	io.exRes := aluRes
	io.load := noLoad
	io.shiftCtr := False
	switch(funct3) {
		is(U"000") {
			// ADDIW
			io.aluCtr := aluADD
		}
		is(U"001") {
			// SLLIW
			io.aluCtr := aluSLL
			io.shiftCtr := True
		}
		is(U"101") {
			// SRLIW SRAIW
			io.shiftCtr := True
			switch(funct7) {
				is(U"0000000") {
					// SRLIW
					io.aluCtr := aluSRL
				}
				is(U"0100000") {
					// SRAIW
					io.aluCtr := aluSRA
				}
			}
		}
	}
}
```

* OP-32 类型

同理，相较于 OP 类型，需要额外发出截取低 32 位的控制信号给 ALU：

```scala
is(U"01_110_11") {
	// OP-32

	// write enable signal
	io.memWriteEnable := False
	io.regWriteEnable := True
	// disable branch & jump signal
	io.jump := False
	io.branch := noBranch

	io.aluSrc := True
	io.strip32 := True
	io.exRes := aluRes
	io.load := noLoad
	io.shiftCtr := False
	switch(funct3) {
		is(U"000") {
			// ADDW SUBW
			switch(funct7) {
				is(U"0000000") {
					// ADDW
					io.aluCtr := aluADD
				}
				is(U"0100000") {
					// SUBW
					io.aluCtr := aluSUB
				}
			}
		}
		is(U"001") {
			// SLLW
			io.aluCtr := aluSLL
			io.shiftCtr := True
		}
		is(U"101") {
			// SRLW SRAW
			io.shiftCtr := True
			switch(funct7) {
				is(U"0000000") {
					// SRLW
					io.aluCtr := aluSRL
				}
				is(U"0100000") {
					// SRAW
					io.aluCtr := aluSRA
				}
			}
		}
	}
}
```

* LUI 和 AUIPC 类型

```scala
is(U"01_101_11") {
	// LUI

	// write enable signal
	io.memWriteEnable := False
	io.regWriteEnable := True

	io.exRes := LUI
	io.load := noLoad
}
is(U"00_101_11") {
	// AUIPC

	// write enable signal
	io.memWriteEnable := False
	io.regWriteEnable := True

	io.exRes := AUIPC
	io.load := noLoad
}
```

## 总结

至此，控制器模块设计完毕。但是，随着数据通路的搭建，也可能出现为了简化指令流程而需要额外控制信号的情况，那时将根据需求增添信号个数。

万变不离其宗的是，控制器作为译码环节最重要的模块，其设计思路一定是从指令的执行过程出发，思考指令流经的模块以及模块各自所需的输入，最后利用 `switch` 语句进行实现。本文也是以这样的思路从最简单的 ADD 指令开始，确定控制信号的个数，根据指令功能分析各信号值，最终在 SpinalHDL 框架下实现控制器。

## 参考资料

- CPU 设计实战  汪文祥 邢金璋 著 ISBN 978-7-111-67413-9
- [SpinalHDL 手册][2]
- [SpinalHDL Getting Started][3]
- [RISC-V 非特权模式手册][4]

[1]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220701-cpu-design-part1-riscv-instruction.md
[2]: https://spinalhdl.github.io/SpinalDoc-RTD/master/index.html
[3]: https://github.com/SpinalHDL/SpinalTemplateSbt
[4]: https://riscv.org/wp-content/uploads/2019/12/riscv-spec-20191213.pdf
