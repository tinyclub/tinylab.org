---
layout: post
author: 'yjmstr'
title: 'QEMU RISC-V ISA 扩展支持'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-isa-discovery-3-qemu/
description: 'QEMU RISC-V ISA 扩展支持'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - QEMU
  - 指令集扩展
  - 检测方式
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [pangu autocorrect epw]
> Author:    YJMSTR [jay1273062855@outlook.com](https://gitee.com/tinylab/riscv-linux/blob/master/articles/mailto:jay1273062855@outlook.com)
> Date:      2023/08/05
> Revisor:   Bin Meng, Falcon
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   ISCAS


## 前言

本文是 RISC-V ISA 扩展的软硬件支持方式调研系列的第 3 篇文章，将介绍 QEMU 对 RISC-V ISA 扩展的检测与支持方式。在本系列前两篇文章中已经介绍过 RISC-V 扩展的命名、分类与硬件支持、GCC 支持现状。

## QEMU 简介与安装

有关 QEMU 的介绍及 QEMU RISC-V 的安装，可以参考 [我之前的文章][001]，此处不再赘述。下载安装时注意修改 QEMU 的版本号为所需的版本（qemu-8.1.0-rc0.tar.xz），本文基于目前的最新版本 QEMU-8.1.0-rc0 进行分析。安装完成后在终端键入 `qemu-system-riscv64 --version`，得到的输出如下：

```sh
$ qemu-system-riscv64 --version
QEMU emulator version 8.0.90
Copyright (c) 2003-2023 Fabrice Bellard and the QEMU Project developers
```

上述安装过程仅涉及 system mode 模拟的编译安装，如需安装 user mode 的 QEMU，只需要在 `./configure --target-list=` 命令的 `--target-list` 中加入 `riscv64-linux-user`，再进行编译即可。随后在终端键入 `qemu-riscv64 --version`，得到的输出如下：

```sh
$ qemu-riscv64 --version
qemu-riscv64 version 8.0.90
Copyright (c) 2003-2023 Fabrice Bellard and the QEMU Project developers

```

RISC-V ISA 扩展数量众多，QEMU 按照如下规则选择要支持哪些扩展：

- 被 RISC-V 基金会标记为 frozen 或 ratified 状态的扩展可以被 QEMU 支持。
- 被 RISC-V 基金会标记为 reasonable draft 状态的扩展可以被 QEMU “实验性支持”，“实验性支持” 的扩展必须在 QEMU 中默认关闭，并且在 CPU/board 的属性中用 "x-" 前缀标记，并包含版本信息。
- 对于 draft 状态的扩展，QEMU 仅对它们的最新版本提交的 patches 提供支持。Draft 状态的扩展可以随时从 QEMU 中被移除，并且这一移除动作不需要遵循 QEMU 的弃用策略。
- QEMU 支持 RISC-V 厂商自定义扩展（vendor extensions），厂商自定义扩展必须是默认关闭的。

## QEMU TCG

本文关注的重点是 QEMU 对 RISC-V ISA 扩展的支持，首先需要了解一下 QEMU 是如何让某一个指令集架构的程序在另一个指令集架构上运行的。

QEMU 的用户态模拟模式（如 `qemu-riscv64`）与系统模拟模式（如 `qemu-system-riscv64`）采用的指令翻译方式相同，均为基于 Tiny Code Generator（参考 [QEMU-wiki][002] 与 [QEMU 文档][003]）的动态二进制翻译，即在程序运行的过程中将指令通过 TCG 前端翻译成中间指令（TCG ops），再通过 TCG 后端将中间指令翻译成宿主机上可以直接运行的指令。要将 QEMU 移植到新处理器上时，需要修改 TCG 后端的逻辑或使用 TCI（TCG Interpreter）来生成后端代码；而在 QEMU 上模拟新处理器时，需要修改前端部分。因此要为 QEMU 添加一个 RISC-V 扩展的支持，可能需要从两个方面进行修改：把目标指令翻译成 TCG ops 的前端和把 TCG ops 翻译成宿主机指令的后端。但通过下文的分析可以得知，QEMU 的后端目前支持的扩展很少，仅会生成使用了少数扩展的 RISC-V 指令。

TCG 的 target 指 TCG 所生成的代码的架构，即运行 QEMU 的主机的架构，这一定义与 QEMU 的 target 不同，QEMU 的 target 指要模拟的架构。

有关 TCG 的更详细介绍可以参考 `/docs/devel` 目录下的相关文档。

## 源码分析

具体分析时，可以找一个向 QEMU 添加 RISC-V 扩展支持的 patch 进行分析，例如 QEMU 8.1.0 中引入的 [对 Zfa 扩展的支持][004]。Zfa 扩展引入了新的浮点指令，其依赖于 F、D、Q、Zfh 等浮点数相关扩展。向 QEMU 添加对某一扩展支持的代码时，可能需要同时修改将 RISC-V 代码翻译成 QEMU 中间代码的 TCG 前端部分与将中间代码翻译为 RISC-V 代码的后端部分，分别对应 RISC-V 设备作为 guest 和作为 host 的情况。

QEMU RISC-V 前端相关的代码位于 `target/riscv`，RISC-V 作为 host 时的后端相关的代码位于 `tcg/riscv`。

### 初始化

首先来看初始化部分，QEMU 使用术语 “target” 来表示模拟的对象，`target/riscv/cpu.c` 包含了 QEMU 对 RISC-V CPU 进行模拟的核心代码。文件中包含了对 RISC-V 扩展组合的检测与合法性判断等函数，以及根据要模拟的硬件信息生成 ISA-string 的相关代码。

在文件开头有表示单字母扩展的字符串，该字符串是符合 RISC-V 单字母扩展的排序规则的：

```c
/* target/riscv/cpu.c:41 */

/* RISC-V CPU definitions */
static const char riscv_single_letter_exts[] = "IEMAFDQCPVH";
```

随后可以看见一些对 RISC-V 扩展及对应规范版本的定义。向 QEMU 添加 RISC-V ISA 多字母的扩展时，需要按照扩展字符串的排序规则在此处按序添加 `ISA_EXT_DATA_ENTRY` 项的定义，其中包含了用于标识各个扩展是否启用的变量在 CPU 的配置数据结构体 `struct RISCVCPUConfig` 中的偏移量，从这段代码中我们也能一览 QEMU RISC-V 目前支持的多字母扩展：

```c
/* target/riscv/cpu.c:64 */

/*
 * Here are the ordering rules of extension naming defined by RISC-V
 * specification :
 * 1. All extensions should be separated from other multi-letter extensions
 *    by an underscore.
 * 2. The first letter following the 'Z' conventionally indicates the most
 *    closely related alphabetical extension category, IMAFDQLCBKJTPVH.
 *    If multiple 'Z' extensions are named, they should be ordered first
 *    by category, then alphabetically within a category.
 * 3. Standard supervisor-level extensions (starts with 'S') should be
 *    listed after standard unprivileged extensions.  If multiple
 *    supervisor-level extensions are listed, they should be ordered
 *    alphabetically.
 * 4. Non-standard extensions (starts with 'X') must be listed after all
 *    standard extensions. They must be separated from other multi-letter
 *    extensions by an underscore.
 *
 * Single letter extensions are checked in riscv_cpu_validate_misa_priv()
 * instead.
 */
static const struct isa_ext_data isa_edata_arr[] = {
    ISA_EXT_DATA_ENTRY(zicbom, PRIV_VERSION_1_12_0, ext_icbom),
    ISA_EXT_DATA_ENTRY(zicboz, PRIV_VERSION_1_12_0, ext_icboz),
    ISA_EXT_DATA_ENTRY(zicond, PRIV_VERSION_1_12_0, ext_zicond),
    ISA_EXT_DATA_ENTRY(zicsr, PRIV_VERSION_1_10_0, ext_icsr),
    ISA_EXT_DATA_ENTRY(zifencei, PRIV_VERSION_1_10_0, ext_ifencei),
    // 此处省略部分代码
    // ...
};
```

同样需要按这个顺序在 RISCVCPUConfig 结构体中添加对应的 bool 变量：

```c
/* target/riscv/cpu_cfg.h:39 */

struct RISCVCPUConfig {
    bool ext_zba;
    bool ext_zbb;
    // 此处省略部分代码
    // ...
    bool ext_sscofpmf;
    bool rvv_ta_all_1s;
    bool rvv_ma_all_1s;

    uint32_t mvendorid;
    uint64_t marchid;
    uint64_t mimpid;

    /* Vendor-specific custom extensions */
    bool ext_xtheadba;
    // 此处省略部分代码
    // ...
    bool ext_XVentanaCondOps;

    uint8_t pmu_num;
    char *priv_spec;
    char *user_spec;
    char *bext_spec;
    char *vext_spec;
    uint16_t vlen;
    uint16_t elen;
    uint16_t cbom_blocksize;
    uint16_t cboz_blocksize;
    bool mmu;
    bool pmp;
    bool epmp;
    bool debug;
    bool misa_w;

    bool short_isa_string;

#ifndef CONFIG_USER_ONLY
    RISCVSATPMap satp_mode;
#endif
};
```

判断扩展是否启用时，分两类进行判断：misa 中的扩展和非 misa 扩展。非 misa 扩展通过参数传入的偏移量计算出标识对应扩展是否启用的变量在结构体中的位置，从而进行判断。`isa_ext_update_enable` 函数通过类似的方法来将指定的扩展标识为启用或关闭：

```c
/* target/riscv/cpu.c:154 */

static bool isa_ext_is_enabled(RISCVCPU *cpu,
                               const struct isa_ext_data *edata)
{
    bool *ext_enabled = (void *)&cpu->cfg + edata->ext_enable_offset;

    return *ext_enabled;
}

static void isa_ext_update_enabled(RISCVCPU *cpu,
                                   const struct isa_ext_data *edata, bool en)
{
    bool *ext_enabled = (void *)&cpu->cfg + edata->ext_enable_offset;

    *ext_enabled = en;
}
```

而 misa 中的扩展通过 `riscv_has_ext()` 函数进行判断：

```c
/* target/riscv/cpu.c:407 */

static inline int riscv_has_ext(CPURISCVState *env, target_ulong ext)
{
    return (env->misa_ext & ext) != 0;
}
```

misa_ext 可以通过 `set_misa` 函数进行设置：

```c
/* target/riscv/cpu.c: 263 */

static void set_misa(CPURISCVState *env, RISCVMXL mxl, uint32_t ext)
{
    env->misa_mxl_max = env->misa_mxl = mxl;
    env->misa_ext_mask = env->misa_ext = ext;
}
```

如果某些型号的 CPU 默认启用了某些扩展，那么也需要在这些 CPU 的初始化函数中进行对应的初始化。以 C906 的初始化函数为例，它默认启用了 misa 寄存器中标识的 C、S、U 标识位，以及字符 G 对应的 IMAFD_Zicsr_Zifencei 扩展组合在 misa 中的部分（IMAFD），此外还手动设置了若干个多字母扩展在 cpu->cfg 中标识是否启用的变量。

```c
/* target/riscv/cpu.c:425 */

static void rv64_thead_c906_cpu_init(Object *obj)
{
    CPURISCVState *env = &RISCV_CPU(obj)->env;
    RISCVCPU *cpu = RISCV_CPU(obj);

    set_misa(env, MXL_RV64, RVG | RVC | RVS | RVU);
    env->priv_ver = PRIV_VERSION_1_11_0;

    cpu->cfg.ext_zfa = true;
    cpu->cfg.ext_zfh = true;
    cpu->cfg.mmu = true;
    cpu->cfg.ext_xtheadba = true;
    cpu->cfg.ext_xtheadbb = true;
    cpu->cfg.ext_xtheadbs = true;
    cpu->cfg.ext_xtheadcmo = true;
    cpu->cfg.ext_xtheadcondmov = true;
    cpu->cfg.ext_xtheadfmemidx = true;
    cpu->cfg.ext_xtheadmac = true;
    cpu->cfg.ext_xtheadmemidx = true;
    cpu->cfg.ext_xtheadmempair = true;
    cpu->cfg.ext_xtheadsync = true;

    cpu->cfg.mvendorid = THEAD_VENDOR_ID;
#ifndef CONFIG_USER_ONLY
    set_satp_mode_max_supported(cpu, VM_1_10_SV39);
#endif

    /* inherited from parent obj via riscv_cpu_init() */
    cpu->cfg.pmp = true;
}
```

下方的 `riscv_cpu_validate_set_extensions` 函数根据 ISA 扩展间的依赖关系来判断当前扩展组合是否合法，如果我们要向 QEMU 中添加的扩展与其它扩展存在依赖，就要在此处添加相应的检测：

```c
/* target/riscv/cpu.c:1050 */

/*
 * Check consistency between chosen extensions while setting
 * cpu->cfg accordingly.
 */
void riscv_cpu_validate_set_extensions(RISCVCPU *cpu, Error **errp)
{
    CPURISCVState *env = &cpu->env;
    Error *local_err = NULL;

    /* Do some ISA extension error checking */
    if (riscv_has_ext(env, RVG) &&
        !(riscv_has_ext(env, RVI) && riscv_has_ext(env, RVM) &&
          riscv_has_ext(env, RVA) && riscv_has_ext(env, RVF) &&
          riscv_has_ext(env, RVD) &&
          cpu->cfg.ext_icsr && cpu->cfg.ext_ifencei)) {
        warn_report("Setting G will also set IMAFD_Zicsr_Zifencei");
        cpu->cfg.ext_icsr = true;
        cpu->cfg.ext_ifencei = true;

        env->misa_ext |= RVI | RVM | RVA | RVF | RVD;
        env->misa_ext_mask |= RVI | RVM | RVA | RVF | RVD;
    }

    if (riscv_has_ext(env, RVI) && riscv_has_ext(env, RVE)) {
        error_setg(errp,
                   "I and E extensions are incompatible");
        return;
    }

    // 此处省略部分代码
    // ...

    /*
     * Disable isa extensions based on priv spec after we
     * validated and set everything we need.
     */
    riscv_cpu_disable_priv_spec_isa_exts(cpu);
}
```

此外从 `target/riscv/cpu.c:84` 处注释中我们可以得知，单个字母表示的 ISA 扩展的检测在 `riscv_cpu_validate_misa_priv()` 中完成，该函数根据 Spec 版本检查了 H 扩展是否合法，如下所示：

```c
/* target/riscv/cpu.c:1384 */

static void riscv_cpu_validate_misa_priv(CPURISCVState *env, Error **errp)
{
    if (riscv_has_ext(env, RVH) && env->priv_ver < PRIV_VERSION_1_12_0) {
        error_setg(errp, "H extension requires priv spec 1.12.0");
        return;
    }
}
```

V 扩展的合法性检测由单独的函数完成，其中没有对 PRIV Spec 版本的检测，因为现在 QEMU 支持的 PRIV Spec 版本至少是 1.10.0，该版本已经支持了 V 向量扩展：

```c
/* target/riscv/cpu.c:937 */

static void riscv_cpu_validate_v(CPURISCVState *env, RISCVCPUConfig *cfg,
                                 Error **errp)
{
    int vext_version = VEXT_VERSION_1_00_0;

    if (!is_power_of_2(cfg->vlen)) {
        error_setg(errp, "Vector extension VLEN must be power of 2");
        return;
    }
    if (cfg->vlen > RV_VLEN_MAX || cfg->vlen < 128) {
        error_setg(errp,
                   "Vector extension implementation only supports VLEN "
                   "in the range [128, %d]", RV_VLEN_MAX);
        return;
    }
    if (!is_power_of_2(cfg->elen)) {
        error_setg(errp, "Vector extension ELEN must be power of 2");
        return;
    }
    if (cfg->elen > 64 || cfg->elen < 8) {
        error_setg(errp,
                   "Vector extension implementation only supports ELEN "
                   "in the range [8, 64]");
        return;
    }
    if (cfg->vext_spec) {
        if (!g_strcmp0(cfg->vext_spec, "v1.0")) {
            vext_version = VEXT_VERSION_1_00_0;
        } else {
            error_setg(errp, "Unsupported vector spec version '%s'",
                       cfg->vext_spec);
            return;
        }
    } else {
        qemu_log("vector version is not specified, "
                 "use the default value v1.0\n");
    }
    env->vext_ver = vext_version;
}
```

随后是对 PRIV Spec 版本的检测函数：

```c
/* target/riscv/cpu.c:977 */

static void riscv_cpu_validate_priv_spec(RISCVCPU *cpu, Error **errp)
{
    CPURISCVState *env = &cpu->env;
    int priv_version = -1;

    if (cpu->cfg.priv_spec) {
        if (!g_strcmp0(cpu->cfg.priv_spec, "v1.12.0")) {
            priv_version = PRIV_VERSION_1_12_0;
        } else if (!g_strcmp0(cpu->cfg.priv_spec, "v1.11.0")) {
            priv_version = PRIV_VERSION_1_11_0;
        } else if (!g_strcmp0(cpu->cfg.priv_spec, "v1.10.0")) {
            priv_version = PRIV_VERSION_1_10_0;
        } else {
            error_setg(errp,
                       "Unsupported privilege spec version '%s'",
                       cpu->cfg.priv_spec);
            return;
        }

        env->priv_ver = priv_version;
    }
}
```

`riscv_cpu_disable_priv_spec_isa_exts(cpu)` 函数在前面的代码中出现过，它会检测各个扩展的规范版本是否与 QEMU 当前模拟的 CPU 支持的 RISC-V PRIV Spec 版本号匹配，若当前 CPU 支持的 PRIV Spec 版本比某 ISA 扩展所需的最低 Spec 版本更旧，则关闭该扩展：

```c
/* target/riscv/cpu.c:1000 */

static void riscv_cpu_disable_priv_spec_isa_exts(RISCVCPU *cpu)
{
    CPURISCVState *env = &cpu->env;
    int i;

    /* Force disable extensions if priv spec version does not match */
    for (i = 0; i < ARRAY_SIZE(isa_edata_arr); i++) {
        if (isa_ext_is_enabled(cpu, &isa_edata_arr[i]) &&
            (env->priv_ver < isa_edata_arr[i].min_version)) {
            isa_ext_update_enabled(cpu, &isa_edata_arr[i], false);
#ifndef CONFIG_USER_ONLY
            warn_report("disabling %s extension for hart 0x" TARGET_FMT_lx
                        " because privilege spec version does not match",
                        isa_edata_arr[i].name, env->mhartid);
#else
            warn_report("disabling %s extension because "
                        "privilege spec version does not match",
                        isa_edata_arr[i].name);
#endif
        }
    }
}
```

完成上述初始化工作，标识了哪些扩展已经启用后，QEMU 就可以通过 `riscv_isa_string` 函数根据模拟的 misa 寄存器中的信息和 RISCVCPUConfig 结构体中的信息来判断启用了哪些扩展，并通过这个函数生成对应的 ISA 扩展组合字符串：

```c
/* target/riscv/cpu.c:2182 */

char *riscv_isa_string(RISCVCPU *cpu)
{
    int i;
    const size_t maxlen = sizeof("rv128") + sizeof(riscv_single_letter_exts);
    char *isa_str = g_new(char, maxlen);
    char *p = isa_str + snprintf(isa_str, maxlen, "rv%d", TARGET_LONG_BITS);
    for (i = 0; i < sizeof(riscv_single_letter_exts) - 1; i++) {
        if (cpu->env.misa_ext & RV(riscv_single_letter_exts[i])) {
            *p++ = qemu_tolower(riscv_single_letter_exts[i]);
        }
    }
    *p = '\0';
    if (!cpu->cfg.short_isa_string) {
        riscv_isa_string_ext(cpu, &isa_str, maxlen);
    }
    return isa_str;
}
```

其中，`riscv_isa_string_ext` 函数用于向 ISA 字符串中加入多字母扩展：

```c
/* target/riscv/cpu.c:2164 */

static void riscv_isa_string_ext(RISCVCPU *cpu, char **isa_str,
                                 int max_str_len)
{
    char *old = *isa_str;
    char *new = *isa_str;
    int i;

    for (i = 0; i < ARRAY_SIZE(isa_edata_arr); i++) {
        if (isa_ext_is_enabled(cpu, &isa_edata_arr[i])) {
            new = g_strconcat(old, "_", isa_edata_arr[i].name, NULL);
            g_free(old);
            old = new;
        }
    }

    *isa_str = new;
}
```

生成的 ISA-string 将会传递给设备树，以 QEMU RISC-V virt 设备为例：

```c
/* hw/riscv/virt.c:227 */

static void create_fdt_socket_cpus(RISCVVirtState *s, int socket,
                                   char *clust_name, uint32_t *phandle,
                                   uint32_t *intc_phandles)
{
    // 此处省略部分代码
    // ...
    for (cpu = s->soc[socket].num_harts - 1; cpu >= 0; cpu--) {
        // 此处省略部分代码
    	// ...
        name = riscv_isa_string(cpu_ptr);
        qemu_fdt_setprop_string(ms->fdt, cpu_name, "riscv,isa", name);
        g_free(name);
        // 此处省略部分代码
        // ...
    }
}
```

### TCG 前端

前端部分负责将目标代码翻译成 TCG ops。我们以用户模式的 QEMU 作为分析对象，借助 GDB 对这一流程进行分析。

首先随便用 C 或 C++ 写个程序，用 RISC-V 交叉编译工具链将其编译为 RISC-V 架构的程序。假设文件名为 test.cpp，再用 GDB 对用户模式 QEMU 进行调试：

```sh
$ riscv64-unknown-elf-g++ test.cpp -o test
$ gdb qemu-riscv64
(gdb) run test
```

借助 GDB，我们可以得到 TCG 前端的大致执行流程如下：

```sh
(gdb) bt
#0  0x000055555562d97b in decode_opc (opcode=<optimized out>, ctx=<optimized out>, env=<optimized out>) at ../target/riscv/translate.c:1134
#1  riscv_tr_translate_insn (dcbase=0x7fffffffd0a0, cpu=<optimized out>) at ../target/riscv/translate.c:1225
#2  0x000055555565f109 in translator_loop (cpu=cpu@entry=0x55555584f0c0, tb=tb@entry=0x7fffe8000040 <code_gen_buffer+19>, max_insns=max_insns@entry=0x7fffffffd224, pc=pc@entry=67678, host_pc=host_pc@entry=0x1085e,
    ops=ops@entry=0x5555557b8660 <riscv_tr_ops>, db=0x7fffffffd0a0) at ../accel/tcg/translator.c:180
#3  0x000055555562f0ec in gen_intermediate_code (cs=cs@entry=0x55555584f0c0, tb=tb@entry=0x7fffe8000040 <code_gen_buffer+19>, max_insns=max_insns@entry=0x7fffffffd224, pc=pc@entry=67678, host_pc=host_pc@entry=0x1085e)
    at ../target/riscv/translate.c:1292
#4  0x000055555565e0a0 in setjmp_gen_code (env=env@entry=0x55555584f3f0, tb=tb@entry=0x7fffe8000040 <code_gen_buffer+19>, pc=pc@entry=67678, host_pc=0x1085e, max_insns=max_insns@entry=0x7fffffffd224, ti=<optimized out>)
    at ../accel/tcg/translate-all.c:278
#5  0x000055555565e4f0 in tb_gen_code (cpu=cpu@entry=0x55555584f0c0, pc=67678, cs_base=0, flags=134365304, cflags=cflags@entry=0) at ../accel/tcg/translate-all.c:360
#6  0x000055555565693e in cpu_exec_loop (cpu=cpu@entry=0x55555584f0c0, sc=<optimized out>) at ../accel/tcg/cpu-exec.c:1005
#7  0x0000555555656b85 in cpu_exec_setjmp (cpu=cpu@entry=0x55555584f0c0, sc=<optimized out>) at ../accel/tcg/cpu-exec.c:1057
#8  0x0000555555657078 in cpu_exec (cpu=cpu@entry=0x55555584f0c0) at ../accel/tcg/cpu-exec.c:1083
#9  0x00005555555a4e08 in cpu_loop (env=env@entry=0x55555584f3f0) at ../linux-user/riscv/cpu_loop.c:37
#10 0x000055555559a874 in main (argc=<optimized out>, argv=0x7fffffffdb78, envp=<optimized out>) at ../linux-user/main.c:973

```

`translator_loop` 为指令翻译的主循环所在的函数，翻译时使用指定的 `translate_insn` 函数进行指令翻译。对于 RISC-V 架构来说，translate_insn 函数如下所示，为 `riscv_tr_translate_insn` 函数：

```c
/* target/riscv/translate.c */

static void riscv_tr_translate_insn(DisasContextBase *dcbase, CPUState *cpu)
{
    DisasContext *ctx = container_of(dcbase, DisasContext, base);
    CPURISCVState *env = cpu->env_ptr;
    uint16_t opcode16 = translator_lduw(env, &ctx->base, ctx->base.pc_next);

    ctx->ol = ctx->xl;
    decode_opc(env, ctx, opcode16);
    ctx->base.pc_next += ctx->cur_insn_len;

    /* Only the first insn within a TB is allowed to cross a page boundary. */
    if (ctx->base.is_jmp == DISAS_NEXT) {
        if (ctx->itrigger || !is_same_page(&ctx->base, ctx->base.pc_next)) {
            ctx->base.is_jmp = DISAS_TOO_MANY;
        } else {
            unsigned page_ofs = ctx->base.pc_next & ~TARGET_PAGE_MASK;

            if (page_ofs > TARGET_PAGE_SIZE - MAX_INSN_LEN) {
                uint16_t next_insn = cpu_lduw_code(env, ctx->base.pc_next);
                int len = insn_len(next_insn);

                if (!is_same_page(&ctx->base, ctx->base.pc_next + len - 1)) {
                    ctx->base.is_jmp = DISAS_TOO_MANY;
                }
            }
        }
    }
}
```

`decode_opc` 函数中会对是否启用了 C 扩展或 Zca 扩展进行判断，如果是，就使用 `decode_insn16` 函数对 16 位长度的 RISC-V 指令进行翻译，否则使用 `decodes[i].decode_func` 进行翻译，后者有三种可能的译码函数，decoders 的定义在 `decode_opc` 函数体中，如下所示：

```c
/* target/riscv/translate.c:1119 */
static void decode_opc(CPURISCVState *env, DisasContext *ctx, uint16_t opcode)
{
    /*
     * A table with predicate (i.e., guard) functions and decoder functions
     * that are tested in-order until a decoder matches onto the opcode.
     */
	static const struct {
        bool (*guard_func)(const RISCVCPUConfig *);
        bool (*decode_func)(DisasContext *, uint32_t);
    } decoders[] = {
        { always_true_p,  decode_insn32 },
        { has_xthead_p, decode_xthead },
        { has_XVentanaCondOps_p,  decode_XVentanaCodeOps },
    };
    ...
}
```

这些译码函数将对应长度的指令翻译成 TCG ops，译码函数由 QEMU 根据 `target/riscv` 目录下的 insn16.decode 与 insn32.decode 文件自动生成，生成的函数中调用了名称格式为 `trans_指令名` 的函数来生成对应的 TCG ops，这些 trans 函数的实现位于 `target/riscv/insn_trans` 目录下，不同类别的 ISA 扩展的 trans 函数放在不同的文件当中。

我们还是以 [向 QEMU 中添加 Zfa 扩展][004] 为例来说明一下上述流程，该 patch 在 `target/riscv/insn_trans` 目录下添加了 `trans_rvzfa.c.inc` 文件，该文件中包含了 Zfa 扩展所包含指令对应的 trans 函数。此外 Zfa 扩展包含的指令为 32 位长，需要在 `target/riscv/insn32.decode` 中添加对应指令的模式串，用于自动生成调用 trans 函数的 TCG 译码函数。

有关 decode 文件中模式串的具体格式以及 trans 函数的写法，可以参考 `docs/devel` 目录下的相关文档。

### TCG 后端

TCG 后端即将 TCG ops 翻译回宿主机能够执行的指令的部分，这里我们讨论的是宿主机为 RISC-V 架构的情况。

 上一小节讨论 TCG 前端流程时曾提到 `setjmp_gen_code` 函数，该函数如下所示：

```c
/* accel/tcg/translate-all.c:262 */

/*
 * Isolate the portion of code gen which can setjmp/longjmp.
 * Return the size of the generated code, or negative on error.
 */
static int setjmp_gen_code(CPUArchState *env, TranslationBlock *tb,
                           vaddr pc, void *host_pc,
                           int *max_insns, int64_t *ti)
{
    int ret = sigsetjmp(tcg_ctx->jmp_trans, 0);
    if (unlikely(ret != 0)) {
        return ret;
    }

    tcg_func_start(tcg_ctx);

    tcg_ctx->cpu = env_cpu(env);
    gen_intermediate_code(env_cpu(env), tb, max_insns, pc, host_pc);
    assert(tb->size != 0);
    tcg_ctx->cpu = NULL;
    *max_insns = tb->icount;

    return tcg_gen_code(tcg_ctx, tb, pc);
}
```

其在通过 `gen_intermediate_code` 函数生成 TCG ops 后，调用 `tcg_gen_code` 函数来将 TCG ops 翻译回 host 可以直接执行的指令。这个流程是各个架构通用的，在将 TCG ops 翻译回 RISC-V host 指令时同样使用这一流程。

`tcg_gen_code` 函数中会调用 `tcg_optimize` 对生成的 TCG ops 先进行优化，再进行后续翻译，此外还有一些与 log 相关的代码。

随后进入后端翻译的主循环：

```c
/* tcg/tcg.c:5910 */

int tcg_gen_code(TCGContext *s, TranslationBlock *tb, uint64_t pc_start)
{
    // 此处省略部分代码
    // ...
    // 后端翻译主循环
    QTAILQ_FOREACH(op, &s->ops, link) {
        TCGOpcode opc = op->opc;

        switch (opc) {
        case INDEX_op_mov_i32:
        case INDEX_op_mov_i64:
        case INDEX_op_mov_vec:
            tcg_reg_alloc_mov(s, op);
            break;
        case INDEX_op_dup_vec:
            tcg_reg_alloc_dup(s, op);
            break;
        case INDEX_op_insn_start:
            if (num_insns >= 0) {
                size_t off = tcg_current_code_size(s);
                s->gen_insn_end_off[num_insns] = off;
                /* Assert that we do not overflow our stored offset. */
                assert(s->gen_insn_end_off[num_insns] == off);
            }
            num_insns++;
            for (i = 0; i < start_words; ++i) {
                s->gen_insn_data[num_insns * start_words + i] =
                    tcg_get_insn_start_param(op, i);
            }
            break;
        case INDEX_op_discard:
            temp_dead(s, arg_temp(op->args[0]));
            break;
        case INDEX_op_set_label:
            tcg_reg_alloc_bb_end(s, s->reserved_regs);
            tcg_out_label(s, arg_label(op->args[0]));
            break;
        case INDEX_op_call:
            tcg_reg_alloc_call(s, op);
            break;
        case INDEX_op_exit_tb:
            tcg_out_exit_tb(s, op->args[0]);
            break;
        case INDEX_op_goto_tb:
            tcg_out_goto_tb(s, op->args[0]);
            break;
        case INDEX_op_dup2_vec:
            if (tcg_reg_alloc_dup2(s, op)) {
                break;
            }
            /* fall through */
        default:
            /* Sanity check that we've not introduced any unhandled opcodes. */
            tcg_debug_assert(tcg_op_supported(opc));
            /* Note: in order to speed up the code, it would be much
               faster to have specialized register allocator functions for
               some common argument patterns */
            tcg_reg_alloc_op(s, op);
            break;
        }
        // 此处省略部分代码
   	 	// ...
    }
}
```

QEMU 后端翻译时，通过 `QTAILQ_FOREACH` 循环从 QEMU 定义的数据结构中依次取出 TCG ops 进行翻译，一些特殊类型的 TCG ops 会在循环体中通过 `switch` 语句进行特判，其余 TCG ops 通过 `tcg_reg_alloc_op` 函数进行翻译。在该函数中生成 host 指令时，又有一个 switch 对一些 op 进行特判，其余情况使用 `tcg_out_op` 函数生成指令：

```c
/* tcg/tcg.c:4644 */

static void tcg_reg_alloc_op(TCGContext *s, const TCGOp *op)
{
    // 此处省略部分代码
    // ...

    /* emit instruction */
    switch (op->opc) {
    case INDEX_op_ext8s_i32:
        tcg_out_ext8s(s, TCG_TYPE_I32, new_args[0], new_args[1]);
        break;
    // 此处省略部分代码
    // ...
    case INDEX_op_extrl_i64_i32:
        tcg_out_extrl_i64_i32(s, new_args[0], new_args[1]);
        break;
    default:
        if (def->flags & TCG_OPF_VECTOR) {
            tcg_out_vec_op(s, op->opc, TCGOP_VECL(op), TCGOP_VECE(op),
                           new_args, const_args);
        } else {
            tcg_out_op(s, op->opc, new_args, const_args);
        }
        break;
    }
	// 此处省略部分代码
    // ...
}
```

在 `tcg/` 目录下包含有各个架构后端译码需要使用的代码，RISC-V 架构相关文件位于 `tcg/riscv` 目录下，包括 RISC-V host 所需的 `tcg_out_op` 函数，定义如下：

```c
static void tcg_out_op(TCGContext *s, TCGOpcode opc,
                       const TCGArg args[TCG_MAX_OP_ARGS],
                       const int const_args[TCG_MAX_OP_ARGS])
{
    TCGArg a0 = args[0];
    TCGArg a1 = args[1];
    TCGArg a2 = args[2];
    int c2 = const_args[2];

    switch (opc) {
    case INDEX_op_goto_ptr:
        tcg_out_opc_imm(s, OPC_JALR, TCG_REG_ZERO, a0, 0);
        break;
	// 此处省略部分代码
    // ...

    case INDEX_op_qemu_st_a64_i32:
        tcg_out_qemu_st(s, a0, a1, a2, TCG_TYPE_I32);
        break;
    case INDEX_op_qemu_st_a32_i64:
    case INDEX_op_qemu_st_a64_i64:
        tcg_out_qemu_st(s, a0, a1, a2, TCG_TYPE_I64);
        break;

    case INDEX_op_extrh_i64_i32:
        tcg_out_opc_imm(s, OPC_SRAI, a0, a1, 32);
        break;

    case INDEX_op_mulsh_i32:
    case INDEX_op_mulsh_i64:
        tcg_out_opc_reg(s, OPC_MULH, a0, a1, a2);
        break;

    case INDEX_op_muluh_i32:
    case INDEX_op_muluh_i64:
        tcg_out_opc_reg(s, OPC_MULHU, a0, a1, a2);
        break;
    case INDEX_op_mb:
        tcg_out_mb(s, a0);
        break;

    case INDEX_op_mov_i32:  /* Always emitted via tcg_out_mov. */
    case INDEX_op_mov_i64:
    case INDEX_op_call:     /* Always emitted via tcg_out_call. */
    case INDEX_op_exit_tb:  /* Always emitted via tcg_out_exit_tb. */
    case INDEX_op_goto_tb:  /* Always emitted via tcg_out_goto_tb. */
    case INDEX_op_ext8s_i32:  /* Always emitted via tcg_reg_alloc_op. */
    case INDEX_op_ext8s_i64:
    case INDEX_op_ext8u_i32:
    case INDEX_op_ext8u_i64:
    case INDEX_op_ext16s_i32:
    case INDEX_op_ext16s_i64:
    case INDEX_op_ext16u_i32:
    case INDEX_op_ext16u_i64:
    case INDEX_op_ext32s_i64:
    case INDEX_op_ext32u_i64:
    case INDEX_op_ext_i32_i64:
    case INDEX_op_extu_i32_i64:
    case INDEX_op_extrl_i64_i32:
    default:
        g_assert_not_reached();
    }
}
```

可以看到，生成 host 代码时调用了对应的 `tcg_out_` 函数，不同 host 架构的这些函数也有不同的实现，RISC-V host 的这些函数同样定义在 `tcg/riscv/tcg-target.c.inc` 文件中。该文件还包含了 RISC-V IM 等扩展相关指令的 opcode，以供这些译码函数使用：

```c
/* tcg/riscv/tcg-target.c.inc:188 */

/*
 * RISC-V Base ISA opcodes (IM)
 */

typedef enum {
    OPC_ADD = 0x33,
    OPC_ADDI = 0x13,
    OPC_AND = 0x7033,
    OPC_ANDI = 0x7013,
    OPC_AUIPC = 0x17,
    OPC_BEQ = 0x63,
    OPC_BGE = 0x5063,
    OPC_BGEU = 0x7063,
    OPC_BLT = 0x4063,
    OPC_BLTU = 0x6063,
    OPC_BNE = 0x1063,
    OPC_DIV = 0x2004033,
    OPC_DIVU = 0x2005033,
    OPC_JAL = 0x6f,
    OPC_JALR = 0x67,
    OPC_LB = 0x3,
    OPC_LBU = 0x4003,
    OPC_LD = 0x3003,
    OPC_LH = 0x1003,
    OPC_LHU = 0x5003,
    OPC_LUI = 0x37,
    OPC_LW = 0x2003,
    OPC_LWU = 0x6003,
    OPC_MUL = 0x2000033,
    OPC_MULH = 0x2001033,
    OPC_MULHSU = 0x2002033,
    OPC_MULHU = 0x2003033,
    OPC_OR = 0x6033,
    OPC_ORI = 0x6013,
    OPC_REM = 0x2006033,
    OPC_REMU = 0x2007033,
    OPC_SB = 0x23,
    OPC_SD = 0x3023,
    OPC_SH = 0x1023,
    OPC_SLL = 0x1033,
    OPC_SLLI = 0x1013,
    OPC_SLT = 0x2033,
    OPC_SLTI = 0x2013,
    OPC_SLTIU = 0x3013,
    OPC_SLTU = 0x3033,
    OPC_SRA = 0x40005033,
    OPC_SRAI = 0x40005013,
    OPC_SRL = 0x5033,
    OPC_SRLI = 0x5013,
    OPC_SUB = 0x40000033,
    OPC_SW = 0x2023,
    OPC_XOR = 0x4033,
    OPC_XORI = 0x4013,

    OPC_ADDIW = 0x1b,
    OPC_ADDW = 0x3b,
    OPC_DIVUW = 0x200503b,
    OPC_DIVW = 0x200403b,
    OPC_MULW = 0x200003b,
    OPC_REMUW = 0x200703b,
    OPC_REMW = 0x200603b,
    OPC_SLLIW = 0x101b,
    OPC_SLLW = 0x103b,
    OPC_SRAIW = 0x4000501b,
    OPC_SRAW = 0x4000503b,
    OPC_SRLIW = 0x501b,
    OPC_SRLW = 0x503b,
    OPC_SUBW = 0x4000003b,

    OPC_FENCE = 0x0000000f,
    OPC_NOP   = OPC_ADDI,   /* nop = addi r0,r0,0 */

    /* Zba: Bit manipulation extension, address generation */
    OPC_ADD_UW = 0x0800003b,

    /* Zbb: Bit manipulation extension, basic bit manipulaton */
    OPC_ANDN   = 0x40007033,
    OPC_CLZ    = 0x60001013,
    OPC_CLZW   = 0x6000101b,
    OPC_CPOP   = 0x60201013,
    OPC_CPOPW  = 0x6020101b,
    OPC_CTZ    = 0x60101013,
    OPC_CTZW   = 0x6010101b,
    OPC_ORN    = 0x40006033,
    OPC_REV8   = 0x6b805013,
    OPC_ROL    = 0x60001033,
    OPC_ROLW   = 0x6000103b,
    OPC_ROR    = 0x60005033,
    OPC_RORW   = 0x6000503b,
    OPC_RORI   = 0x60005013,
    OPC_RORIW  = 0x6000501b,
    OPC_SEXT_B = 0x60401013,
    OPC_SEXT_H = 0x60501013,
    OPC_XNOR   = 0x40004033,
    OPC_ZEXT_H = 0x0800403b,

    /* Zicond: integer conditional operations */
    OPC_CZERO_EQZ = 0x0e005033,
    OPC_CZERO_NEZ = 0x0e007033,
} RISCVInsn;

```

从后端代码文件定义的这些 OPC 中可以看出，QEMU 后端目前并没有对很多扩展提供支持，仅定义了 I、M、Zba、Zbb、Zicond 等扩展所包含指令的 opcode。

## 总结

通过对 QEMU 文档和部分代码进行分析，我们可以得出以下结论：

- QEMU 是否对 RISC-V 扩展提供支持，是遵循一定规则的

- QEMU 可以模拟的 RISC-V 扩展数量丰富

- QEMU TCG 后端所生成的 RISC-V 代码仅用到了少数 RISC-V 扩展，大多数向 QEMU 添加扩展的 patch 仅添加了使用 QEMU 在其它处理器架构上模拟该扩展指令的功能

此外，QEMU 还有反汇编器和测试文件，向 QEMU 中添加对 ISA 扩展的支持时，有可能也需要在这两部分进行对应的修改，本文并未进行相关分析。

之后的文章将接着从 OpenSBI，Linux 等软件的角度分析 RISC-V 扩展的支持现状。

## 参考资料

- [QEMU 及 RISC-V 启动流程简介][001]
- [TCG-QEMU wiki][002]
- [QEMU TCG 文档][003]
- [riscv: Add support for the Zfa extension][004]
- [在 QEMU 里增加指令的前端解码 - wangzhou 的博客][005]

[001]: https://gitee.com/tinylab/riscv-linux/blob/master/articles/20220816-introduction-to-qemu-and-riscv-upstream-boot-flow.md
[002]: https://wiki.qemu.org/Documentation/TCG
[003]: https://gitlab.com/qemu-project/qemu/-/blob/master/docs/devel/tcg.rst
[004]: https://gitlab.com/qemu-project/qemu/-/commit/a47842d16653b4f73b5d56ff0c252dd8a329481b
[005]: https://wangzhou.github.io/%E5%9C%A8qemu%E9%87%8C%E5%A2%9E%E5%8A%A0%E6%8C%87%E4%BB%A4%E7%9A%84%E5%89%8D%E7%AB%AF%E8%A7%A3%E7%A0%81/
