---
layout: post
author: '乖乖是干饭王'
title: 'Stratovirt 的 RISC-V 虚拟化支持（二）：库的 RISC-V 适配'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /stratovirt-riscv-part2/
description: 'Stratovirt 的 RISC-V 虚拟化支持（二）：库的 RISC-V 适配'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - Stratovirt
  - KVM
  - 虚拟化
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [urls refs]
> Author:    Sunts <stsmail163@163.com>
> Date:      2024/09/02
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

前文提到，Stratovirt 是一种基于 Linux 内核虚拟化（KVM）的开源轻量级虚拟化技术。而在 RUST 中调用 KVM 的接口的重要的两个库分别为：kvm-ioctls 和 kvm-bindings。

kvm-ioctls 为 KVM API 提供了安全的封装，KVM API 是一组用于在 Linux 上创建和配置虚拟机（VMs）的 ioctl（输入/输出控制）调用。这个库通过四个主要结构来提供对 ioctl 的访问。Kvm 封装了系统级的 ioctl 调用。这些 ioctl 通常涉及到 KVM 子系统的初始化和配置，比如启用 KVM 功能等。VmFd 封装了针对虚拟机实例的 ioctl 调用。这些 ioctl 通常用来创建一个新的虚拟机实例、设置虚拟机的属性或者获取虚拟机的状态信息。VcpuFd 封装了针对虚拟 CPU 实例的 ioctl 调用。这些 ioctl 可以用来启动、停止虚拟 CPU，或者向虚拟 CPU 注册内存区域等。DeviceFd 封装了针对设备的 ioctl 调用。这些 ioctl 用于添加或移除虚拟设备，比如虚拟硬盘、网络接口卡等。

kvm-bindings 提供了与 Linux 内核中的 KVM（Kernel-based Virtual Machine）模块交互的 FFI（Foreign Function Interface）绑定。

Stratovirt 的 mini_stratovirt_edu 分支库中 kvm-ioctls 的版本为 0.6.0，kvm-bindings 的版本为 0.3.0。本次的库适配保持和其要求的一致。

## kvm-bindings 库的 RISC-V 支持

kvm-bindings 库使用 bindgen 工具从特定内核版本的头文件中静态生成绑定代码，并支持 x86_64 和 arm64 这两种目标架构。

安装 bindgen 工具，官方目前使用版本为 0.64.0。

```shell
cargo install bindgen-cli --vers 0.64.0
```

下载 Linux 内核源码。

```shell
git clone https://github.com/torvalds/linux.git
```

下载库对应版本的源码，解压缩。

```shell
wget https://github.com/rust-vmm/kvm-bindings/archive/refs/tags/v0.3.0.tar.gz
tar -xzvf v0.3.0.tar.gz
```

为 RISC-V 生成 kvm 绑定内容。假设当前目录中同时有 kvm-bindings-0.3.0 和 linux 两个文件夹。

```shell
# 建立架构相关文件夹

pushd kvm-bindings-0.3.0
mkdir src/riscv
popd

pushd linux
# 切换到所需版本的分支

git checkout v6.9

# 使用 bindgen 生成绑定内容

export ARCH=riscv
make headers_install ARCH=$ARCH INSTALL_HDR_PATH="$ARCH"_headers
pushd "$ARCH"_headers
bindgen include/linux/kvm.h -o bindings.rs  \
     --impl-debug --with-derive-default  \
     --with-derive-partialeq  --impl-partialeq \
     -- -Iinclude
popd

popd
# 拷贝生成的文件到 kvm-bindings 库中
cp linux/"$ARCH"_headers/bindings.rs kvm-bindings-0.3.0/src/riscv
```

修改 kvm-bindings-0.3.0/src/lib.rs，添加 RISC-V 架构相关内容。

```rust
#[cfg(target_arch = "riscv64")]
mod riscv;
#[cfg(target_arch = "riscv64")]
pub use self::riscv::*;
```

## kvm-ioctls 库的 RISC-V 支持

下载库对应版本的源码，解压缩。

```shell
wget https://github.com/rust-vmm/kvm-ioctls/archive/refs/tags/v0.6.0.tar.gz
tar -xzvf v0.6.0.tar.gz
```

根据 linux 内核的 kvm 文档，搜索 RISC-V 架构相关的 kvm 内容，并在 kvm-ioctls 中做对应架构调整。

### KVM_INTERRUPT

KVM_INTERRUPT 用于 VCPU 外部中断相关操作。

```c
# linux 内核中对 KVM_INTERRUPT 的定义
#define KVM_INTERRUPT             _IOW(KVMIO,  0x86, struct kvm_interrupt)
```

RUST 中有类似用于定义 ioctl 操作的宏 ioctl_iow_nr，修改 src/kvm_ioctls.rs 添加定义即可。

```rust
# src/kvm_ioctls.rs: 98

ioctl_io_nr!(KVM_INTERRUPT, KVMIO, 0x86, kvm_interrupt);
```

该宏展开之后为如下形式，以函数形式调用，返回一个能够代表 KVM_INTERRUPT 这一操作的唯一的无符号 64bit 整数。（宏内部未展开部分全都是整数，其具体的值见 kvm-bindings 库中的声明）。

```rust
pub fn KVM_INTERRUPT() -> std::os::raw::c_ulong {
    (
        (_IOC_WRITE << _IOC_DIRSHIFT)
        | (KVMIO << _IOC_TYPESHIFT)
        | (0x86 << _IOC_NRSHIFT)
        | (std::mem::size_of::<kvm_interrupt>() as u32 << _IOC_SIZESHIFT)
    ) as std::os::raw::c_ulong
}
```

要支持设置和清除 VCPU 的外部中断，需用到 `ioctl_io_nr!(KVM_INTERRUPT, KVMIO, 0x86, kvm_interrupt);` 的结果。需要在 VcpuFd 的成员函数中添加架构相关代码，具体修改如下：

```rust
# src/ioctls/vcpu.rs

impl VcpuFd {
...
    /// This sets pending external interrupt for a virtual CPU
    ///
    /// see documentation for 'KVM_INTERRUPT' in the
    /// [KVM API documentation](https://www.kernel.org/doc/Documentation/virtual/kvm/api.txt)
    #[cfg(any(target_arch = "riscv64"))]
    pub fn set_interrupt(&self) -> Result<()> {
        let interrupt = kvm_interrupt {
            irq: KVM_INTERRUPT_SET as u32,
        };
        let ret = unsafe { ioctl_with_ref(self, KVM_INTERRUPT(), &interrupt)  };
        if ret != 0 {
            return Err(errno::Error::last());
        }
        Ok(())
    }

    /// This unsets pending external interrupt for a virtual CPU
    ///
    /// see documentation for 'KVM_INTERRUPT' in the
    /// [KVM API documentation](https://www.kernel.org/doc/Documentation/virtual/kvm/api.txt)
    #[cfg(any(target_arch = "riscv64"))]
    pub fn unset_interrupt(&self) -> Result<()> {
        let interrupt = kvm_interrupt {
            irq: KVM_INTERRUPT_UNSET as u32,
        };
        let ret = unsafe { ioctl_with_ref(self, KVM_INTERRUPT(), &interrupt)  };
        if ret != 0 {
            return Err(errno::Error::last());
        }
        Ok(())
    }

```

### KVM_GET_MP_STATE 和 KVM_SET_MP_STATE

KVM_GET_MP_STATE 用于返回当前 VCPU 的内部多处理器状态。返回值为 kvm_mp_state 结构体。

KVM_SET_MP_STATE 用于设置当前 VCPU 的内部多处理器状态。所需参数为 kvm_mp_state 结构体。

kvm_mp_state 定义如下所示：

```rust
#[repr(C)]
#[derive(Debug, Default, Copy, Clone, PartialEq)]
pub struct kvm_mp_state {
     pub mp_state:__u32,
}
```

其中，mp_state 所有有效的值中对 RISC-V 有效的值为 KVM_MP_STATE_RUNNABLE 代表 VCPU 正在运行以及 KVM_MP_STATE_STOPPED 代表 VCPU 停止。

kvm-ioctls 库中定义了宏 KVM_GET_MP_STATE 和 KVM_SET_MP_STATE 以及函数 get_mp_state 和 set_mp_state，只需添加 rv64 支持。

```rust
// src/kvm_ioctls.rs

#[cfg(any(
    target_arch = "x86",
    target_arch = "x86_64",
    target_arch = "arm",
    target_arch = "aarch64",
    target_arch = "s390",
    target_arch = "riscv64"
))]
ioctl_ior_nr!(KVM_GET_MP_STATE, KVMIO, 0x98, kvm_mp_state);
/* Available with KVM_CAP_MP_STATE */
#[cfg(any(
    target_arch = "x86",
    target_arch = "x86_64",
    target_arch = "arm",
    target_arch = "aarch64",
    target_arch = "s390",
    target_arch = "riscv64"
))]
ioctl_iow_nr!(KVM_SET_MP_STATE, KVMIO, 0x99, kvm_mp_state);

 // src/ioctls/vcpu.rs

 627     #[cfg(any(
 628         target_arch = "x86",
 629         target_arch = "x86_64",
 630         target_arch = "arm",
 631         target_arch = "aarch64",
 632         target_arch = "s390",
 633         target_arch = "riscv64"
 634     ))]
 635     pub fn get_mp_state(&self) -> Result<kvm_mp_state> {
 636     ...

 669     #[cfg(any(
 670         target_arch = "x86",
 671         target_arch = "x86_64",
 672         target_arch = "arm",
 673         target_arch = "aarch64",
 674         target_arch = "s390",
 675         target_arch = "riscv64"
 676     ))]
 677     pub fn set_mp_state(&self, mp_state: kvm_mp_state) -> Result<()> {
 678     ...
```

### KVM_SET_ONE_REG 和 KVM_GET_ONE_REG

KVM_GET_ONE_REG 用于获取 VCPU 中单个寄存器的值。

KVM_SET_ONE_REG 用于设置 VCPU 中单个寄存器的值。

kvm-ioctls 库中定义了宏 KVM_GET_ONE_REG 和 KVM_SET_ONE_REG 以及函数 get_one_reg 和 set_one_reg，只需添加 rv64 支持。

```rust
// src/kvm_ioctls.rs

#[cfg(any(target_arch = "arm", target_arch = "aarch64", target_arch = "riscv64"))]
ioctl_iow_nr!(KVM_GET_ONE_REG, KVMIO, 0xab, kvm_one_reg);
#[cfg(any(target_arch = "arm", target_arch = "aarch64", target_arch = "riscv64"))]
ioctl_iow_nr!(KVM_SET_ONE_REG, KVMIO, 0xac, kvm_one_reg);

// src/ioctls/vcpu.rs

1103     /// Sets the value of one register for this vCPU.
1104     ///
1105     /// The id of the register is encoded as specified in the kernel documentation
1106     /// for `KVM_SET_ONE_REG`.
1107     ///
1108     /// # Arguments
1109     ///
1110     /// * `reg_id` - ID of the register for which we are setting the value.
1111     /// * `data` - value for the specified register.
1112     ///
1113     #[cfg(any(target_arch = "arm", target_arch = "aarch64", target_arch = "riscv64"))]
1114     pub fn set_one_reg(&self, reg_id: u64, data: u64) -> Result<()> {
1115     ...

1129     /// Returns the value of the specified vCPU register.
1130     ///
1131     /// The id of the register is encoded as specified in the kernel documentation
1132     /// for `KVM_GET_ONE_REG`.
1133     ///
1134     /// # Arguments
1135     ///
1136     /// * `reg_id` - ID of the register.
1137     ///
1138     #[cfg(any(target_arch = "arm", target_arch = "aarch64", target_arch = "riscv64"))]
1139     pub fn get_one_reg(&self, reg_id: u64) -> Result<u64> {
1140     ...
```

### 检查其余部分

检查 kvm 文档中适用于所有架构的内容是否在 kvm-ioctls 中有架构限制。做对应修改即可。

例如：KVM_CREATE_VCPU、KVM_GET_VCPU_MMAP_SIZE、KVM_CHECK_EXTENSION 等等。一般不用做任何修改。

## 小结

库适配工作并不困难，内容上比较繁琐需要细心比对。

## 参考资料

- [Linux 内核 kvm 文档][001]
- [kvm-bindings 官方架构移植文档][002]
- [kvm-ioctls][003]

[001]: https://docs.kernel.org/virt/kvm/api.html#api-description
[002]: https://github.com/rust-vmm/kvm-bindings/blob/main/CONTRIBUTING.md
[003]: https://github.com/rust-vmm/kvm-ioctls
