---
layout: post
author: '乖乖是干饭王'
title: 'Stratovirt 的 RISC-V 虚拟化支持（四）：内存模型和 CPU 模型'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /stratovirt-riscv-part4/
description: 'Stratovirt 的 RISC-V 虚拟化支持（四）：内存模型和 CPU 模型'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - KVM
  - Stratovirt
  - 虚拟机
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [spaces codeblock]
> Author:    Sunts <stsmail163@163.com>
> Date:      2024/09/11
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

前文介绍了基本的 KVM 模型，本文将通过增加 memory 子模块和 cpu 子模块来进一步完善虚拟机功能。

## 内存模型

在前文中我们仅申请固定大小的空间用于虚拟机的 ram 部分并存放汇编指令代码。但这远远不能满足中断控制器、PCI 设备等的要求。memory 子模块包含地址资源管理和虚拟机内存管理以及内存读写功能。

### 地址空间分布

在 risc-v 的 stratovirt 中，对地址空间布局如下图所示。

![Image Description](/wp-content/uploads/2022/03/riscv-linux/images/stratovirt-riscv/memory_layout.jpg)

在初始 edu 分支中并不会用到类似 PCI 的地址空间，edu 后面会使用到 IRQCHIP 作为 PLIC 的内存映射区域。
考虑到 edu 的全部内容，我们使用三种 edu 分支中会用到的内存区域，IRQCHIP 用于 PLIC 空间，MMIO 用于串口空间，RAM 用于内存，内存的最大边界已在图中指定，真正内存的大小由 stratovirt 中调用内存子模块接口时指定，一般较小，例如：128M，256M 等。最大不超过内存空间的最大边界。

```rust
// src/memory/mod.rs

pub enum LayoutEntryType {
    IrqChip = 0_usize,
    Mmio,
    MemRam
}

pub const MEM_LAYOUT: &[(u64, u64)] = &[
    (0x08000000, 0x08000000),
    (0x10000000, 0x20000000),
    (0x80000000, ((1 << 40) - 0x80000000))
];
```

### 内存地址映射管理

前文中我们直接在主函数中为虚拟机的运行分配 RAM 空间。本文中我们定义 HostMemMapping 结构体记录宿主机虚拟内存和客户机物理内存的一个连续区域的映射关系。其结构体定义如下所示：

```rust
pub struct HostMemMapping {
    // 客户机物理地址起始地址
    guest_addr: u64,
    // 映射区域大小
    size: u64,
    // 宿主机虚拟地址起始地址
    host_addr: u64,
}
```

假如一个区域需要真实物理内存，则通过 HostMemMapping 的 new 函数实现。其通过 mmap 系统调用来分配宿主机虚拟内存，映射关系通过结构体成员来保存。在 HostMemMapping 的析构函数中，会通过 unmap 系统调用来释放宿主机的虚拟内存资源。具体 new 函数实现如下：

```rust
pub fn new(guest_addr: u64, size: u64) -> Result<HostMemMapping> {
    let flags = libc::MAP_ANONYMOUS | libc::MAP_PRIVATE;
    let host_addr = unsafe {
        let hva = libc::mmap(
            std::ptr::null_mut() as *mut libc::c_void,
            size as libc::size_t,
            libc::PROT_READ | libc::PROT_WRITE,
            flags,
            -1,
            0
        );
        if hva == libc::MAP_FAILED {
            return Err(Error::Mmap(std::io::Error::last_os_error()));
        }
        hva
    };
    Ok(HostMemMapping {
        guest_addr,
        size,
        host_addr: host_addr as u64,
    })
}
```

内存子模块的对外接口为 GuestMemory，其成员保存所有的内存区域映射关系。例如，当拥有 PLIC 时，IrqChip 部分空间可能会使用作为 PLIC 的 MMIO 空间，同时还存在虚拟机运行必须的 RAM。这两部分分别保存在两个 HostMemMapping 中。

```rust
// src/memory/guest_memory.rs

impl GuestMemory {
    pub fn new(vm_fd: &Arc<VmFd>, mem_size: u64) -> Result<GuestMemory> {
        let range = Self::arch_ram_ranges(mem_size);

        let mut host_mmaps = Vec::new();
        for (index, range) in ranges.iter().enumerate() {
            let host_mmap = Arc::new(HostMemMapping::new(range.0, range.1));
            host_mmaps.push(host_mmap.clone());

            let kvm_region = kvm_userspace_memory_region {
                slot: index as u32,
                guest_phys_addr: host_mmap.guest_address(),
                memory_size: host_mmap.size(),
                userspace_addr: host_mmap.host_address(),
                flags: 0
            };
            unsafe {
                vm_fd
                    .set_user_memory_region(kvm_region)
                    .map_err(Error::KvmSetMR);
            }
        }
        Ok(GuestMemory{ host_mmaps })
    }
}
```

### 内存访问接口

在 edu 分支中，其他模块需要通过 GuestMemory 对象的成员方法来访问内存，完成读写。读和写自然作为两个最基本最重要的接口必须实现。

```rust
// src/memory/guest_memory.rs

impl GuestMemory {
    pub fn read(&self, dst: &mut [u8], addr: u64) -> Result<()> {
        let count = dst.len() as u64;
        let host_mmap = self.find_host_mmap(addr, count);
        let offset = addr - host_mmap.guest_address();
        let host_addr = host_mmap.host_address();
        let slice = unsafe {
            std::slice::from_raw_parts((host_addr + offset) as * const u8, count as usize)
        };
        dst.write_all(slice).map_err(Error::IoError);
        Ok(())
    }
    pub fn read(&self, src: &[u8], addr: u64) -> Result<()> {
        let count = src.len() as u64;
        let host_mmap = self.find_host_mmap(addr, count);
        let offset = addr - host_mmap.guest_address();
        let host_addr = host_mmap.host_address();
        let slice = unsafe {
            std::slice::from_raw_parts_mut((host_addr + offset) as * const u8, count as usize)
        };
        slice.write_all(src).map_err(Error::IoError);
        Ok(())
    }
}
```

### 错误处理

错误处理不可缺少，对于在内存申请映射，读写过程中可能出现的错误，通过 Error 枚举类型做不同的处理。为它实现 `std::fmt::Display` 这个 trait，方便自定义每种错误发生时的输出信息。

```rust
// src/memory/mod.rs

pub enum Error {
    Overflow(u64, u64, u64),
    HostMmapNotFound(u64),
    Mmap(std::io::Error),
    IoError(std::io::Error),
    KvmSetMR(kvm_ioctls::Error)
}
impl std::fmt::Display for Error {
    ...
}

// 通过 type 定义已经存在的数据类型别名
pub type Result<T> = std::result::Result<T, Error>;
```

## CPU 模型

CPU 子模块需要处理寄存器数据的读写，并完成对部分计算机指令的模拟。常规用户级指令会在 KVM 内核模块中处理，CPU 模块中主要负责对 VM-Exit 退出事件的处理。

CPU 结构体需要记录 vCPU 相关信息，与 KVM 模块进行交互，包括但不限于读写寄存器的信息，开始执行 vCPU 等。

```rust
// src/cpu/mod.rs

pub struct CPU {
    // 虚拟 VCPU 的 id
    pub id: u8;
    // 调用 KVM 模块中的 VCPU 接口所用句柄
    fd: Arc<VcpuFd>;
    // 该 VCPU 所在的虚拟机的地址空间
    sys_mem: Arc<GuestMemory>;
}
```

构造函数对 CPU 结构体初始化。

```rust
// src/cpu/mod.rs

impl CPU {
    pub fn new(vm_fd: &VmFd, sys_mem: Arc<GuestMemory>, vcpu_id: u8) -> Self {
        let vcpu_fd = vm_fd
            .create_vcpu(vcpu_id as u8)
            .expect("Failed to create VCPU");
        Self {
            id: vcpu_id,
            fd: Arc::new(vcpu_fd),
            sys_mem: sys_mem.clone(),
        }
    }
}
```

读写寄存器是非常重要的和 KVM 交互的功能。结合前文中通过 id 来写 PC 寄存器，在 CPU 模块实现对寄存器的访问。目前只考虑通用寄存器。由于每个寄存器的 id 都是一个无符号 64 位整数表示的唯一值，故为通用寄存器枚举类型 Riscv64CoreRegs 实现 std::convert::Into 这个 trait 来为每个寄存器返回其 id。

```rust
// src/cpu/mod.rs

use std::convert::Into;
pub enum Riscv64CoreRegs{
    PC,
    RA,
    ...
    T6,
    MODE,
}
impl Into<u64> for Riscv64CoreRegs{
    fn into(self) -> u64 {
        let reg_offset = match self {
            Riscv64CoreRegs::PC => {
                offset_of!(kvm_riscv_core, regs, user_regs_struct, pc)
            }
            ...
            Riscv64CoreRegs::T6 => {
                offset_of!(kvm_riscv_core, regs, user_regs_struct, t6)
            }
            Riscv64CoreRegs::MODE => {
                offset_of!(kvm_riscv_core, mode)
            }
        };
        KVM_REG_RISCV as u64
            | KVM_REG_SIZE_U64 as u64
            | u64::from(KVM_REG_RISCV_CORE)
            | (reg_offset / mem::size_of::<u64>()) as u64
    }
}

impl CPU {
    pub fn set_core_reg(&self, reg: Riscv64CoreRegs, val: u64) -> Result<()>{
        self.fd.set_one_reg(reg.into(), val).expect("Failed to set register");
        Ok(())
    }
    pub fn get_core_reg(&self, reg: Riscv64CoreRegs) -> Result<u64>{
        let res = self.fd.get_one_reg(reg.into()).unwrap();
        Ok(res)
    }
}
```

最后正式运行抽象出的 CPU，运行中最重要的部分为 vCPU 的指令模拟和对陷出事件的处理。

```rust
// src/cpu/mod.rs

impl CPU {
    pub fn kvm_vcpu_exec(&self) {
        match self.fd.run().unwrap() {
            VcpuExit::IoIn(addr, data) => {
                println!("VCPU{} VmExit IO in: addr 0x{:x}, data is {}",
                self.id, addr, data[0])
            }
            VcpuExit::IoOut(addr, data) => {
                println!("VCPU{} VmExit IO out: addr 0x{:x}, data is {}",
                self.id, addr, data[0])
            }
            VcpuExit::MmioRead(addr, _data) => {
                println!("VCPU{} VmExit MMIO read: addr 0x{:x}",
                self.id, addr)
            }
            VcpuExit::MmioWrite(addr, _data) => {
                println!("VCPU{} VmExit MMIO write: addr 0x{:x}",
                self.id, addr)
            }
            r => panic!("Unexpected exit reason: {:?}", r)
        }
        true
    }
}
```

### CPU 并发运行多个任务

多个 vCPU 可以同时运行通过并行计算加快程序运行速度，可通过 start 接口返回线程的 handle，实现对同一个虚拟机多线程运行多个不同的 vCPU。

```rust
// src/cpu/mod.rs

impl CPU {
    pub fn start(arc_cpu: Arc<CPU>) -> std::thread::JoinHandle<()>{
        let cpu_id = arc_cpu.id;
        thread::Builder::new()
            .name(format!("CPU {}/KVM", cpu_id))
            .spawn(move || {
                loop {
                    if !arc_cpu.kvm_vcpu_exec() { break; }
                }
            }).expect(&format!("thread CPU {}/KVM Failed", cpu_id))
    }
}
```

## 小结

CPU 模型和内存模型进一步完善了 RISC-V 下内存和 CPU 虚拟化功能。后面会实现加载内核文件、PLIC 中断控制等。

## 参考资料

- [RUST thread 官方文档][001]

[001]: https://doc.rust-lang.org/std/thread/
