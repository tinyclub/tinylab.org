---
layout: post
author: 'sugarfillet'
title: 'RISC-V Linux 内核 UEFI 启动过程分析（Part1）：构建、加载与启动内核'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /riscv-linux-uefi-boot-1/
description: 'RISC-V Linux 内核 UEFI 启动过程分析（Part1）：构建、加载与启动内核'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
  - UEFI
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.1 - [spaces toc]
> Author:    sugarfillet <sugarfillet@yeah.net>
> Date:      2023/04/17
> Revisor:   Falcon falcon@tinylab.org
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Proposal:  [RISC-V UEFI 启动流程分析与 EDK2 移植](https://gitee.com/tinylab/riscv-linux/issues/I64FSG)
> Sponsor:   PLCT Lab, ISCAS


## 前言

现阶段 RISC-V 主要专注于嵌入式领域，供学习和开发用的评估板一般是单板计算机的形式（Single Board Computer），软件方面基本上是依赖半导体厂商发布完整的 SDK，在 bootloader 这方面轻量级的 U-Boot 成为了首选。随着厂商不断提高 RISC-V 的硬件性能，将不可避免地向上进入台式机甚至是服务器领域。届时，RISC-V 需要面对一个成熟的、分散的、玩家众多的和重度依赖生态的市场。而 UEFI 是市场给出的选择和答案，RISC-V 也必须遵守。

本文结合 RISC-V 架构对 UEFI 的启动过程进行简单介绍，并重点分析 RISC-V Linux 中的 UEFI 启动相关实现。

*说明*
 - Linux 版本采用 v6.3
 - UEFI 标准采用 [2.10][1] 版本文档
 - edk2 版本采用 `edk2-stable202302` 分支

## 构建 RISC-V EDK2 实验环境

EDK2 作为 UEFI 标准的开源实现，主要包括以下三个代码仓库：

- [edk2][5]：edk2 主分支
- [edk2-platforms][6]：edk2 的平台支持分支
- [edk2-non-osi][7]: 不兼容 edk2 和 edk2-platform license 的分支

在构建 RISC-V edk2 实验环境过程中，主要用到前两个仓库：可通过第一个仓库构建 QEMU virt 的 edk2 镜像 ([参考][2])，也可结合第二仓库构建 QEMU sifive_u (HiFiveUnleashedBoard) 的 edk2 镜像 ([参考][3])，这里以 QEMU virt 为例，列出几个关键步骤：

### 编译 QEMU virt edk2

执行如下命令构建 RISC-V QEMU virt 的 edk2 镜像，最终生成 `Build/RiscVVirtQemu/RELEASE_GCC5/FV/RISCV_VIRT.fd` 文件。

> 注意：需要对 edk2 镜像文件的大小进行调整以解决后续 QEMU 启动过程中有关 pflash 的报错

```sh
git clone --recurse-submodule https://github.com/tianocore/edk2.git

export WORKSPACE=`pwd`
export GCC5_RISCV64_PREFIX=/usr/bin/riscv64-linux-gnu-
export PACKAGES_PATH=$WORKSPACE/edk2
export EDK_TOOLS_PATH=$WORKSPACE/edk2/BaseTools
source edk2/edksetup.sh
make -C edk2/BaseTools clean
make -C edk2/BaseTools
make -C edk2/BaseTools/Source/C
source edk2/edksetup.sh BaseTools
build -a RISCV64 --buildtarget RELEASE -p OvmfPkg/RiscVVirt/RiscVVirtQemu.dsc -t GCC5

truncate -s 32M Build/RiscVVirtQemu/RELEASE_GCC5/FV/RISCV_VIRT.fd
```

### 制作 efi.img

提前编译好 RISC-V Linux 内核镜像文件 `arch/riscv/boot/Image`，并使用如下命令保存内核镜像到 `efi.img` 中。

```sh
fallocate -l 512M efi.img
sgdisk -n 1:34: -t 1:EF00 efi.img
sudo losetup -fP efi.img
loopdev=`losetup -j efi.img | awk -F: '{print $1}'`
efi_part="$loopdev"p1
sudo mkfs.msdos $efi_part
mkdir -p /tmp/mnt
sudo mount $efi_part /tmp/mnt/
sudo cp linux/arch/riscv/boot/Image /tmp/mnt/
sudo umount /tmp/mnt
sudo losetup -D $loopdev
```

### 制作 RISC-V Rootfs

除了内核镜像，我们还需要一个 RISC-V Rootfs，可以直接复用 [Linux Lab](https://gitee.com/tinylab/riscv-linux/blob/master/articles/https://tinylab.org/linux-lab) 中编译好的，也可以自行参考 [使用 buildroot 构建 QEMU 和哪吒开发板的系统镜像](https://gitee.com/tinylab/riscv-linux/blob/master/articles/20221228-riscv-buildroot-nezha.md) 编译制作。

下一节我们假设已经基于 Buildroot 制作好 Rootfs，并放置在 `buildroot/output/images/rootfs.ext2`。

### 启动 QEMU

接着执行如下命令启动 Qemu。之后在 EFI Shell 执行内核镜像。

```sh
qemu-system-riscv64 -nographic \
-drive file=Build/RiscVVirtQemu/RELEASE_GCC5/FV/RISCV_VIRT.fd,if=pflash,format=raw,unit=1 \
-machine virt -m 2G \
-drive file=buildroot/output/images/rootfs.ext2,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 \
-drive file=efi.img,format=raw,id=hd1 -device virtio-blk-device,drive=hd1

Shell> fs0:\Image root=/dev/vda console=ttyS0 rootwait earlycon=uart8250,mmio,0x10000000
```

## RISC-V EDK2 启动流程简介

RISC-V 架构的 edk2 移植的基本思路是基于 edk2 项目现有的启动流程以及构建环境，将 OpenSBI 编译为库并链接到 SEC 模块以充分利用 OpenSBI 进行平台的初始化。这里基于 UEFI 启动的七个启动阶段对 RISC-V 的实现做简单介绍（详见 edk2-platform 的 `Platform/RISC-V/PlatformPkg/Readme.md`）。

![riscv-edk2-boot.png](/wp-content/uploads/2022/03/riscv-linux/images/riscv_uefi/riscv-edk2-boot.png)

- SEC 阶段

  处理系统上电或重启，执行 ResetVector 代码；创建临时内存；提供安全信任链的根；传送系统参数到下一阶段。

  RISC-V: SEC 阶段调用 `sbi_init` 执行 OpenSBI 的初始化，之后以 NextAddr 和 NextMode 跳转到 PEI 阶段。其中 SEC 以及 OpenSBI 运行在 M-mode，而之后的阶段（PEI/DXE/BDS）则运行在 NextMode 指定的 S-mode (OEM 可通过相关的 PCD 设置 `PcdPeiCorePrivilegeMode` 或者 `PcdDxeCorePrivilegeMode` 指定 PEI/DXE 阶段运行在其他模式）

- PEI 阶段

  此阶段依次执行 PEIM (PEI Module) 进行平台的初始化，将需要传递给 DXE 的信息组成 HOB(Handoff Block) 表，最终将控制权转交给 DXE。

  RISC-V: PEI 运行在 `PcdPeiCorePrivilegeMode` 默认指定的 S-mode，如果需要运行 SEC 阶段的 PEI protocol interface (PPI) 代码，则要在该阶段早期安装 PPI 并通过 PlatformSecPpiLib 库来避免模式保护限制。

  PEI 通过 RiscVFirmwareContextLib 库访问 OpenSBI 固件上下文 -- EFI_RISCV_OPENSBI_FIRMWARE_CONTEXT。

  ```c
  typedef struct {
    UINT64              BootHartId;
    VOID                *PeiServiceTable;      // PEI Service table // 向上以 PeiServiceTablePointerOpensbi 库提供访问
    UINT64              FlattenedDeviceTree;   // Pointer to Flattened Device tree
    UINT64              SecPeiHandOffData;     // This is EFI_SEC_PEI_HAND_OFF passed to PEI Core.
    EFI_RISCV_FIRMWARE_CONTEXT_HART_SPECIFIC  *HartSpecific[RISC_V_MAX_HART_SUPPORTED];   // Hart 信息（拓展支持、厂商信息、模式切换方法(HartSwitchMode))
  } EFI_RISCV_OPENSBI_FIRMWARE_CONTEXT;
  ```

   PEI 驱动可通过 PEI OpenSBI PPI 调用 SBI 服务。

- DXE 阶段

  该阶段执行系统初始化工作，为后续 UEFI Application 和操作系统提供 UEFI 系统表、启动服务和运行时服务。

  RISC-V: DXE 运行在 `PcdDxeCorePrivilegeMode` 默认指定的 S-mode，DXE 驱动可通过 DXE OpenSBI protocol 调用 OpenSBI 服务。

- BDS 阶段

  此阶段枚举每个启动设备，并执行启动策略（由全局 NVRAM 变量指定，运行时可修改）。如果 BDS 启动失败，系统会重新调用 DXE 派遣器，再次进入寻找启动设备的流程。

  RISC-V: BDS 阶段必须要在将系统控制权移交给 S-mode 的 OS、OS loader、UEFI Application 之前切换到 S-mode。

- TSL 阶段

  此阶段为 OS loader（比如：grub、Linux EFI Boot Stub）执行的第一阶段，在这个阶段系统资源还是被 UEFI 所控制，直到 OS loader 执行 `BS.ExitBootServices()` 退出 Boot Service 进入 Runtime 阶段。

  RISC-V：此阶段为 Linux 内核的 EFI Boot Stub 处理流程，我们放在后文详细介绍。

- RT 阶段

  UEFI 各种系统资源被转移到 OS loader，启动服务不能再使用，仅保留运行时服务供操作系统使用。

  RISC-V: 此阶段涉及 Linux 内核的 UEFI 运行时的初始化流程，我们放在后文详细介绍。

- AL 阶段

  在 RT 阶段，如果系统遇到灾难性错误，系统固件需要提供错误处理和灾难恢复机制，这种机制运行在 AL（AferLife）阶段。UEFI 和 UEFI PI 标准都没有定义此阶段的行为和规范。

## UEFI Linux 启动过程

### UEFI 内核镜像

UEFI Boot Manager 用于加载并执行 PE 格式的 UEFI 镜像，UEFI 镜像分为三类 UEFI Application、UEFI boot service drivers、UEFI runtime drivers，体现在 PE 头的 "Subsystem" 字段，三者的主要区别在于镜像加载时分配的内存空间不同（详见后文关于 UEFI 内存映射表的描述）。另外 PE 头的 "Machine" 字段表示该镜像可运行的平台，edk2 中 `MdePkg/Library/BasePeCoffLib/RiscV/PeCoffLoaderEx.c` 就定义了对 `EFI_IMAGE_MACHINE_RISCV64` 类镜像的处理函数。

```c
// BaseTools/Source/C/Include/IndustryStandard/PeImage.h : 22

// PE32+ Subsystem type for EFI images
#define EFI_IMAGE_SUBSYSTEM_EFI_APPLICATION          10
#define EFI_IMAGE_SUBSYSTEM_EFI_BOOT_SERVICE_DRIVER  11
#define EFI_IMAGE_SUBSYSTEM_EFI_RUNTIME_DRIVER       12

// PE32+ Machine type for EFI images
#define EFI_IMAGE_MACHINE_IA32                       0x014c
#define EFI_IMAGE_MACHINE_IA64                       0x0200
#define EFI_IMAGE_MACHINE_EBC                        0x0EBC
#define EFI_IMAGE_MACHINE_x64                        0x8664
#define EFI_IMAGE_MACHINE_ARMTHUMB_MIXED             0x01C2
#define EFI_IMAGE_MACHINE_AARCH64                    0xAA64
#define EFI_IMAGE_MACHINE_RISCV32                    0x5032
#define EFI_IMAGE_MACHINE_RISCV64                    0x5064
#define EFI_IMAGE_MACHINE_RISCV128                   0x5128
#define EFI_IMAGE_MACHINE_LOONGARCH32                0x6232
#define EFI_IMAGE_MACHINE_LOONGARCH64                0x6264
```

在 UEFI Application 中有一类特殊的应用 - UEFI OS Loader，顾名思义，此应用是用来加载操作系统的，其被 Boot Manager 加载并执行，如果成功加载 OS，调用 `EFI_BOOT_SERVICES.ExitBootServices()` 结束 Boot Services 并将系统控制权转移给 OS，OS 继而可以使用 UEFI 提供的 Runtime Services。比如：grub 其在 EFI 分区存放的 grubx86.efi 就是一个 UEFI OS Loader, 通过 file 命令可以看到它是一个格式为 PE32+ 的 EFI Application。

```bash
$file /boot/efi/EFI/boot/grubx64.efi
/boot/efi/EFI/boot/grubx64.efi: PE32+ executable (EFI application) x86-64 (stripped to external PDB), for MS Windows
```

在“构建 RISC-V EDK2 实验环境”一节中，我们可以在 UEFI Shell 中直接运行内核镜像 -- Image，难道 Image 也是一个 UEFI Boot Loader 么？

是的，Linux 内核提供 `CONFIG_EFI_STUB` 选项用于将内核镜像封装为 PE 镜像，当固件加载并执行此镜像时会跳转到镜像中定义的入口地址，继而执行与 OS Loader 相似的功能，并最终跳转到正式内核入口 `_start`，这一部分代码称之为 EFI Boot Stub。我们接下来，看下 UEFI 内核镜像是如何构建的：

在 `arch/riscv/kernel/head.S` 中 `_start` 使用 `_HEAD` 修饰，声明其定义在 `.head.text` 节中，此节的开头部分按照 `struct riscv_image_header` 布局，其中：

`riscv_image_header.{code0,code1)` 以 64 位对齐，如果开启 `CONFIG_EFI`，填充 `c.li s4,-13` 指令和 `j _start_kernel`。其中 `c.li` 指令编码为 16 位的 '0x5a4d'，此值对应 `MZ_MAGIC`，使得该节经过链接以及 objcopy 可生成开头为 "MZ" 魔数的 PE 镜像。

```c

// arch/riscv/include/asm/image.h : 55

struct riscv_image_header {
        u32 code0;
        u32 code1;
        u64 text_offset;
        ...
        u32 res3;
};

// arch/riscv/kernel/head.S : 21

__HEAD
ENTRY(_start)
#ifdef CONFIG_EFI
        c.li s4,-13        // #define MZ_MAGIC        0x5a4d
        j _start_kernel
#else
        j _start_kernel
        .word 0
#endif
        .balign 8

        // ...
#ifdef CONFIG_EFI
        .word pe_head_start - _start // riscv_image_header.rev3
pe_head_start:
        __EFI_PE_HEADER
#else
        .word 0
#endif

       // ...
```

`riscv_image_header.res3` 为最后的成员，存储 PE 头与 _start 的偏移，并在其后追加 PE 头 `__EFI_PE_HEADER`。`__EFI_PE_HEADER` 定义在 `arch/riscv/kernel/efi-header.S` 文件中，按照 PE 镜像相关结构进行布局，这里摘录几个关键的点进行介绍：

- `coff_header.Machine` 定义为 `IMAGE_FILE_MACHINE_RISCV64` 或者 `IMAGE_FILE_MACHINE_RISCV32`，此值与前面介绍的 UEFI 镜像中的 "Machine" 字段相对应，在 edk2 中定义为 `EFI_IMAGE_MACHINE_RISCV64` 和 `EFI_IMAGE_MACHINE_RISCV32`

- `extra_header_fields.Subsystem` 定义为 `IMAGE_SUBSYSTEM_EFI_APPLICATION`，表明此镜像为 EFI Application 类型的 UEFI 镜像，此值在 edk2 中定义为 `EFI_IMAGE_SUBSYSTEM_EFI_APPLICATION`

- `optional_header.AddressOfEntryPoint` 定义为 `__efistub_efi_pe_entry - _start`，表明此镜像被加载后并执行的入口函数为 `efi_pe_entry`（`__efi_stub_` 前缀为 EFI Boot Stub 相关代码 objcopy 时所添加）

```c

// arch/riscv/kernel/efi-header.S : 10

        .macro  __EFI_PE_HEADER
        .long   PE_MAGIC
coff_header:
#ifdef CONFIG_64BIT
        .short  IMAGE_FILE_MACHINE_RISCV64              // Machine
#else
        .short  IMAGE_FILE_MACHINE_RISCV32              // Machine
#endif

optional_header:
#ifdef CONFIG_64BIT
        .short  PE_OPT_MAGIC_PE32PLUS                   // PE32+ format
#else
        .short  PE_OPT_MAGIC_PE32                       // PE32 format
#endif

        .long   __efistub_efi_pe_entry - _start         // AddressOfEntryPoint

extra_header_fields:
        //...
        .short  IMAGE_SUBSYSTEM_EFI_APPLICATION         // Subsystem

// ./drivers/firmware/efi/libstub/Makefile : 149

STUBCOPY_FLAGS-$(CONFIG_RISCV)  += --prefix-alloc-sections=.init \
                                   --prefix-symbols=__efistub_
STUBCOPY_RELOC-$(CONFIG_RISCV)  := R_RISCV_HI20
```

### EFI Boot Stub efi_pe_entry

上节中介绍到，在 UEFI Shell 中直接执行的 UEFI 内核镜像是一个 PE 格式的 UEFI Application（准确说是一个 UEFI OS Loader），其被加载后执行的入口函数为 `efi_pe_entry`（也可理解为是 EFI Boot Stub 的入口），此函数执行 OS Loader 相关的任务，并最终跳转到正式内核的入口 `_start`。

`efi_pe_entry` 作为 UEFI 镜像的入口函数，遵守 UEFI 标准中 EFI 镜像入口点 -- "EFI_IMAGE_ENTRY_POINT" 的接口定义，此接口的第一个参数 `ImageHandle` 是固件为当前镜像创建的句柄，在入口函数的后续流程中可通过 `EFI_LOADED_IMAGE_PROTOCOL` 获取当前镜像的一些信息；第二个参数 `SystemTable` 为系统表，这个参数主要包含以下信息：

- 控制台的标准输入输出、错误输出 (ConsoleInHandle/ConsoleOutHandle/StandardErrorHandle)
- Boot Services / Runtime 服务表 (BootServices/RuntimeServices)，后续分析中会大量用到 Boot Services 提供的服务
- 配置表 (ConfigurationTable)，比如：ACPI, SMBIOS、设备树 等等

```c
// MdePkg/Include/Uefi/UefiSpec.h : 1975

typedef
EFI_STATUS
(EFIAPI *EFI_IMAGE_ENTRY_POINT) (
  IN EFI_HANDLE                  ImageHandle,
  IN EFI_SYSTEM_TABLE            *SystemTable
  );

typedef struct {
  EFI_TABLE_HEADER                   Hdr;
  CHAR16                             *FirmwareVendor;
  UINT32                             FirmwareRevision;
  EFI_HANDLE                         ConsoleInHandle;
  EFI_SIMPLE_TEXT_INPUT_PROTOCOL     *ConIn;
  EFI_HANDLE                         ConsoleOutHandle;
  EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL    *ConOut;
  EFI_HANDLE                         StandardErrorHandle;
  EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL    *StdErr;
  EFI_RUNTIME_SERVICES               *RuntimeServices;
  EFI_BOOT_SERVICES                  *BootServices;
  UINTN                              NumberOfTableEntries;
  EFI_CONFIGURATION_TABLE            *ConfigurationTable;
} EFI_SYSTEM_TABLE;
```

`efi_pe_entry()` 函数执行如下步骤：

调用 `BS.HandleProtocol()` 接口获取当前 UEFI 镜像到 `image` 变量；`efi_handle_cmdline` 函数可通过 `image->load_options` 获取 UEFI Shell 中指定的内核命令行参数。

`handle_kernel_image()` 调用 `efi_relocate_kernel` 进行内核的重定位：调用 `BS.AllocatePages(EFI_ALLOCATE_ADDRESS)` 在 `EFI_LOADER_DATA` 内存空间为内核镜像分配内存，分配的起始地址为 2M(if 64bit)，分配大小为 `_end - start` 即内核镜像大小，并逐字拷贝内核镜像，需要注意的是这里没有拷贝 bss 相关段。如果给定的起始地址不满足条件，则会调用 `efi_low_alloc_above()` 在 UEFI 内存映射表的 `EFI_LOADER_DATA` 空间找到尽可能小的地址进行内存分配。

```c
// drivers/firmware/efi/libstub/efi-stub-entry.c

efi_status_t __efiapi efi_pe_entry(efi_handle_t handle, efi_system_table_t *systab)

  WRITE_ONCE(efi_system_table, systab);

  // get image by BS.HandleProtocol(handle,EFI_LOADED_IMAGE_PROTOCOL,)
  efi_bs_call(handle_protocol, handle, &loaded_image_proto, (void *)&image);

  // 处理 EFI 应用的命令行
  efi_handle_cmdline(image, &cmdline_ptr);

  // kernel 重定位
  handle_kernel_image(&image_addr, &image_size, &reserve_addr, &reserve_size, image, handle); // relocate kernel
    kernel_size = _edata - _start;
    *image_addr = (unsigned long)_start;
    *image_size = kernel_size + (_end - _edata); // efi kernel size

    efi_relocate_kernel(image_addr, kernel_size, *image_size, preferred_addr, efi_get_kimg_min_align(), 0x0);
      efi_bs_call(allocate_pages, EFI_ALLOCATE_ADDRESS, EFI_LOADER_DATA, nr_pages, &efi_addr);
      memcpy((void *)new_addr, (void *)cur_image_addr, image_size);
      image_addr = efi_addr or new_addr; // update image_addr

  efi_stub_common(handle, image, image_addr, cmdline_ptr);
```

`efi_pe_entry()` 在对内核镜像进行重定位后，调用 `efi_stub_common()` 访问必要的 UEFI 接口执行一些简单的初始化任务，最终调用 `efi_boot_kernel()` 启动正式内核：

- `check_platform_features()` 通过 `RISCV_EFI_BOOT_PROTOCOL_GUID` 协议设置 `hartid`，如果失败则通过配置表中的 FDT 的 "chosen" 节点的 "boot-hartid" 属性获取（可通过平台级的 `PcdBootHartId` 进行配置）

- `setup_graphics()` 通过 `EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID` 协议获取显示相关信息

- `efi_load_initrd()` 加载 initrd

  initrd 一般有两个来源，固件提供（比如：QEMU 命令行指定、或者通过 UEFI Shell 的 initrd 命令指定）以及 Linux 命令行指定。第一种情况下，执行 `efi_load_initrd_dev_path()` 访问 `LINUX_EFI_INITRD_MEDIA_GUID` 配置表来获取；第二种情况下，执行 `efi_load_initrd_cmdline()` 调用 `efi_open_file` 来获取。之后，在 `EFI_LOADER_DATA` 中为其分配内存空间，并将 initrd 以 `LINUX_EFI_INITRD_MEDIA_GUID` 安装到配置表中。

- `efi_random_get_seed()` 通过 `EFI_RNG_PROTOCOL_GUID` 获取随机源，并将其以 `LINUX_EFI_RANDOM_SEED_TABLE_GUID` 安装到配置表中

- `install_memreserve_table()` 安装 `LINUX_EFI_MEMRESERVE_TABLE_GUID` 配置表

```c
// drivers/firmware/efi/libstub/efi-stub.c : 287

efi_stub_common(handle, image, image_addr, cmdline_ptr);

    check_platform_features(); // set `hartid` by RISCV_EFI_BOOT_PROTOCOL_GUID

    setup_graphics(); // get struct screen_info by EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID

    efi_load_initrd() // loaded initrd
      efi_load_initrd_dev_path()
      efi_load_initrd_cmdline()

    efi_random_get_seed()  // EFI_RNG_PROTOCOL random bytes saved as a configuration table

    efi_novamap // 此变量表示代表是否支持为 RT 设置虚拟地址，后文做详细介绍

    install_memreserve_table()  // BS.InstallConfigurationTable LINUX_EFI_MEMRESERVE_TABLE_GUID

    efi_boot_kernel(handle, image, image_addr, cmdline_ptr);
```

### EFI Boot Stub efi_boot_kernel

`efi_boot_kernel()` 主要执行两个函数 -- `allocate_new_fdt_and_exit_boot()`、`efi_enter_kernel()`。

`allocate_new_fdt_and_exit_boot()` 函数最终会调用 `BS.ExitBootServices()` 接口结束所有的 UEFI Boot Services，但在这个过程中有两个额外的任务需要处理：

第一个是与 dtb 相关的处理：dtb 与 initrd 类似有两个来源，一个是固件提供（比如：QEMU 提供给 edk2 的 dtb），还有一个是通过 Linux 命令行提供的。前者从配置表 `DEVICE_TREE_GUID` 中获取，后者通过 `efi_load_dtb()` 走 UEFI 文件接口来获取。之后为 dtb 分配内存，并执行 `update_fdt()` 函数在 dtb 的 chosen 节点中创建如下几个 chosen 变量，配合后续的 `update_fdt_memmap()` 函数对其进行设置。这几个变量会在 EFI Boot Stub 跳转到正式内核后以 dtb 的形式提供，而正式内核则解析这些变量继而执行相应的初始化。

- `bootargs`

  存放命令行参数，传递给正式内核进行解析

- `linux,uefi-system-table`

  存放系统表，正式内核可通过系统表获取 ACPI/INITRD/SMBIOS 等配置表信息并执行对应的初始化，也可通过系统表获取到 UEFI Runtime 服务表。相关内容会在后文详细介绍。

- `linux,uefi-mmap-start`, `linux,uefi-mmap-size`, `linux,uefi-mmap-desc-size`, `linux,uefi-mmap-desc-ver`

  存放 UEFI 内存映射，正式内核可通过 UEFI 内存映射表了解物理内存布局，从而更新 memblock 内存分配器。

  edk2 中以内存描述符 -- `EFI_MEMORY_DESCRIPTOR` 构成的链表描述 UEFI 内存映射表，并对外提供 `EFI_BOOT_SERVICES.GetMemoryMap()` 接口获取内存映射表。在执行之后的 `efi_exit_boot_services()` 过程中会调用此接口并通过 `update_fdt_memmap()` 函数对相关的 chosen 变量进行更新。相关结构定义如下：

```c
// MdePkg/Include/Uefi/UefiSpec.h : 160

typedef struct {
   UINT32                     Type;   // enum EFI_MEMORY_TYPE eg: EfiLoaderCode、EfiLoaderData、EfiBootServicesCode、EfiBootServicesData ..
   EFI_PHYSICAL_ADDRESS       PhysicalStart; // 物理内存起始地址
   EFI_VIRTUAL_ADDRESS        VirtualStart; // 虚拟地址起始地址
   UINT64                     NumberOfPages; // 内存空间大小
   UINT64                     Attribute; // 内存属性 eg: Memory cacheability attribute、Physical memory protection attribute、Runtime memory attribute
  } EFI_MEMORY_DESCRIPTOR;

typedef
EFI_STATUS
(EFIAPI *EFI_GET_MEMORY_MAP) (
   IN OUT UINTN                  *MemoryMapSize,  // 整个内存映射表的大小
   OUT EFI_MEMORY_DESCRIPTOR     *MemoryMap,  // 内存映射表
   OUT UINTN                     *MapKey,     // 固件返回的内存映射 key 值
   OUT UINTN                     *DescriptorSize, // 内存描述符的大小
   OUT UINT32                    *DescriptorVersion //  内存描述符的版本 -- EFI_MEMORY_DESCRIPTOR_VERSION = 1
  );
```

`allocate_new_fdt_and_exit_boot()` 函数还有一个任务就是与 Runtime Services 相关的处理：

在 UEFI 标准中定义 `EFI_RT_PROPERTIES_TABLE` 结构来表示 `EFI_RT_PROPERTIES_TABLE_GUID` 配置表，其关键成员 `RuntimeServicesSupported` 用来表示 Runtime 所支持的服务，该成员的 `EFI_RT_SUPPORTED_SET_VIRTUAL_ADDRESS_MAP` 标志位表示是否支持为 Runtime 服务设置虚拟地址。在 `efi_stub_common` 阶段会对此标志位进行检查并保存到 `efi_novamap` 变量中。

```c
// MdePkg/Include/Guid/RtPropertiesTable.h : 28

typedef struct {
  UINT16    Version;
  UINT16    Length;
  UINT32    RuntimeServicesSupported;
} EFI_RT_PROPERTIES_TABLE;

typedef
EFI_STATUS
SetVirtualAddressMap (
   IN UINTN                 MemoryMapSize,
   IN UINTN                 DescriptorSize,
   IN UINT32                DescriptorVersion,
   IN EFI_MEMORY_DESCRIPTOR *VirtualMap   // runtime_map
  );
```

`allocate_new_fdt_and_exit_boot()` 函数对 `efi_novamap` 进行判断，如果支持虚拟地址设置，则在 `EFI_LOADER_DATA` 空间分配 UEFI 内存映射大小的内存，保存在 `struct exit_boot_struct` 实例的 `runtime_map` 中。在执行之后的 `efi_exit_boot_services()` 函数过程中，会调用 `efi_get_virtmap()` 遍历 UEFI 内存映射表，如果为 `EFI_MEMORY_RUNTIME` 类型的内存描述符，则以 `phys_addr + EFI_RT_VIRTUAL_OFFSET` 设置其 `virt_addr`（线性映射），最后将此描述符拷贝到 `runtime_map` 中，并更新其计数 `runtime_entry_count`。

`efi_exit_boot_services()` 结尾处调用 `BS.ExitBootServices()` 接口结束所有的 UEFI Boot Services，在此接口成功返回后，调用 `RT.SetVirtualAddressMap()` 接口，从而固件中的所有运行时服务都采用虚拟地址进行访问。

```c
// drivers/firmware/efi/libstub/fdt.c : 184

struct exit_boot_struct {
        struct efi_boot_memmap  *boot_memmap;  // UEFI 内存映射表
        efi_memory_desc_t       *runtime_map;  // 已设置虚拟地址的 EFI_MEMORY_RUNTIME 类型的内存描述符链表
        int                     runtime_entry_count; // runtime_map 表数目
        void                    *new_fdt_addr;  // 分配的 fdt 地址
};

struct efi_boot_memmap {   // 对应 EFI_GET_MEMORY_MAP 接口
        unsigned long           map_size;
        unsigned long           desc_size;
        u32                     desc_ver;
        unsigned long           map_key;
        unsigned long           buff_size;
        efi_memory_desc_t       map[];
};

// drivers/firmware/efi/libstub/fdt.c : 343

efi_boot_kernel(void *handle, efi_loaded_image_t *image, unsigned long kernel_addr, char *cmdline_ptr);

  allocate_new_fdt_and_exit_boot(handle, image, &fdt_addr, cmdlinetr);

    // 创建 p->runtime_map in LOADER_DATA
    !efi_novamap  && efi_alloc_virtmap(&priv.runtime_map, &desc_size, &desc_ver);

    // 处理 fdt
    efi_load_dtb(image, &fdt_addr, &fdt_size); // same as efi_load_initrd

    efi_allocate_pages(MAX_FDT_SIZE, new_fdt_addr, ULONG_MAX);
    update_fdt((void *)fdt_addr, fdt_size,...)) // 添加 chosen 变量
    priv.new_fdt_addr = (void *)*new_fdt_addr;

    // 更新 fdt，退出 Boot Services，设置 RT 为虚拟地址

    efi_exit_boot_services(handle, &priv, exit_boot_func)
      efi_get_memory_map(&map, true); // BS.GetMemoryMemmep
      exit_boot_func(map,priv)
        p->boot_memmap = map;  // struct exit_boot_struct p;

        efi_get_virtmap(map->map, map->map_size, map->desc_size, p->runtime_map, &p->runtime_entry_count);
          in->virt_addr = in->phys_addr + EFI_RT_VIRTUAL_OFFSET   // RISC-V EFI_RT_VIRTUAL_OFFSET = 0

        update_fdt_memmap(p->new_fdt_addr, map)

      efi_bs_call(exit_boot_services, handle, map->map_key); // BS.ExitBootServices
      // RT.SetVirtualAddressMap() : Changes the runtime addressing mode of EFI firmware from physical to virtual
      efi_system_table->runtime->set_virtual_address_map(priv.runtime_entry_count * desc_size, desc_size, desc_ver, priv.runtime_map);

  efi_enter_kernel(kernel_addr, fdt_addr, fdt_totalsize((void fdt_addr));
```

`efi_boot_kernel()` 函数最后调用 `efi_enter_kernel()`，清空 `satp` 以关闭 MMU，以 `hartid` 和 `fdt` 为参数调用 `_start`。

```c
// drivers/firmware/efi/libstub/riscv.c : 97

// entrypoint 就是 efi_relocate_kernel 阶段返回的 _start 加载地址
efi_enter_kernel(unsigned long entrypoint, unsigned long fdt, unsigned long fdt_size);
      csr_write(CSR_SATP, 0);
      jump_kernel(hartid, fdt);
```

## 小结

Linux EFI Boot Stub 作为一种 UEFI OS Loader 在 UEFI 的 TSL 阶段调用 Boot Services 接口为正式内核准备系统表、UEFI 内存映射表、命令行参数，并在退出 Boot Services 后，又为 Runtime Services 设置虚拟地址，最终跳转到正式内核。那么正式内核又将如何处理 EFI Boot Stub 传递的数据呢？且看下文分解。

## 参考资料

- [UEFI 标准][1]
- [OpenSBI/U-Boot/UEFI 简介][4]

[1]: https://uefi.org/specs/UEFI/2.10/index.html
[2]: https://github.com/vlsunil/riscv-uefi-edk2-docs/wiki/RISC-V-Qemu-Virt-support
[3]: https://github.com/riscv-admin/riscv-uefi-edk2-docs
[4]: https://tinylab.org/riscv-uefi-part1/
[5]: http://github.com/tianocore/edk2
[6]: https://github.com/tianocore/edk2-platforms.git
[7]: https://github.com/tianocore/edk2-non-osi
