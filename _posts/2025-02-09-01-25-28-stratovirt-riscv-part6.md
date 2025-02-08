---
layout: post
author: '乖乖是干饭王'
title: 'Stratovirt 的 RISC-V 虚拟化支持（六）：PLIC 和 串口支持'
draft: false
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /stratovirt-riscv-part6/
description: 'Stratovirt 的 RISC-V 虚拟化支持（六）：PLIC 和 串口支持'
category:
  - 开源项目
  - RISC-V
tags:
  - Linux
  - RISC-V
  - PLIC
  - 串口
---

> Corrector: [TinyCorrect](https://gitee.com/tinylab/tinycorrect) v0.2-rc2 - [spaces comments codeblock urls pangu]
> Author:    Sunts <stsmail163@163.com>
> Date:      2024/09/13
> Revisor:   Falcon <falcon@tinylab.org>
> Project:   [RISC-V Linux 内核剖析](https://gitee.com/tinylab/riscv-linux)
> Sponsor:   PLCT Lab, ISCAS


## 前言

上文支持了通过 bootloader 模块配合设备树模块进一步完善了引导 Linux 所需的内容，但没有串口就没有输出，无法调试看不到 Linux 的启动 log，更不能接收用户输入。因此，本文增加串口设备支持以及平台级中断控制器 PLIC 支持，PLIC 用于外部中断的接收和递送。

## PLIC 支持

由于 KVM 对 RISC-V 的中断控制器支持尚未有类似 ARM 的 GICV3 可以通过 KVM API 来直接创建设备并通过 KVM API 来调整设备配置。所以在 RISC-V 下的 stratovirt 中需要模拟 PLIC 设备，向下对外部设备需要为每一个中断源提供相应服务，支持中断源的边缘触发和水平触发，向上对 CPU 需要为每一个 vCPU 提供相应服务，支持每一个 vCPU 配置自己的中断使能和中断阈值以及支持每一个 vCPU 中断响应和中断完成信号。

位于 device 子模块下的 plic 模块负责 PLIC 设备的模拟。向下，需要为设备提供中断触发的函数，plic__irq_trig。设备可控制中断触发方式，水平触发还是边缘触发。

```rust
// src/device/plic.rs

/**
@irq: 表示待操作中断的 irq 号
@level: 表示触发中断还是取消中断
@edge: 表示中断触发是否是水平触发
 */
impl PlicState {
    ...
    pub fn plic__irq_trig(&mut self, irq: u32, level: bool, edge: bool) {
        let mut irq_marked: bool = false;
        let (irq_prio, irq_word): (u8, u8);
        let irq_mask: u32;

        if !self.ready {
            return;
        }
        if irq < 0 || self.num_irq <= irq {
            return;
        }
        irq_prio = self.irq_priority[irq as usize];
        irq_word = (irq / 32) as u8;
        irq_mask = 1 << (irq % 32);

        if level {
            self.irq_level[irq_word as usize] |= irq_mask;
        } else {
            self.irq_level[irq_word as usize] &= !irq_mask;
        }

        for i in 0..self.num_context {
            let mut context = &mut self.contexts[i as usize];
            if (context.irq_enable[irq_word as usize] & irq_mask) != 0 {
                if level {
                    context.irq_pending[irq_word as usize] |= irq_mask;
                    context.irq_pending_priority[irq as usize] = irq_prio;
                    if edge {
                        // 边缘触发中断设置中断完成信号之后自动清除挂起中断
                        context.irq_autoclear[irq_word as usize] |= irq_mask;
                    }
                } else {
                    context.irq_pending[irq_word as usize] &= !irq_mask;
                    context.irq_pending_priority[irq as usize] = 0;
                    context.irq_claimed[irq_word as usize] &= !irq_mask;
                    context.irq_autoclear[irq_word as usize] &= !irq_mask;
                }
                self.__plic_context_irq_update(i);
                irq_marked = true;
            }
            if irq_marked {
                break;
            }
        }
    }
}

```

plic 模块向上要为 vCPU 提供服务，vCPU 可以配置相关寄存器来设置是否接收特定类型的中断，以及在响应中断时正确返回待服务的中断 irq 号等。具体包括两个接口：mmio_write 和 mmio_read。

```rust
impl PlicState{
    ...
    pub fn mmio_write(&mut self, addr: u64, data: u32) {
        let mut address = addr & !0x3;
        address -= MEM_LAYOUT[LayoutEntryType::IrqChip as usize].0;
        if PRIORITY_BASE <= address && address < ENABLE_BASE {
            self.plic__priority_write(address, data);
        }else if ENABLE_BASE <= address && address < CONTEXT_BASE {
            let cntx = ((address - ENABLE_BASE) as u32) / ENABLE_PER_HART;
            address -= (cntx * ENABLE_PER_HART) as u64  + ENABLE_BASE;
            if cntx < self.num_context {
                self.plic__context_enable_write(cntx, address, data);
            }
        }else if CONTEXT_BASE <= address && address < REG_SIZE {
            let cntx = ((address - CONTEXT_BASE)as u32) / CONTEXT_PER_HART;
            address -= (cntx * CONTEXT_PER_HART)as u64 + CONTEXT_BASE;
            if cntx < self.num_context {
                self.plic__context_write(cntx, address, data);
            }
        }
    }

    pub fn mmio_read(&mut self, addr: u64) -> u32{
        let mut data: u32 = 0;
        let mut address = addr & !0x3;
        address -= MEM_LAYOUT[LayoutEntryType::IrqChip as usize].0;
        if PRIORITY_BASE <= address && address < ENABLE_BASE {
            return self.plic__priority_read(address);
        }else if ENABLE_BASE <= address && address < CONTEXT_BASE {
            let cntx = ((address - ENABLE_BASE) as u32) / ENABLE_PER_HART;
            address -= (cntx * ENABLE_PER_HART) as u64  + ENABLE_BASE;
            if cntx < self.num_context {
                return self.plic__context_enable_read(cntx, address);
            }
        }else if CONTEXT_BASE <= address && address < REG_SIZE {
            let cntx = ((address - CONTEXT_BASE)as u32) / CONTEXT_PER_HART;
            address -= (cntx * CONTEXT_PER_HART)as u64 + CONTEXT_BASE;
            if cntx < self.num_context {
                return self.plic__context_read(cntx, address);
            }
        }
        0
    }
}
```

plic 模块的其余内部函数不再详细介绍，主要通过 plic 的文档实现了 plic 的模拟功能。

本项目 plic 模块的另外一个重要接口是为 PLIC 设备生成设备树。

```rust
// src/device/plic.rs

impl PlicState {
    ...
    pub fn generate_fdt_node(&self, fdt: &mut Vec<u8>) {
        let node = format!(
            "/interrupt-controller@{:x}",
            MEM_LAYOUT[LayoutEntryType::IrqChip as usize].0
        );
        add_sub_node(fdt, &node);
        set_property_string(fdt, &node, "compatible", "riscv,plic0");
        set_property_array_u32(
            fdt,
            &node,
            "reg",
            &[
                0x0,
                MEM_LAYOUT[LayoutEntryType::IrqChip as usize].0 as u32,
                0x0,
                MEM_LAYOUT[LayoutEntryType::IrqChip as usize].1 as u32,
            ],
        );
        set_property_u32(fdt, &node, "#interrupt-cells", 1);
        set_property(fdt, &node, "interrupt-controller", None);
        set_property_u32(fdt, &node, "riscv,max-priority", (1 << PRIORITY_PER_ID) - 1);
        set_property_u32(fdt, &node, "riscv,ndev", MAX_DEVICES - 1);
        set_property_u32(fdt, &node, "phandle", PHANDLE_PLIC);
        let mut interrupt_extend: Vec<u32> = Vec::new();
        for i in 0..self.num_context / 2 {
            interrupt_extend.push(CPU_PHANDLE_START + i);
            interrupt_extend.push(0xffffffff);
            interrupt_extend.push(CPU_PHANDLE_START + i);
            interrupt_extend.push(0x9);
        }
        set_property_array_u32(fdt, &node, "interrupts-extended", &interrupt_extend[..]);
    }
}
```

## 串口设备和 epoll

串口设备模拟中，需要监听 STDIN_FILENO 这个标准输入文件句柄来监听用户的输入并送入模拟串口的缓冲进而向 vCPU 发送外部中断。

### epoll 实现

首先定义当监听的目标事件发生时，要调用的闭包类型并规定其参数，另外，其必须线程间传递安全。

```rust
pub type NotifierCallback = dyn Fn(EventSet, RawFd) + Send + Sync;
```

定义事件通知的入口结构。

```rust
// / Epoll Event Notifier Entry.
pub struct EventNotifier {
    /// 文件描述符
    pub raw_fd: RawFd,
    /// 监控这个文件描述符的某个特定事件类型
    pub event: EventSet,
    /// 事件发生时的回调函数句柄
    pub handler: Arc<Mutex<Box<NotifierCallback>>>,
}
```

定义 epoll 的结构体。

```rust
pub struct EpollContext {
    /// Epoll 负责真正监听事件
    epoll: Epoll,
    /// 作为事件的 handler
    events: Arc<Mutex<BTreeMap<RawFd, Box<EventNotifier>>>>,
}
```

为 epoll 核心结构体实现对外的接口函数，添加监听事件和控制监听启动。

```rust
impl EpollContext {
    pub fn new() -> Self {
        EpollContext {
            epoll: Epoll::new().unwrap(),
            events: Arc::new(Mutex::new(BTreeMap::new())),
        }
    }
    // 添加监听事件
    pub fn add_event(&mut self, event: EventNotifier) {
        let mut events = self.events.lock().unwrap();
        let raw_fd = event.raw_fd;
        // 首先在事件 handler 中添加
        events.insert(raw_fd, Box::new(event));

        let event = events.get(&raw_fd).unwrap();
        // 其次将事件添加到监听列表
        self.epoll
            .ctl(
                // 表示监听事件增加操作
                ControlOperation::Add,
                // 待监听事件的文件描述符
                raw_fd,
                // 待监听事件的类型和附加参数 event 的地址待事件发生时使用
                EpollEvent::new(event.event, &**event as *const _ as u64),
            )
            .unwrap();
    }

    pub fn run(&self) -> bool {
        let mut ready_events = vec![EpollEvent::default(); READY_EVENT_MAX];

        let ev_count = match self.epoll.wait(READY_EVENT_MAX, -1, &mut ready_events[..]) {
            Ok(ev_count) => ev_count,
            Err(e) if e.raw_os_error() == Some(libc::EINTR) => 0,
            Err(_e) => return false,
        };

        for ready_event in ready_events.iter().take(ev_count) {
            // 事件发生，取出事件添加时传递的 event 地址，转为正确类型
            let event = unsafe {
                let event_ptr = ready_event.data() as *const EventNotifier;
                &*event_ptr as &EventNotifier
            };
            // 调用其回调函数
            let handler = event.handler.lock().unwrap();
            handler(ready_event.event_set(), event.raw_fd);
        }

        true
    }
}
```

### 串口实现

有了 epoll 的支持，现在可以借助 epoll 更快实现串口模拟。

```rust
pub struct Serial {
    /// RBR, Receiver buffer register.
    rbr: VecDeque<u8>,
    /// IER, Interrupt enable register.
    ier: u8,
    /// IIR, interrupt identification register.
    iir: u8,
    /// LCR, Line control register.
    lcr: u8,
    /// MCR, Modem control register.
    mcr: u8,
    /// LSR, Line status register.
    lsr: u8,
    /// MSR, Modem status register.
    msr: u8,
    /// Scratch register.
    scr: u8,
    /// Divisor Latch, 控制波特率
    div: u16,
    /// THR, Transmitter holding register.
    thr_pending: u32,
    /// Operation methods.
    output: Box<dyn io::Write + Send + Sync>,
    /// Plic，用于作为中断源发起外部中断
    serial_ctrl: Option<PlicState>,
    /// state control
    state: u8,
}
```

串口结构体的主要属性为 16550 UART 的常用寄存器组。串口结构体的构造函数负责初始化串口的寄存器组为待操作系统用户初始化的状态。

```rust
impl Serial {
    pub fn new(vm_fd: &VmFd, serial_ctrl: Option<PlicState>) -> Arc<Mutex<Self>> {
        ...
        let serial = Arc::new(Mutex::new(Serial {
            // rbr 寄存器以队列形式处理
            rbr: VecDeque::new(),
            ier: 0,
            // UART_IIR_NO_INT 表示无中断状态
            iir: UART_IIR_NO_INT,
            // 字符字长为 8 bit
            lcr: 0x03, // 8 bits
            // OUT2 信号置 1，全局中断掩码
            mcr: UART_MCR_OUT2,
            // tramsmit holding empty 和 tramsmit empty
            lsr: UART_LSR_TEMT | UART_LSR_THRE,
            // Data Set Ready 和 Clear to Send 和 Carrier Dected 信号
            msr: UART_MSR_DCD | UART_MSR_DSR | UART_MSR_CTS,
            scr: 0,
            div: 0x0c,
            thr_pending: 0,
            output: Box::new(std::io::stdout()),
            serial_ctrl,
            state: 0,
        }));
        ...
    }
}
```

根据串口文档，初始化好串口各寄存器的状态之后，利用 epoll 来监听标准输入。设置 handler 处理监听事件的发生，并启动监听线程开始执行。

```rust
impl Serial {
    pub fn new(vm_fd: &VmFd, serial_ctrl: Option<PlicState>) -> Arc<Mutex<Self>> {
        ...
        let mut epoll = EpollContext::new();
        let handler: Box<dyn Fn(EventSet, RawFd) + Send + Sync> = Box::new(move |event, _| {
            if event == EventSet::IN && serial_clone.lock().unwrap().stdin_exce().is_err() {
                println!("Failed to excecute the stdin");
            }
        });

        let notifier = EventNotifier::new(
            libc::STDIN_FILENO,
            EventSet::IN,
            Arc::new(Mutex::new(handler)),
        );

        epoll.add_event(notifier);

        let _ = thread::Builder::new()
            .name("serial".to_string())
            .spawn(move || loop {
                if serial_clone1.lock().unwrap().state & STOP_SIGNAL != 0 {
                    break;
                }
                if !epoll.run() {
                    break;
                }
            });
    }
}
```

当用户有输入时，触发串口的 stdin_exec 函数，处理用户输入内容。将用户输入作为 RBR 寄存器的内容，同时通过 PLIC 发起中断告知 vCPU 有外部输入。

```rust
fn update_iir(&mut self) -> Result<()> {
    let mut iir = UART_IIR_NO_INT;
    // Data Ready Interrupt enable && Data Ready Signal
    if self.ier & UART_IER_RDI != 0 && self.lsr & UART_LSR_DR != 0 {
        iir &= !UART_IIR_NO_INT;
        iir |= UART_IIR_RDI;

    // Transmit Holding Reg Intr && thr_pending
    } else if self.ier & UART_IER_THRI != 0 && self.thr_pending > 0 {
        iir &= !UART_IIR_NO_INT;
        // THR Empty Interupt
        iir |= UART_IIR_THRI;
    }

    self.iir = iir;

    if iir != UART_IIR_NO_INT {
        // 触发 PLIC 的外部中断
        self.serial_ctrl.as_ref().unwrap().interrupt_trigger();
    }

    Ok(())
}
fn receive(&mut self, data: &[u8]) -> Result<()> {
    if self.mcr & UART_MCR_LOOP == 0 {
        if self.rbr.len() >= RECEIVER_BUFF_SIZE {
            return Err(Error::Overflow(self.rbr.len(), RECEIVER_BUFF_SIZE));
        }

        self.rbr.extend(data);
        // Data Ready Signal
        self.lsr |= UART_LSR_DR;
        // 更新中断状态
        self.update_iir()?;
    }

    Ok(())
}
fn stdin_exce(&mut self) -> Result<()> {
        let mut out = [0_u8; 64];
        if let Ok(count) = std::io::stdin().lock().read_raw(&mut out) {
            self.receive(&out[..count])
        } else {
            Ok(())
        }
    }
```

串口面向操作系统的重要接口为读写功能，供 Guest OS 读用户输入、配置串口、向屏幕输出字符。

读接口用于读取串口相关寄存器。

```rust
pub fn read(&mut self, offset: u64) -> u8 {
    let mut ret: u8 = 0;

    match offset {
        0 => {
            if self.lcr & UART_LCR_DLAB != 0 {
                // 读除数值低位寄存器
                ret = self.div as u8;
            } else {
                // 返回最新的接收到的用户输入
                if !self.rbr.is_empty() {
                    ret = self.rbr.pop_front().unwrap_or_default();
                }
                // 为空，则更新状态不为 Data Ready
                if self.rbr.is_empty() {
                    self.lsr &= !UART_LSR_DR;
                }
                // 更新中断状态
                if self.update_iir().is_err() {
                    println!(
                        "Failed to update iir for reading the register {} of serial",
                        offset
                    );
                }
            }
        }
        1 => {
            if self.lcr & UART_LCR_DLAB != 0 {
                // 读除数值寄存器高位
                ret = (self.div >> 8) as u8;
            } else {
                // IER 寄存器
                ret = self.ier
            }
        }
        2 => {
            // 16550 中高 2bit 必须有效
            ret = self.iir | 0xc0;
            // 无数据传输
            self.thr_pending = 0;
            // 无中断
            self.iir = UART_IIR_NO_INT
        }
        3 => {
            ret = self.lcr;
        }
        4 => {
            ret = self.mcr;
        }
        5 => {
            ret = self.lsr;
        }
        6 => {
            if self.mcr & UART_MCR_LOOP != 0 {
                // loop back 状态
                ret = (self.mcr & 0x0c) << 4;
                ret |= (self.mcr & 0x02) << 3;
                ret |= (self.mcr & 0x01) << 5;
            } else {
                ret = self.msr;
            }
        }
        7 => {
            ret = self.scr;
        }
        _ => {}
    }
    ret
}
```

写接口用于根据 Guest OS 传递的偏移写相关串口寄存器。

```rust
pub fn write(&mut self, offset: u64, data: u8) -> Result<()> {
    match offset {
        0 => {
            if self.lcr & UART_LCR_DLAB != 0 {
                // 写除数值寄存器低位
                self.div = (self.div & 0xff00) | u16::from(data);
            } else {
                // 写 THR 寄存器，传输数据
                self.thr_pending = 1;

                if self.mcr & UART_MCR_LOOP != 0 {
                    // loopback mode
                    if self.rbr.len() >= RECEIVER_BUFF_SIZE {
                        return Err(Error::Overflow(self.rbr.len(), RECEIVER_BUFF_SIZE));
                    }

                    self.rbr.push_back(data);
                    self.lsr |= UART_LSR_DR;
                } else {
                    // 向 stdout 写数据
                    self.output.write_all(&[data]).map_err(Error::IoError)?;
                    self.output.flush().map_err(Error::IoError)?;
                }
                // 更新中断状态
                self.update_iir()?;
            }
        }
        1 => {
            if self.lcr & UART_LCR_DLAB != 0 {
                // 写除数值寄存器高位
                self.div = (self.div & 0x00ff) | (u16::from(data) << 8);
            } else {
                let changed = (self.ier ^ data) & 0x0f;
                self.ier = data & 0x0f;

                if changed != 0 {
                    self.update_iir()?;
                }
            }
        }
        3 => {
            self.lcr = data;
        }
        4 => {
            self.mcr = data;
        }
        7 => {
            self.scr = data;
        }
        _ => {}
    }

    Ok(())
}
```

## 实验结果

至此，起操作系统所需的基本内容已经全部完备，vCPU，内存，bootloader，ramdisk 和设备树，PLIC，串口。通过 `cargo run` 命令启动 stratovirt 之后即可成功启动一个使用 ramdisk 的由 RISC-V 虚拟化支持的 Linux。

![Image Description](/wp-content/uploads/2022/03/riscv-linux/images/stratovirt-riscv/linux-stratovirt.jpg)

## 总结

项目至此已经包含了 KVM 虚拟化在 RISC-V 架构下使用的所有关键步骤，验证了在 RISC-V 下 stratovirt 的可行性。为学习虚拟化，实现 PLIC 模拟，学习串口设备模拟和控制，以及从模拟真实硬件设备角度理解操作系统行为等各方面都提供了参考。

## 参考资料

- [byteRunner 串口资料][001]

[001]: http://byterunner.com/16550.html
