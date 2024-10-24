---
layout: post
author: 'BossWangST'
title: 'RISC-V CPU 设计（2）：RISC-V 特权指令架构'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /cpu-design-part1-riscv-privilleged-instruction/
description: 'RISC-V CPU 设计（2）：RISC-V 特权指令架构'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - CPU 设计
  - 指令集
---

> Author:  Fajie.WangNiXi <YuHaoW1226@163.com>
> Date:    2022/07/10
> Revisor: Falcon, Jack.Y
> Project: [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V CPU Design](https://gitee.com/tinylab/riscv-linux/issues/I5EIOA)
> Environment: [Linux Lab](https://tinylab.org/linux-lab)
> Sponsor: PLCT Lab, ISCAS


RISC-V 的指令集架构 ISA 是由两大部分组成，分别是**非特权级 ISA** 和**特权级 ISA**。而正是因为**特权级 ISA** 的存在，才使得 RISC-V 可以在硬件层面（硬件线程）至多拥有 3 个不同的特权级模式，从而对不同的软件栈部件之间提供保护。

本文将介绍 RISC-V 的特权指令架构以及支撑 RISC-V 特权指令集的重要概念：CSR 寄存器。

## RISC-V 特权软件栈术语

RISC-V 结构支持多种软件栈的实现方式，如下图所示：

![image-20220704152156216](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/image-20220704152156216.png)

从图中可以看出，从左至右分别代表了 3 种软件栈的通用形式：

* 在图中最左部，展示了一个简单的系统结构：
  * 单一的应用程序（Application）经由一个特定的应用程序（Application）二进制接口（ABI）编码，在一个应用程序执行环境（AEE）上运行。
  * ABI 包含了其支持的用户级 ISA 以及与 AEE 进行交互的 ABI 调用（ABI calls）集合。在这样的结构中，AEE 的所有细节将对应用程序完全透明，从而使 AEE 的设计具备了更高的灵活性。

* 在图中正中央，展示了一个传统的，支持多个应用程序多道运行的系统结构：
  * 系统中每一个应用程序都通过 ABI 与操作系统（OS）进行交互（此处 OS 提供了 AEE）；同时和上一种结构中 ABI 与 AEE 的交互一样，RISC-V OS 需要通过一个 supervisor 二进制接口（SBI）来与管理员执行环境（SEE）交互。
  * SBI 包含了用户级和 **supervisor 级**的 ISA 以及与 SEE 进行交互的 SBI 调用（SBI calls）。在所有的 SEE 实现中，使用单个的 SBI 则允许在任何一个 SEE 上运行单个的 OS 映像（image）。
  * 在低端的硬件平台中，SEE 可以是一个简单的 boot loader 或是类似于 BIOS 的 IO 系统；而在高端的硬件平台中，SEE 则可以是一台提供了 hypervisor 的虚拟机，或者是一个模拟器系统（如 QEMU）中主机与模拟器之间的转换层。

* 在图中最右部，展示了一个虚拟机监视系统：
  * 系统中一个单一的 hypervisor 支持了多个多道 OS。每一个 OS 都经由一个 SBI 与 hypervisor 通信（此处的 hypervisor 提供了 HEE），而 hypervisor 则是通过 hypervisor 二进制接口（HBI）与 hypervisor 执行环境 （HEE）进行交互，保证 HEE 对 hypervisor 透明。


而对于 RISC-V ISA 的硬件实现，通常需要除了特权指令集之外的其他一些特性，才能支持各种各样的执行环境（AEE、SEE、HEE 等）。

## RISC-V 特权级

无论何时，一个 RISC-V 硬件线程（hart）总是会运行在某一个特权级，而这个信息则是通过编码记录在了多个 **CSR** 寄存器（control and status registers）中。本节将据此介绍 RISC-V 的**特权级**和**特权模式**。

根据最新的 RISC-V spec 规定，现在共有 3 个特权级，如下图所示：

![image-20220704160712068](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/image-20220704160712068.png)

特权级的划分，是为了在不同软件栈部件之间提供安全机制，任何试图执行在某一特权级不被允许的操作，都将会产生一个异常；而这些异常通常会导致下层执行环境产生自陷（trap）。

在上面的描述中我们需要区分出**特权级**和**特权模式**的区别：
* 举例来说，一个**特权级**为 S 级的 OS 当然能够以 S 模式运行在一个支持 3 个**特权模式**的系统中；而如果一个系统只支持 2 个**特权模式**（如某些虚拟机系统），那么**特权级**为 S 级的 OS 也能够以 U 模式正常运行。
* 在上述两个例子中，虽然使用的是同样的 S 级 OS 代码，但是经由 SBI 的编码转换，OS 都将在系统中拥有 S 特权级应有的对应权限（可以执行 S 级特权指令或操纵部分 CSR）；但是在第二个例子中，实际的系统并不存在 S 模式，所以当 OS 执行 S 级特权指令时，执行的操作就会自陷（trap）到拥有更高权限级别的 M 模式（下文会解释此原因）从而获取执行 S 级特权指令的权限，最终成功执行 S 级特权指令。
* 根据 RISC-V 官方手册，本文中的高特权级总是指代拥有更高权限的特权级，低特权级则指代拥有较低权限的特权级。具体划分如下（特权模式同理）：
  * 高特权级 ==> 低特权级
  * M 特权级 => S 特权级 => U 特权级



在所有特权级别中，M 级总是拥有最高的权限，并且是 RISC-V 规定中唯一必须拥有的**特权级**。所以任何运行于 M 模式的代码都应当是固有可信的（inherently trusted），因为在 M 模式下的代码都可以直接访问到底层硬件实现。所以，在这里我们可以对 3 个模式的功能进行定义：

* M 模式是从 RISC-V 硬件层面进行管理，为上层模式提供一个安全的执行环境（EE）的特权模式
* S 模式是 OS 等系统应用所处于的特权模式
* U 模式是普通应用程序所处于的特权模式

在具体实现中，所有的 RISC-V 硬件都必须提供 M 模式，因为这是唯一可以不受限制访问整个硬件的模式。通过以上特权级的划分，RISC-V 的实现方式如图所示：

![image-20220704201253178](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/image-20220704201253178.png)

在一个实现全部 3 个模式的 RISC-V 系统中（这里的前提说明，在此系统中**特权模式**和**特权级别**一一对应），硬件线程（hart）通常是在 U 模式中执行普通应用而不会切换模式，只有通过某些方式（如系统调用或某些中断）触发了自陷（trap），hart 才会被强制切换至执行自陷处理函数（trap handler），由于自陷处理函数通常是在更高特权级别运行的函数代码，调用函数最终会使得 hart 的特权级别升高。在 RISC-V 设计中，能够提升特权等级的自陷称为**垂直自陷（vertical trap）**，而保持原有特权级别的自陷则称为**水平自陷（horizontal trap）**。

下面对操作系统中的 3 个重要名词进行解释：异常（Exception）、中断（Interrupt）和自陷（Trap）的联系与区别
* 异常：用以指代硬件线程（hart）正常运行时，**内部指令**出现的异常情形
* 中断：用以指代硬件线程（hart）因出现了一个**外部**的异步事件而导致的意外的（此处的意外是指，对于一个正常运行的硬件线程 hart 来说，执行内部指令是**正常行为**，而外部事件则是**意外行为**）控制权转移
* 自陷：用以指代由**异常**或**中断**导致的，将系统控制权转移给自陷处理程序的行为

一句话总结：**自陷**是用来处理**内部异常**或**外部中断**的一种系统控制权转让的方法，其也会导致系统**特权模式**的改变。

## RISC-V CSRs

CSR 是 Control and Status Register 的简称，顾名思义，这一类寄存器的作用就是用来**记录系统当前控制和状态信息**的寄存器；操作这些寄存器的指令，是在 RISC-V Zicsr 扩展模块中，手册规定，所有的 CSR 指令必须是**原子性读写指令**，即这些指令本身不可分割，属于**原语**。

CSR 与特权级密不可分，在描述中，通常是根据特权级来对每个 CSR 的功能进行阐释。但是请注意，虽然 CSR 和特权级所拥有的特权指令相关，但是特权级更高的指令仍然是可以**向下访问**特权级更低指令可访问的 CSR（如：M 特权级的指令允许访问 U 特权级可以访问的 `instret` 寄存器。`instret` 是 RISC-V 提供的 3 个硬件性能计数器之一，用于统计自 CPU 复位以来执行的指令数）。

### CSR 的地址映射

标准 RISC-V ISA 设置了 12 位的编码空间（csr[11:0]）预留给至多 4096 个 CSR。通常来说，CSR 寄存器地址的高 4 位（csr[11:8]）是用来编码对 CSR 的读写指令，具体来说：

* csr[11:10]：设定 CSR 的读写权限
  * 00、01、10：可读可写
  * 11：只读

* csr[9:8]：设定能够访问此 CSR 的最低特权级
  * 00：U 级
  * 01：S 级
  * 11：M 级

  注：由于手册最新版已经没有定义 Hypervisor 级别，所以在这里若 csr[9:8] 取值为 10 则会自动落入 S 级。

下图中展示了 CSR 的地址传统分布：

![image-20220707145631097](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/image-20220707145631097.png)

从图中可以看到，最低访问特权级为 M 级的 CSR 中，地址范围是 `0x7A0~0x7BF` 的 CSR 明确描述为 debug CSRs。这也就意味着，当且仅当系统处于调试模式时，才可以访问这些 CSR。那么这里就有必要介绍一下 RISC-V 的调试模式。同时，在 RISC-V 的实现中，还需要保证当低特权级想要访问高特权级对应的 CSR 时，系统能够抛出异常。

在 RISC-V 的具体实现中，通常会包含一个调试模式（Debug Mode）。调试模式支持 **off-chip 调试** 和 手动测试，在调试模式（又称为 D 模式）中，模式本身可认为是一个额外的特权模式，但更为底层；D 模式为了调试的目标，会将完全的硬件资源暴露出来，所以 D 模式对于系统的访问范围甚至比 M 模式要更高，故对于调试模式的细节，大家可以参照[调试模式规范](https://riscv.org/wp-content/uploads/2019/03/riscv-debug-release.pdf)。同时 D 模式会保留一些 CSR 的地址（`0x7A0~0x7BF`），专门用于调试时使用。

### CSR 的字段访问权限

本节将从 CSR 寄存器中存储的信息字段角度，介绍 CSR 不同的读写访问权限。

* WPRI（Reserved **W**rites **P**reserve Values, **R**ead **I**gnore Values）
  在 CSR 中，某些读/写字段是为未来发展而保留的，所以系统中的软件应当**忽略**从这些字段中读取的值（即 Read Ignore Values），并且在向 CSR 其他字段写入数据的时候，还需要保护这些预留字段，维持字段中的值不变（即 Reserved Writes Preserve Values）。为了将来的扩展需要，如果某一个 RISC-V 系统中实现了包含 WPRI 字段的 CSR 读写功能，则必须保持 WPRI 字段**只读且为 0** ，所以在 RISC-V 规范有关 CSR 的描述中，这些字段被标识为 **WPRI**。

* WLRL（**W**rite/**R**ead Only **L**egal Values）
  在某些 CSR 的读写字段中，只允许存在某一类合法编码，而其他编码则判定为非法。所以系统中的软件只可以向此字段中写入字段所规定的合法数据（即 Write Only Legal Values），同时若从此字段中读取，则软件也只会读取到合法编码集合中的某一个编码（即 Read Only Legal Values）。这些 CSR 的字段被标识为 **WLRL**。

  这里需要补充说明一下，如果向 WLRL 字段写入了非法数据会怎么样？
  在 RISC-V 的规范中，并没有对此作出强制规定，即当有操作向 WLRL 字段中写入了非法数据时，由系统的实现者去决定要不要抛出异常。同样，当写入非法数据后，对字段（当前是非法数据）的读取操作也没有规定必须抛出异常，这完全由系统实现者决定。

* WARL（**W**rite **A**ny Values, **R**ead **L**egal Values）
  和 WLRL 权限类似，某些 CSR 中的字段定义了一类合法的编码，和 WLRL 不同的是，其允许非法数据进行写入；但是 RISC-V 规范明确规定，对此字段的读取**必须**返回合法的编码。所以这一字段可以用来测试 CSR 的合法编码集合，假设对某一 CSR 的写入没有任何副作用，那么我们可以向其中写入任何编码，这之后再读取这一字段，如果读取的值和写入的数据相同，则可以判定此数据属于合法编码集合。这些 CSR 的字段被标识为 **WARL**。对于非法数据的处理，WARL 字段的处理和 WLRL 相同，已在上文叙述。

### CSR 的指令格式

在 CPU 的设计中，我们必须了解指令的格式，才可以编写**译码**模块，本节将从 CSR 的指令格式角度进行介绍。

正如上文所介绍的，所有的 CSR 指令必须是**原子性读写指令**，且每一条 CSR 指令只允许操作单个 CSR，下图中展示了一条通用的 CSR 指令格式：

![image-20220707194824502](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/image-20220707194824502.png)

从图中可以得到以下结论：

* inst[31:20]：指定需要操作的 CSR，内容为 12 位的地址（CSR 的地址映射已在上文进行说明）
* inst[19:15]：指定使用的第一个寄存器，对于立即数版本的指令，则是将**零扩展** 5 位的立即数编码后填入 rs1 的字段
* inst[14:12]：指定具体的 CSR 指令类型
* inst[6:0]：固定为 SYSTEM 的操作码，即 `1110011`

下面对 3 个原子指令（立即数版本的同理）逐一进行分析：

* CSR**RW**（Atomic **R**ead/**W**rite CSR）：交换 CSR 和整数寄存器中的值，先读取 CSR 值，**零扩展**后送入寄存器 rd，并将 rs1 的值送入 CSR；若 rd 为 x0，则指令将不允许**读取** CSR，但可以正常写入 CSR
* CSR**RS**（Atomic **R**ead and **S**et Bits in CSR）：读取 CSR 的值，**零扩展**后送入寄存器 rd，而 rs1 的值则翻译为掩码，对 CSR 进行**置位**（rs1 中 1 的位置会将 CSR 对应位**置位**，0 的位置则 CSR 对应位保持不变）
* CSR**RC**（Atomic **R**ead and **C**lear Bits in CSR）：读取 CSR 的值，**零扩展**后送入寄存器 rd，而 rs1 的值则翻译为掩码，对 CSR 进行**清零**（rs1 中 1 的位置会将 CSR 对应位**清零**，0 的位置则 CSR 对应位保持不变）

下图中介绍了 CSR 指令的相关读写限制：

![image-20220707201610137](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/image-20220707201610137.png)

图中明确指出了，当对应指令字段的寄存器是 x0 或不是 x0 时，指令中 CSR 寄存器的读写权限。利用读写权限的不同，汇编器就可以对 CSR 寄存器进行读取，如：

```assembly
CSRRS rd, csr, x0 # read csr
CSRRW x0, csr, rs1 # write csr with rs1
CSRWI x0, csr, uimm # write csr with immediate
```

### 典型 CSR 案例

在介绍完 CSR 的地址映射及指令格式后，本节将用 2 个典型的 CSR 案例来进一步阐释上文的理论。

#### 状态寄存器（mstatus/sstatus）

状态寄存器（Status Register）分为两种，`mstatus` 对应 M 模式，`sstatus` 对应 S 模式；此 CSR 的作用在于记录并控制当前 CPU 的运行状态。

根据地址映射规则，`mstatus` 的地址为 `0x300` ，而 `sstatus` 的地址为 `0x100` ，下面用图表的形式分别讲解 `mstatus` 和 `sstatus` 的内容格式：

* `mstatus`：

![mstatus register](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/mstatus.png)

* `sstatus`：

![sstatus register](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/sstatus.png)

* 从图片中我们可以得到以下结论：
  * 在 RV64 指令集中，CSR 的宽度和 32 个通用寄存器一样是 64 位

  * 不同的字段会明确用不同的标识来说明字段本身的读写访问权限

  * 字段中每一位都赋予了不同的含义，目的是使得应用程序可以通过读写 CSR 来获取、改变当前 CPU 的状态；这里对常用字段简略介绍：

    * `mstatus[12:11]`：MPP（Machine Previous Privilege），通常是出现一个切换到 M 模式的自陷时自动设定，表示切换到 M 模式之前的模式；模式的编码如下：

      `Machine Mode` => `11`

      `Supervisor Mode` => `01`

      `User Mode` => `00`

    * `status[8]`：SPP（Supervisor Previous Privilege），表示切换到 S 模式之前的模式，模式的编码为：

      `Supervisor Mode` => `1`

      `User Mode` => `0`

    * `mstatus[3]`, `status[1]`：分别是 MIE（Machine Interrupt Enable）和 SIE（Supervisor Interrupt Enable），表示 M 模式和 S 模式下的中断使能，当字段置位时表明为 M 模式或 S 模式的开中断状态，清零时则是关中断状态

    * `mstatus[37]`, `mstatus[36]` `mstatus[6]`：分别是 MBE、SBE 和 UBE，其中 BE 表示 Byte Endianness 即字节的大小端方式；RISC-V 的指令读写强制为小端编码，但是内存的编码方式则由 BE 字段管理。MBE、SBE 和 UBE 分别表示 M 模式、S 模式和 U 模式下的内存编码方式，当字段置位时表示大端编码方式，清零时则是小端编码方式。

#### 自陷向量基址寄存器（mtvec/stvec）

自陷向量寄存器（Trap-vector Base-address Register）分为两种，`mtvec` 对应 M 模式，`stvec` 对应 S 模式；此 CSR 的作用在于配置自陷向量。

根据地址映射规则，`mtvec` 的地址为 `0x303`，而 `stvec` 的地址为 `0x105`，下面用图表的形式展示 CSR：

* `mtvec`/`stvec`

![mtvec register](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/mtvec.png)

* 图中寄存器内容分为两部分，`BASE` 和 `MODE`
  * `BASE` 记录的是自陷发生时（不论是中断还是异常），自陷处理函数所需要跳转的地址（基址）
  * `MODE` 可以在 `BASE` 的基础上加入地址对齐的约束条件，具体来说：
    * 当 `MODE` 为 0 时，PC 寄存器中下一条指令的地址直接使用 `BASE` 字段中的值
    * 当 `MODE` 为 1 时，PC 寄存器中下一条指令的地址为 `BASE + 4 * cause`，这里的 `cause` 可以从导致自陷发生的寄存器中直接获得

#### 异常程序计数寄存器（mepc/sepc）

异常程序计数寄存器（Exception Program Counter Register）分为两种，`mepc` 对应 M 模式，`sepc` 对应 S 模式；此 CSR 的作用在于记录触发异常的指令逻辑地址，以便系统处理异常结束后，`pc` 寄存器可以返回到原先程序的指令地址继续执行。

根据地址映射规则，`mepc` 的地址为 `0x341`，而 `sepc` 的地址为 `0x141`，下面用图表的形式展示 CSR：

* `mepc`

![image-20220717151146355](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/mepc.png)

* 当异常触发时，系统会自动记录此时执行的指令地址并装入 `mepc` 寄存器

#### 异常处理寄存器（medeleg）

在默认情况下，任何特权级的异常都会在 M 模式下进行处理；而为了提升 CPU 的处理性能，机器级异常处理寄存器（Machine Exception Delegation Registers）中记录的异常可以交由更低级别的特权模式（如 S 模式甚至于 U 模式）进行处理。

注意，当且仅当系统提供 S 模式时，`medeleg` 寄存器才可以存在；且自陷永远不会从更高特权级的模式（如最高特权级的 M 模式）转移至更低特权级的模式（如 S 模式）进行处理。根据地址映射规则，`medeleg` 的地址为 `0x302`，下面用图表的形式展示 CSR：

* `medeleg`

![image-20220717152818018](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/deleg.png)

* 当异常交由 S 模式处理时，`scause` 寄存器（下文将介绍）会记录自陷原因；`sepc` 寄存器会记录触发异常的指令逻辑地址；`mstatus` 寄存器的 SPP 字段会记录自陷发生时的特权模式，同时将 SIE 字段清零表示 S 模式的关中断状态；而此时 `mcause`、`mepc` 以及 `mstatus` 中的 MPP、MIE 字段将保持不变。
* `medeleg` 寄存器的每一位都可以对应一类异常进行处理，其编码如图所示：

![image-20220717155106545](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/exception_priority.png)

当异常编码值所对应的 `medeleg` 位为 1 时，此类异常就可交由更低级的特权模式进行处理。如将 `mdeleg[8]` 置位时，表示 Environment call 类异常可交由更低级的特权模式处理（在下面的综合实例中就可以看到这样的应用)。

#### 自陷原因寄存器（mcause）

Machine Cause Register 为机器级自陷原因寄存器。顾名思义，当出现切换至 M 模式的自陷时，此 CSR 会记录导致自陷的事件编号，编号含义如下图所示：

![image-20220717160017786](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/mcause_value.png)

根据地址映射规则，`mcause` 的地址为 `0x342`，下面用图表的形式展示此 CSR：

* `mcause`

![image-20220717160243663](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part1/mcause.png)

* 图表中最高位的 Interrupt 字段置位时表示触发自陷的是**中断**事件，清零时表示触发自陷的是**异常**事件
* Exception Code 字段记录的是触发自陷的事件编号

## RISC-V 特权模式与 CSR 综合实例

本节将使用 Linux Lab 实验环境，结合 QEMU 模拟器与跨架构版 GDB 调试器，编写一段简单的汇编语言程序，展示 RISC-V 特权模式的切换与 CSR 记录的值。

RISC-V 系统中，一个硬件线程（hart）总是从 M 模式开始运行，我们首先编写一段简单的 RISC-V 汇编程序 `entry.S`：

```assembly
.section .text
.globl start

start:
    la      t0, supervisor
    csrw    mepc, t0
    la      t1, m_trap
    csrw    mtvec, t1
    li      t2, 0x1800
    csrc    mstatus, t2
    li      t3, 0x800
    csrs    mstatus, t3
    li      t4, 0x100
    csrs    medeleg, t4
    mret

m_trap:
    csrr    t0, mepc
    csrr    t1, mcause
    la      t2, supervisor
    csrw    mepc, t2
    mret

supervisor:
    la      t0, user
    csrw    sepc, t0
    la      t1, s_trap
    csrw    stvec, t1
    sret

s_trap:
    csrr    t0, sepc
    csrr    t1, scause
    ecall

user:
    csrr    t0, instret # 这里仅为了展示在 U 模式下可以访问的为数不多的 CSR，表示当前硬件线程已执行指令的条数
    ecall
```

由于我们即将使用 QEMU 模拟器对这一 RISC-V 硬件线程进行模拟，而此时系统中并没有运行一个 OS，所以我们必须编写一个简单的**链接器脚本**用以指明上面的代码位于内存中的地址，编写的脚本名为 `virt.ld`：

```assembly
SECTIONS
{
    . = 0x80000000;
    .text : { *(.text) }
}
```

`virt.ld` 脚本各字段的含义如下：

* `. = 0x80000000`：可执行的代码内存地址为 `0x80000000`
* `.text : { *(.text) }`：将汇编中的 text 节代码直接关联到运行时系统的 text 节进行执行
* 脚本的作用是：运行 `entry.S` 程序时，起始地址为 `0x80000000`，以 `.start` 为程序起始点（`ld` 脚本在没有特殊指定情况下，默认以 `start` 为起始点）

下面，我们可以直接使用 Linux Lab 中预编译好的 gcc 交叉编译工具链对 `entry.S` 进行汇编和链接，所用命令如下：

```bash
riscv64-linux-gnu-as entry.S -o entry.o
riscv64-linux-gnu-ld -T virt.ld entry.o -o entry
```

现在，我们就可以使用 QEMU 模拟器开始模拟这一简单的演示程序了：

```bash
ubuntu@linux-lab:/labs/linux-lab/src/examples/privillege$ qemu-system-riscv64 -smp 1 -s -S -nographic -bios none -kernel entry

```

这段命令的参数含义是：

* `-smp 1`：使用 1 个硬件线程运行
* `-s`：是 `-gdb tcp::1234` 的简写，表示启用了 gdb 调试模式，且本地端口为 1234
* `-S`：在程序执行前必须等待 gdb 的指令
* `-nographic`：禁用图形接口
* `-bios none` 和 `-kernel entry`：表示硬件线程只执行单一的程序 `entry`，不启用 OpenSBI

由于使用了 `-S` 选项，程序必须等待 gdb 输入命令后才能继续执行，这很有助于我们进行调试；下面使用 gdb 连接本地的 1234 端口，就可以开始对 QEMU 模拟的系统进行调试了：

```bash
ubuntu@linux-lab:/labs/linux-lab/src/examples/privillege$ gdb-multiarch entry -ex "target remote :1234"
Reading symbols from entry...
(No debugging symbols found in entry)
Remote debugging using :1234
0x0000000000001000 in ?? ()
(gdb)
```

为了调试中更清晰的看到各个重要寄存器以及特权模式的切换，我们接下来需要在 gdb 中加入断点并要求显示寄存器：

```bash
(gdb) display /i $pc
1: x/i $pc
=> 0x1000:	auipc	t0,0x0
(gdb) display /x $mstatus
2: /x $mstatus = 0x0
(gdb) display /x $mepc
3: /x $mepc = 0x0
(gdb) display /x $sstatus
4: /x $sstatus = 0x0
(gdb) display /x $sepc
5: /x $sepc = 0x0
(gdb) b *start
Breakpoint 1 at 0x80000000
(gdb) b *m_trap
Breakpoint 2 at 0x8000003c
(gdb) Kb *supervisor
Breakpoint 3 at 0x80000054
(gdb) b *s_trap
Breakpoint 4 at 0x80000070
(gdb) b *user
Breakpoint 5 at 0x8000007c
(gdb) c
Continuing.

Breakpoint 1, 0x0000000080000000 in start ()
1: x/i $pc
=> 0x80000000 <start>:	auipc	t0,0x0
2: /x $mstatus = 0x0
3: /x $mepc = 0x0
4: /x $sstatus = 0x0
5: /x $sepc = 0x0
```

在做好调试准备后，我们就可以正式开始调试了，因为本质上 `-S` 的选项相当于在 `0x0` 地址处打了一个断点，我们可以直接使用 `c`，让程序继续运行。从程序日志中可以看到，我们成功的让程序停在了 `start` 标签所对应的断点处，并且可以清楚地确认各寄存器中的值（CSR 均初始化为 0）。

接下来介绍为什么 gdb 中第一条指令不是 `entry.S` 中的 `la t0, supervisor`：事实上，加载地址指令（`la`）是一条伪指令，其作用是将一个指定的**符号**（如 `start` `supervisor` 等）加载到 GPR 中，这条指令允许我们使用一个**符号名**来代指**符号的地址**，从而避免了使用两条指令 `auipc` 和 `addi` 来将一个宽地址加载进入寄存器。如果我们使用 gdb 查看指令，就能发现汇编器已经自动将 `la` 转换成了两条指令：

```bash
Breakpoint 1, 0x0000000080000000 in start ()
1: x/i $pc
=> 0x80000000 <start>:	auipc	t0,0x0
2: /x $mstatus = 0x0
3: /x $mepc = 0x0
4: /x $sstatus = 0x0
5: /x $sepc = 0x0
(gdb) x/2i $pc
=> 0x80000000 <start>:	auipc	t0,0x0
   0x80000004 <start+4>:	addi	t0,t0,84
```

我们接着单步执行到 `csrw` 指令处：

```bash
(gdb) si 2
0x0000000080000008 in start ()
1: x/i $pc
=> 0x80000008 <start+8>:	csrw	mepc,t0
2: /x $mstatus = 0x0
3: /x $mepc = 0x0
4: /x $sstatus = 0x0
5: /x $sepc = 0x0
(gdb) p /x $t0
$1 = 0x80000054
```

可以看到，此时的 `t0` 寄存器中已经存放了 `supervisor` 节的地址，而 `csrw` 指令会将此地址写入 `mepc` 寄存器（Machine Exception Program Counter）中；正如上文所介绍的，此处填写的地址表示系统处理异常结束后返回的地址，所以为了演示模式切换，这里填入了 S 模式下的指令地址：

```bash
(gdb) si
0x000000008000000c in start ()
1: x/i $pc
=> 0x8000000c <start+12>:	auipc	t1,0x0
2: /x $mstatus = 0x0
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x0
```

单步执行后，`mepc` 寄存器成功装入了地址；下面同样的，我们使用两行汇编代码将 `m_trap` 节的地址装入 `mtvec` 寄存器（Machine Trap Vector）中：

```assembly
    la      t1, m_trap
    csrw    mtvec, t1
```

这一 CSR 的作用是指明当一个自陷（trap）发生时，处理器应该去执行指令的地址（即自陷处理函数的地址）。在 OS 中，这些自陷处理函数往往是一系列 S 模式中的系统调用；继续单步执行指令，可以看到 `m_trap` 的地址正确的装入了 `mtvec` 寄存器中：

```bash
(gdb) p m_trap
$2 = {<text variable, no debug info>} 0x8000003c <m_trap>
(gdb) si 3
0x0000000080000018 in start ()
1: x/i $pc
=> 0x80000018 <start+24>:	lui	t2,0x2
2: /x $mstatus = 0x0
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x0
(gdb) p /x $mtvec
$3 = 0x8000003c
```

下面的操作略微复杂，我们又一次的使用了 `li` 指令来直接加载一个宽立即数（即大于 12 位的立即数）`0x1800` ，在这里实质上是需要将 `mstatus` 的 MPP 字段修改为 S 模式的编码（01），汇编代码截取如下：

```assembly
    li      t2, 0x1800
    csrc    mstatus, t2
    li      t3, 0x800
    csrs    mstatus, t3
```

由于我们一开始就在 M 模式，所以并未对 `mstatus` 寄存器修改，但是为了让 `mret` 指令执行后 `mstatus` 能够正确的表示系统当前特权模式（此处为 S 模式），我们必须手动写入 `mstatus` 寄存器；在这里，为了保证 `mstatus` 寄存器的其他字段不受干扰，我们必须利用位运算中的掩码（使用 `csrc` 和 `csrs` 实现），只修改 MPP 字段而保持其他位数不变：

```bash
(gdb) si 3
0x0000000080000018 in start ()
1: x/i $pc
=> 0x80000018 <start+24>:	lui	t2,0x2
2: /x $mstatus = 0x0
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x0
(gdb) p /x $mtvec
$3 = 0x8000003c
(gdb) si 5
0x000000008000002c in start ()
1: x/i $pc
=> 0x8000002c <start+44>:	csrs	mstatus,t3
2: /x $mstatus = 0x0
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x0
(gdb) si
0x0000000080000030 in start ()
1: x/i $pc
=> 0x80000030 <start+48>:	li	t4,256
2: /x $mstatus = 0x800
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x0
```

在真正的切换到 S 模式前，我们还需要调整一下 `medeleg` 寄存器（Machine Trap Delegation），使得部分自陷交由更低级别的特权模式处理，这里将 `medeleg` 寄存器的第 8 位置位，表示让 S 模式处理 Environment Call 类的异常，而 `entry.S` 程序中 U 模式下调用的 `ecall` 函数正是会触发属于此类异常的函数，所以可以从 U 模式通过异常切换到 S 模式，汇编代码截取如下：

```assembly
user:
    csrr    t0, instret
    ecall
```

从调试输出也可以看到成功将 `medeleg` 寄存器的第 8 位置位：

```bash
(gdb) si 2
0x0000000080000038 in start ()
1: x/i $pc
=> 0x80000038 <start+56>:	mret
2: /x $mstatus = 0x800
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x0
(gdb) p /x $medeleg
$4 = 0x100
(gdb) si
```

至此，所有的准备工作都已就绪，现在终于可以利用**异常**来切换到 S 模式了：

```bash
(gdb) si

Breakpoint 3, 0x0000000080000054 in supervisor ()
1: x/i $pc
=> 0x80000054 <supervisor>:	auipc	t0,0x0
2: /x $mstatus = 0x80
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x0
```

接下来，程序将一直进行模式切换（死循环），我们可以用 `c` 来让程序继续运行，过程中会不断的利用 `ecall` 触发  `s_trap` 从而进入 S 模式，再碰到 `m_trap` 进入 M 模式，并且能从 `mstatus` 寄存器明显的看出模式切换：

```bash
(gdb) c
Continuing.

Breakpoint 5, 0x000000008000007c in user ()
1: x/i $pc
=> 0x8000007c <user>:	rdinstret	t0
2: /x $mstatus = 0xa0
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x20
5: /x $sepc = 0x8000007c
(gdb) c
Continuing.

Breakpoint 4, 0x0000000080000070 in s_trap ()
1: x/i $pc
=> 0x80000070 <s_trap>: csrr	t0,sepc
2: /x $mstatus = 0x80
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x80000080
(gdb) c
Continuing.

Breakpoint 2, 0x000000008000003c in m_trap ()
1: x/i $pc
=> 0x8000003c <m_trap>: csrr	t0,mepc
2: /x $mstatus = 0x800
3: /x $mepc = 0x80000078
4: /x $sstatus = 0x0
5: /x $sepc = 0x80000080
(gdb) c
Continuing.

Breakpoint 3, 0x0000000080000054 in supervisor ()
1: x/i $pc
=> 0x80000054 <supervisor>:	auipc	t0,0x0
2: /x $mstatus = 0x80
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x80000080
(gdb) c
Continuing.

Breakpoint 5, 0x000000008000007c in user ()
1: x/i $pc
=> 0x8000007c <user>:	rdinstret	t0
2: /x $mstatus = 0xa0
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x20
5: /x $sepc = 0x8000007c
(gdb) c
Continuing.

Breakpoint 4, 0x0000000080000070 in s_trap ()
1: x/i $pc
=> 0x80000070 <s_trap>: csrr	t0,sepc
2: /x $mstatus = 0x80
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x80000080
(gdb) c
Continuing.

Breakpoint 2, 0x000000008000003c in m_trap ()
1: x/i $pc
=> 0x8000003c <m_trap>: csrr	t0,mepc
2: /x $mstatus = 0x800
3: /x $mepc = 0x80000078
4: /x $sstatus = 0x0
5: /x $sepc = 0x80000080
(gdb) c
Continuing.

Breakpoint 3, 0x0000000080000054 in supervisor ()
1: x/i $pc
=> 0x80000054 <supervisor>:	auipc	t0,0x0
2: /x $mstatus = 0x80
3: /x $mepc = 0x80000054
4: /x $sstatus = 0x0
5: /x $sepc = 0x80000080
```

从这个简单的案例中，我们可以实实在在的看到 RISC-V 系统中特权模式的切换以及 CSR 在其中起到的重要支撑作用。

## 总结

本文首先介绍了 RISC-V 特权指令集中特权等级和特权模式的划分，并阐述了等级和模式的异同以及模式切换的方法；在后半段文章也详细介绍了 RISC-V 中 CSR 的相关知识。

系列文章预告：CPU 设计中的数字逻辑电路知识以及新型的硬件设计语言：泛 Scala 语言体系下的 SpinalHDL 介绍。

## 参考资料

* [RISC-V Privileged Spec](https://github.com/riscv/riscv-isa-manual/releases/download/Priv-v1.12/riscv-privileged-20211203.pdf)
* [RISC-V Unprivileged Spec](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf)
* [RISC-V Unprivileged Spec](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf)
* [RISC-V 中文特权指令手册](https://www.icfedu.cn/wp-content/uploads/2021/03/riscv-privileged-spec-v1.7%E4%B8%AD%E6%96%87%E7%89%88.pdf)
* [RISC-V Debug Spec](https://riscv.org/wp-content/uploads/2019/03/riscv-debug-release.pdf)
* [Writing a RISC-V Emulator in Rust](https://book.rvemu.app/index.html)

本文部分图片来自参考资料（Wiki 和 RISC-V 手册等），感谢原作者的辛苦工作！
