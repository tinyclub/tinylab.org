---
layout: post
author: 'BossWangST'
title: 'RISC-V CPU 设计（5）：RISC-V CPU 设计模块软件行为仿真与下板实验调试'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /cpu-design-module-board-test/
description: 'RISC-V CPU 设计（5）：RISC-V CPU 设计模块软件行为仿真与下板实验调试'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1-rc3 - [header]
> Author:   Fajie.WangNiXi <YuHaoW1226@163.com>
> Date:     2022/08/16
> Revisor:  Falcon <falcon@tinylab.org>
> Project:  [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal: [RISC-V CPU Design](https://gitee.com/tinylab/riscv-linux/issues/I5EIOA)
> Sponsor:  PLCT Lab, ISCAS


## 前言

CPU 设计其本质是数字逻辑电路的总体设计，电路只有真正烧录进实体的 FPGA 开发板后才可以真正验证其正确性与可靠性。而在下板测试之前，为了保证其逻辑功能上的正确性，还必须对设计的各个组成子模块进行软件模拟仿真以进行功能方面的测试。本文以 CPU 设计中的子模块为例，对软件模拟仿真与烧录进 FPGA 开发板测试的流程进行介绍。

## 软件行为仿真

在传统的仿真测试流程中，基本上都是采用英特尔的 ModelSim FPGA 行为仿真软件对模块进行仿真测试；我们由于在设计的时候就没有使用 Verilog 语言设计电路，而是使用了 SpinalHDL 这一基于 Scala 语言的硬件设计框架进行开发，所以可以借助 SpinalHDL 框架下的仿真库，便捷的继续使用 SpinalHDL 框架编写仿真测试的 Testbench 以对模块进行测试。

下面首先对仿真所需环境进行介绍：

### Verilator 仿真软件

本软件官方提供了相应的 [用户手册][1]，参照手册我们可以进行 Verilator 的安装，安装过程分为以下情况：

* 如果使用 Linux Lab，则可以直接使用对应 Linux 版本的软件包管理器（如 Ubuntu 系统是 apt，CentOS 系统是 yum 等）直接对 Verilator 进行安装，安装命令如下：

```bash
$ sudo apt install verilator # for Ubuntu
$ sudo yum install verilator # for CentOS
$ sudo pacman -S verilator # for Arch series
```

* 如果使用 macOS 系统，则可以使用 macOS 下的 brew 软件包管理器进行安装，命令如下：

```bash
$ brew install verilator # for macOS
```

* 如果在其他系统中或想自己手动编译，则可以使用 Git 拉取 Verilator 的源代码手动进行编译与安装，命令如下：

```bash
# Prerequisites:
#sudo apt install git perl python3 make autoconf g++ flex bison ccache
#sudo apt install libgoogle-perftools-dev numactl perl-doc
#sudo apt install libfl2  # Ubuntu only (ignore if gives error)
#sudo apt install libfl-dev  # Ubuntu only (ignore if gives error)
#sudo apt install zlibc zlib1g zlib1g-dev  # Ubuntu only (ignore if gives error)

git clone https://github.com/verilator/verilator   # Only first time

# Every time you need to build:
unsetenv VERILATOR_ROOT  # For csh; ignore error if on bash
unset VERILATOR_ROOT  # For bash
cd verilator
git pull         # Make sure git repository is up-to-date
git tag          # See what versions exist
#git checkout master      # Use development branch (e.g. recent bug fixes)
#git checkout stable      # Use most recent stable release
#git checkout v{version}  # Switch to specified release version

autoconf         # Create ./configure script
./configure      # Configure and create Makefile
make -j `nproc`  # Build Verilator itself (if error, try just 'make')
sudo make install
```

注：由于 Verilator 本身是在 Ubuntu 系统下开发和测试的，所以目前对基于 Unix 的系统全部支持，但是在 Windows 系统中，则只能通过 WSL、Cygwin、MinGW 等方式进行编译与安装。

### GTKWave 波形跟踪软件

使用 Verilator 进行行为仿真时，会自动生成 `.tcd` 格式的波形文件，我们可以使用轻量级的波形跟踪软件 GTKWave 对仿真波形进行查看以比对预期结果和真正的仿真结果。

GTKWave 也提供了完整的 [用户手册][2]，我们可以参照用户手册对 GTKWave 进行安装，具体安装方法如下（以 Ubuntu 系统为例）：

```bash
$ sudo apt install iverilog # for compiling *.v
$ sudo apt install gtkwave
```

安装完毕之后，我们可以直接在 GUI 界面双击图标启动软件，将会是如下的界面：

![GTKWave 启动界面](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/GTKWave启动界面.png)

表示安装完毕，在此之后我们就可以直接将 Verilator 生成的 `.tcd` 文件拖入 GTKWave 对波形进行跟踪查看了。

### SpinalHDL 行为仿真库

正如上文所言，SpinalHDL 不仅提供了便捷的 RTL 设计框架，其还支持对功能子模块进行行为仿真。我们要想利用 SpinalHDL 进行行为仿真，就必须创建一个 Scala 的 Object 对象，并在其中调用仿真库进行仿真。

下面我们将用一个具体的 ALU 仿真代码实例来演示：

```scala
package alu

import spinal.core._
import spinal.core.sim._

object ALUSim {
	def main(args: Array[String]): Unit = {
		SimConfig.withWave.compile(new ALU).doSim { dut =>
			dut.clockDomain.forkStimulus(10)
			SimTimeout(10000)
			dut.clockDomain.waitSampling(10)
			var data1 = 10
			var data2 = 20
			var aluOp = 0
			//ADD SUB
			dut.io.data1 #= data1
			dut.io.data2 #= data2
			dut.io.aluOp #= aluOp

			dut.clockDomain.waitRisingEdge()
			aluOp = 8
			dut.io.aluOp #= aluOp

			//SLT SLTU
			dut.clockDomain.waitRisingEdge()
			aluOp = 1
			dut.io.aluOp #= aluOp

			dut.clockDomain.waitRisingEdge()
			data1 = -10
			dut.io.data1 #= data1

			dut.clockDomain.waitRisingEdge()
			aluOp = 2
			dut.io.aluOp #= aluOp

			dut.clockDomain.waitRisingEdge()
			data1 = 10
			dut.io.data1 #= data1
			dut.io.aluOp #= aluOp

			//AND OR XOR
			dut.clockDomain.waitRisingEdge()
			data1 = 1
			aluOp = 3
			dut.io.data1 #= data1
			dut.io.aluOp #= aluOp

			dut.clockDomain.waitRisingEdge()
			data1 = 65536
			aluOp = 4
			dut.io.data1 #= data1
			dut.io.aluOp #= aluOp

			dut.clockDomain.waitRisingEdge()
			data1 = 10
			data2 = 15
			aluOp = 5
			dut.io.data1 #= data1
			dut.io.data2 #= data2
			dut.io.aluOp #= aluOp

			//SLL SRL SRA
			dut.clockDomain.waitRisingEdge()
			data1 = 128
			data2 = 2
			aluOp = 6
			dut.io.data1 #= data1
			dut.io.data2 #= data2
			dut.io.aluOp #= aluOp

			dut.clockDomain.waitRisingEdge()
			data1 = -2
			aluOp = 7
			dut.io.data1 #= data1
			dut.io.aluOp #= aluOp

			dut.clockDomain.waitRisingEdge()
			aluOp = 9
			dut.io.aluOp #= aluOp

			dut.clockDomain.waitRisingEdge()
			simSuccess()
		}
	}
}
```

对于仿真的 Scala 对象，我们需要在其中的 main 函数里编写仿真的代码，首先需要调用仿真库并制定需要进行行为仿真的功能子模块：

```scala
SimConfig.withWave.compile(new ALU).doSim{
	// testbench
}
```

* SimConfig：调用 SpinalHDL 的仿真库，并可以对仿真进行配置，常用参数如下：
  * withWave：开启仿真波形跟踪
  * withConfig(SpinalConfig)：指定生成电路的 SpinalHDL 配置
  * allOptimisation：开启 RTL 编译优化以降低仿真时间（但是会增加编译时间）
  * workspacePath(path)：指定仿真文件目录
* compile(rtl)：编译模块并预先启动仿真器 Verilator
* doSim：开始仿真直至主线程结束或所有线程都卡死

同时，SpinalHDL 的仿真库支持在同一硬件电路上运行多个 TestBench：

```scala
val compiled = SimConfig.withWave.compile(new Dut)

compiled.doSim("testA") { dut =>
    // Simulation code here
}

compiled.doSim("testB") { dut =>
    // Simulation code here
}
```

在具体的仿真代码中，为了进行多组测试，这里推荐大家不论是组合逻辑电路还是时序逻辑电路，都调用 SpinalHDL 仿真库中的时钟选项，利用时钟周期的改变来测试多组数据，方法如下：

```scala
dut.clockDomain.forStimulus(10) // 获取时钟信号，这里的 10 表示 10ps 的时钟周期
SimTimeout(10000) // 设定最大仿真时间，当仿真出现死循环时可以抛出异常退出仿真程序
dut.clockDomain.waitSampling(10) // 等待获取的时钟信号稳定，这里的 10 表示等待 10 个时钟周期后仿真程序才会继续向下执行
```

以上的准备工作结束后，就可以正式进入 TestBench 部分的编写了。同时因为本质上 TestBench 是在编写一个 Scala 的对象，所以代码就可以使用全部的 Scala 语法和语言特性：for 循环、if 语句、函数式编程等。

在编写仿真代码中，有一点需要注意，就是对于仿真模块的输入接口，我们需要使用仿真库中的 `#=` 符号进行赋值操作。利用时钟周期进行多组测试的时候，还需要在不同的测试数据间插入 `dut.clockDomain.waitRisingEdge()` 来分割，最终可以得到如下的仿真代码：

```scala
SimConfig.withWave.compile(new Register_file).doSim { dut =>
	//get clock
	dut.clockDomain.forkStimulus(10)
	SimTimeout(10000)
	dut.clockDomain.waitSampling(10)

	for (i <- 1 to 20) {
		//test write
		dut.io.writeReg #= i + 1
		dut.io.writeData #= i + 1
		if (i < 10) {
			dut.io.RegWrite #= true
		} else {
			dut.io.RegWrite #= false
		}

		//test read
		dut.io.readReg1 #= i
		dut.io.readReg2 #= i - 1

		dut.clockDomain.waitRisingEdge()
		if (i == 7) {
			dut.clockDomain.assertReset()
		} else {
			dut.clockDomain.deassertReset()
		}
	}
	simSuccess() // 仿真结束
}
```

在编写好仿真代码后，我们可以直接在 IDEA 中运行此 Scala 对象中的 main 函数（如果使用 sbt 运行 SpinalHDL 框架，则是在命令行中执行 `sbt run`），就可以在对应仿真目录中生成波形跟踪文件了。利用 GTKWave 打开波形跟踪文件后就可以检验设计的模块功能是否达到了预期目标。

## 硬件下板测试

本节将介绍在模块设计完毕，行为仿真测试通过之后，如何将其烧录到真实的 FPGA 开发板中进行实验测试。

### 软硬件选择

在硬件电路开发中，主要有两个软件可供使用：Quartus II 和 Vivado，分别隶属于 FPGA 芯片领域的两大公司 Altera 和 Xilinx。虽然 Quartus II 界面简单，但是实际工作中应用却较为复杂，尤其是 IP 核的调用，需要花费不小的学习成本去查看官方手册进行配置。而 Vivado 相对而言操作层面对用户更为友好，大多数 IP 核的配置作为用户只需要设定好核心的接口就可以使用，同时如果想更细化的自定义 IP 核，Vivado 也完全可以做到。

更重要的一点，软件的选择和硬件生产厂商联系紧密，**Xilinx 的 FPGA 开发板只能在 Vivado 上进行烧录和调试**；**Altera 的 FPGA 开发板则只能在 Quartus II 中烧录和调试**。但两者对于 RTL 源代码的语法检查，综合电路等任务都是可以胜任的。

由于作者的 FPGA 开发板芯片是 Xilinx 公司的，型号为 xc7a100t fgg676-2，所以选择 Vivado 作为硬件烧录和调试的软件。（注：作者使用的 FPGA 开发板是 PRX100，但目前官方淘宝商店已经无法购买。使用其他 Xilinx 芯片的 FPGA 开发板同样可以在 Vivado 下进行实验）

首先，我们需要安装 Vivado 软件，从官方网站下载下来之后可以直接安装（ArchLinux 用户可以直接 [使用 AUR 安装][3]），过程中选择 Vivado Webpack 版本（免费版）进行安装即可（请保证电脑有足够的空间，总体安装完毕后 Vivado 大约会占用 50 GB）。正常安装完毕后打开界面如下：

![Vivado 起始界面](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/Vivado起始界面.png)

下面将逐步介绍如何建立工程，导入 RTL 源代码，进行管脚约束以及硬件如何调试。

### 建立 Vivado 工程

选择菜单栏 <kbd>File</kbd> => <kbd>Project</kbd> => <kbd>New</kbd> 会弹出新建项目引导界面，如下图所示：

![新建工程引导](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/新建工程引导.png)

点击 <kbd>Next</kbd> 选项进入工程路径设置界面，我们需要在此界面中设置项目名称和项目路径。注意，顶层文件（即最终烧录进 FPGA 开发板的设计电路）的命名一定要和后续 Verilog 的顶层文件名称一致，顶层文件的命名区分大小写：

![项目名称设定](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/项目名称设定.png)

接下来为刚才建立的空白工程指定类型，这里选择 RTL Project 后点击 <kbd>Next</kbd>：

![项目类型设定](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/项目类型设定.png)

在添加设计源文件界面可以直接选择利用 SpinalHDL 生成出来的 `*.v` 文件，也可以暂时留空等待项目创建完毕后再进行源文件的选择：

![添加设计文件界面](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/添加设计文件界面.png)

下面是添加管脚约束文件的界面，此时我们尚未进行管脚分配，所以并没有约束文件可以选择，故直接点击 <kbd>Next</kbd> 跳过此步骤。

此时需要选取对应硬件的 FPGA 开发板型号，由于作者本人的开发板核心是 xc7a100t fgg676-2，所以可以通过 Family、Package 和 Speed 选项迅速定位开发板，选中后即可进入下一步：

![FPGA 开发板选择](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/FPGA开发板选择.png)

最后，在项目工程建立总览的界面，我们可以再次对项目的各个配置进行回顾，检查无误后点击 <kbd>Finish</kbd> 即可完成项目的建立：

![建立工程总览](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/建立工程总览.png)

### 添加项目源文件与 IP 核的配置

在建立好一个 RTL 空白项目后，下面需要添加项目的源文件。首先在 Sources 菜单中点击加号，会弹出添加源文件的菜单。这里选择 Add or create design sources 添加 SpinalHDL 生成的 Verilog 源代码：

![添加 RTL 源文件](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/添加RTL源文件.png)

添加完毕后，下一步就是配置设计代码时调用的 IP 核，点击左侧导航栏中的 <kbd>IP Catalog</kbd> 选项，会在右侧弹出 IP 核列表；我们可以输入关键词进行搜索定位到需要的 IP 核（此处以 Virtual Input/Output 为例）：

![配置 IP 核](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/配置IP核.png)

双击所需 IP 核，会弹出配置 IP 核的界面，此处需要根据不同 IP 核对应的手册进行 IP 核名称、端口、内部结构等信息的配置。对于 VIO 来说，其需要配置虚拟输入输出的端口数量及其各自宽度；注意，一旦初始化好了 IP 核，此 IP 核的名称将无法变更，如需变更则需要强行删除 IP 核的所有关联文件并重新进行初始化的 IP 核配置。

接下来会弹出生成 IP 核的预览界面，此处会有 Synthesis Option 综合选项：

* Global：表示将 IP 核与工程绑定，当顶层文件综合时连带 IP 核一起综合，同时生成 IP 核时不会对 IP 核进行单独的综合操作
* Out of context per IP：表示 IP 核与工程分离，生成 IP 核时会自动单独综合 IP 核
* 两者的区别在于，如果采用 Global 方式生成 IP 核，则当工程移植到其他机器时 IP 核的相关配置能够保持；如果采用 Out of context per IP 方式生成 IP 核，则工程移植时无法携带 IP 核的配置，需要重新在移植后的新平台生成 IP 核

而对于单独模块测试，我们可以选择 Out of context per IP 选项，在生成 IP 核时单独综合，从而节省后续顶层文件综合的时间；菜单中的 Number of jobs 类似于 Make 编译时的线程选项，表示综合 IP 核时使用线程的数量：

![生成 IP 核](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/生成IP核.png)

### 综合工程与管脚分配

在所有源文件和 IP 核都导入至 Vivado 工程中后，下面就需要进行**综合**。点击左侧导航栏中的 <kbd>Run Synthesis</kbd> 即可对设计的电路模块进行**综合**。**综合**即对应软件开发中的编译环节，在电路设计中是指将 RTL 设计转换为门级描述：

![综合完成](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/综合完成.png)

综合完毕之后，我们需要点击左侧导航栏中的 <kbd>Open Synthesized Design</kbd> 查看综合结果并进行管脚分配，在综合设计界面底部的 I/O Ports 菜单中，可以指定每个 I/O 端口连接到 FPGA 开发板的引脚，在这一步骤中需要参照对应 FPGA 开发板的手册完成：

![管脚分配](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/管脚分配.png)

在引脚分配结束后，下一步是根据引脚分配生成的约束文件，生成对应于 FPGA 开发板的**实现方案**，其分为 3 个步骤：

* opt_design：在这一步，Vivado 会对综合后的网表文件进行优化，删除一些无用的或者 Vivado 认为是冗余的逻辑
* place_design：这一步是将电路布局到 FPGA 开发板，Vivado 的布局器会优先考虑以下 3 个方面：
  * Timing Slack：电路的延迟时间，包含了建立时间和保持时间
  * Wirelength：电路长度
  * Congestion：尽可能确保电路中不出现拥塞（在 Vivado 的评估体系中，拥塞程度 < 5 时可认为设计不存在拥塞问题，拥塞程度 >= 5 时则有可能出现布线失败）
* route_design：在前两步完成之后，Vivado 会优先对全局资源进行布线（如时钟、复位等），接下来就是根据时序的紧张程度进行布线，优先布线时序紧张的路径

在 Vivado 中，点击左侧导航栏中的 <kbd>Run Implementation</kbd> 即可开始保存管脚分配的约束文件并生成工程的**实现方案**：

![保存约束文件](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/保存约束文件.png)

### 连接 FPGA 开发板与硬件调试

在生成了实现方案之后，接下来就需要生成烧入到 FPGA 开发板的**比特流**。点击左侧导航栏的 <kbd>Generate Bitstream</kbd> 后，Vivado 就会根据**实现方案**自动生成对应于 FPGA 开发板的**比特流**。生成完毕后，点击左侧导航栏中的 <kbd>Open Hardware Manager</kbd> 打开硬件管理面板：

![连接开发板](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/连接开发板.png)

根据 FPGA 开发板的手册，连接电脑与开发板后，点击管理界面上方的 <kbd>Open target</kbd> => <kbd>Auto Connect</kbd>，Vivado 就会自动扫描电脑当前连接的所有开发板并自动开启本地端口连接开发板。

连接完毕后我们就可以正式开始硬件调试，下面将逐一介绍硬件调试中常用的 IP 核及其使用方式：

#### PLL 时钟分频

由于 SpinalHDL 框架已经为我们提供了**时钟域**，在编写硬件电路时就可以区别于 Verilog，只需要根据变量是否定义为 Reg 类型就能自动判断出其时序逻辑。但是在实际下板测试的时候，这一便捷特性却会带来一些麻烦：电路总是需要一个输入端口连接 FPGA 开发板上的时钟晶振以获取真实的时钟信号，复位信号同理，但是 SpinalHDL 省略掉这些信号的显式定义后，在**综合**后就无法进行管脚分配。

而利用 PLL 时钟分频的 IP 核就成为了这一问题的解决方案。在实例化了一个 PLL 时钟分频 IP 核后，我们就将 PLL 的输出抽象成为自定义**时钟域**，从而解决没有信号分配管脚的难题。

PLL 在 IP Catalog 菜单中的全称是 Clocking Wizard，可以直接搜索关键词 clock 后翻阅找到：

![PLL](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/PLL.png)

在初始化 PLL 时非常简单，只需要对输入的时钟频率和输出的时钟频率进行配置即可，如下图所示：

* 输入时钟频率配置

![PLL 配置输入](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/PLL配置输入.png)

* 输出时钟频率配置

![PLL 配置输出](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/PLL配置输出.png)

下面将使用一个实例代码进行演示：

* PLL 黑盒代码（注意，在 Vivado 初始化 IP 核时必须端口变量名完全一致）

```scala
class PLL extends BlackBox {
    val io = new Bundle {
        val clkIn = in Bool()
        val reset = in Bool()
        val clkOut = out Bool()
        val isLocked = out Bool()
    }
    noIoPrefix()
}
```

* 顶层测试代码（实例化 PLL、被测试模块）

```scala
val pll = new PLL
pll.io.clkIn := io.clk_50M
pll.io.reset := ~io.rst
val clk = pll.io.clkOut

val IF = new Instruction_Fetcher
IF.io.rst := rst
IF.io.clk := clk
```

* 被测试模块代码（利用自定义**时钟域**，保证端口引脚分配）

```scala
class Instruction_Fetcher extends Component {
	val io = new Bundle {
		val clk = in Bool()
		val rst = in Bool()
		// 其余 I/O 端口
	}
	noIoPrefix()
	val clkCtrl = new Area {

		val coreClockDomain = ClockDomain.internal(
			name = "core",
			frequency = FixedFrequency(25 MHz)
		)

		coreClockDomain.clock := io.clk
		coreClockDomain.reset := io.rst
	}

	val coreArea = new ClockingArea(clkCtrl.coreClockDomain) {

		//... 模块实现

		// 模块内调用 IP 核时，需要提供 clk 和 rst 的端口，利用自定义时钟域的相关方法即可完成端口接入
		val instRom = new Rom
		instRom.io.clk := ClockDomain.current.clock
		instRom.io.rst := ClockDomain.current.reset
		instRom.io.addr := pc
		io.instruction := instRom.io.data

		//...
		// 当模块内非时序逻辑变量需要复位时，也利用自定义时钟域的方法完成条件判断
		when(ClockDomain.current.reset) {
			pc := 0
			next_pc := 0
		}
	}
}
```

#### ILA 集成逻辑分析器

硬件调试不同于软件行为仿真，其内部电路的状态我们无法直接获取，所以需要利用一些调试用的 IP 核来辅助查看电路状态，验证电路功能正确性。ILA 集成逻辑分析器就是其中的代表之一，其作用就如同探针，可以在电路运行时对内部信号进行探测，并将结果传输到电脑的调试核（当引入 ILA 时，Vivado 的引脚分配和**实现方案**就会自动加入调试核，使得 ILA 可以与电脑终端通信）以波形的形式呈现以便调试。

ILA 在 IP Catalog 中的全称是 Integrated Logic Analyzer，可以搜索 ila 关键词得到：

![ila](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/ila.png)

初始化 ILA 时，首先需要配置探测的信号数量，在采样深度选项中可以保持默认的 1024，这已经足够我们进行模块调试：

![ila 端口配置](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/ila端口配置.png)

接下来只需要填写不同探测信号的宽度，即可完成 ILA 的配置：

![ila 端口宽度](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/ila端口宽度.png)

下面进行实例代码演示：

* ILA 黑盒代码

```scala
class ila extends BlackBox {
	val io = new Bundle {
		val clk = in Bool()
		val probe0 = in Bool()
		val probe1 = in UInt (64 bits)
		val probe2 = in UInt (64 bits)
		val probe3 = in UInt (64 bits)
		val probe4 = in UInt (32 bits)
	}

	noIoPrefix()
}
```

* 顶层测试代码（实例化 ILA 并连接需要观察的信号）

```scala
val ila_0 = new ila
ila_0.io.clk := io.clk_50M
ila_0.io.probe0 := clk
ila_0.io.probe1 := IF.io.pc_debug
ila_0.io.probe2 := IF.io.next_pc_debug
ila_0.io.probe3 := IF.io.pc_reg_debug
ila_0.io.probe4 := IF.io.instruction
```

配置完毕 IP 核并生成好比特流后，就可以将比特流烧入 FPGA 开发板中，在 Hardware Manager 界面右键点击 FPGA 开发板选择 Program Device，Vivado 就会弹出烧入菜单界面；注意，只有在配置有 ILA 等硬件调试 IP 核的比特流烧入时，Debug probes file 一栏才会自动填入调试核相关文件，其余情况下此栏为空：

![烧入开发板](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/烧入开发板.png)

烧入 FPGA 开发板后，Hardware Manager 会自动显示调试核的相关信息，总体分为三大板块：

* 波形查看界面：用来查看波形内容
* ILA 控制菜单：在此菜单中可以对 ILA 的状态进行控制：
  * 普通三角符号：进入 ILA 等待触发状态，当触发条件到来时自动采样
  * 圆圈三角符号：进入 ILA 连续等待触发状态，当触发条件到来时自动采样并再次进入 ILA 等待触发状态
  * 双箭头符号：立即采样当前电路状态
* ILA 触发器菜单：在此菜单中可以设定 ILA 触发器的条件

![ila 波形界面](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/ila波形界面.png)

利用 ILA 的调试核，硬件调试就会和软件行为仿真很相似，可以通过波形来验证模块功能的正确性，上图中展示了一个利用 ILA 采样到的波形案例，其中触发器设置了 2 个条件并要求同时满足时触发。

在设置 ILA 触发条件时，我们可以灵活多样的进行组合，ILA 调试核提供了 4 种触发策略：

* 与运算：全部条件满足时进行采样
* 或运算：任一条件满足时进行采样
* 与非运算：任一条件不满足时进行采样
* 或非运算：全部条件不满足时进行采样

#### VIO 虚拟输入输出

在测试单独模块时，通常需要给予模块的输入端口一定数据进行测试。软件行为仿真时，我们是通过编写 TestBench 来完成模块输入端口的赋值操作；但是对于硬件调试，往往 FPGA 开发板上的输入硬件并不能满足模块输入端口宽度的要求。

此时 VIO 虚拟输入输出 IP 核便非常重要，其提供了模拟硬件输入的接口，是我们可以通过 VIO 的调试核在电脑端手动设定数据，并传输到模块的对应端口中，从而解决了硬件输入设备不足的问题。

VIO 在 IP Catalog 中的全称是 Virtual Input/Output，可以通过关键词 VIO 直接搜索得到：

![VIO](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/VIO.png)

当初始化 VIO 时，需要设定好 VIO 输入输出端口的数量；这里一定要注意，VIO 作为虚拟输入输出设备，其**输入**本质上是**输入到电脑端的 VIO 调试核**，而**输出**则是**将电脑端 VIO 调试核中设定的信号值输出到 FPGA 开发板**。

举例来说，当我们的模块需要 5 个**输入**信号时，如果使用 VIO 提供，则 VIO 需要配置 5 个**输出端口**，表明总共有 5 个信号将**从电脑端输出到模块中**；同理，如果想在 VIO 中观察模块的 1 个输出信号，则 VIO 需要配置 1 个**输入端口**，表明只有 1 个信号将**从模块输入到电脑端**。切记此处 VIO 配置的信号方向不可出错！

* 配置端口数量的界面：

![VIO 端口数量](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/VIO端口数量.png)

* 配置输入端口宽度的界面：

![VIO 输入宽度](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/VIO输入宽度.png)

* 配置输出端口宽度及初始值的界面：

![VIO 输出宽度](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/VIO输出宽度.png)

下面给出一个 VIO IP 核使用的实例代码可供参照：

* VIO 黑盒代码（注意端口名称与宽度必须同 IP 核配置一致）

```scala
class vio_0 extends BlackBox {
	val io = new Bundle {
		val clk = in Bool()

		val probe_out0=out Bool()
		val probe_out1=out Bool()
		val probe_out2=out Bool()
		val probe_out3=out UInt(12 bits)
		val probe_out4=out UInt(20 bits)
	}
	noIoPrefix()
}
```

* 顶层测试代码（实例化 VIO 并连接端口）

```scala
val IF = new Instruction_Fetcher
IF.io.rst := rst
IF.io.clk := clk

val vio = new vio_0
vio.io.clk := io.clk_50M
IF.io.enable := vio.io.probe_out0
IF.io.branch := vio.io.probe_out1
IF.io.jump := vio.io.probe_out2
IF.io.branchAddr := vio.io.probe_out3
IF.io.jumpAddr := vio.io.probe_out4
```

将 Vivado 生成的比特流烧入 FPGA 开发板并打开 Hardware Manager 后，VIO 调试核会自动显示在 Hardware 菜单栏中，双击即可弹出 New Dashboard 界面提示我们可以载入 VIO 调试核进行硬件端口赋值：

![VIO 调试界面](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/VIO调试界面.png)

载入 VIO 调试核后，需要将端口添加进当前调试核中：

![VIO 添加调试核](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/VIO添加调试核.png)

接下来，界面中的所有**输出**端口值皆可在电脑端设置并传输到 FPGA 开发板中，我们便可以同时结合 ILA 进行硬件调试了：

![VIO 硬件赋值](/wp-content/uploads/2022/03/riscv-linux/images/riscv_cpu_design/part2/VIO硬件赋值.png)

### SpinalHDL 下板测试技巧

在利用 SpinalHDL 生成 Verilog 源文件后，有时调试过程会遇到一些问题，如时钟信号无法赋值，时序逻辑电路有误等。本节将对常见问题进行解答：

* 时钟无法赋值

由于 SpinalHDL 提供了**时钟域**这一特性，当我们进行硬件调试时，需要利用 Internal ClockDomain 内部时钟域对 clk 信号进行配置，如果单纯使用普通的 ClockDomain 将会导致无法赋值的问题，如下方代码所示：

```scala
val clkCtrl = new Area {

	val coreClockDomain = ClockDomain.internal(
		name = "core",
		frequency = FixedFrequency(25 MHz)
	)

	coreClockDomain.clock := io.clk
	coreClockDomain.reset := io.rst
}

val coreArea = new ClockingArea(clkCtrl.coreClockDomain) {
	// do something
}
```

* 时序逻辑电路影响普通 wire 信号

这是由于在时钟域的控制下，Reg 类型的所有变量都不需要特定的 when 语句进行复位或更新，Reg 完全受控于时钟域：即时钟域的 clock 信号自动更新 Reg，时钟域的 reset 信号自动复位 Reg。所以只有当 wire 信号需要复位时才会使用 when 语句。同时，可以灵活使用 RegNextWhen 对不同的 Reg 更新时机进行调整，如下方代码所示：

```scala
val pc_reg = RegNextWhen(next_pc, io.enable) init (0)
io.pc_reg_debug := pc_reg
pc := pc_reg
// 这里的 pc 表示程序计数器，如果将其定义为 Reg，则由于时钟域的影响，无法使用 io.enable 使能信号进行控制
// 所以转换思路，利用 RegNextWhen 函数定义一个名为 pc_reg 的 Reg 类型变量，并用 io.enable 作为更新条件
// 最后将 pc_reg 赋值给 pc 即可满足要求
when(ClockDomain.current.reset) {
	pc := 0
	next_pc := 0
}
```

* 模块内调用 IP 核的时钟信号无法获得

同样是采取 Internal ClockDomain 的手段，将模块置入这一时钟域控制下，我们就可以利用 SpinalHDL 时钟域的相关方法对 IP 核的时钟信号进行赋值，如下方代码所示：

```scala
val instRom = new Rom
instRom.io.clk := ClockDomain.current.clock // 利用时钟域的 current.clock 获得时钟信号
instRom.io.rst := ClockDomain.current.reset // 利用时钟域的 current.reset 获得复位信号
instRom.io.addr := pc
io.instruction := instRom.io.data
```

## 总结

本文具体的介绍了在 CPU 设计中电路行为仿真与下板硬件调试的流程，并讲解了常用的硬件调试辅助 IP 核的使用，最后总结了硬件调试时的部分问题。

系列文章预告：SpinalHDL 框架下，单周期 CPU 控制器的设计与数据通路的搭建。

## 参考资料

- CPU 设计实战  汪文祥 邢金璋 著 ISBN 978-7-111-67413-9
- [SpinalHDL 手册][4]
- [SpinalHDL Getting Started][5]

[1]: https://verilator.org/guide/latest/index.html
[2]: http://gtkwave.sourceforge.net/gtkwave.pdf
[3]: https://aur.archlinux.org/packages/vivado
[4]: https://spinalhdl.github.io/SpinalDoc-RTD/master/index.html
[5]: https://github.com/SpinalHDL/SpinalTemplateSbt
