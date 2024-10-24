---
layout: post
author: 'sugarfillet'
title: 'RISC-V Linux 内核 UEFI 启动过程分析（Part2）：内核侧 UEFI 支持'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-linux-uefi-boot-2/
description: 'RISC-V Linux 内核 UEFI 启动过程分析（Part2）：内核侧 UEFI 支持'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - UEFI
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces header toc codeinline pangu epw]
> Author:    sugarfillet <sugarfillet@yeah.net>
> Date:      2023/04/21
> Revisor:   Falcon falcon@tinylab.org
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V UEFI 启动流程分析与 EDK2 移植](https://gitee.com/tinylab/riscv-linux/issues/I64FSG)
> Sponsor:   PLCT Lab, ISCAS


## 前言

上文对 RISC-V Linux 的 EFI Boot Stub 进行了介绍，它给正式内核传递了不少的信息。本文趁热打铁，继续分析正式内核的 UEFI 初始化相关流程。

*说明*
 - Linux 版本采用 v6.3

## UEFI 初始化 -- efi_init

Linux EFI Boot Stub 以 `boothardid` 和修改了 `chosen` 变量的 fdt 跳转到 `_start` 启动正式内核。正式内核在 `setup_arch()` 阶段调用 `efi_init()` 进行 EFI 的初始化。整体来看，`efi_init()` 的主要工作有两个，一个是对 UEFI 系统表的处理，包括运行时服务的保存、配置表的解析和初步处理；还有一个是把从 UEFI Boot Stub 传递过来的 UEFI 内存映射表交接给 memblock。此函数的关键过程按序分析如下：

> `memblock` 是内核启动初期用于管理内存的机制，主要将可用、保留以及不可用的物理内存进行划分和管理，后续会移交管理权给伙伴系统。
>
> Linux 维护一个 `struct memblock memblock` 实体，其中 `memblock.memory` 描述了 `memblock` 管理的可用内存，`memblock.reserved` 描述了 `memblock` 管理的预留内存

`efi_get_fdt_params()` 函数以 `dt_params` 全局变量匹配 fdt 中的 `chosen` 变量，保存内存映射表信息到 `struct efi_memory_map_data` 实例中，并返回 UEFI 系统表的物理地址。

`efi_memmap_init_early()` 函数重新以 `struct efi_memory_map` 结构保存内存映射表，其中 `map` 成员为映射表的虚拟地址，通过 `early_memremap()` 函数在 fixed-mapping 中创建页表映射，最终记录到 `efi.memap` 全局结构中。

```c
// include/linux/efi.h : 547

struct efi_memory_map_data {
        phys_addr_t phys_map;
        unsigned long size;
        unsigned long desc_version;
        unsigned long desc_size;
        unsigned long flags;
};

struct efi_memory_map {
        phys_addr_t phys_map;
        void *map;
        void *map_end;
        int nr_map;
        unsigned long desc_version;
        unsigned long desc_size;
        unsigned long flags;
};
```

```c
// drivers/firmware/efi/fdtparams.c : 35

static __initconst const struct {
        const char      path[17];
        u8              paravirt;
        const char      params[PARAMCOUNT][26];
} dt_params[] = {

                .path = "/chosen",
                .params = {     //  <-----------26----------->
                        [SYSTAB] = "linux,uefi-system-table",
                        [MMBASE] = "linux,uefi-mmap-start",
                        [MMSIZE] = "linux,uefi-mmap-size",
                        [DCSIZE] = "linux,uefi-mmap-desc-size",
                        [DCVERS] = "linux,uefi-mmap-desc-ver",
                }
}

// drivers/firmware/efi/efi-init.c :199

efi_init()
  // Grab UEFI information placed in FDT by stub
  efi_system_table = efi_get_fdt_params(&data); // struct efi_memory_map_data * data
      return systab;

  efi_memmap_init_early(&data)
    struct efi_memory_map map;
    map.map = early_memremap(data->phys_map, data->size); // 内存映射表的虚拟地址
    set_bit(EFI_MEMMAP, &efi.flags); // we use EFI memory map
    efi.memmap = map
```

`uefi_init()` 函数用于处理 UEFI 系统表，保存运行时服务到 `efi.runtime`；调用 `efi_config_parse_tables()` 函数以 `common_tables` 为参照，保存配置表到对应的变量中进行部分初步处理，比如：

- `LINUX_EFI_INITRD_MEDIA_GUID` 表保存到 initrd 变量中，initrd 地址和大小分别保存到 `phys_initrd_start`、`phys_initrd_size`
- `EFI_RT_PROPERTIES_TABLE_GUID` 表代表 UEFI 运行时所支持的服务，通过 `rt_prop` 进一步更新到 `efi.runtime_supported_mask`
- `LINUX_EFI_MEMRESERVE_TABLE_GUID` 表代 UEFI 所保留的物理内存空间，调用 `memblock_reserve()` 接口将其更新到 `memblock.reserved` 中

而其他的一些变量，比如 `efi.acpi*` 则在 `setup_arch()` 的后续流程 `acpi_boot_table_init()` 中处理。

```c
efi_init()
  // drivers/firmware/efi/efi-init.c : 78
  uefi_init(efi_system_table)
    systab = early_memremap_ro(efi_system_table // remap systable
    set_bit(EFI_BOOT, &efi.flags);
    set_bit(EFI_64BIT, &efi.flags);

    efi.runtime = systab->runtime;

    config_tables = early_memremap_ro(efi_to_phys(systab->tables), table_size); // remap conftable
    efi_config_parse_tables(config_tables, systab->nr_tables, efi_arch_tables);
      match_config_table(guid, table, common_tables) // 解析 common_tables (ACPI/SMBIOS/ESRT/INITRD/MEMRESERVE)
      set_bit(EFI_CONFIG_TABLES, &efi.flags);

      // 处理 efi_rng_seed mem_reserve rt_prop initrd ...

      // set the reserved memory in the memblock.reserved
      memblock_reserve(prsv, struct_size(rsv, entry, rsv->size));

static const efi_config_table_type_t common_tables[] __initconst = {
        {ACPI_20_TABLE_GUID,                    &efi.acpi20,            "ACPI 2.0"      },
        {ACPI_TABLE_GUID,                       &efi.acpi,              "ACPI"          },
        {SMBIOS_TABLE_GUID,                     &efi.smbios,            "SMBIOS"        },
        {SMBIOS3_TABLE_GUID,                    &efi.smbios3,           "SMBIOS 3.0"    },
        {EFI_SYSTEM_RESOURCE_TABLE_GUID,        &efi.esrt,              "ESRT"          },
        {EFI_MEMORY_ATTRIBUTES_TABLE_GUID,      &efi_mem_attr_table,    "MEMATTR"       },
        {LINUX_EFI_RANDOM_SEED_TABLE_GUID,      &efi_rng_seed,          "RNG"           },
        // ...
        {LINUX_EFI_MEMRESERVE_TABLE_GUID,       &mem_reserve,           "MEMRESERVE"    },
        {LINUX_EFI_INITRD_MEDIA_GUID,           &initrd,                "INITRD"        },
        {EFI_RT_PROPERTIES_TABLE_GUID,          &rt_prop,               "RTPROP"        },
        // ...
}
```

`reserve_regions()` 函数首先清空从 dtb 中构建的 memblock，之后遍历 UEFI 内存描述表 (efi.memmap)，对于在 [MIN_MEMBLOCK_ADDR,MAX_MEMBLOCK_ADDR] 范围内的内存执行 `memblock_add()` 添加到 `memblock.memory` 类型中，并对那些不可用的内存（比如：用于 Runtime Services 的内存、用于特殊目的的内存 `EFI_MEMORY_SP` 等等）调用 `memblock_mark_nomap()` 设置其内存区域（memblock region）标志位为 `MEMBLOCK_NOMAP`，此标志位表示此内存区域不用于内存映射。

`efi_init()` 继续执行从 UEFI 内存映射表到 memblock 的交接工作，篇幅有限，这里不一一列举：

- `early_init_dt_check_for_usable_mem_range()` 函数解析 dtb 中的 `linux,usable-memory-range` 节点，并修饰 memblock，此节点描述用于内核 kdump 的内存范围
- `efi_find_mirror()` 函数根据 UEFI 内存标志位 `EFI_MEMORY_MORE_RELIABLE` 处理高可靠内存，调用 `memblock_mark_mirror()` 设置 `MEMBLOCK_MIRROR` 标志位
- `init_screen_info()` 函数处理 UEFI 屏幕信息 `struct screen_info` 的物理地址 `screen_info.lfb_base`，在 memblock 中设置为 `MEMBLOCK_NOMAP`

```c
efi_init()
  //drivers/firmware/efi/efi-init.c : 155

  reserve_regions()
    // discard memblock which originated from memory nodes in the DT
    memblock_dump_all(); && memblock_remove(0, PHYS_ADDR_MAX);

    for_each_efi_memory_desc(md)
      early_init_dt_add_memory_arch()
        memblock_add(md->phys_addr, size);
      !is_usable_memory(md) && memblock_mark_nomap()  // nomap some ram

  early_init_dt_check_for_usable_mem_range() // 处理 linux,usable-memory-range
  efi_find_mirror()  // 处理高可靠内存 EFI_MEMORY_MORE_RELIABLE
  efi_esrt_init()  // Reserving ESRT space in memblock.reserved
  efi_mokvar_table_init(); // 处理 EFI MOK config table
  memblock_reserve(data.phys_map & PAGE_MASK, PAGE_ALIGN(data.size + (data.phys_map & ~PAGE_MASK))); // 设置 UEFI 内存映射表到 memblock.reserved
  init_screen_info() // 处理 screen_info_table
```

## UEFI 运行时服务

### UEFI 运行时服务初始化

`riscv_enable_runtime_services()` 为 RISC-V 架构下 UEFI Runtime Services 初始化函数，主要执行如下流程：

对于 UEFI 内存映射表的内存映射，存在两个版本：一个是调用 `efi_memmap_init_early()` 以 fixed-mapping 空间进行早期映射，另一个调用 `efi_memmap_init_late()` 在 vmalloc 空间进行后期映射。两个函数都调用 `__efi_memmap_init()` 函数，以传入的参数中是否有 `EFI_MEMMAP_LATE` 标志为条件分别调用 `early_memremap()`, `memremap()`。

在 `efi_init()` 阶段完成早期映射，考虑到 fixed-mapping 空间的稀缺性，在当前阶段调用 `efi_memmap_unmap()` 解除早期映射，并调用 `efi_memmap_init_late()` 对 UEFI 内存映射表进行后期映射。

`efi_virtmap_init` 对 `efi_mm` 进行初始化，首先为其分配页目录项，之后遍历 UEFI 内存映射表，对 `EFI_MEMORY_RUNTIME` 类型的内存描述符，执行 `efi_create_mapping(&efi_mm, md)` 创建 `md->virt_addr` 到 `md->phys_addr` 的页表映射（这里的虚拟地址 `md->virt_addr` 正是在 EFI Boot Stub 基于 `EFI_RT_VIRTUAL_OFFSET` 计算的）；最后调用 `efi_memattr_apply_permissions()` 基于 UEFI 内存属性配置表 -- `efi_mem_attr_table` 对虚拟地址进行权限设置。如果设置了 `efi=debug` 命令行选项，可以看到这样的输出：

```
[    0.115472] Remapping and enabling EFI services.
[    0.122078] efi: memattr: Processing EFI Memory Attributes table:
[    0.122844] efi: memattr:  0x0000ffe3d000-0x0000ffe8dfff [Runtime Code|RUN|  |  |  |  |XP|  |  |  |   |  |  |  |  ]
[    0.124471] efi: memattr:  0x0000ffe8e000-0x0000ffe8ffff [Runtime Code|RUN|  |  |  |  |  |  |  |RO|   |  |  |  |  ]
[    0.125622] efi: memattr:  0x0000ffe90000-0x0000ffe92fff [Runtime Code|RUN|  |  |  |  |XP|  |  |  |   |  |  |  |  ]
[    0.126453] efi: memattr:  0x0000ffe93000-0x0000ffe95fff [Runtime Code|RUN|  |  |  |  |  |  |  |RO|   |  |  |  |  ]
...
```

`efi_native_runtime_setup()` 函数负责对 `efi` 变量中的 Runtime Services 函数进行设置，比如：设置 `efi.get_time = virt_efi_get_time`),而其他的模块（比如：rtc-efi -- `drivers/rtc/rtc-efi.c`）则可通过 `efi.get_time` 来获取固件提供的时间。

```c
// drivers/firmware/efi/riscv-runtime.c : 66

early_initcall(riscv_enable_runtime_services);

riscv_enable_runtime_services()

  efi_memmap_unmap();
    early_memunmap(efi.memmap.map, size); // clear the early EFI memmap
    efi.memmap.map = NULL;
    clear_bit(EFI_MEMMAP, &efi.flags);

  // EFI map 有两个初始化
  // 早期初始化（efi_init/efi_memmap_init_early -> early_memremap）使用稀缺的 fixmap 空间
  // 后期初始化（efi_memmap_init_late -> memremap）使用 vmalloc 空间
  efi_memmap_init_late(efi.memmap.phys_map, mapsize)

  // Remapping and enabling EFI services
  efi_virtmap_init()

    efi_mm.pgd = pgd_alloc(&efi_mm);
    for_each_efi_memory_desc(md)
      if (md->attribute & EFI_MEMORY_RUNTIME)  efi_create_mapping(&efi_mm, md);
        for (i = 0; i < md->num_pages; i++)
          create_pgd_mapping(mm->pgd, md->virt_addr + i * PAGE_SIZE, md->phys_addr + i * PAGE_SIZE, PAGE_SIZE, prot);

    efi_memattr_apply_permissions(&efi_mm, efi_set_mapping_permissions)
      tbl = memremap(efi_mem_attr_table, tbl_size, MEMREMAP_WB); // 映射内存属性表
      efi_set_mapping_permissions(mm, &md, has_bti);       // print EFI memmap attr table
        apply_to_page_range(mm, md->virt_addr, md->num_pages << EFI_PAGE_SHIFT, set_permissions, md); // 对 vm 设置权限，底层实现为设置 pte_val(pte)

  efi_native_runtime_setup() // efi.get_time = virt_efi_get_time // efi.reset_system = virt_efi_reset_system
  set_bit(EFI_RUNTIME_SERVICES, &efi.flags);
```

### UEFI 运行时服务函数

我们以获取系统时间函数 -- `virt_efi_get_time()` 为例进行分析，此函数内部使用 `efi_queue_work` 宏，此宏对传入的参数保存到 `struct efi_runtime_work efi_rts_work` 全局变量中，同时保存当前运行时服务 ID 到 `efi_rts_work.efi_rts_id`，并以 `efi_call_rts` 函数初始化工作 `struct work_struct &efi_rts_work.work`，插入工作队列 `efi_rts_wq`，之后等待工作队列函数释放 `&efi_rts_work.efi_rts_comp` 完成变量。

`efi_call_rts` 函数根据保存的运行时服务 ID 调用对应的运行时服务，并释放完成变量。运行时服务的调用过程分为三个阶段：

1. `arch_efi_call_virt_setup()` 以 `efi_mm.pgd` 设置内核根页目录项，并调用 `efi_virtmap_load` 切换当前进程的内存上下文为 `efi_mm`
2. `arch_efi_call_virt(efi.runtime, get_time, args)` 调用 UEFI 提供的运行时服务 `efi.runtime.get_time()`
3. `arch_efi_call_virt_teardown()` 调用 `efi_virtmap_unload()` 恢复进程的内存上下文

关键代码摘录如下：

```c
// include/linux/efi.h : 1249

struct efi_runtime_work {
        void *arg1;
        void *arg2;
        void *arg3;
        void *arg4;
        void *arg5;
        efi_status_t status;
        struct work_struct work;
        enum efi_rts_ids efi_rts_id;
        struct completion efi_rts_comp;
};

// drivers/firmware/efi/runtime-wrappers.c : 253

static efi_status_t virt_efi_get_time(efi_time_t *tm, efi_time_cap_t *tc)
  status = efi_queue_work(EFI_GET_TIME, tm, tc, NULL, NULL, NULL); //
    init_completion(&efi_rts_work.efi_rts_comp);
    INIT_WORK(&efi_rts_work.work, efi_call_rts);
    efi_rts_work.arg1 = _arg1;
    //...
    efi_rts_work.efi_rts_id = _rts;
    if (queue_work(efi_rts_wq, &efi_rts_work.work))
      wait_for_completion(&efi_rts_work.efi_rts_comp);

// drivers/firmware/efi/runtime-wrappers.c : 174

void efi_call_rts(struct work_struct *work)

  switch (efi_rts_work.efi_rts_id) {
    case EFI_GET_TIME:
      status = efi_call_virt(get_time, (efi_time_t *)arg1, (efi_time_cap_t *)arg2);
        efi_call_virt_pointer(efi.runtime, f, args)

          arch_efi_call_virt_setup()
            sync_kernel_mappings(efi_mm.pgd);
            efi_virtmap_load(); // switch_mm

          arch_efi_call_virt(efi.runtime,f,args)
            // call efi.runtime.get_time
          arch_efi_call_virt_teardown()
```

## 小结

本文介绍了 RISC-V Linux 内核在加载并启动后的 UEFI 初始化流程，包括从 UEFI 内存映射表到 memblock 分配器的交接过程、UEFI 配置表的部分解析过程，以及 UEFI 运行时服务的初始化和调用过程，希望对你有帮助。

## 参考资料

- [memblock 内存分配器原理和代码分析][1]

[1]: https://tinylab.org/riscv-memblock/
