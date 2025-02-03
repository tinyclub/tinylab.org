---
layout: post
author: '乖乖是干饭王'
title: 'Stratovirt 的 RISC-V 虚拟化支持（五）：BootLoader 和设备树'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /stratovirt-riscv-part5/
description: 'Stratovirt 的 RISC-V 虚拟化支持（五）：BootLoader 和设备树'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - Bootloader
  - 设备树
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [pangu]
> Author:    Sunts <stsmail163@163.com>
> Date:      2024/09/12
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

前文实现了对内存和 CPU 的抽象，可以启动更多 vCPU 线程来并行执行。但前文我们只通过 vCPU 执行简单的汇编语言字节码程序，完成简单任务。本文通过 bootloader 模块引导 Linux，并同时通过生成设备树为 Linux 启动准备所需的必要信息。

## Bootloader

bootloader 负责将内核文件读入内存正确位置，设置 vCPU 相关寄存器传递信息给内核来支持代码正确运行。

具体地，RISC-V 内核期望在 rv64 中内核按照 2M 地址边界对齐，同时在内核启动时，a0 寄存器当中为当前核心的 hartid，a1 寄存器中为设备树的起始地址，satp 寄存器为 0，禁用 MMU。而 ramdisk 内存文件系统的地址以及启动内核的命令等则通过具体设备树的内容来传递给内核。

内核引导方式：固件仅释放一个单核执行初始化阶段并通过 OpenSBI 的扩展来启动其余核心。这种引导方式支持 CPU 的热拔插，内核更加推荐这种引导方式。Linux 内核中拥有启动其余核心的内容。

bootloader 子模块需要接收用户输入的配置信息来加载文件内容。

```rust
// src/bootloader/mod.rs

const RISCV64_KERNEL_OFFSET: u64 = 0x20_0000;
const FDT_ALIGN: u64 = 0x40_0000;
const INITRD_ALIGN: u64 = 0x8;

pub struct Riscv64BootLoaderConfig {
    // 内核镜像路径
    pub kernel: PathBuf,
    // intird 镜像路径
    pub initrd: PathBuf,
    // 客户机物理地址起点
    pub mem_start: u64,
}
```

bootloader 同时返回 Riscv64BootLoader 类型作为模块的输出内容，通知其余模块内核加载位置，fdt 起始地址等信息。

```rust
pub struct Riscv64BootLoader {
    // 客户机内核镜像文件起始地址
    pub kernel_start: u64,
    // 客户机 initrd 镜像文件起始地址
    pub initrd_start: u64,
    // initrd 镜像文件大小，0 代表没有启用内存文件系统
    pub initrd_size: u64,
    // 设备树起始地址
    pub dtb_start: u64,
}
```

bootloader 模块的 load_kernel 函数根据用户的配置来加载内核和 initrd 镜像文件。

```rust
pub fn load_kernel(config: &Riscv64BootLoaderConfig, sys_mem: &Arc<GuestMemory>) -> Riscv64BootLoader {
    let kernel_start = config.mem_start + RISCV64_KERNEL_OFFSET;
    let mut kernel_image = File::open(&config.kernel).expect("Failed to open kernel file");
    let kernel_size = kernel_image.metadata().unwrap().len();
    let kernel_end = kernel_start + kernel_size;
    // 加载内核到虚拟机的内存位置
    sys_mem
        .write(&mut kernel_image, kernel_start, kernel_size)
        .expect("Failed to load kernel image to memory");

    // 预留 fdt 的空间
    let dtb_addr = (kernel_end + (FDT_ALIGN - 1)) & (!(FDT_ALIGN - 1));
    if dtb_addr + u64::from(FDT_MAX_SIZE) >= sys_mem.memory_end_address() {
        panic!("no memory to load DTB")
    }
    let mut initrd_image = File::open(&config.initrd).expect("Failed to open initrd file");
    let initrd_size = initrd_image.metadata().unwrap().len();
    let initrd_start = dtb_addr + u64::from(FDT_MAX_SIZE);
    if initrd_start + u64::from(initrd_size) >= sys_mem.memory_end_address() {
        panic!("no memory to load initrd image")
    }
    // 加载 initrd 文件内容到客户机内存
    sys_mem
        .write(&mut initrd_image, initrd_start, initrd_size)
        .expect("Failed to load initrd to memory");

    Riscv64BootLoader {
        kernel_start，
        initrd_start，
        initrd_size，
        dtb_start: dtb_addr,
    }
}
```

### 内核配置引入

kvm 子模块来负责指定内核引导所需的参数，具体包括内核文件地址、initrd 镜像地址以及客户机物理地址起始位置。主要通过函数 load_boot_source 实现，初始化好配置之后调用 load_kernel 加载内核到客户机虚拟内存地址中。

```rust
// src/kvm/mod.rs

pub fn load_boot_source(guest_memory: &Arc<GuestMemory>) -> BootLoader {
    let initrd_path = PathBuf::from("/tmp/initramfs.cpio.gz");
    let boot_cfg = BootLoaderConfig {
        kernel: PathBuf::from("/tmp/vmlinux.bin"),
        initrd: initrd_path,
        mem_start: MEM_LAYOUT[LayoutEntryType::Mem as usize].0,
    };
    load_kernel(&boot_cfg, &guest_memory)
}
```

### bootloader 对外接口

上文提到，加载内核，预留设备树空间，加载 initrd 镜像之后，bootloader 模块需要返回 Riscv64BootLoader 类型的数据供其余模块使用。这主要通过 bootloader 模块对外的接口函数 kvm_load_kernel 实现。

```rust
pub fn kvm_load_kernel(guest_memory: &Arc<GuestMemory>, vcpu : &mut CPU, vm_fd: &Arc<VmFd>) -> Riscv64BootLoader {
    let layout = load_boot_source(guest_memory);
    let cpu_boot_cfg = CPUBootConfig {
        fdt_addr: layout.dtb_start,
        kernel_addr: layout.kernel_start,
    };
    // 初始化 CPU 结构体相关信息，用于初始化 vCPU 的寄存器
    vcpu.realize(&vm_fd, cpu_boot_cfg);

    layout
}
```

## 扁平设备树

在内核引导阶段，a1 寄存器需要包含内存中设备树的起始地址。设备树包含 Linux 内核启动时所有硬件信息，具体但不限于 CPU 信息，内存信息，总线信息，中断控制信息，串口等等。

要使用设备树需要使用 Linux 内部提供的 fdt 的库，在 Linux 环境下的 C 语言中可以通过直接包含头文件 `#include <libfdt.h>` 的方式使用。

```rust
// .cargo/config

rustflags = [
    "-C", "link-arg=-lgcc",
    "-C", "link-arg=-lfdt",
]
```

在 rust 中这个附加参数会告诉 rustc 链接时链接 gcc 库和 fdt 库。

```rust

// src/device_tree/mod.rs

pub const FDT_MAX_SIZE: u32 = 0x1_0000;
extern "C" {
    fn fdt_create(buf: *mut c_void, bufsize: c_int) -> c_int;
    fn fdt_finish_reservemap(fdt: *mut c_void) -> c_int;
    fn fdt_begin_node(fdt: *mut c_void, name: *const c_char) -> c_int;
    fn fdt_end_node(fdt: *mut c_void) -> c_int;
    fn fdt_finish(fdt: *const c_void) -> c_int;
    fn fdt_open_into(fdt: *const c_void, buf: *mut c_void, size: c_int) -> c_int;

    fn fdt_path_offset(fdt: *const c_void, path: *const c_char) -> c_int;
    fn fdt_add_subnode(fdt: *mut c_void, offset: c_int, name: *const c_char) -> c_int;
    fn fdt_setprop(
        fdt: *mut c_void,
        offset: c_int,
        name: *const c_char,
        val: *const c_void,
        len: c_int,
    ) -> c_int;
}
```

同时声明对外部 C 库函数的引用供后面 fdt 相关函数的调用。

device_tree 模块后面部分负责通过上方库文件的辅助函数生成设备树操作的具体函数作为本模块对外的接口提供设备树相关服务。例如，新建设备树。

```rust
// src/device_tree/mod.rs

pub fn create_device_tree(fdt: &mut Vec<u8>) {
    let mut ret = unsafe { fdt_create(fdt.as_mut_ptr() as *mut c_void, FDT_MAX_SIZE as c_int) };
    if ret < 0 {
        panic!("Failed to fdt_create, return {}.", ret);
    }

    ret = unsafe { fdt_finish_reservemap(fdt.as_mut_ptr() as *mut c_void) };
    if ret < 0 {
        panic!("Failed to fdt_finish_reservemap, return {}.", ret);
    }

    let c_str = CString::new("").unwrap();
    ret = unsafe { fdt_begin_node(fdt.as_mut_ptr() as *mut c_void, c_str.as_ptr()) };
    if ret < 0 {
        panic!("Failed to fdt_begin_node, return {}.", ret);
    }

    ret = unsafe { fdt_end_node(fdt.as_mut_ptr() as *mut c_void) };
    if ret < 0 {
        panic!("Failed to fdt_end_node, return {}.", ret);
    }

    ret = unsafe { fdt_finish(fdt.as_mut_ptr() as *mut c_void) };
    if ret < 0 {
        panic!("Failed to fdt_finish, return {}.", ret);
    }

    ret = unsafe {
        fdt_open_into(
            fdt.as_ptr() as *mut c_void,
            fdt.as_mut_ptr() as *mut c_void,
            FDT_MAX_SIZE as c_int,
        )
    };
    if ret < 0 {
        panic!("Failed to fdt_open_into, return {}.", ret);
    }
}
```

给设备树某一节点添加子节点。

```rust
pub fn add_sub_node(fdt: &mut Vec<u8>, node_path: &str) {
    let names: Vec<&str> = node_path.split('/').collect();
    if names.len() < 2 {
        panic!("Failed to add sub node, node_path: {} invalid.", node_path);
    }

    let node_name = names[names.len() - 1];
    let pare_name = names[0..names.len() - 1].join("/");

    let c_str = if pare_name.is_empty() {
        CString::new("/").unwrap()
    } else {
        CString::new(pare_name).unwrap()
    };

    let offset = unsafe { fdt_path_offset(fdt.as_ptr() as *const c_void, c_str.as_ptr()) };
    if offset < 0 {
        panic!("Failed to fdt_path_offset, return {}.", offset);
    }

    let c_str = CString::new(node_name).unwrap();
    let ret = unsafe { fdt_add_subnode(fdt.as_mut_ptr() as *mut c_void, offset, c_str.as_ptr()) };
    if ret < 0 {
        panic!("Failed to fdt_add_subnode, return {}.", ret);
    }
}
```

给设备树某一节点添加属性，其值为字符串类型。

```rust
pub fn set_property_string(fdt: &mut Vec<u8>, node_path: &str, prop: &str, val: &str) {
    set_property(
        fdt,
        node_path,
        prop,
        Some(&([val.as_bytes(), &[0_u8]].concat())),
    )
}
```

具体还包括给设备树节点添加值为 u32 的属性等等函数，不再给出。

### 生成设备树

device 子模块负责包含所有需要的设备，模块对外接口 `kvm_setup_fireware` 需要接收虚拟机相关配置信息并生成虚拟机所需设备树，写入由 bootloader 模块预留好的虚拟机内存空间中。

```rust
// src/device/mod.rs

pub fn kvm_setup_fireware(guest_memory: &Arc<GuestMemory>, vcpus : &mut Vec<&mut CPU>, vm_fd: &Arc<VmFd>, layout : &Riscv64BootLoader) {
    let cmdline = "console=ttyS0 panic=1 reboot=k root=/dev/ram rdinit=/bin/sh";
    let initrd_range = (layout.initrd_start, layout.initrd_size);
    let fdt_addr = layout.dtb_start;
    fdt::generate_fdt(
        guest_memory,
        initrd_range,
        cmdline,
        vcpus[0],
        fdt_addr,
    );
}
```

device 子模块中的 fdt 模块负责根据内存，cpu 信息等内容生成设备树并写入内存特定位置。下面具体说明 fdt 模块的主要方法。

```rust
// src/device/fdt.rs

pub fn generate_fdt(
    sys_mem: &Arc<GuestMemory>,
    initrd_range: (u64, u64),
    cmdline: &str,
    cpu: &CPU,
    fdt_addr: u64,
) {
    let mut fdt = vec![0; FDT_MAX_SIZE as usize];

    create_device_tree(&mut fdt);
    set_property_string(&mut fdt, "/", "compatible", "linux,dummy-virt");
    set_property_u32(&mut fdt, "/", "#address-cells", 0x2);
    set_property_u32(&mut fdt, "/", "#size-cells", 0x2);

    generate_chosen_node(&mut fdt, cmdline, initrd_range.0, initrd_range.1);
    generate_memory_node(&mut fdt, sys_mem);
    generate_cpu_node(&mut fdt, cpu);
    let fdt_len = fdt.len() as u64;
    sys_mem
        .write(&mut fdt.as_slice(), fdt_addr, fdt_len)
        .expect("Failed to load fdt to memory");

    dump_dtb(&fdt, "/tmp/stratovirt.dtb");
}
```

#### 设备树内存节点

生成设备树中内存相关信息，给出 device_type 以及内存空间起始地址和大小。

```rust
fn generate_memory_node(fdt: &mut Vec<u8>, sys_mem: &Arc<GuestMemory>) {
    let mem_base = MEM_LAYOUT[LayoutEntryType::Mem as usize].0;
    let mem_size = MEM_LAYOUT[LayoutEntryType::Mem as usize].1;
    let node = "/memory";
    add_sub_node(fdt, node);
    set_property_string(fdt, node, "device_type", "memory");
    set_property_array_u64(fdt, node, "reg", &[mem_base, mem_size as u64]);
}
```

#### 设备树 cpu 节点

生成设备树中 cpu 相关信息较为复杂，需要一些 vCPU 寄存器信息之后才能继续。因此在 bootloader 模块的对外接口函数 kvm_load_kernel 加载内核，返回内核镜像地址和 initrd 位置信息之前，调用 CPU 的 realize 函数给 vCPU 使能。同时给 CPU 结构体添加属性，获取生成 cpu 设备树所需的信息。

```rust
// src/cpu/mod.rs
pub struct CPU{
    ...
    // 记录内核起始地址
    boot_ip: u64,
    // 记录 fdt 起始地址，用于写入设备树
    fdt_addr: u64,
    // 记录当前 CPU 支持的扩展，用于生成设备树相关信息
    pub isa: u64,
    // 记录当前 VCPU 频率信息
    pub frequency: u64,
    // 记录当前 VCPU 的 MMU 类型
    pub satp_mode: u64,
}
impl CPU {
    ...
    pub fn realize(&mut self, bootconfig: CPUBootConfig) {
        self.boot_ip = boot_config.kernel_addr;
        self.fdt_addr = boot_config.fdt_addr;
        self.isa = self.fd.get_one_reg(Riscv64ConfigRegs::ISA.into()).unwrap();
        self.satp_mode = self.fd.get_one_reg(Riscv64ConfigRegs::SATP_MODE.into()).unwrap();
        self.frequency = self.fd.get_one_reg(Riscv64Timer::FREQUENCY.into()).unwrap();
    }
}
```

CPU 结构体中的这些信息足够设备模块生成设备树中 cpu 的信息。

```rust
fn generate_cpu_node(fdt: &mut Vec<u8>, cpu: &CPU) {
    let node = "/cpus";
    add_sub_node(fdt, node);
    set_property_u32(fdt, node, "#address-cells", 0x01);
    set_property_u32(fdt, node, "#size-cells", 0x00);
    set_property_u32(fdt, node, "timebase-frequency", cpu.frequency as u32);

    for num in 0..cpu.nr_vcpus {
        let node = format!("/cpus/cpu@{:x}", num);
        add_sub_node(fdt, &node);
        set_property_string(fdt, &node, "device_type", "cpu");
        set_property_string(fdt, &node, "compatible", "riscv");
        let mmu_type = match cpu.satp_mode {
            10 => "riscv,sv57",
            9 => "riscv,sv48",
            8 => "riscv,sv39",
            _ => "riscv,none",
        };
        // 设置 MMU 类型
        set_property_string(fdt, &node, "mmu-type", mmu_type);
        let valid_isa_order = "IEMAFDQCLBJTPVNSUHKORWXYZG";
        let mut cpu_isa = String::from("rv64");
        for i in 0..valid_isa_order.len() {
            let index = valid_isa_order.as_bytes()[i] as u32 - 65;
            if cpu.isa & (1 << index) != 0 {
                let char_to_add = ((index as u8) + b'a') as char;
                cpu_isa.push(char_to_add);
            }
        }
        // 设置当前 CPU 支持的指令集扩展情况
        set_property_string(fdt, &node, "riscv,isa", &cpu_isa);
        set_property_u32(fdt, &node, "reg", num);
        // 设置状态
        set_property_string(fdt, &node, "status", "okay");

        let node = format!("/cpus/cpu@{:x}/interrupt-controller", num);
        add_sub_node(fdt, &node);
        set_property_string(fdt, &node, "compatible", "riscv,cpu-intc");
        set_property_u32(fdt, &node, "#interrupt-cells", 0x01);
        set_property(fdt, &node, "interrupt-controller", None);
        set_property_u32(
            fdt,
            &node,
            "phandle",
            u32::from(num) + CPU_PHANDLE_START,
        );
    }
}
```

## 小结

本文通过 bootloader 模块引导 Linux，并同时通过生成设备树为 Linux 启动准备所需的必要信息。后文将为 Linux 添加中断控制器和串口设备，真正启动 Linux。

## 参考资料

- [risc-v Linux 引导流程][001]
- [libfdt 文档][002]

[001]: https://docs.kernel.org/arch/riscv/boot.html
[002]: https://github.com/torvalds/linux/blob/master/scripts/dtc/libfdt/libfdt.h
