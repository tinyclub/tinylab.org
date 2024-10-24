---
layout: post
author: 'sugarfillet'
title: 'RISC-V 休眠实现分析 3 -- 恢复系统'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-hibernation-impl-3/
description: 'RISC-V 休眠实现分析 3 -- 恢复系统'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - swap
  - suspend
  - restore
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces header codeinline pangu autocorrect]
> Author:    sugarfillet <sugarfillet@yeah.net>
> Date:      2023/05/27
> Revisor:   Falcon falcon@tinylab.org
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V Linux SMP 技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I5MU96)
> Sponsor:   PLCT Lab, ISCAS


## 前言

上文介绍了 swap 镜像的加载过程，整个过程主要使用 `snapshot_write_next` 和 `swap_read_page` 两个接口进行唤醒镜像的构建。同时，留下了两个小问题：

1. 在 `swsusp_read` 的后续流程中，如何使用 `resume_hdr`
2. 如何对 `retore_pblist` 链表进行页拷贝

本文继续分析 `software_resume => load_image_and_restore` 中的 `hibernation_restore` 函数，并在分析过程中，解答以上两个问题。

**说明**：

- 本文的 Linux 版本采用 `Linux v6.4-rc1`

## hibernation_restore

在 `swsusp_read` 加载完 swap 镜像之后，`load_image_and_restore` 函数调用 `hibernation_restore` 恢复系统状态。执行一些准备工作，比如：切换到挂起控制台、关闭非 `sleep_cpu` 的 CPU、关中断，最后执行架构级的唤醒函数 -- `swsusp_arch_resume`，如果执行失败，则恢复当前系统状态，如果执行成功，`swsusp_arch_resume` 会返回到架构级的休眠触发函数 `swsusp_arch_suspend` 处执行。

```c
// kernel/power/hibernate.c : 1367

hibernation_restore()
      suspend_console();

      resume_target_kernel()
        hibernate_resume_nonboot_cpu_disable(); // disable nonboot_cpu  call freeze_secondary_cpus
          freeze_secondary_cpus(sleep_cpu);
        local_irq_disable();
        system_state = SYSTEM_SUSPEND;
        save_processor_state();

        swsusp_arch_resume // execution continues at the place where * swsusp_arch_suspend() was called.

        swsusp_free();
        restore_processor_state();
        system_state = SYSTEM_RUNNING;
```

## swsusp_arch_resume

此函数是在唤醒核心流程基础上的架构支持，主要执行以下过程：

1. 为线性地址空间 `PAGE_OFFSET -- pfn_to_virt(max_low_pfn)` 建立临时映射根页表 -- `resume_pg_dir`

   其实是在复制 lowmem 在当前的根页表的映射，不过页表的权限变更为可写，为后续 `restore_pblist` 链表的页拷贝提供条件

2. 拷贝 `hibernate_core_restore_code` 到唤醒镜像分配的安全页空间 -- `safe_pages_list` 中，以 `relocated_restore_code` 地址返回

   后续 `restore_pblist` 链表的页拷贝可能会覆盖 `hibernate_core_restore_code` 原始地址，保存在 safe page 中避免覆盖

3. 为从 `arch_hibernation_header_restore()` 获取到的 `resume_hdr.restore_cpu_addr` 地址在临时页表建立映射

   如果不映射，切换到临时映射后，会找不到保存的恢复地址 `resume_hdr.restore_cpu_addr` -- `__hibernate_cpu_resume`

4. 调用 `hibernate_restore_image` 汇编函数，设置相关参数，跳转到步骤 2 的 `hibernate_core_restore_code`

   休眠镜像保存的根页表：`resume_hdr.saved_satp`、临时映射根页表 `resumepg_dir | satp_mode`、保存的恢复地址 `__hibernate_cpu_resume`、构建唤醒镜像时遗留的 `restore_pblist`

```c
// arch/riscv/kernel/hibernate.c : 394

swsusp_arch_resume()

  unsigned long end = (unsigned long)pfn_to_virt(max_low_pfn);
  unsigned long start = PAGE_OFFSET;

  resume_pg_dir = (pgd_t *)get_safe_page(GFP_ATOMIC);

  // remap whole linear region
  temp_pgtable_mapping(resume_pg_dir, start, end, __pgprot(_PAGE_WRITE | _PAGE_EXEC));
    pgd_t *dst_pgdp = pgd_offset_pgd(pgdp, start);
    pgd_t *src_pgdp = pgd_offset_k(start);

    if (pgd_leaf(pgd))
      set_pgd(dst_pgdp, __pgd(pgd_val(pgd) | pgprot_val(prot))); // 如果当前根页表是叶子（物理地址直接存放在 pgd 中），则复制表项到当前虚拟地址在 resume_pg_dir 对应的表项 -- `dst_pgdp`
    else
      ret = temp_pgtable_map_p4d(dst_pgdp, src_pgdp, start, next, prot); // 否则递归设置 p4d/pud/pmd/pte

  /* Move the restore code to a new page so that it doesn't get overwritten by itself. */

  relocated_restore_code = relocate_restore_code();  // 拷贝 hibernate_core_restore_code 到唤醒镜像的 `safe_pages_list`
    void *page = (void *)get_safe_page(GFP_ATOMIC);
    copy_page(page, hibernate_core_restore_code);
    return page;

  start = (unsigned long)resume_hdr.restore_cpu_addr; // __hibernate_cpu_resume
  end = start + PAGE_SIZE;
  temp_pgtable_mapping(resume_pg_dir, start, end, __pgprot(_PAGE_WRITE));

// arch/riscv/kernel/hibernate-asm.S" 76L

  hibernate_restore_image(resume_hdr.saved_satp, (PFN_DOWN(__pa(resume_pg_dir)) | satp_mode), resume_hdr.restore_cpu_addr);
    mv      s0, a0  // resume_hdr.saved_satp
    mv      s1, a1  // resumepg_dir with satp_mod
    mv      s2, a2  // __hibernate_cpu_resume
    REG_L   s4, restore_pblist
    REG_L   a1, relocated_restore_code  // goto hibernate_core_restore_code
    jalr    a1
```

## hibernate_core_restore_code

`hibernate_core_restore_code` 汇编函数负责在临时页表下对 `restore_pblist` 进行页拷贝。首先切换到临时根页表，遍历 `struct pbe * restore_pblist` 链表，拷贝 `address` 成员到 `orig_address` 成员，最后跳转到保存的恢复地址 `__hibernate_cpu_resume`。

```c
// arch/riscv/kernel/hibernate-asm.S : 61

ENTRY(hibernate_core_restore_code)
        /* switch to temp page table. */
        csrw satp, s1
        sfence.vma
.Lcopy:
        /* The below code will restore the hibernated image. */
        REG_L   a1, HIBERN_PBE_ADDR(s4)   // restore_pblist struct pbe
        REG_L   a0, HIBERN_PBE_ORIG(s4)

        copy_page a0, a1

        REG_L   s4, HIBERN_PBE_NEXT(s4)
        bnez    s4, .Lcopy

        jalr    s2  // goto __hibernate_cpu_resume
END(hibernate_core_restore_code)

```

`__hibernate_cpu_resume` 汇编函数切换到休眠镜像中保存的根页表，并根据保存的 `hibernate_cpu_context` 逐个还原对应的寄存器，最后以 0 返回。这里 `ret` 返回的地址（ra 寄存器）存放的地址就是 `swsusp_arch_suspend()` 函数中做判断的地址，以 0 返回的话，就执行其中的 `else` 分支。

> 由于在 `swsusp_arch_suspend.else` 中也会调用 `suspend_restore_csrs`，且两次调用之间没有 `sfence.vma` 指令，所以第一个是多余的。这里提了个 [补丁][1] 删除它。

```c
// arch/riscv/kernel/hibernate-asm.S : 76

ENTRY(__hibernate_cpu_resume)
        /* switch to hibernated image's page table. */
        csrw CSR_SATP, s0  // saved_satp
        sfence.vma

        REG_L   a0, hibernate_cpu_context

        suspend_restore_csrs  // 多余的
        suspend_restore_regs

        /* Return zero value. */
        mv      a0, zero

        ret  // ra is the else in swsusp_arch_suspend()
END(__hibernate_cpu_resume)

```

`swsusp_arch_suspend` 的 `else` 分支还原 `hibernate_cpu_context.{scratch,tvec,ie,satp}` 刷新 TLB 和 icache（这里相当于又切换到了 `hibernate_cpu_context.satp 保存的页表`），最后设置 `in_suspend = 0` 和 `sleep_cpu = -EINVAL` 用来控制返回的休眠核心代码执行“休眠镜像恢复成功”的逻辑，返回路径为：`swsusp_arch_suspend.else => create_image => hibernation_snapshot => hibernate`。

```c
// arch/riscv/kernel/hibernate.c : 468

int swsusp_arch_suspend(void)
{
        int ret = 0;

        if (__cpu_suspend_enter(hibernate_cpu_context)) {  // save hibernate_cpu_context->regs return 1
                sleep_cpu = smp_processor_id();
                suspend_save_csrs(hibernate_cpu_context);  // save hibernate_cpu_context->{scratch,tvec,ie,satp}
                ret = swsusp_save();
        } else {                                           // 系统恢复，跳转到这里执行
                suspend_restore_csrs(hibernate_cpu_context); // restore hibernate_cpu_context->{scratch,tvec,ie,satp}
                flush_tlb_all();
                flush_icache_all();

                /*
                 * Tell the hibernation core that we've just restored the memory.
                 */
                in_suspend = 0;
                sleep_cpu = -EINVAL;
        }

        return ret;
}

```

## 小结

本系列文章分析了 Linux 休眠/唤醒的核心代码及其在 RISC-V 架构上的实现。整个休眠唤醒机制的核心功能在于如何构建休眠镜像和唤醒镜像及其与 swap 设备的交互，第一篇并没有过多的介绍休眠镜像的写入 swap 的过程，但本系列的第二篇为了解读 `restore_pblist` 的必要性对唤醒镜像的构建做了比较详细的分析，读者可以对比第二篇进行理解。RISC-V 架构在 Linux v6.4-rc1 上实现了休眠功能的基本支持，经过三篇文章的分析，我们可看到其更多代码用在了基于唤醒镜像恢复系统的过程中。

最后，总结一下 Linux 休眠/唤醒的整个流程图，希望对你有所帮助。

```c
      hibernate <=> hibernation_snapshot       <=> create_image         <=> swsusp_arch_suspend.if <=> swsusp_save
                 => swsusp_write && power_down                          ^
                                                                        |
                                                                        -------------------------------------------------------
software_resume => swsusp_read                                                                                                |
                => hibernation_restore          => resume_target_kernel  => swsusp_arch_resume =>  __hibernate_cpu_resume => swsusp_arch_suspend.else
```

## 参考资料

- [[PATCH V2] riscv: hibernation: Remove duplicate call of suspend_restore_csrs][1]
- [[PATCH v8 0/4] RISC-V Hibernation Support][2]

[1]: https://lore.kernel.org/linux-riscv/20230522025020.285042-1-songshuaishuai@tinylab.org/T/#u
[2]: https://lore.kernel.org/all/20230330064321.1008373-5-jeeheng.sia@starfivetech.com/
