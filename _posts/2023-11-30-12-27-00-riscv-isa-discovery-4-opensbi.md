---
layout: post
author: 'yjmstr'
title: 'OpenSBI RISC-V ISA 扩展检测与支持方式分析'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-isa-discovery-4-opensbi/
description: 'OpenSBI RISC-V ISA 扩展检测与支持方式分析'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - OpenSBI
  - 指令集扩展
  - 检测方式
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [spaces quotes header comments urls]
> Author:    YJMSTR [jay1273062855@outlook.com](https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:jay1273062855@outlook.com)
> Date:      2023/08/16
> Revisor:   Bin Meng, Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

本文是 RISC-V 扩展的软硬件支持方式调研系列的第 4 篇文章，将以 OpenSBI 为例分析 SBI 对 RISC-V 扩展的检测与支持方式。

SBI 指 Supervisor Binary Interface，其将 M 模式下对硬件的操作抽象成 S 模式软件可以调用的统一接口，来将硬件与 S 模式软件进行一定程度的解耦；此外，SBI 也是 HS 模式的虚拟机与 VS 模式程序之间的推荐接口。RISC-V 定义了 [SBI 的规范][001]，SBI 规范中并未指定任何的硬件检测机制，S 模式的软件必须通过诸如 Device Tree 或 ACPI 这样的机制来实现硬件检测。

本文基于 QEMU v8.1.0-rc0 与 OpenSBI v1.3.1 进行分析。

## OpenSBI 快速上手

之前社区已有介绍 OpenSBI 的文章（参考：[OpenSBI 快速上手][002]），此处不再赘述。

目前 OpenSBI 的最新 release 版本是 OpenSBI v1.3.1，按如下命令获得源码并编译。

```sh
$ git clone https://github.com/riscv-software-src/opensbi.git
$ cd opensbi
$ git checkout v1.3.1
$ export CROSS_COMPILE=riscv64-linux-gnu-
$ make all PLATFORM=generic PLATFORM_RISCV_XLEN=64
```

其中 PLATFORM 选择 QEMU RISC-V 'virt' 虚拟板卡所需的 generic 平台。

在 `qemu-system-riscv64` 启动时通过 `-bios` 参数指定刚才编译出的 OpenSBI firmware，可以得到如下启动日志：

```sh
$ qemu-system-riscv64 -M virt -m 256M -nographic -bios build/platform/generic/firmware/fw_jump.bin

OpenSBI v1.3.1
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|___/_____|
        | |
        |_|

Platform Name             : riscv-virtio,qemu
Platform Features         : medeleg
Platform HART Count       : 1
Platform IPI Device       : aclint-mswi
Platform Timer Device     : aclint-mtimer @ 10000000Hz
Platform Console Device   : uart8250
Platform HSM Device       : ---
Platform PMU Device       : ---
Platform Reboot Device    : sifive_test
Platform Shutdown Device  : sifive_test
Platform Suspend Device   : ---
Platform CPPC Device      : ---
Firmware Base             : 0x80000000
Firmware Size             : 194 KB
Firmware RW Offset        : 0x20000
Firmware RW Size          : 66 KB
Firmware Heap Offset      : 0x28000
Firmware Heap Size        : 34 KB (total), 2 KB (reserved), 9 KB (used), 22 KB (free)
Firmware Scratch Size     : 4096 B (total), 760 B (used), 3336 B (free)
Runtime SBI Version       : 1.0

Domain0 Name              : root
Domain0 Boot HART         : 0
Domain0 HARTs             : 0*
Domain0 Region00          : 0x0000000002000000-0x000000000200ffff M: (I,R,W) S/U: ()
Domain0 Region01          : 0x0000000080000000-0x000000008001ffff M: (R,X) S/U: ()
Domain0 Region02          : 0x0000000080020000-0x000000008003ffff M: (R,W) S/U: ()
Domain0 Region03          : 0x0000000000000000-0xffffffffffffffff M: (R,W,X) S/U: (R,W,X)
Domain0 Next Address      : 0x0000000080200000
Domain0 Next Arg1         : 0x0000000082200000
Domain0 Next Mode         : S-mode
Domain0 SysReset          : yes
Domain0 SysSuspend        : yes

Boot HART ID              : 0
Boot HART Domain          : root
Boot HART Priv Version    : v1.12
Boot HART Base ISA        : rv64imafdch
Boot HART ISA Extensions  : time,sstc
Boot HART PMP Count       : 16
Boot HART PMP Granularity : 4
Boot HART PMP Address Bits: 54
Boot HART MHPM Count      : 16
Boot HART MIDELEG         : 0x0000000000001666
Boot HART MEDELEG         : 0x0000000000f0b509

```

 从中可以看见 Boot HART Base ISA 信息与 Boot HART ISA Extensions 信息。

QEMU RISC-V 平台内置了 OpenSBI，如果在启动参数中将 `-bios` 设置为 default 或不指定该参数，就会启动内置的 OpenSBI。

```sh
$ qemu-system-riscv64 -M virt -m 256M -nographic

OpenSBI v1.3
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|___/_____|
        | |
        |_|

Platform Name             : riscv-virtio,qemu
Platform Features         : medeleg
Platform HART Count       : 1
Platform IPI Device       : aclint-mswi
Platform Timer Device     : aclint-mtimer @ 10000000Hz
Platform Console Device   : uart8250
Platform HSM Device       : ---
Platform PMU Device       : ---
Platform Reboot Device    : sifive_test
Platform Shutdown Device  : sifive_test
Platform Suspend Device   : ---
Platform CPPC Device      : ---
Firmware Base             : 0x80000000
Firmware Size             : 194 KB
Firmware RW Offset        : 0x20000
Firmware RW Size          : 66 KB
Firmware Heap Offset      : 0x28000
Firmware Heap Size        : 34 KB (total), 2 KB (reserved), 9 KB (used), 22 KB (free)
Firmware Scratch Size     : 4096 B (total), 760 B (used), 3336 B (free)
Runtime SBI Version       : 1.0

Domain0 Name              : root
Domain0 Boot HART         : 0
Domain0 HARTs             : 0*
Domain0 Region00          : 0x0000000002000000-0x000000000200ffff M: (I,R,W) S/U: ()
Domain0 Region01          : 0x0000000080000000-0x000000008001ffff M: (R,X) S/U: ()
Domain0 Region02          : 0x0000000080020000-0x000000008003ffff M: (R,W) S/U: ()
Domain0 Region03          : 0x0000000000000000-0xffffffffffffffff M: (R,W,X) S/U: (R,W,X)
Domain0 Next Address      : 0x0000000000000000
Domain0 Next Arg1         : 0x000000008fe00000
Domain0 Next Mode         : S-mode
Domain0 SysReset          : yes
Domain0 SysSuspend        : yes

Boot HART ID              : 0
Boot HART Domain          : root
Boot HART Priv Version    : v1.12
Boot HART Base ISA        : rv64imafdch
Boot HART ISA Extensions  : time,sstc
Boot HART PMP Count       : 16
Boot HART PMP Granularity : 4
Boot HART PMP Address Bits: 54
Boot HART MHPM Count      : 16
Boot HART MIDELEG         : 0x0000000000001666
Boot HART MEDELEG         : 0x0000000000f0b509

```

可以看见，目前 QEMU v8.1.0-rc0 内置的 OpenSBI 版本为 v1.3。

## 源码分析

在 OpenSBI 的 `docs/platform/qemu_virt.md` 中有使用 GDB 对 QEMU + OpenSBI 进行调试的教程，此处不再赘述。

前一小节中 OpenSBI 启动时会在命令行中输出当前设备的相关信息，其中输出扩展信息的相关代码如下：

```c
/* lib/sbi/sbi_init.c:152 */

static void sbi_boot_print_hart(struct sbi_scratch *scratch, u32 hartid)
{
	int xlen;
	char str[128];
	const struct sbi_domain *dom = sbi_domain_thishart_ptr();

	if (scratch->options & SBI_SCRATCH_NO_BOOT_PRINTS)
		return;

	/* Determine MISA XLEN and MISA string */
	xlen = misa_xlen();
	if (xlen < 1) {
		sbi_printf("Error %d getting MISA XLEN\n", xlen);
		sbi_hart_hang();
	}

	/* Boot HART details */
	sbi_printf("Boot HART ID              : %u\n", hartid);
	sbi_printf("Boot HART Domain          : %s\n", dom->name);
	sbi_hart_get_priv_version_str(scratch, str, sizeof(str));
	sbi_printf("Boot HART Priv Version    : %s\n", str);
	misa_string(xlen, str, sizeof(str));
	sbi_printf("Boot HART Base ISA        : %s\n", str);
	sbi_hart_get_extensions_str(scratch, str, sizeof(str));
	sbi_printf("Boot HART ISA Extensions  : %s\n", str);
	sbi_printf("Boot HART PMP Count       : %d\n",
		   sbi_hart_pmp_count(scratch));
	sbi_printf("Boot HART PMP Granularity : %lu\n",
		   sbi_hart_pmp_granularity(scratch));
	sbi_printf("Boot HART PMP Address Bits: %d\n",
		   sbi_hart_pmp_addrbits(scratch));
	sbi_printf("Boot HART MHPM Count      : %d\n",
		   sbi_hart_mhpm_count(scratch));
	sbi_hart_delegation_dump(scratch, "Boot HART ", "         ");
}
```

可以看见上述代码分别调用了 `misa_string` 和 `sbi_hart_get_extensions_str` 函数来获取 Boot HART Base ISA 信息与 Boot HART ISA Extensions 信息。

`misa_string` 的实现如下：

```c
/* lib/sbi/riscv_asm.c:53 */

void misa_string(int xlen, char *out, unsigned int out_sz)
{
	unsigned int i, pos = 0;
	const char valid_isa_order[] = "iemafdqclbjtpvnhkorwxyzg";

	if (!out)
		return;

	if (5 <= (out_sz - pos)) {
		out[pos++] = 'r';
		out[pos++] = 'v';
		switch (xlen) {
		case 1:
			out[pos++] = '3';
			out[pos++] = '2';
			break;
		case 2:
			out[pos++] = '6';
			out[pos++] = '4';
			break;
		case 3:
			out[pos++] = '1';
			out[pos++] = '2';
			out[pos++] = '8';
			break;
		default:
			sbi_panic("%s: Unknown misa.MXL encoding %d",
				   __func__, xlen);
			return;
		}
	}

	for (i = 0; i < array_size(valid_isa_order) && (pos < out_sz); i++) {
		if (misa_extension_imp(valid_isa_order[i]))
			out[pos++] = valid_isa_order[i];
	}

	if (pos < out_sz)
		out[pos++] = '\0';
}
```

上述代码通过枚举 misa 中每一个扩展所对应的字符，作为参数传入 `misa_extension_imp` 函数来判断该扩展是否启用，若支持该扩展，返回非 0 值：

```c
/* lib/sbi/riscv_asm.c:16 */

/* determine CPU extension, return non-zero support */
int misa_extension_imp(char ext)
{
	unsigned long misa = csr_read(CSR_MISA);

	if (misa) {
		if ('A' <= ext && ext <= 'Z')
			return misa & (1 << (ext - 'A'));
		if ('a' <= ext && ext <= 'z')
			return misa & (1 << (ext - 'a'));
		return 0;
	}

	return sbi_platform_misa_extension(sbi_platform_thishart_ptr(), ext);
}
```

其中，`csr_read` 函数通过内联汇编读取 misa 寄存器的值。如果读出的 misa 值是 0，说明当前设备没有实现 MISA 寄存器，需要通过其它非标准的方式来确定启用了哪些扩展。这里首先通过 `sbi_platform_thishart_ptr` 函数从 mscratch 寄存器中读出当前 hart 的 `struct sbi_platform` 结构体，该结构体中包含了 `struct sbi_platform_operations` 结构体的所在地址，而这个结构体中又包括了平台特定的 `misa_check_extension` 函数，`sbi_platform_misa_extension` 会判断平台是否实现了该函数，如果实现了该函数，就调用平台所指定的函数进行判断：

```c
/* include/sbi/sbi_platform.h:461 */

/**
 * Check CPU extension in MISA
 *
 * @param plat pointer to struct sbi_platform
 * @param ext shorthand letter for CPU extensions
 *
 * @return zero for not-supported and non-zero for supported
 */
static inline int sbi_platform_misa_extension(const struct sbi_platform *plat,
					      char ext)
{
	if (plat && sbi_platform_ops(plat)->misa_check_extension)
		return sbi_platform_ops(plat)->misa_check_extension(ext);
	return 0;
}
```

回到 `sbi_boot_print_hart` 函数，对于不在 misa 中的扩展，OpenSBI 通过 `sbi_hart_get_extensions_str` 函数进行检测，该函数如下：

```c
/* lib/sbi/sbi_hart.c:463 */

/**
 * Get the hart extensions in string format
 *
 * @param scratch pointer to the HART scratch space
 * @param extensions_str pointer to a char array where the extensions string
 *			 will be updated
 * @param nestr length of the features_str. The feature string will be
 *		truncated if nestr is not long enough.
 */
void sbi_hart_get_extensions_str(struct sbi_scratch *scratch,
				 char *extensions_str, int nestr)
{
	struct sbi_hart_features *hfeatures =
			sbi_scratch_offset_ptr(scratch, hart_features_offset);
	int offset = 0, ext = 0;
	char *temp;

	if (!extensions_str || nestr <= 0)
		return;
	sbi_memset(extensions_str, 0, nestr);

	if (!hfeatures->extensions)
		goto done;

	do {
		if (hfeatures->extensions & BIT(ext)) {
			temp = sbi_hart_extension_id2string(ext);
			if (temp) {
				sbi_snprintf(extensions_str + offset,
					     nestr - offset,
					     "%s,", temp);
				offset = offset + sbi_strlen(temp) + 1;
			}
		}

		ext++;
	} while (ext < SBI_HART_EXT_MAX);

done:
	if (offset)
		extensions_str[offset - 1] = '\0';
	else
		sbi_strncpy(extensions_str, "none", nestr);
}
```

`hfeatures` 结构体中包含一个 `unsigned long extensions` 成员，其每一位对应一种扩展，目前仅支持下述几种 misa 寄存器无法标识的扩展：

```c
/* include/sbi/sbi_hart.h:27 */

/** Possible ISA extensions of a hart */
enum sbi_hart_extensions {
	/** Hart has Sscofpmt extension */
	SBI_HART_EXT_SSCOFPMF = 0,
	/** HART has HW time CSR (extension name not available) */
	SBI_HART_EXT_TIME,
	/** HART has AIA M-mode CSRs */
	SBI_HART_EXT_SMAIA,
	/** HART has Smstateen CSR **/
	SBI_HART_EXT_SMSTATEEN,
	/** HART has Sstc extension */
	SBI_HART_EXT_SSTC,

	/** Maximum index of Hart extension */
	SBI_HART_EXT_MAX,
};
```

这些非 misa 扩展会组成为 `extensions_str` 字符串，在 OpenSBI 的启动日志中作为 `Boot HART ISA Extensions` 输出。

本文所分析的 OpenSBI 版本虽然是当前最新的 Release 版本，但就在近几天内 OpenSBI 的开发版本中又新增了对若干扩展的支持，最新的 `sbi_hart_extensions` 如下所示：

```c
/* include/sbi/sbi_hart.h:27 */

/** Possible ISA extensions of a hart */
enum sbi_hart_extensions {
	/** HART has AIA M-mode CSRs */
	SBI_HART_EXT_SMAIA = 0,
	/** HART has Smepmp */
	SBI_HART_EXT_SMEPMP,
	/** HART has Smstateen CSR **/
	SBI_HART_EXT_SMSTATEEN,
	/** Hart has Sscofpmt extension */
	SBI_HART_EXT_SSCOFPMF,
	/** HART has Sstc extension */
	SBI_HART_EXT_SSTC,
	/** HART has Zicntr extension (i.e. HW cycle, time & instret CSRs) */
	SBI_HART_EXT_ZICNTR,
	/** HART has Zihpm extension */
	SBI_HART_EXT_ZIHPM,
	/** Hart has Smcntrpmf extension */
	SBI_HART_EXT_SMCNTRPMF,

	/** Maximum index of Hart extension */
	SBI_HART_EXT_MAX,
};
```

## 总结

本文对 OpenSBI 目前的 RISC-V ISA 扩展检测机制与支持情况进行了简要分析，SBI 规范并未规定 SBI 检测硬件的方式，S 模式的软件必须通过诸如 Device Tree 或 ACPI 这样的机制来实现硬件检测。不过 OpenSBI 会在启动时进行 RISC-V ISA 扩展的检测，并在启动时输出当前 hart 支持的部分扩展，这些扩展被 OpenSBI 分为 Base ISA（misa 中包含的扩展）和 ISA Extension 分别进行检测和输出。

Base ISA 的检测是通过直接读取 misa CSR 来完成的，当未实现 misa 寄存器时，则是通过读取 mscratch 寄存器来获取平台特定的检测函数，调用该函数进行检测。

ISA Extension 通过读取 mscratch 寄存器获得 hfeature 结构体的地址，从该结构体中判断实现了哪些扩展。目前 OpenSBI 启动时仅会通过这种方式检测少数几种扩展，如 SMAIA 等。

## 参考资料

- [riscv-sbi-doc][001]
- [OpenSBI 快速上手][002]

[001]: https://github.com/riscv-non-isa/riscv-sbi-doc
[002]: https://tinylab.org/riscv-opensbi-quickstart/
