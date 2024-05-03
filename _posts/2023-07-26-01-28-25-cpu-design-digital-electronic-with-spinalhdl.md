---
layout: post
author: 'falcon'
title: 'RISC-V CPU 设计（3）：数电基本知识与基于 Scala 的硬件设计框架 SpinalHDL'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /cpu-design-digital-electronic-with-spinalhdl/
description: 'RISC-V CPU 设计（3）：数电基本知识与基于 Scala 的硬件设计框架 SpinalHDL'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - CPU 设计
  - 数电
  - Scala
  - SpinalHDL
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [epw]
> Author:   Fajie.WangNiXi <YuHaoW1226@163.com>
> Date:     2022/07/22
> Revisor:  ENJOU1224, Falcon
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V CPU Design](https://gitee.com/tinylab/riscv-linux/issues/I5EIOA)
> Sponsor:  PLCT Lab, ISCAS


## 前言

对于 CPU 设计，从最底层的角度来说，就是需要设计一套组合逻辑电路与时序逻辑电路相结合的系统。那么我们必须先对数字逻辑电路的基本知识加以了解，并且使用一款高效的硬件开发工具来协助我们学习各种电路的具体实现。

本篇文章将分为两部分，先从理论角度介绍 CPU 设计中涉及到的数字电路理论知识，再从编程开发的角度实际的展示如何将理论与实践相结合进行硬件电路的开发。

## 数字逻辑电路基本知识

现代计算机的内部电子元件是**数字**电路。数字电子元件仅在两个电压水平下运行：高电平和低电平。所有其他电压值均为瞬时值，且只出现在两个电压值转换过程中。数字计算机也是因其使用二进制方式而得名，因为二进制系统可以匹配电子元件中的**底层抽象**。

下面我们将从电路中最基本的电子元件开始介绍，逐步解构数字逻辑电路世界中的两大电路类型：组合逻辑电路与时序逻辑电路。

### 真值表、门电路和逻辑方程

正如上文所言，计算机采用二进制系统可以匹配电子元件的底层抽象（高电压和低电压）；而在不同的逻辑系列中，两个电压值以及它们之间的关系是不同的，分为**正逻辑电路**（高电压为真值）和**负逻辑电路**（低电压为真值）。

因此，本文中我们将**不**参考电压水平的高低，而是谈论（逻辑上）为真、为 1 或**有效（asserted）**的信号，或者（逻辑上）为假、为 0 或**无效（deasserted）**的信号。称值 0 和 1 彼此**互补**或**反转**。

根据逻辑块是否包含**存储器**，我们可以将其分为两类：

* 不包含存储器的逻辑块称为**组合逻辑电路**，组合电路的输出**仅**取决于当前输入
* 含有存储器的逻辑块称为**时序逻辑电路**，时序电路的输出可以由外部输入以及当前存储器中的值（称该值为逻辑块的**状态**）共同决定

#### 真值表

由于组合逻辑块不包含存储器，因此通过为每个可能的**输入值集合**定义对应的**输出值**，就可以完全指定一个组合逻辑电路。这种确定的对应关系通常用**真值表**给出。对于一个包含 $n$ 个输入的逻辑块，存在许多可能的输入值组合，因此真值表含有 $2^n$ 个表项。每个表项为特定输入组合指定所有的输出值。下面给出一个具体案例：

![真值表](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/真值表.png)

这一真值表所对应的逻辑函数是：

* 如果有一个输入为真，则 D 为真
* 如果有两个输入为真，则 E 为真
* 如果有三个输入为真，则 F 为真

真值表可以完整地描述任何组合逻辑电路，我们将在介绍 SpinalHDL 语言时具体的讲解如何实现。

#### 门电路

逻辑块由实现基本逻辑功能的**门（gate）**构成。例如，与门实现逻辑**与**操作，或门实现逻辑**或**操作。由于**与**和**或**操作都是可交换、可结合的，因此与门和或门可以有多个输入，输出等于所有输入的与操作或者或操作。逻辑**非**操作通过一个始终具有单个输入的反相器实现。这三种逻辑构建块的标准表示如下图所示：

![门电路示意图](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/门电路.png)

从左至右分别是**与门**、**或门**和**非门**的标准表示形式。每个门的左侧为输入信号，右侧为输出信号。**与门**和**或门**均为两个输入信号，**非门**仅有单个输入信号。

#### 逻辑方程

我们也可以用逻辑方程表示逻辑函数，通过使用**布尔代数**来完成。在布尔代数中，所有变量的值非 0 即 1，在典型的表达式中有 3 个运算符：

* 或操作记作 $+$，如 $A+B$。如果任一变量为 1，则或操作的结果为 1；所以或操作也称为**逻辑和**
* 与操作记作 $\cdot$，如 $A\cdot B$。只有当两个输入都为 1 时，与操作的结果才为 1；所以与操作也称为**逻辑积**
* 一元非操作写作 $\overline{A}$。非操作也称为**逻辑取反**

### 组合逻辑电路

在本节中，我们将介绍一些常用的较大的逻辑单元，并讨论结构化的逻辑设计，最后我们将讨论逻辑阵列的概念。

#### 译码器

译码器（decoder）适用于构造更大组件的一种逻辑单元。最常见的译码器有 $n$ 位输入和 $2^n$ 个输出，其中每种输入组合仅对应一个输出。该译码器将 $n$ 位输入转化为对应于 $n$ 位二进制的信号。因此 $n$ 个输出通常被标作 $Out_0, Out_1,...,Out_{2^n-1}$。如果输入的值是 $i$，那么 $Out_i$ 为真，其他所有输出均为假。下图给出了一个 3 位译码器及其对应的真值表：

![译码器示意图](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/38译码器.png)

该译码器有 3 位输入和 8 个输出，因此称为 **3-8 译码器**。此外，还有一种称为编码器的逻辑元件，它与译码器的功能正好相反。编码器有 $2^n$ 个输入并产生 $n$ 位输出。

#### 多选器

在 ALU（算术逻辑单元）中经常用到的一个基本逻辑功能单元就是**多选器**。首先我们考虑双输入**多选器**，其应当有 3 个输入：两个数据值和一个**选择器值（selector value）**。选择器值确定哪个输入信号将成为输出信号，使用门电路的构成方式如下图：

![多选器](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/多选器.png)

图中右侧的门电路表示由双输入**多选器**计算的逻辑函数：$C=(A\cdot S)+(B\cdot S)$。

**多选器**可以由任意数量的输入信号，如果有 $n$ 个数据输入，则需要 $\lceil log_2n\rceil$ 个选择信号。此时的**多选器**包含以下 3 个部分：

* 产生 $n$ 个信号的译码器，每个信号指示一个不同的输入信号值
* $n$ 个与门组成的阵列，每个与门将一个输入信号和对应于译码器的一个信号相结合
* 一个大的或门，用来合并与门的输出

为了将输入信号与**选择器值**相关联，我们经常用数字来标记数据输入的信号，并将**选择器值**信号转化为二进制数。在介绍 SpinalHDL 的小节中，我们将展示实现**多选器**的代码实例。

#### 逻辑单元阵列

由于许多组合操作进行数据处理时，需要对整个数据字（例如 RV64I 指令系统中的 64 位）进行处理。因此，在 CPU 设计时常常需要构建一个逻辑单元阵列，来操作整个输入集合。

在机器内部，大多数时候都需要在一对总线之间进行选择。例如，在 RV64I 指令系统中的写入寄存器操作，最终写入寄存器的 64 位数据可以来自 ALU 的输出，也可以来自内存中读取的数值。所以，此时**多选器**需要能够在两条总线（每个 64 位宽）中选择出一条总线，将其数据写入结果寄存器。如果是使用前面提到的 1 位**多选器**进行扩展，则需要重复 64 次才能将结果写入。

下图中展示了如何绘制一个**多选器**，如何在一对 64 位总线之间进行选择，以及如何扩展 1 位宽的**多选器**：

![多选器阵列](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/64多选器.png)

### 时序逻辑电路

本节将对时序逻辑电路进行介绍，在讨论存储元件和时序逻辑之前，简要的讨论一下**时钟**是十分有益的。

#### 时钟

时序逻辑中需要时钟来决定何时更新存储元件的**状态**。时钟本身只是一个具有固定**周期（$T$）**的不停运转的信号，**时钟频率**是时钟周期的倒数，即时钟频率 $f=\frac{1}{T}$。如下图所示：

![时钟](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/时钟.png)

时钟信号在高电平和低电平之间振荡，时钟周期是指从一个上升沿（或下降沿）到下一个上升沿（或下降沿）之间所间隔的时间。在**边沿触发**设计中，时钟的上升沿或下降沿是有效信号并导致当前电路中存储元件的**状态**发生变化。

时钟系统（也称为**同步系统**）的主要约束是，当有效时钟边沿发生时，写入状态单元的信号**必须有效**。如果信号稳定（即不改变），则称该信号有效，并且在输入改变之前该值不会再次改变。下图中展示了同步时序逻辑设计中**状态**单元和组合逻辑结构之间的关系：

![组合逻辑和时序逻辑](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/同步时序逻辑设计.png)

状态单元的输出仅在时钟**有效边沿**来临时更新，其中状态单元 1 的输出作为组合逻辑电路的输入。为确保在有效时钟边沿写入的状态单元的值有效（即保证状态单元 2 的输入稳定），时钟必须具有足够长的周期，从而让组合逻辑中的所有信号稳定，然后在时钟边沿对这些值进行采样以便存储在状态单元。下图中展示了一个触发器（下文会进行介绍）所需要的时序逻辑约束：

![触发器的时序](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/触发器的时序.png)

在图中可以看到两个重要的时间段：

* 建立时间（Setup Time）：在触发时钟边沿**之前**输入必须稳定
* 保持时间（Hold Time）：在触发时钟边沿**之后**输入必须保持
* Clock-to-Q time（也称为 Latch Prop 锁存延迟）：在触发时钟边沿，输出不能立即变化

#### 触发器和锁存器

所有的存储元件（触发器、锁存器、存储器等）其本质都是存储**状态**：任何存储元件的输出都取决于输入和存储在存储单元内的值。因此包含存储元件的所有逻辑块都包含状态并且是时序可控的。

触发器和锁存器是最简单的存储元件：

* 在锁存器中，只要时钟信号有效，若输入改变，状态就会随之改变
* 在触发器中，状态仅在时钟边沿上改变

对于计算机应用，触发器和锁存器的功能是存储信号。D 锁存器或 D 触发器将其数据输入信号的值存储在内部存储中。虽然还有许多其他类型的锁存器和触发器，但 D 型是我们需要的唯一基本逻辑单元。

D 锁存器有两个输入和两个输出：

* 输入：数据值 $D$ 和时钟信号 $C$
  * $C$ 控制锁存器应何时读取 $D$ 输入上的值并存储它
* 输出：内部状态 $Q$ 及其反向值 $\overline Q$

当时钟信号 $C$ 有效时，锁存器处于**开**状态，输出（$Q$）的值变为输入（$D$）的值；当时钟信号 $C$ 无效时，锁存器处于**关**状态，并且输出（$Q$）保持上次锁存器打开时存储的值。我们可以利用门电路构造出 D 锁存器，如下图所示：

![D 锁存器电路](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/D锁存器.png)

上图显示了如何通过为交叉耦合的或非门（即或门结果取反的一种复合门电路）添加两个额外的门电路来实现 D 锁存器，下面用时序图对其功能进行展示：

![D 锁存器时序图](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/D锁存器时序.png)

可以看到，当且仅当 $C$ 有效时，输出 $Q$ 才会更新为输入 $D$ 的值，且当 $C$ 无效时，输出 $Q$ 保持不变。

如前所述，我们在 CPU 设计中使用触发器而不是锁存器作为基本逻辑单元，它们的输出仅在时钟边沿发生变化。所以我们可以利用一对 D 锁存器构建一个 D 触发器，在 D 触发器中，输出在时钟边沿时刻存储，如下图所示：

![D 触发器电路](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/D触发器.png)

从图中可以看出 D 触发器的基本原理：当第一个锁存器（称为主器件）打开，并在时钟输入 $C$  有效时遵循 $D$ 的输入。当时钟输入 $C$ 下降时，第一个锁存器关闭，但第二个锁存器（称为从器件）打开，并从主锁存器的输出获得其输入，并最终输出到 $Q$。

同样的，对于时序逻辑元件，我们可以利用时序图对其功能进行展示：

![D 触发器时序图](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/D触发器时序.png)

可以看到，下降沿触发的 D 触发器，当时钟输入 $C$ 从有效变为无效时，$Q$ 输出存储 $D$ 输入的值；反之保持原先的输出 $Q$ 不改变。

## SpinalHDL：Scala 语言体系下的新型硬件设计框架

在传统的 CPU 设计包括更广泛的硬件开发领域，Verilog 语言都是一个不可忽视的存在。虽然 Verilog 简单易用，在历史上相当程度的提高了芯片的设计效率，但是这么多年过去了，Verilog 显然已经落后于时代，集成电路的规模以摩尔指数增长，复杂度越来越高，种类也越来越多，但是 Verilog 还是在以一种非常低效的方式开展工作，高效的复用并不能展开。

所以，本节将对一种新型硬件设计框架 SpinalHDL 进行介绍，虽然其本质仍然是转换成 Verilog 源代码后进行仿真、综合以及下板，但是由于是 Scala 语言体系（注：本节仅介绍 SpinalHDL 框架，Scala 语言本身请读者自行查阅文档学习），就为开发过程提供了诸多的便利：

* 位宽自动推断
* 错误检查能力
* 彻底的参数化能力
* 大量的基础组件及可重用 IP
* 继承了 Scala 语言的所有特性

下面我们将对照数电理论知识部分，从硬件实现的角度出发，讲解如何在 SpinalHDL 中实现各种数字逻辑电路。

### SpinalHDL 环境搭建

SpinalHDL 环境的搭建需要预先安装以下工具：

* Java JDK（1.8 及以上版本）
* Scala 2.11.X 发行版
* SBT 构建工具

通常来说，SpinalHDL 环境的搭建有两种主要方式：IDE 方式和 SBT 方式，下面逐一进行介绍（在这里推荐 IDE 方式，搭建时会方便许多）

#### SBT 方式

首先下载或克隆 [SpinalHDL Getting Started][001] 仓库，在仓库根目录下打开终端并输入 `sbt run` 指令，即可自动下载运行 SpinalHDL 所需的依赖库。正常情况下，这样的方式会自动生成一个 `MyTopLevel.v` 的 Verilog 文件，表明环境搭建完成。下面给出一个可供参考的命令行指令（Linux 环境下）：

```bash
sudo apt-get install openjdk-8-jdk
sudo apt-get install scala
echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
echo "deb https://repo.scala-sbt.org/scalasbt/debian /" | sudo tee /etc/apt/sources.list.d/sbt_old.list
curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823" | sudo apt-key add
sudo apt-get update
sudo apt-get install sbt
git clone https://github.com/SpinalHDL/SpinalTemplateSbt.git SpinalTemplateSbt
cd SpinalTemplateSbt
sbt run
ls MyTopLevel.v
```

#### IDE 方式（推荐）

在 IDE 方式中，需要我们拥有一个完整的 IntelliJ IDEA IDE 以及其对应的 Scala 插件。在使用 IDEA 进行环境搭建时较为简便：同样的，下载或克隆 [SpinalHDL Getting Started][001] 仓库，这之后在 IDEA 中选择**文件—打开**并选中仓库根目录即可自动导入到 IDEA 项目中。IDEA 会自动检查 JDK 适配、SBT 环境以及 Scala 插件是否齐全，之后自动化的完成环境搭建。

在 IDEA 搭建完成环境后，我们就可以和开发 Java 或 Scala 程序那样使用 SpinalHDL 框架进行硬件电路设计了。

### SpinalHDL 数据类型

在 SpinalHDL 框架中，一共有 5 个基本数据类型和 2 个复合数据类型可供使用。请注意，这里的数据类型是指 SpinalHDL 特有的数据类型，但是其作为 Scala 语言体系下的框架，Scala 语言的所有数据类型和特性都可以在 SpinalHDL 框架下正常使用。下面的图片展示了各数据类型之间的关系：

![数据类型](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/数据类型.svg)

* 基本数据类型：Bool、Bits、UInt、SInt 和 Enum
* 复合数据类型：Bundle 和 Vec

下面对常用的数据类型进行讲解。

#### UInt 和 SInt

UInt 和 SInt 两个数据类型都是位向量，分别用于表示无符号整数和带符号整数。下面将用实际的代码直观的介绍数据类型的不同用法：

* 声明方式

```scala
val myUInt = UInt(8 bits) // 直接声明固定宽度的 UInt
myUInt := U(2,8 bits) // 声明固定宽度的 UInt 并初始化
myUInt := U(2) // 声明宽度不固定的 UInt 并初始化
myUInt := U"0000_0101"  // 字符串方式中，默认为二进制数
myUInt := U"h1A"        // 基数可以是 x (base 16)
                        //            h (base 16)
                        //            d (base 10)
                        //            o (base 8)
                        //            b (base 2)
myUInt := U"8'h1A"
myUInt := 2             // 使用 Scala 的 Int 数据类型直接赋值（默认为 UInt）

val myBool := myUInt === U(7 -> true,(6 downto 0) -> false)
val myBool := myUInt === U(myUInt.range -> true)

// 在不明确声明 UInt 还是 SInt 时，可以使用 [default -> ???] 进行声明
myUInt := (default -> true)                        // Assign myUInt with "11111111"
myUInt := (myUInt.range -> true)                   // Assign myUInt with "11111111"
myUInt := (7 -> true, default -> false)            // Assign myUInt with "10000000"
myUInt := ((4 downto 1) -> true, default -> false) // Assign myUInt with "00011110"
```

* 逻辑运算符

```scala
// 位运算
val a, b, c = SInt(32 bits)
c := ~(a & b) // a 与 b 后取反

val all_1 = a.andR // 等价于 Verilog 中的 &a，表示自身所有位进行与运算，得到 1 位的结果

// 移位（SInt 默认为算术移位，即右移时保持符号位不变）
val uint_10bits = uint_8bits << 2  // 左移（得到 10 位的结果）
val shift_8bits = uint_8bits |<< 2 // 左移（得到 8 位的结果）

// 循环移位
val myBits = uint_8bits.rotateLeft(3) // 左循环移位

// 置位和清零
val a = B"8'x42"
when(cond) {
  a.setAll() // 当 cond 为真时，将 a 置位（所有位为 1）
}otherwise{
  a.clearAll() // 当 cond 为假时，将 a 清零（所有位为 0）
}
```

* 算术运算符（注意，尽可能不使用乘法和除法，硬件实现上使用对应 IP 核更佳）

```scala
val Sres = mySInt_1 + mySInt_2 // res 为 SInt
val Ures = myUInt_1 - myUInt_2 // res 为 UInt
```

* 比较运算符（和 Scala 本身语法有较大不同）

```scala
// 注意，比较时左右数据类型必须一致
myBool := mySInt_1 > mySInt_2

myBool := myUInt_8bits >= U(3, 8 bits)

when(myUInt_8bits === 3) {
  // 注意这里的相等符号，是 ===
}

when(mySInt_16bits =/= -12){
  // 这里的不等号，是 =/=
}
```

* 类型转换

```scala
// SInt 转 Bits
val myBits = mySInt.asBits

// UInt 转 Bool 向量
val myVec = myUInt.asBools

// Bits 转 SInt
val mySInt = S(myBits)

// SInt 转 UInt
val myUInt = mySInt.asUInt

// UInt 转 SInt
val mySInt_2 = myUInt.asSInt
```

* 取位操作

```scala
// 取第 4 位
val myBool = myUInt(4)

// 将 mySInt 的第 1 位置位
mySInt(1) := True

// 范围
val myUInt_8bits = myUInt_16bits(7 downto 0) // 取 [0,7] 位
val myUInt_7bits = myUInt_16bits(0 to 6) // 取 [0,6]
val myUInt_6bits = myUInt_16Bits(0 until 6) // 取 [0,6)

mySInt_8bits(3 downto 0) := mySInt_4bits
```

* 常用函数

```scala
myBool := mySInt.lsb  // 取 LSB，等价于取 mySInt(0)

// 位拼接
val mySInt = mySInt_1 @@ mySInt_1 @@ myBool
val myBits = mySInt_1 ## mySInt_1 ## myBool

// 位分割
val sel = UInt(2 bits)
val mySIntWord = mySInt_128bits.subdivideIn(32 bits)(sel)
    // sel = 0 => mySIntWord = mySInt_128bits(127 downto 96)
    // sel = 1 => mySIntWord = mySInt_128bits( 95 downto 64)
    // sel = 2 => mySIntWord = mySInt_128bits( 63 downto 32)
    // sel = 3 => mySIntWord = mySInt_128bits( 31 downto  0)

// 位反转（顺序颠倒，如 11110000 变为 00001111）
val myVector   = mySInt_128bits.subdivideIn(32 bits).reverse
val mySIntWord = myVector(sel)

// 重置大小
myUInt_32bits := U"32'x112233344"
myUInt_8bits  := myUInt_32bits.resized       // 自动判定新宽度（myUInt_8bits = 0x44）
myUInt_8bits  := myUInt_32bits.resize(8)     // 手动确定新宽度（myUInt_8bits = 0x44）

// 取绝对值
mySInt_abs := mySInt.abs
```

#### Bool

Bool 类型表示 SpinalHDL 中的布尔值，区别于 Scala 中的 Boolean 数据类型。下面将用实际的代码直观的介绍数据类型的不同用法：

* 声明

```scala
val myBool_1 = Bool()          // 声明 Bool 类型变量
myBool_1 := False            // 使用 := 符号赋值

val myBool_2 = False         // 直接声明并初始化一个 Bool 类型变量

val myBool_3 = Bool(5 > 12)  // 使用 Scala 的 Boolean 类型声明 Bool 类型变量
```

* 操作符

```scala
val a, b, c = Bool()
val res = (!a & b) ^ c   // 逻辑运算

val d = False
when(cond) {
  d.set()    // 置位，等价于 d := True
}

val e = False
e.setWhen(cond) // 等价于 when(cond) { d := True }

val f = RegInit(False) fallWhen(ack) setWhen(req)
 /** 等价于以下代码
  * when(f && ack) { f := False } 当 ack 信号为真时，f 为假
  * when(req) { f := True } 当 req 信号为真时，f 为真
  * or
  * f := req || (f && !ack)
  */

// 注意赋值顺序
val g = RegInit(False) setWhen(req) fallWhen(ack)
// 等价于 g := ((!g) && req) || (g && !ack)
```

* 边沿信号检测

```scala
when(myBool_1.rise(False)) {
    // 当检测到 myBool_1 出现上升沿时
}

val edgeBundle = myBool_2.edges(False) // 这里是一个 Bundle 数据类型，记录了 myBool_2 的边沿信息（rise, fall, toggle）
when(edgeBundle.rise) {
    // 当检测到 myBool_2 出现上升沿时
}
when(edgeBundle.fall) {
    // 当检测到 myBool_2 出现下降沿时
}
when(edgeBundle.toggle) {
    // 当检测到 myBool_2 信号翻转时
}
```

#### Bundle

Bundle 数据类型是一个复合的，定义了一系列 SpinalHDL 基本数据类型的结构（类似于 C/C++ 中的结构体）。在开发过程中，几乎所有的组件都需要 IO 口，而通常来说 IO 口都是使用 Bundle 数据类型进行声明。下面将用实际的代码直观的介绍数据类型的不同用法：

* 声明

```scala
case class myBundle extends Bundle {
  // 直接定义 Bundle
  val bundleItem0 = AnyType
  val bundleItem1 = AnyType
  val bundleItemN = AnyType
}

case class myBundle(dataWidth: Int) extends Bundle {
  // 带有条件的定义 Bundle
  val data = (dataWidth > 0) generate (UInt(dataWidth bits))
}
```

* 位向量与 Bundle 的相互转换

这里展示了如何将一个 Bundle 转为一系列的 Bits，以及如何将一个 Bits 序列转换回 Bundle。常用的实例如下图所示：

![总线案例示意图](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/CommonDataBus.png)

```scala
case class TestBundle () extends Component {
  val io = new Bundle {
    val we      = in     Bool()
    val addrWr  = in     UInt (7 bits)
    val dataIn  = slave  (CommonDataBus())

    val addrRd  = in     UInt (7 bits)
    val dataOut = master (CommonDataBus())
  }

  val mm = Ram3rdParty_1w_1rs (G_DATA_WIDTH = io.dataIn.getBitsWidth,
                               G_ADDR_WIDTH = io.addrWr.getBitsWidth,
                               G_VENDOR     = "Intel_Arria10_M20K")

  mm.io.clk_in    := clockDomain.readClockWire
  mm.io.clk_out   := clockDomain.readClockWire

  mm.io.we        := io.we
  mm.io.addr_wr   := io.addrWr.asBits
  mm.io.d         := io.dataIn.asBits

  mm.io.addr_rd   := io.addrRd.asBits
  io.dataOut.assignFromBits(mm.io.q)
}
```

* IO 端口的 Bundle 声明

用作 IO 端口的 Bundle 和一般的 Bundle 相比，最大的区别就是 IO 端口是**带方向**的，所以我们必须在 Bundle 中指明 IO 端口的方向，通常有以下两种方式：

1. in/out

```scala
val io = new Bundle {
  val input  = in (Color(8))
  val output = out(Color(8))
}
```

2. master/slave

```scala
case class HandShake(payloadWidth: Int) extends Bundle with IMasterSlave {
  val valid   = Bool()
  val ready   = Bool()
  val payload = Bits(payloadWidth bits)

  // 若使用 master/slave 方式，则必须先实现 asMaster() 函数
  // 这一函数将定义各个信号的方向
  override def asMaster(): Unit = {
    out(valid, payload)
    in(ready)
  }
}

val io = new Bundle {
  val input  = slave(HandShake(8))
  val output = master(HandShake(8))
}
```

### SpinalHDL 变量赋值

在 SpinalHDL 中，有多种赋值方法：

* `:=`：标准赋值符号，等价于 Verilog 中的 `<=` 非阻塞赋值符号；同一时钟周期中，变量最终只会存储最后一次的 `:=` 符号赋值，且直到下一个时钟周期开始都保持不变
* `\=`：等价于 Verilog 中的 `=` 阻塞赋值符号（下面会使用实例展示和 `:=` 符号的不同）；变量的值原地立即更新
* `<>`：自动连接符号，由 SpinalHDL 自动判断连接方向，将两个信号或 Bundle 直接连接（赋值方式等价于 `:=` 符号）

下面是用具体代码实例来演示三者之间的联系与区别：

```scala
val a, b, c = UInt(4 bits)
a := 0
b := a
a := 1  // a := 1 最终赋值成功，且在本时钟周期内，b 和 c 的值也都是 1
c := a

var x = UInt(4 bits) // 注意这里的 x 是 var 类型
val y, z = UInt(4 bits)
x := 0
y := x      // y 读到的 x 是 0
x \= x + 1
z := x      // z 读到的 x 是 1

// 自动连接两个 UART 接口
uartCtrl.io.uart <> io.uart
```

#### 关于 := 和 \= 的辨析

首先，所谓的**非阻塞赋值**和**阻塞赋值**两个概念是由 Verilog 语言所提出来的。在真实的逻辑电路操作对象中，一共只有两种：Wire 和 Reg；两者之间的关系也很单一即**谁驱动谁**的关系，而不存在阻塞和非阻塞的概念。

`:=` 符号本质上不是赋值，而是做了一次**记录**。举例来说，`a := b` 就是记录了 a 端口被 b 端口驱动。至于是对应 Verilog 中的阻塞赋值还是非阻塞赋值，这只取决于 a 是不是寄存器。

* 若 a 定义为寄存器 Reg 类型（下文时钟部分将会进行介绍），则此时 `:=` 表示非阻塞赋值
* 若 a 定义为硬连线 Wire 类型（没有 Reg 关键词修饰的基本数据类型默认均为 Wire，如 UInt、SInt、Bool 等），则此时 `:=` 表示阻塞赋值

对于 `\=` 符号，由于电路的本质中赋值就是连线，`\=` 符号要求左值变量是 `var` 类型，即数据可以动态改变的类型，而电路本身是静态的，所以声明一个 `var` 类型的变量并非一个很好的选择。同时 SpinalHDL 本身已经将寄存器 Reg 和普通的硬连线 Wire 进行了明确的定义，所以也不必纠结所谓的阻塞赋值还是非阻塞赋值。因而在电路中大多全部采用 `:=` 对电路对象进行赋值。

如果我们查看 `\=` 在 SpinalHDL 里实现的源码：

```scala
def \(that: T): T = {

    val globalData = GlobalData.get

    val ctx = DslScopeStack.set(_data.parentScope)

    val swapContext = _data.parentScope.swap()
    val ret = cloneOf(that) // 先进行了电路对象的复制

    ret := _data // 将当前电路对象赋值给了新的电路对象

    swapContext.appendBack()
    ctx.restore()

    ret.allowOverride
    ret := that // 将 \= 右边的电路对象再赋值给新的电路对象

    (this, ret) match {
      case (from: Data with Nameable, to: Data with Nameable) => {
        val t = from.getTag(classOf[VarAssignementTag]) match {
          case Some(t) => t
          case None => new VarAssignementTag(from)
        }
        t.id += 1
        to.setCompositeName(t.from,t.id.toString)

        from.removeTag(t)
        ret.addTag(t)
      }
      case _ =>
    }

    ret
}
```

从源代码可以看出，每调用一次 `\=` 运算符，均会产生一个新的电路对象，并未违背电路对象不可改变的要求。但是这样并非对于静态电路来说是一个很好的赋值方式，且对于初学者而言也较为难以理解。所以下文电路实例中都将全部使用 `:=` 符号进行赋值。

### SpinalHDL 电路设计实例

在介绍完 SpinalHDL 的数据类型之后，本节将对数电部分的理论进行代码上的实践，展示如何在 SpinalHDL 框架下对数字电路进行设计。

#### 译码器

译码器的实现非常简单，只需要使用 SpinalHDL 中的 `switch` 语句即可完成，下面展示一个简单的 ALU 控制信号译码器：

```scala
switch(aluop) {
  is(ALUOp.add) {
    immediate := instruction.immI.signExtend
  }
  is(ALUOp.slt) {
    immediate := instruction.immI.signExtend
  }
  is(ALUOp.sltu) {
    immediate := instruction.immI.signExtend
  }
  is(ALUOp.sll) {
    immediate := instruction.shamt
  }
  is(ALUOp.sra) {
    immediate := instruction.shamt
  }
}
```

#### 多选器

SpinalHDL 同样提供了多选器的实现方式，只需要使用 `mux` 语句即可完成，下面展示一个 ALU 中逻辑运算模块的多选器：

```scala
// 采用基本数据类型自带的 mux() 函数实现多选器
val bitwiseSelect = UInt(2 bits)
val bitwiseResult = bitwiseSelect.mux(
  0 -> (io.src0 & io.src1),
  1 -> (io.src0 | io.src1),
  2 -> (io.src0 ^ io.src1),
  3 -> (io.src0)
)

// 采用三目运算符方式实现多选器
val bitwiseResult_2 = (bitwiseSelect === 0) ? (io.src0 & io.src1) |
											(bitwiseSelect === 1) ? (io.src0 | io.src1) |
											(bitwiseSelect === 2) ? (io.src0 ^ io.src1) |
											(io.src0)
```

#### 时钟

SpinalHDL 框架提供了一种简便的实现时钟域的方式，称为 `clock domain`。在时钟域中同时存在时钟信号（clk）和复位信号（rst），并作用于某一个区域，在时钟域作用的区域中，所有的**寄存器**都将自动受到时钟控制，从而进行时序逻辑电路的设计。

* 声明

```scala
ClockDomain(
  clock: Bool
  [,reset: Bool]
  [,softReset: Bool]
  [,clockEnable: Bool]
  [,frequency: IClockDomainFrequency]
  [,config: ClockDomainConfig]
)

// 实例如下
val coreClock = Bool()
val coreReset = Bool()

// 定义一个时钟域，名叫 coreClockDomain
val coreClockDomain = ClockDomain(coreClock, coreReset)

// 将时钟域 coreClockDomain 应用于区域 coreArea
// 则 coreArea 区域中的所有寄存器 Reg 都受控于时钟域 coreClockDomain
val coreArea = new ClockingArea(coreClockDomain) {
  val coreClockedRegister = Reg(UInt(4 bits))
}
```

* 配置时钟域

```scala
class CustomClockExample extends Component {
  val io = new Bundle {
    val clk    = in Bool()
    val resetn = in Bool()
    val result = out UInt (4 bits)
  }

  // 配置一个自定义时钟域，可以调整触发边沿，复位类型等
  val myClockDomain = ClockDomain(
    clock  = io.clk,
    reset  = io.resetn,
    config = ClockDomainConfig(
      clockEdge        = RISING,
      resetKind        = ASYNC,
      resetActiveLevel = LOW
    )
  )

  // 将时钟域 myClockDomain 应用于区域 myArea
  val myArea = new ClockingArea(myClockDomain) {
    val myReg = Reg(UInt(4 bits)) init(7)

    myReg := myReg + 1

    io.result := myReg
  }
}
```

注意：默认情况下，时钟域的配置是：

1. 触发边沿：上升沿

2. 复位方式：异步复位，复位信号为高电平

3. 时钟使能：无

* 时钟跨域

有时我们不想让单一的时钟控制整个电路，所以需要有多个时钟进行控制，下面给出一个实例：

```scala
//             _____                        _____             _____
//            |     |  (crossClockDomain)  |     |           |     |
//  dataIn -->|     |--------------------->|     |---------->|     |--> dataOut
//            | FF  |                      | FF  |           | FF  |
//  clkA   -->|     |              clkB -->|     |   clkB -->|     |
//  rstA   -->|_____|              rstB -->|_____|   rstB -->|_____|

class CrossingExample extends Component {
  val io = new Bundle {
    val clkA = in Bool()
    val rstA = in Bool()

    val clkB = in Bool()
    val rstB = in Bool()

    val dataIn  = in Bool()
    val dataOut = out Bool()
  }

  // sample dataIn with clkA
  val area_clkA = new ClockingArea(ClockDomain(io.clkA,io.rstA)) {
    val reg = RegNext(io.dataIn) init(False)
  }

  // 2 register stages to avoid metastability issues
  val area_clkB = new ClockingArea(ClockDomain(io.clkB,io.rstB)) {
    val buf0   = RegNext(area_clkA.reg) init(False) addTag(crossClockDomain)
    val buf1   = RegNext(buf0)          init(False)
  }

  io.dataOut := area_clkB.buf1
}

// Alternative implementation where clock domains are given as parameters
class CrossingExample(clkA : ClockDomain,clkB : ClockDomain) extends Component {
  val io = new Bundle {
    val dataIn  = in Bool()
    val dataOut = out Bool()
  }

  // sample dataIn with clkA
  val area_clkA = new ClockingArea(clkA) {
    val reg = RegNext(io.dataIn) init(False)
  }

  // 2 register stages to avoid metastability issues
  val area_clkB = new ClockingArea(clkB) {
    val buf0   = RegNext(area_clkA.reg) init(False) addTag(crossClockDomain)
    val buf1   = RegNext(buf0)          init(False)
  }

  io.dataOut := area_clkB.buf1
}
```

* 时钟分频

在 SpinalHDL 框架下，时钟分频操作非常简单，只需要使用 `SlowArea` 即可完成，下面给出一个实例：

```scala
class TopLevel extends Component {

  // 使用当前时钟域 假设为 100MHz
  val areaStd = new Area {
    val counter = out(CounterFreeRun(16).value)
  }

  // 四分频时钟域 25 MHz
  val areaDiv4 = new SlowArea(4) {
    val counter = out(CounterFreeRun(16).value)
  }

  // 固定频率的分频时钟域
  val area50Mhz = new SlowArea(50 MHz) {
    val counter = out(CounterFreeRun(16).value)
  }
}

def main(args: Array[String]) {
  new SpinalConfig(
    defaultClockDomainFrequency = FixedFrequency(100 MHz)
  ).generateVhdl(new TopLevel)
}
```

#### 触发器

有了时钟域这一简单方便的时钟控制方式后，触发器的编写则变得非常轻松，只需要定义为 Reg 数据类型，即可受控于时钟，在有效触发边沿时对 Reg 进行更新。

* 声明

```scala
// 4 位的 UInt 寄存器
val reg1 = Reg(UInt(4 bits))

// 有效触发边沿到来时自动 +1 更新的寄存器
val reg2 = RegNext(reg1 + 1)

// 设定好复位值（和初始值）的寄存器
val reg3 = RegInit(U"0000")
reg3 := reg2
when(reg2 === 5) {
  reg3 := 0xF
}

// 条件为真时，采样 reg3 赋予值给 reg4
val reg4 = RegNextWhen(reg3, cond)
```

上面的实例代码实现了这样的一个时序逻辑电路：

![触发器实现](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/register.svg)

## 总结

本文首先从理论的角度对 CPU 设计中涉及的数字逻辑电路知识进行了讲解，接着介绍了 SpinalHDL 的硬件开发框架，并从代码的角度实现了理论部分的各典型电路。接下来我们就可以真正进入 CPU 设计的阶段了。

系列文章预告：CPU 设计的理论知识和单周期 CPU 中所需模块的设计与实现。

## 参考资料

- 计算机组成与设计：硬件/软件接口（第五版）戴维 A. 帕特森 约翰 L. 亨尼斯 著
- 计算机系统实验 刘卫东 张宇翔 陈康 李山山 著
- [SpinalHDL 手册][002]
- [SpinalHDL Getting Started][001]

本文部分图片来自参考资料（Wiki 和 RISC-V 手册等），感谢原作者的辛苦工作！

[001]: https://github.com/SpinalHDL/SpinalTemplateSbt
[002]: https://spinalhdl.github.io/SpinalDoc-RTD/master/index.html
