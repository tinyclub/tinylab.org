---
layout: post
author: 'sugarfillet'
title: 'RISC-V 休眠实现分析 2 -- 加载 swap 镜像'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-hibernation-impl-2/
description: 'RISC-V 休眠实现分析 2 -- 加载 swap 镜像'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - Hibernation
  - 休眠
  - 唤醒
  - swap
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces header codeblock codeinline pangu]
> Author:    sugarfillet <sugarfillet@yeah.net>
> Date:      2023/05/27
> Revisor:   Falcon falcon@tinylab.org
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V Linux SMP 技术调研与分析](https://gitee.com/tinylab/riscv-linux/issues/I5MU96)
> Sponsor:   PLCT Lab, ISCAS


## 前言

上文介绍了 RISC-V Linux 中休眠流程，本文紧随其后介绍休眠的唤醒流程。

**说明**：

- 本文的 Linux 版本采用 `Linux v6.4-rc1`
- 下文用到的术语：
  - 休眠镜像 - 表示休眠触发过程中，记录要保存的页的镜像
  - swap 镜像 - 表示休眠镜像写入到 swap 设备中的镜像
  - 唤醒镜像 - 表示从 swap 镜像加载到内存中的镜像

## 唤醒入口 -- software_resume

Linux 的休眠唤醒可通过在内核命令行中指定 `resume=/dev/swappart` 休眠镜像所在的 swap 分区。系统启动时在 `late_initcall` 阶段调用 `software_resume` 触发休眠唤醒流程。

`software_resume` 函数前期用于处理 swap 分区和 swap 文件，保存在 `swsusp_resume_device` 变量中，如果没有通过内核命令行指定的话，会以第一个发现的 swap 设备执行唤醒操作，之后跳转到 `Check_image` 标签。你可能会看到类似这样的日志：

```
[    3.481250] PM: hibernation: Checking hibernation image partition /dev/vdb2
[    3.483419] PM: hibernation: Hibernation image partition 254:18 present
[    3.484130] PM: hibernation: Looking for hibernation image.
[    3.487953] PM: hibernation: resume from hibernation

```

`Check_image` 首先校验 swap 头 `struct swsusp_header`，之后执行一些准备工作（比如：准备挂起控制台、冻结进程），调用 `load_image_and_restore` 用于加载休眠镜像并恢复系统状态，后续的逻辑（比如：解冻进程）用于在休眠唤醒失败后恢复到现有的系统。

`load_image_and_restore` 函数主要涉及两个过程：

1. `swsusp_read` 加载 swap 镜像并构建唤醒镜像，获取之前保存的系统状态
2. `hibernation_restore` 根据之前保存的系统状态恢复系统

```c
// kernel/power/hibernate.c : 914

late_initcall_sync(software_resume);

software_resume()
  //... 处理 swap 分区和文件
  swsusp_resume_device = name_to_dev_t(resume_file);

Check_image:
  swsusp_check(); // 校验 swap 头
  pr_info("resume from hibernation\n");

  pm_prepare_console();
  freeze_processes();
  freeze_kernel_threads();

  load_image_and_restore()
    pm_pr_dbg("Loading hibernation image.\n");

    swsusp_read(&flags);

    hibernation_restore(flags & SF_PLATFORM_MODE);

   thaw_processes();
   pm_restore_console();
   pr_info("resume failed (%d)\n", error);
   pm_pr_dbg("Hibernation image not present or could not be loaded.\n");

```

## 加载 swap 镜像 -- swsusp_read

`swsusp_read` 从 swap 设备中读取 swap 镜像，并加载为唤醒镜像。其中涉及两个关键的数据结构及其相关结构：

`struct swap_map_handle` 用于跟踪对 swap 设备的以页为单位的读写操作，`get_swap_reader` 用于初始化读句柄，`swap_read_page` 用于从 swap 中读取一页到 `buf` 参数，`release_swap_reader` 用于关闭读句柄；写句柄也是类似的接口，不做赘述。

```c
// kernel/power/swap.c : 96

struct swap_map_handle {
        struct swap_map_page *cur;
        struct swap_map_page_list *maps;
        sector_t cur_swap;
        sector_t first_sector;
        unsigned int k;
        unsigned long reqd_free_pages;
        u32 crc32;
};
struct swap_map_page_list {
        struct swap_map_page *map;
        struct swap_map_page_list *next;
};
struct swap_map_page {
        sector_t entries[MAP_PAGE_ENTRIES];
        sector_t next_swap;
};

static int get_swap_reader(struct swap_map_handle *handle, unsigned int *flags_p);
static int swap_read_page(struct swap_map_handle *handle, void *buf, struct hib_bio_batch *hb);
static void release_swap_reader(struct swap_map_handle *handle);

```

`struct snapshot_handle` 结构用于管理对休眠/唤醒镜像的读写，并提供 `snapshot_read_next`、`snapshot_write_next` 两个接口可以用于读写操作。比如：在从 swap 中读取镜像时，调用 `snapshot_write_next` 接口会从系统休眠镜像中返回一页，后续可以调用 `swap_read_page` 接口对该页填充数据；当往 swap 中写入镜像时，调用 `snapshot_read_next` 接口从系统休眠镜像中获取一页（已有数据填充），后续可以调用 `swap_write_page` 接口将该页写入 swap。

```c
// kernel/power/power.h : 134

struct snapshot_handle {
        unsigned int    cur;    /* number of the block of PAGE_SIZE bytes the
                                 * next operation will refer to (ie. current)
                                 */
        void            *buffer;        /* address of the block to read from
                                         * or write to
                                         */
        int             sync_read;      /* Set to one to notify the caller of
                                         * snapshot_write_next() that it may
                                         * need to call wait_on_bio_chain()
                                         */
};

int snapshot_write_next(struct snapshot_handle *handle);

```

在 `swsusp_read` 函数中，就是重复的调用 `snapshot_write_next` 和 `swap_read_page` 两个接口处理 swap 镜像。`swap_read_page` 相对简单，就是负责把读到的页填充到 `buf` 中，而 `snapshot_write_next` 由于休眠/唤醒镜像的基本结构（如下），则需要进行更加复杂的处理。

```c
// hibernation/resuming image
| snapshot header | meta pages | data pages |
```

```c
// kernel/power/swap.c : 1619

int swsusp_read(unsigned int *flags_p)

  get_swap_reader(&handle, flags_p);      // get swap handle

  error = snapshot_write_next(&snapshot); // get header buffer
  header = (struct swsusp_info *)data_of(snapshot); // data_of(snapshot) => snapshot->buffer
  swap_read_page(&handle, header, NULL);          // read a page from swap to header

  load_image(&handle, &snapshot, header->pages - 1) : // now we have header->page
    for ( ; ; ) {
        snapshot_write_next(snapshot);
        swap_read_page(handle, data_of(*snapshot), &hb);

  swap_reader_finish(&handle); // release swap handle

  pr_debug("Image successfully loaded\n");
```

## 构建唤醒镜像 -- snapshot_write_next

### 处理镜像头信息

第一次调用 `snapshot_write_next()`（下文代码中标记为 A）：会调用 `get_image_page` 申请一个用于唤醒镜像的页，记录在 `snapshot->buffer` 中，`handle->cur++` 用于记录镜像当前分配的页数；之后调用 `swap_read_page(&handle, header, NULL);` 从 swap 中读取一页，这一页表示为一个 `struct swsusp_info` 结构，其中记录了如下信息。

```c
// kernel/power/power.h : 10
struct swsusp_info { // 镜像头信息
        struct new_utsname      uts;
        u32                     version_code;
        unsigned long           num_physpages;
        int                     cpus;
        unsigned long           image_pages; // swap 镜像中的数据页
        unsigned long           pages;  // 此 swap 镜像中的总页数 = 数据页 + meta 页
        unsigned long           size;
} __aligned(PAGE_SIZE);

struct new_utsname {
        char sysname[__NEW_UTS_LEN + 1];
        char nodename[__NEW_UTS_LEN + 1];
        char release[__NEW_UTS_LEN + 1];
        char version[__NEW_UTS_LEN + 1];
        char machine[__NEW_UTS_LEN + 1];
        char domainname[__NEW_UTS_LEN + 1];
};
```

通过解析镜像头信息，我们知道了 swap 镜像中的总页数，之后调用 `load_image(&handle, &snapshot, header->pages - 1)`，此函数只是循环地调用 `snapshot_write_next()` 和 `swap_read_page()` 从 swap 中读入镜像页。

第二次调用 `snapshot_write_next()`（下文代码中标记为 B）：对当前 `snapshot->buffer` 调用 `load_header` 校验并加载头信息：

- 调用 `arch_hibernation_header_restore` 处理架构定义的头信息，以 `struct arch_hibernate_hdr *` 结构强制转换 `struct swsusp_info* buffer`
  - 对比内核版本信息 `init_utsname()->version` -- `uname -v` 保证唤醒与休眠在同一个内核上执行
  - 设置并启动（如果需要的话）`sleep_cpu`，保证从休眠的 CPU 上唤醒
  - 保存 `struct arch_hibernate_hdr` 信息到静态变量 `resume_hdr`，以供后续流程使用，比如：`.saved_satp` 为镜像保存的根页表地址，`restore_cpu_addr` 为镜像保存的用于跳转到 `swsusp_arch_suspend` else 分支的函数（后面会对这两个成员做详细介绍）
- 设置 `nr_copy_pages` 变量用来保存 swap 镜像中的数据页数，`nr_meta_pages` 变量用来保存 swap 镜像中的 meta 页数

> RISC-V 支持 `CONFIG_ARCH_HIBERNATION_HEADER` 选项，故而可以处理架构定义的头信息

```c
// arch/riscv/kernel/hibernate.c : 59

static struct arch_hibernate_hdr {
        struct arch_hibernate_hdr_invariants invariants;
        unsigned long   hartid;
        unsigned long   saved_satp;
        unsigned long   restore_cpu_addr;
} resume_hdr;

struct arch_hibernate_hdr_invariants {
        char            uts_version[__NEW_UTS_LEN + 1];
};

// arch/riscv/kernel/hibernate.c : 152

int arch_hibernation_header_restore(void *addr)

  arch_hdr_invariants(&invariants);
  memcmp(&hdr->invariants, &invariants, sizeof(invariants))

  sleep_cpu = riscv_hartid_to_cpuid(hdr->hartid);

  ret = bringup_hibernate_cpu(sleep_cpu);

  resume_hdr = *hdr;
```

### 处理镜像体

第三次以及后续调用 `snapshot_write_next()`（下文代码中标记为 C）：用于处理 swap 镜像中的 meta page，调用 `unpack_orig_pfns` 函数在 `copy_bm` bitmap 中对 `buffer` 中描述的页置位；当 meta page 处理完后，调用 `prepare_image` 为 data pages 分配内存，之后调用 `get_buffer` 为 `orig_bm` 中标记的页获取一个唤醒镜像地址。

```c
// kernel/power/snapshot.c : 2629

snapshot_write_next(&snapshot);  // Get the address to store the next image page.

    if (!handle->cur) {       // 为 header page 分配空间                         // ---------  A
        buffer = get_image_page(GFP_ATOMIC, PG_ANY);
        handle->buffer = buffer;

    } else if (handle->cur == 1) // 处理 header，创建 copy_bm 用于记录            // ------------ B

      load_header(buffer);
        check_header(info)
          check_image_kernel(info)
            arch_hibernation_header_restore(info) // RISC-V restore struct arch_hibernate_hdr
        nr_copy_pages = info->image_pages;
        nr_meta_pages = info->pages - info->image_pages - 1;
      memory_bm_create(&copy_bm, GFP_ATOMIC, PG_ANY); // create copy_bm for restore meta page

    else if (handle->cur <= nr_meta_pages + 1) // 处理 meta pages               // ----------- C

      unpack_orig_pfns(buffer, &copy_bm);  // set the pfn from meta pages in copy_bm

      if (handle->cur == nr_meta_pages + 1) {  // image meta pages 读取结束
         prepare_image(&orig_bm, &copy_bm);   // 为 data pages 分配内存

         handle->buffer = get_buffer(&orig_bm, &ca);  // 从分配的内存中获取一页，以供 swap 写入

         return PTR_ERR(handle->buffer);

    else {
        handle->buffer = get_buffer(&orig_bm, &ca); // 从分配的内存中获取一页，以供 swap 写入
        return PTR_ERR(handle->buffer);
    handle->cur++;
    return PAGE_SIZE;
```

`prepare_image` 为 data pages 分配内存，关键过程如下：

- 复制 `copy_bm` 到 `free_pages_map`，用来表示 meta pages 中记录的页
- 复制 `copy_bm` 到 `orig_bm`，并释放 `copy_bm`
- 为 data pages 分配内存
  1. 调用 `get_image_page` 分配 `safe_pages_list` 链表，在 `get_buffer` 中预分配内存不足时提供内存分配空间
  2. 调用 `get_zeroed_page` 为 data pages 预分配内存
  3. `safe_pages_list` 与预分配内存都记录到 `forbidden_pages_map`、`free_pages_map` bitmap 中，用来记录那些用于唤醒镜像的页

```c
// kernel/power/snapshot.c : 2500

prepare_image(&orig_bm, &copy_bm); // Make room for loading hibernation image. 创建 orig_bm，分配 safe_pages_list 以及预分配内存

           duplicate_memory_bitmap(free_pages_map, bm); // free_pages_map 中标记 meta pages 中记录的页

           duplicate_memory_bitmap(new_bm, bm);       // copy copy_bm to orig_bm
           memory_bm_free(bm, PG_UNSAFE_KEEP);

           // Reserve some safe pages for potential later use.
           nr_pages = nr_copy_pages - nr_highmem - allocated_unsafe_pages;
           nr_pages = DIV_ROUND_UP(nr_pages, PBES_PER_LINKED_PAGE); //  需要多少个页来管理 pbe（对应一页 nr_copy_pages）
           while (nr_pages > 0) {
              lp = get_image_page(GFP_ATOMIC, PG_SAFE); // 这里基于 `free_pages_map` 保证用于唤醒镜像的内存页不与 swap 镜像中页冲突
              lp->next = safe_pages_list;
              safe_pages_list = lp;

           // Preallocate memory for the image   // 为唤醒镜像预分配内存
           nr_pages = nr_copy_pages - nr_highmem - allocated_unsafe_pages; // allocated_unsafe_pages：之前分配到的页是 meta pages 中的页，这里就不用分配了
           while (nr_pages > 0) {
              lp = (struct linked_page *)get_zeroed_page(GFP_ATOMIC);
              swsusp_set_page_forbidden(virt_to_page(lp));
              swsusp_set_page_free(virt_to_page(lp));

// kernel/power/snapshot.c : 177

static void *get_image_page(gfp_t gfp_mask, int safe_needed)
{
        void *res;

        res = (void *)get_zeroed_page(gfp_mask);
        if (safe_needed)
                while (res && swsusp_page_is_free(virt_to_page(res))) {  // 当前分配的页，与 meta pages 中描述的页冲突了
                        /* The page is unsafe, mark it for swsusp_free() */
                        swsusp_set_page_forbidden(virt_to_page(res));    // 标记该页
                        allocated_unsafe_pages++;
                        res = (void *)get_zeroed_page(gfp_mask);        // 为 safe_pages_list 重新分配
                }
        if (res) {
                swsusp_set_page_forbidden(virt_to_page(res));
                swsusp_set_page_free(virt_to_page(res));
        }
        return res;
}
```

`get_buffer` 函数用于获取唤醒镜像下一页地址，首先从 `orig_bm` 中获取一个 meta pages 中的页，如果该页已经在预分配内存中，则直接返回该页的地址（该页会被 swap 中的页直接覆盖），否则从 `safe_pages_list` 链表中分配。分配时，需要有个结构来记录 1. 当前页在当前系统的地址（`orig_address`）. 临时页用来存放 swap 的页数据 (`address`)，这个结构就是 `struct pbe`，该结构通过 `chain_alloc` 函数从 `safe_pages_list` 链表中分配，设置其 `orig_address`, `address` 成员，并链接到 `struct pbe *restore_pblist;` 链表中，最后返回 `pbe->address` 以供 swap 填充。

```c
// kernel/power/snapshot.c : 2762

get_buffer(&orig_bm, &ca); // Get the address to store the next image data page.
           pfn = memory_bm_next_pfn(bm);
           page = pfn_to_page(pfn);

           if swsusp_page_is_forbidden(page) && swsusp_page_is_free(page) // 命中预分配内存，直接返回该页的地址
             return page_address(page);

           pbe = chain_alloc(ca, sizeof(struct pbe)); // 从 `safe_pages_list` 链表中分配

           pbe->orig_address = page_address(page);  // 保存该页在当前系统中的地址

           pbe->address = safe_pages_list; safe_pages_list = safe_pages_list->next; // pbe->address 被 swap 填充，也就休眠时的内存页

           pbe->next = restore_pblist; restore_pblist = pbe; // 插入 restore_pblist
           return pbe->address;

// include/linux/suspend.h : 616

struct pbe {
        void *address;          /* address of the copy */
        void *orig_address;     /* original address of a page */
        struct pbe *next;
};

struct pbe *restore_pblist;
```

以上内容可能比较晦涩，这里举个例子来说明：

假设 meta pages 中记录了 4 个页帧 -- `{1,2,6,7}`，步骤 1 调用 `get_image_page` 进行内存分配，第一次得到页帧 `1`，与 meta pages 中的页冲突，再次分配得到页帧 `2`
同样冲突，再次分配得到页帧 `5`，则 `safe_pages_list` 中记录页帧 `5`。步骤 2 则只需要分配 2 个页帧，比如为页帧 `6`、页帧 `8`。在 `get_buffer` 时，页帧 `1`、页帧 `2`、页帧 `6` 存在于 `forbidden_pages_map`，直接返回当前页帧的虚拟地址，以供 swap 填充，但页帧 `7` 就需要在页帧 `5` 中分配 `struct pbe`,设置 `pbe.orig_address` 为页帧 `7` 的虚拟地址、设置 `pbe.address` 为一个来自于 `safe_pages_list` 的页并返回，以供 swap 填充。为了对页帧 `7` 中数据进行恢复，则需要后续操作在 `restore_pblist` 链表中，拷贝 `pbe.address` 到 `pbe.orig_address`。

## 小结

本节主要介绍 swap 镜像的加载过程，整个过程主要使用 `snapshot_write_next` 和 `swap_read_page` 两个接口进行唤醒镜像的构建。meta pages 中的页帧，一部分采用预分配内存交由 swap 直接覆盖，剩余的页帧则需要后续流程中对 `retore_pblist` 链表进行页拷贝。

RISC-V 架构开启 `CONFIG_ARCH_HIBERNATION_HEADER` 选项，提供架构定义的休眠镜像头结构 `struct arch_hibernate_hdr`，在第二次调用 `snapshot_write_next()` 处理镜像头信息的过程中对其进行恢复，并保存到静态变量 `resume_hdr`。

在 `swsusp_read` 的后续流程中，如何使用 `resume_hdr` 以及如何对 `retore_pblist` 链表进行页拷贝，我们放在下篇文章进行介绍。

## 参考资料

- [[PATCH v8 0/4] RISC-V Hibernation Support][1]

[1]: https://lore.kernel.org/all/20230330064321.1008373-5-jeeheng.sia@starfivetech.com/
