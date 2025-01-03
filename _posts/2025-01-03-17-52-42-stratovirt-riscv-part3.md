---
layout: post
author: '乖乖是干饭王'
title: 'Stratovirt 的 RISC-V 虚拟化支持（三）：KVM 模型'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /stratovirt-riscv-part3/
description: 'Stratovirt 的 RISC-V 虚拟化支持（三）：KVM 模型'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - KVM
  - Stratovirt
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [spaces toc codeblock urls pangu]
> Author:    Sunts <stsmail163@163.com>
> Date:      2024/09/05
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

KVM 模型用于展示 KVM 模块的简单使用。本节借助 KVM API，构建一个最小虚拟机，运行一段汇编指令。本文代码都运行在前文已经构建好的 RISC-V 架构下的 qemu-system-riscv64 以及用它引导的 RISC-V 架构的 Ubuntu 22.04 环境中。

## 项目准备

下载 stratovirt 源码，从官方 edu 分支起点新建分支并切换到新的分支。新建项目。

```shell
git clone https://gitee.com/openeuler/stratovirt.git
git checkout 0b2c26
git checkout -b mini_riscv_edu
```

## 汇编指令定义

最小模型给定一段汇编语言让 vCPU 运行，运行结束，vCPU 退出。

```rust
// src/main.rs

fn main() {
    let mem_size = 0x1000;
    let guest_addr: u64 = 0x80000000;

    let asm_code: &[u8] = &[
        0x93, 0x02, 0x80, 0x3f,   // li t0, 0x3f8
        0x03, 0xb3, 0x02, 0x00,   // ld t1, 0(t0)
    ];
}
```

汇编代码逻辑为从地址 0x3f8 位置读取一个双字内容，而这个地址为非注册的 RAM 地址，vCPU 会退出进而被 host 捕获。

## 打开 KVM 模块，创建虚拟机

打开 KVM 模块需要使用前文移植好的库：kvm-ioctls 和 kvm-bindings。将两个依赖库复制到项目目录下后修改依赖文件，具体依赖文件内容如下。

```rust
// src/Cargo.toml

[package]
name = "stratovirt"
version = "0.1.0"
edition = 2021

[dependencies]
libc = ">=0.2.39"
kvm-ioctls = { path = "kvm-ioctls" }
kvm-bindings = { path = "kvm-bindings" }
```

调用 kvm_ioctls::Kvm 的构造函数打开 /dev/kvm 模块，拿到 Kvm 对象，调用其 create_vm 成员函数创建虚拟机，得到虚拟机句柄。

```rust
// src/main.rs

use kvm_ioctls::Kvm;

fn main() {
    let mem_size = 0x1000;
    let guest_addr: u64 = 0x80000000;

    let asm_code: &[u8] = &[
        0x93, 0x02, 0x80, 0x3f,   // li t0, 1016
        0x03, 0xb3, 0x02, 0x00,   // ld t1, 0(t0)
    ];

    let kvm = Kvm::new().expect("Failed to open /dev/kvm");
    let vm_fd = kvm.create_vm().expect("Failed to create a vm");
}
```

## 初始化虚拟机内存

用 libc 库中的 mmap 系统调用在宿主机中申请内存空间同时可以得到内存起始地址的指针。得到该宿主机的虚拟地址之后需要将宿主机的虚拟地址和客户机的物理地址以及地址空间的大小通知给 KVM。其中，映射关系和内存大小通过 kvm_userspace_memory_region 结构体传递。

```rust
// src/main.rs

use kvm_bindings::kvm_userspace_memory_region;
use kvm_ioctls::Kvm;

fn main() {
    ...
    let host_addr: *mut u8 = unsafe {
        libc::mmap(
            std::ptr::null_mut(),
            mem_size,
            libc::PROT_READ | libc::PROT_WRITE,     // 映射的内存可读可写
            libc::MAP_ANONYMOUS | libc::MAP_PRIVATE,
            -1,                                     // 不映射文件，不需要 fd
            0                                       // 不映射文件，offset=0
        ) as *mut u8
    };
    let kvm_region = kvm_userspace_memory_region {
        slot: 0,
        guest_phys_addr: guest_addr,
        memory_size: mem_size as u64,
        userspace_addr: host_addr as u64,
        flags: 0
    };
    unsafe {
        vm_fd
            .set_user_memory_region(kvm_region)
            .expect("Failed to set memory region to KVM")
    }
}
```

将汇编字节码写入 mmap 分配的虚拟内存中。

```rust
// src/main.rs

use kvm_bindings::kvm_userspace_memory_region;
use kvm_ioctls::Kvm;

fn main() {
    ...
    unsafe {
        let mut slice = std::slice::from_raw_parts_mut(host_addr, mem_size);
        slice
            .write_all(&asm_code)
            .expect("Failed to load asm code to memory");
    }
}
```

## 创建虚拟机和 vCPU 并初始化寄存器

risc-v 中设置寄存器的值需要通过 VcpuFd 的 set_one_reg 方法，该方法需要传入一个代表某一特定寄存器的 ID 值，ID 值是 KVM 对该寄存器的唯一编码表示。在 risc-v 中，经过宏扩展之后通用寄存器的 ID 值计算方式如下：

```c
#define RISCV_CORE_REG(name) KVM_REG_RISCV \
                                | KVM_REG_RISCV_CORE \
                                | KVM_REG_SIZE_U64   \
                                | (offsetof(struct kvm_riscv_core, name) / sizeof(unsigned long))
```

`kvm_riscv_core` 结构体具体定义见 Linux 内核文件。

```c
# 源码目录 arch/riscv/include/uapi/asm/kvm.h
struct kvm_riscv_core {
	struct user_regs_struct regs;
	unsigned long mode;
};

# 源码目录 arch/riscv/include/uapi/asm/ptrace.h
struct user_regs_struct {
    unsigned long pc;
    unsigned long ra;
    ...
    unsigned long t6;
};
```

对于 `RISCV_CORE_REG(regs.pc)` 的调用，宏最终扩展为 `KVM_REG_RISCV | KVM_REG_RISCV_CORE | KVM_REG_SIZE_U64 | (offsetof(struct kvm_riscv_core, regs.pc) / 64)`，`pc` 字段位于 `struct user_regs_struct` 首个成员，故偏移为 0。

```rust
// src/main.rs

use kvm_bindings::{ kvm_userspace_memory_region, KVM_REG_RISCV, KVM_REG_RISCV_CORE, KVM_REG_SIZE_U64};
use kvm_ioctls::Kvm;
use std::io::Write;

const PC_ID: u64 = KVM_REG_RISCV as u64
                           | KVM_REG_RISCV_CORE as u64
                           | KVM_REG_SIZE_U64 as u64
                           | 0;

fn main() {
    ...
    let vcpu_fd = vm_fd.create_vcpu(0).expect("Failed to create vCPU");
    vcpu_fd.set_one_reg(PC_ID, guest_addr);
}
```

## 处理 vCPU 退出事件

执行汇编指令 `ld t1, 0(t0)` 时会访问地址 0x3f8，该地址未映射，vCPU 会退出，交由 KVM，KVM 交由 stratovirt 来处理。根据 vCPU 退出事件类型分别处理。这里只简单处理端口读写和 MMIO 的读写。

```rust
// src/main.rs

use kvm_ioctls::{ Kvm, VcpuExit };

fn main() {
    ...
    loop {
        match vcpu_fd.run().expect("vcpu run failed") {
            VcpuExit::IoIn(addr, data) => {
                println!("VmExit IO in : addr 0x{:x}, data is {}", addr, data[0]);
                break;
            }
            VcpuExit::IoOut(addr, data) => {
                println!("VmExit Out in : addr 0x{:x}, data is {}", addr, data[0]);
                break;
            }
            VcpuExit::MmioRead(addr, _data) => {
                println!("VmExit MMIO read: addr 0x{:x}", addr);
                break;
            }
            VcpuExit::MmioWrite(addr, _data) => {
                println!("VmExit MMIO write: addr 0x{:x}", addr);
                break;
            }
            r => panic!("Unexpected exit reason: {:?}", r)
        }
    }
}
```

运行 `cargo run` 执行之后 vCPU 退出，进而被 host 捕获，打印信息 `VmExit MMIO read: addr 0x3f8` 后程序退出。

## 小结

本文使用 KVM 的 API 通过 vCPU 运行一段汇编语言代码并成功捕获并处理 vCPU 的退出事件。

## 参考资料

- [Linux KVM 文档][001]
- [Using the KVM API][002]

[001]: https://docs.kernel.org/virt/kvm/api.html#api-description
[002]: https://lwn.net/Articles/658511/
