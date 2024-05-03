---
layout: post
author: 'yjmstr'
title: 'RISC-V Unified Discovery 简介及其软硬件协作现状'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-isa-extensions-discovery-6-unified-discovery/
description: 'Unified Discovery 简介及其软硬件协作现状'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - Unified Discovery
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [spaces quotes comments tables urls epw]
> Author:    YJMSTR [jay1273062855@outlook.com](https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:jay1273062855@outlook.com)
> Date:      2023/09/28
> Revisor:   Bin Meng, Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   ISCAS


## 前言

本文是 RISC-V ISA 扩展的软硬件支持调研系列的第 6 篇文章，将介绍 Unified Discovery 机制。之前的文章中已经对 RISC-V ISA 扩展的分类、命名、硬件支持机制、GCC 支持、OpenSBI 支持、QEMU 支持和 Linux 内核支持进行了分析。

RISC-V 官方的 GitHub 仓库于 2023 年 9 月 8 日更新了 Unified Discovery Spec 的[草稿][001]，其定义了统一的底层硬件检测机制。本文会对此草稿进行翻译，并结合之前介绍过的 mconfigptr 和 ACPI/SMBIOS/设备树进行分析。

在本系列第 1 篇文章[《RISC-V 当前指令集扩展类别与检测方式》][002] 中，已经介绍过了 RISC-V ISA 以及 mconfigptr 相关的基本概念。系统固件可以将从配置结构或其它地方获取的信息编码为设备树/SMBIOS/ACPI 等，再传递给后续启动流程。

## Unified Discovery Spec 翻译

### Introduction

> Unified Discovery is intended to be a low-level discovery mechanism. A low-level discovery mechanism is distinguished from a high-level discovery mechanism. The former typically prepare and produce necessary data that is consumed by the latter. Diversified applications would require different high-level mechanism, meanwhile, the low-level mechanism provides the foundation.

Unified Discovery 旨在成为底层的检测机制。底层的检测机制与上层的检测机制不同，前者通常准备并提供用于后者使用的数据。多种多样的应用程序对上层检测机制的要求不同，于此同时，底层的检测机制为其提供了基础。

> This proposal describes a low-level discovery mechanism that is capable of supporting the following use cases:
>
> 1. Hosted discovery of features by firmware, operating systems and applications
>    1. Rich operating systems
>    2. Simple software applications
> 2. Discovery of features by external debug tools
> 3. Out-of-band discovery of features to allow development tools to specialise
> 4. firmware (e.g. choose the appropriate target flags for compilation and link in the required libraries) for deeply embedded applications

本提案描述了适用于以下场景的底层检测机制：

1. 固件，操作系统和应用程序托管而来的硬件特性检测
   1. Rich OS
   2. 简单的软件应用
2. 外部调试工具的硬件检测
3. 允许开发工具特化的带外检测
4. 用于深度嵌入式应用的固件（例：选择合适的 target flags 用于编译，并链接到所需的库）

> As an example, consider a typical Linux stack:
>
> 1. Firmware performs system/machine-dependent discovery and populates either a Linux device tree or ACPI tables.
> 2. The Linux kernel parses either a Linux device tree or ACPI tables, exposing system specifics to userland processes through multiple interfaces:
>    1. special files the /proc filesystem
>    2. device drivers available under /dev
>    3. files in a mounted sysfs instance
>    4. flags injected into ELF binaries through the ELF auxiliary vector and accessible through getauxval()
>    5. configuration retrieved through the sysconf() system call
>    6. information retrievable through the vdso (a virtual DSO mapped by the kernel into each processes’ address space)

例如，考虑如下的典型 Linux 栈：

1. 固件执行依赖于系统/机器的检测机制并生成 Linux 设备树或 ACPI 表格
2. Linux 内核解析 Linux 设备树或 ACPI 表，通过多个接口向用户侧进程暴露系统特性：
   1. /proc 文件系统中的特殊文件
   2. /dev 目录下可用的设备驱动
   3. 已挂载的 sysfs 实例中的文件
   4. 通过 ELF auxiliary vector 注入到 ELF 二进制中并可以通过 getauxval() 访问的标志
   5. 从 sysconf() 系统调用返回的配置信息
   6. vdso（一个虚拟 dynamic shared object，由内核映射到每个进程的地址空间）返回的信息

#### No Central Registry

> The proposal provides a solution that does not require a central registry.
>
> RISC-V allows the vendor-specific extensibility of the ISA without any coordination with RISC-V International (as long as no required features are removed and no incompatible features are introduced).

本提案提供了一种不需要中间登记处的解决方案。

RISC-V 允许厂商在没有 RISC-V 国际基金会参与的情况下添加自定义 ISA 扩展（只要没有将要求的功能移除，并且没有引入新的不兼容的特性）

> This should also be reflected in the architecture of the discovery format and require a minimum coordination between implementation and RISC-V International:
>
> 1. Based on the published “rules of the land” (i.e. modelling language, encoding rules and the top-level message description), implementers (both soft- and hardware) shall be able to:
>    1. add proprietary entries in the configuration message, that can safely be identified, skipped and linked back to the vendor (without a global vendor registry being operated by RISC-V) that specified the proprietary entry
>    2. parse any configuration message, including the ability:
>       1. to parse a newer-version message, identifying the new “extensions” and being able to safely skip over them
>       2. To parse a message containing vendor-extensions
> 2. Publish a basic message format that enforces the presence of required fields as a machine-readable document/schema.

这同样需要体现在检测格式的架构中，并且要求实现和 RISC-V 国际基金会之间进行最低限度的协调：

1. 基于已发布的规则（即建模语言、编码规则和顶层信息描述），实施者（软件和硬件）应该能够：
   1. 向配置信息报文中添加可以被安全地识别，跳过和链接回指定该属性条目的产商（在没有 RISC-V 操作的中间注册处的情况下）的属性条目
   2. 解析任何配置信息报文，包括如下能力：
      1. 解析更新版本的报文，识别新扩展并能安全地跳过它们。
      2. 解析包含产商信息的报文
2. 发布基本报文格式，在基本报文格式中强制要求所需字段作为机器可读文档/表格存在。

#### Complete Consumption Requirement

> A key requirement in any discovery process that avoids a centralized registry is a client’s ability to discover that it has read the entire message (including parts that it can not understand and skips over) and whether any unparsable extra elements were included in the message. This is termed the Complete Consumption Requirement.

为了避免 centralized registry，所有检测过程都应满足一个关键要求：客户端要能够检测到它自己已经读取了完整的报文（包括它无法识别和跳过的部分）并能够检测到报文中是否包含任何无法解析的额外元素。这被称为 Complete Consumption Requirement。

> | Note | The complete consumption requirement is one of the unresolvable issues for CPUID-style instructions that query for values using keys. |
> | ---- | ------------------------------------------------------------ |

| 注意 | Complete comsumption requirement 是用键查询值的类 CPUID 指令无法解决的问题 |
| ---- | ------------------------------------------------------------ |

#### Note on Security

> Independent of the underlying mechanism (i.e. whether a memory-based configuration message is read or CPUID-style instructions are used), securing the discovery mechanism will require cryptographically signed checksums (i.e. electronic signatures) to ascertain the authenticity, integrity and the originator of the configuration data.

不管底层使用了怎样的检测机制（即读取基于内存的配置报文或使用类 CPUID 的指令），确保检测机制的安全需要用到加密签名校验和（即电子签名）以确保配置数据的真实性、完整性和来源。

> Signing the configuration message should be an integral (albeit optional) part of the message format. While this can not address the playback of a valid configuration message, it allows the discovery of modified messages.

配置报文的签名应当成为报文格式的组成部分之一（尽管是可选的）。虽然这不能解决有效配置报文的回放问题，但是它能够检测报文是否被修改过。

> We do not believe that the goal of end-to-end security can be efficiently achieved using a design-approach similar to Intel’s CPUID instruction: a cryptographic signature would need to be computed across the entire configuration space (and not merely individual elements). This precludes the absence of a central registry, as the valid key space needs to be known in advance to concatenate the plaintext for signing.

我们认为，使用类似于 Intel 的 CPUID 指令无法有效实现端到端安全：因为加密签名需要在整个配置空间（而不仅仅是单个元素）内进行计算。这使得 central registry 必须存在，因为有效键空间需要被提前知晓，用于连接明文，进行签名。

### Solution Outline

> 1. Schema + Value Notation (human readable form) + Parser
> 2. Reuse existing standards → ITU standards & examples (SNMP)
> 3. vendor-specific info
>
> A binary-encoded representation of a device’s configuration is made available to software within the device’s physical address space. The data structure is described as a subset of ASN.1 (see ITU-T X.680 and ISO/IEC 8824) and encoded using standardized encoding rules (see ITU-T X.690 and ISO 8825). For in-memory representations, the unaligned packed encoding rules (unaligned PER, see ITU-T X.691) are used. The configuration data can (optionally) be cryptographically signed.

1. 模式 + 值标记（人类可读形式）+ 解析器
2. 重用已存在的标准 → ITU 标准和例子（SNMP）
3. 厂商特定的信息

用二进制编码表示的设备配置信息可供设备物理地址空间内的软件使用。配置信息数据结构用 ASN.1 的子集（见 ITU-T X.680 和 ISO/IEC 8824）进行描述，并用标准化编码规则进行编码（见 ITU-T X.690 和 ISO 8825）。内存中的数据使用非对齐打包编码规则（unaligned PER，见 ITU-T X.691）进行表示。配置数据可以（可选地）被加密签名。

> | Note | The data structure is static in the sense that no attempt to dynamically enumerate hardware resource is performed. For example, for devices on a hot-pluggable bus such as USB, it is up to the subsequent boot sequences, if needed, to enumerate the devices and add to the handover structure, such as a device tree, expected by the next boot stage after the boot loader. |
> | ---- | ------------------------------------------------------------ |

| 注意 | 数据结构是静态的，即其不会对硬件资源进行动态枚举。例如，对于 USB 等热拔插总线上的设备，如果需要，可以交由引导子序列来枚举设备，并添加到设备树这样的结构中，交给 boot loader 之后的引导阶段。|
| ---- | ------------------------------------------------------------ |

> This proposal provides a schema of the data structure that is generic and extensible. See Section 8 for the schema. Vendor-specific data can be included without hindering the successful parsing of the configuration.(?)

本提案提供了数据结构的一种模式规则，这一模式是通用的、可扩展的。关于该模式的具体描述见 Section 8。制造商特定的数据可以在不妨碍配置的解析的情况下被包含。（？）

> The base-address of the binary-encoded representation is accessible through a single CSR. No other ISA considerations, beyond the provision of an additional CSR, are required.

二进制编码表示的基地址可以通过单个 CSR 来取得。除此之外不需要扩展 ISA。

> Target software (usually firmware) that performs discovery will read the uPER-encoded message to retrieve the relevant configuration elements. The message can be decoded either using a stream parser with small memory footprint (i.e. the parser reads from the beginning until it retrieves the requested data element) or can be converted start-to-finish into a firmware-specific data structure. Given the compact representation and the low memory requirements for parsers, a uPER message can be efficiently parsed even during the startup of a deeply embedded microcontroller application (even though we envision out-of-band discovery and specialization for deeply embedded and resource-constrained use-cases).

负责进行检测的目标软件（通常是固件）会读取 uPER 编码的报文，来返回相关的配置元素。报文可以通过占用少量内存的流解析器（即从头开始读取，直到检索到所需元素的解析器）来解码，也可以将从头到尾的解析转换为固件特定的数据结构。鉴于 uPER 报文的表示紧凑，以及对解析器的内存要求低，即使是在深度嵌入式微控制器应用（即使我们设想了针对深度嵌入式设备和资源受限使用情况下的带外发现和专门化）的启动过程中，uPER 报文也可以被有效解析。

> The unified discovery mechanism for RISC-V builds on the following technology stack:
>
> 1. ASN.1 (X.680) for modelling the data structures, independent of their encoding
> 2. Packed Encoding Rules (X.691) for the binary encoding of data structures (in-band)
> 3. XML Encoding Rules (X.693) for the XML encoding of data structures (out-of-band)
> 4. RISC-V International specific guidelines to allow the efficient aggregation of RISC-V global and vendor-specific data elements without a central registration authority
> 5. RISC-V International specific guidelines for the encoding of detached signatures (PKCS#7/CMS) using Packed Encoding Rules

RISC-V 的 Unified discovery 机制基于如下技术栈：

1. ASN.1（X.680）用于对数据结构进行建模，与其编码无关
2. 用于数据结构二进制编码（带内）的 Packed Encoding Rules (X.691)。
3. XML Encoding Rules (X.693) 用于数据结构（带外）的 XML 编码。
4. RISC-V 国际基金会的指南，允许在没有中间注册机构的情况下有效汇总 RISC-V 的全球产商特定元素。
5. RISC-V 国际基金会的指南，使用 Packed Encoding Rules 对分离签名（PKCS#7/CMS）进行编码。

> | Note | The benefits of using X.680 and X.693 over vendor-specific (e.g., Google Protobuf, Apache Avro, …) marshalling frameworks are its international standardization, widespread adoption and availability of open-source and commercial codec libraries. |
> | ---- | ------------------------------------------------------------ |

| 注意 | 与使用产商特定编组框架（如 Google Protobuf，Apache Avro 等）相比，使用 X.680 和 X.693 的好处是它们是国际标准化的，其开源和商业解码器库被广泛使用，可用性强。|
| ---- | ------------------------------------------------------------ |

> Retrieval and decoding of the configuration structure can happen in any of the following scenarios:
>
> - Software (in-band)
>
> Firmware will access the CSR and read the configuration message to extract the device’s configuration as part of its discovery process. The implementation details of this process (e.g., whether firmware initiates a read from the top and searches for individual tags, or if firmware converts the entire discovery information into an in-memory representation at once) are left to device implementers.
>
> - External debug (in-band)
>
> External debug will retrieve the CSR and then read out (once) the referenced memory region to retrieve the configuration information for a specific target device. The retrieved configuration message is then parsed by the external debugger to determine the configuration, features and capabilities of the device.
>
> - Software development environment (out-of-band)
>
> For (deeply) embedded applications, firmware will be specialised to target the specific target device only by pushing the discovery and configuration to the software development environment. These cases can be efficiently supported either by reading the configuration structure from a target device using an external debugger, or by retrieving a configuration structure from the manufacturer’s website.

配置结构的检索和编码可能发生在以下任一场景中：

- 软件（带内）

固件将访问 CSR 并读取配置报文来提取设备的配置信息，作为其检测过程中的一部分。该过程的实现细节（例如固件是否从顶部发起一次读取，并搜索独立标签，或固件是否立刻将整个检测信息转换为内存内的表示方式）交由设备实现者来决定。

- 外部调试（带内）

外部调试会检索 CSR 并读出（一次）引用的内存区域，来检索特定目标设备的配置信息。被检索的配置报文随后会被外部调试器解析，来确定设备的配置、特性和兼容性。

- 软件开发环境（带外）

对于（深度）嵌入式应用程序，固件只需要将检测和配置传给软件开发环境，就可以针对专门的目标设备进行特化。这些情况可以通过用外部调试器读取特定设备的配置结构，或从制造商的网站上检索数据结构来有效实现。

### The mconfig CSR

> The machine config pointer (mconfigptr) CSR provides the base-address of the binary-encoded representation. The mconfigptr is a machine-mode CSR. On platforms that does not require runtime update of the address of the binary representation of the configuration, this register can be hardwired to zero.
>
> For backward compatibility, the firmware can emulate this CSR on platforms that does not implement this CSR prior to this proposal.

machine config pointer (mconfigptr) CSR 提供了二进制编码表示的基地址。mconfigptr 是机器模式的 CSR。在没有要求要在运行时更新配置二进制表示的基地址的平台上，这个寄存器可以硬连线到 0。

为了向后兼容，固件可以在本提案之前未实现该 CSR 的平台上模拟这个 CSR。

### Hypervisor: Unified Discovery for Guest OSes

> For virtualisation purposes, only the retrieval of the mconfigptr CSR has to be intercepted (i.e. either a virtualized CSR would be provided to the guest that can be written by the hypervisor — or trap-and-emulate would be used) if the guest is to be provided with a configuration structure that may or may not be from what is retrieved from the underlying hardware.

在用于虚拟化时，如果要向客户机提供配置结构，只需要拦截对 mconfigptr CSR 的检索（即向客户机提供一个可以被 hypervisor 写入的虚拟 CSR，或使用 trap-and-emulate）即可。该配置结构可能来自底层硬件，也可能不来自底层硬件。

### 其它

此规范草稿中的其它部分目前仅有标题，如下所示：

```
RISC-V Unified Discovery Specification
	Introduction
		No Central Registry
		Complete Consumption Requirement
		Note on Security
	Solution Outline
	The mconfigptr CSR
	Hypervisor: Unified Discovery for Guest OSes
	/** 下面的部分目前仅有标题 * */
	Referenced standards
	Guidelines/Mappings from discoverable elements → ASN.1
		Extensibility, versioning & “container format”
		What types of discoverable elements do we support?
			Existence
			Structural elements (lists, arrays)
			Parameters (enums, integer ranges, addresses)
		How to map these to ASN.1
	Encoding rules
		Reference back to X.69x ?
	Top-level schema → appendix ( normative )
		container format
		standard elements (vectors, bitmanip, …)
```

此规范的草稿近期还在不断更新中，本文翻译的部分可能不全，仅供参考，请以 [GitHub 仓库][001] 为准。当规范草稿更新后，本文的翻译部分也会不定期更新。

## 从配置结构到业界标准

SBI 规范并没有规定标准的硬件检测方法，S 模式的软件需要借助其它的业界标准方法来实现硬件检测，即设备树或 ACPI 等。

与此同时，SBI 规范中也没有将设备树作为规范的一部分。如果 SBI 实现不使用 a1 寄存器来传输设备树地址，这也是符合 SBI 规范的，但会导致 Linux 无法启动（Linux 会在启动过程中从 a1 寄存器获取设备树地址）。

configuration-structure 的规范中提到，系统固件可以根据配置结构来生成设备树/SMBIOS/ACPI，以供启动流程中的后续阶段使用。系统固件通常是在系统上电时被执行的，其初始化硬件，并建立固件服务或引导所需的数据结构。常见的系统固件如嵌入式系统所使用的 U-Boot 或 PC 和服务器所使用的 BIOS。

由于 mconfigptr 是 M 模式的 CSR，而 U-Boot Proper 运行在 S 模式，若 U-Boot 想要访问 mconfigptr，要么通过 M 模式的 U-Boot SPL 访问，要么借助 SBI 实现来访问。

那 SBI 实现是怎么使用 mconfigptr 指向的 configuration-structure 的呢？以 OpenSBI 为例，查阅 OpenSBI 的仓库、源码与和邮件列表可知，目前 OpenSBI 并没有使用 configuration-structure 来生成设备树/ACPI/SMBIOS，其 `include/sbi/riscv_encoding.h` 文件中也未对 mconfigptr CSR 进行编码。据此可以判断目前 OpenSBI v1.3.1 还没有使用 mconfigptr 和 configuration-structure。不过 RISC-V Priv Spec v1.12 已经将 mconfigptr 视为必须实现的 CSR，其编号 0xf15 不应再分配给其它 CSR。

## 总结

近期，RISC-V 的 GitHub 仓库中出现了 Unified Discovery 的规范草稿，其介绍了新的硬件检测机制的动机、性质，以及 Unified Discovery 解决方案的大纲等。本文对其现有的部分进行了翻译。

RISC-V 通常使用 CSR 来检测硬件信息，但这对于某些类型的信息来说显得有些不够灵活，而且随着要检测的信息种类和数量的增加，要不断消耗 CSR。对于 RISC-V ISA 扩展而言，misa 寄存器能够检测的扩展数量有限，如果还沿用 misa 的方法对其它扩展的检测提供支持，就需要新增若干个类似 misa 的寄存器。

为了解决这些问题，configuration-structure 被提了出来。RISC-V 设备仅需使用 mconfigptr 这一个 CSR 来指向 configuration-structure 的地址，硬件信息被保存在这一结构中。不过目前关于这个配置结构的文档还处于草稿状态。

系统固件可以借助 configuration-structure 来生成设备树/SMBIOS/ACPI 等结构，但目前 OpenSBI 还没这么做。相关规范进入 ratified 状态后，可以根据本系列调研的成果向相关的开源软件提交 patch，加入使用 Unified Discovery 机制进行硬件检测的支持。

## 参考资料

- [Unified Discovery Spec(Draft)][001]
- [RISC-V 当前指令集扩展类别与检测方式][002]
- [riscv-sbi-doc:Add Hart Discovery Extension #60][003]

[001]: https://github.com/riscv/configuration-structure/blob/master/riscv-unified-discovery-draft.adoc
[002]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20230715-riscv-isa-extensions-discovery-1.md
[003]: https://github.com/riscv-non-isa/riscv-sbi-doc/pull/60
