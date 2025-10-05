const kstd = @import("../kstd.zig");
const idt = @import("idt.zig");
const io = @import("io.zig");

pub const irq_offset = 0x20;

const Pic = struct {
    const Self = @This();

    addr: u16,

    pub fn cmd(self: Self) u16 {
        return self.addr;
    }

    pub fn data(self: Self) u16 {
        return self.addr + 1;
    }
};

// (master) Handles IRQs 0x00 -> 0x07.
const pic1 = Pic{ .addr = 0x20 };

// (secondary) Handles IRQs 0x08 -> 0x0f.
const pic2 = Pic{ .addr = 0xa0 };

pub const InitProof = kstd.types.UniqueProof();

// Initializes PICs and remaps their vectors to start at 0x20 to avoid ambiguity with IDT
// exception ISRs.
pub fn init(idt_proof: idt.InitProof) !InitProof {
    try idt_proof.prove();

    const proof = try InitProof.new();

    // ICW1: Start init.
    io.outb(pic1.cmd(), InitControlWord1.init | InitControlWord1.icw4);
    io.wait();
    io.outb(pic2.cmd(), InitControlWord1.init | InitControlWord1.icw4);
    io.wait();

    // ICW2: Set vector table offsets so there are no conflicts with between cpu interrupts and hardware interrupts.
    io.outb(pic1.data(), irq_offset);
    io.wait();
    io.outb(pic2.data(), irq_offset + 8);
    io.wait();

    // ICW3: Tell master PIC there's a secondary at IRQ2 (0000_0100).
    io.outb(pic1.data(), 0x04);
    io.wait();

    // ICW3: Tell secondary PIC its cascade identity (0000_0010).
    // TODO: what the hell is a cascade identity
    io.outb(pic2.data(), 0x02);
    io.wait();

    // ICW4: Put PICs in 8086 mode.
    // TODO: also what's the difference between 8080 and 8086 mode?
    io.outb(pic1.data(), InitControlWord4.@"8086Mode");
    io.wait();
    io.outb(pic2.data(), InitControlWord4.@"8086Mode");
    io.wait();

    // Unmask PICs.
    io.outb(pic1.data(), 0);
    io.outb(pic2.data(), 0);

    return proof;
}

pub fn eoi(irq: u8) void {
    eoiRaw(irq_offset + irq);
}

fn eoiRaw(irq: u8) void {
    if (irq >= 8) {
        io.outb(pic2.cmd(), @intFromEnum(PicCmd.eoi));
    }

    io.outb(pic1.cmd(), @intFromEnum(PicCmd.eoi));
}

pub fn getMask() u16 {
    const pic1_mask = io.inb(pic1.data());
    const pic2_mask = io.inb(pic2.data());

    return @as(u16, pic1_mask) | (@as(u16, pic2_mask) << 8);
}

pub fn setMask(mask: u16) void {
    io.outb(pic1.data(), @truncate(mask));
    io.outb(pic2.data(), @truncate(mask >> 8));
}

// NOTE: IRQ2 on PIC1 is wired to PIC2, so masking IRQ2 will mask the secondary PIC entirely
pub fn maskIRQ(irq: u4) void {
    const port, const pic_irq = blk: {
        if (irq < 8) {
            break :blk .{ pic1.data(), irq };
        } else {
            break :blk .{ pic2.data(), irq - 8 };
        }
    };

    const mask = io.inb(port);
    const new_mask = mask | (1 << pic_irq);

    io.outb(port, new_mask);
}

pub fn unmaskIRQ(irq: u4) void {
    const port, const pic_irq = blk: {
        if (irq < 8) {
            break :blk .{ pic1.data(), irq };
        } else {
            break :blk .{ pic2.data(), irq - 8 };
        }
    };

    const mask = io.inb(port);
    const new_mask = mask & ~(1 << pic_irq);

    io.outb(port, new_mask);
}

pub fn getIRR() u16 {
    return getIRQReg(0x0a);
}

pub fn getISR() u16 {
    return getIRQReg(0x0b);
}

fn getIRQReg(cmd: u8) u16 {
    io.outb(pic1.cmd(), cmd);
    io.outb(pic2.cmd(), cmd);

    const res = @as(u16, io.inb(pic2.cmd())) << 8 | @as(u16, io.inb(pic1.cmd()));
    return res;
}

const PicCmd = enum(u8) {
    eoi = 0x20,
};

const InitControlWord1 = struct {
    // Indicates ICW4 will be present.
    pub const icw4 = 0x01;

    // Single (cascade) mode.
    pub const single = 0x02;

    // Call address interval 4.
    pub const interval4 = 0x04;

    // Level triggered (edge) mode.
    pub const level = 0x08;

    // Initialization.
    pub const init = 0x10;
};

const InitControlWord4 = struct {
    // 8086 mode.
    pub const @"8086Mode" = 0x01;
};
