const io = @import("io.zig");

pub const Pic = struct {
    const Self = @This();

    addr: u16,

    pub inline fn cmd(self: Self) u16 {
        return self.addr;
    }

    pub inline fn data(self: Self) u16 {
        return self.addr + 1;
    }
};

// (master) Handles IRQs 0x00 -> 0x07.
const pic1 = Pic{ .addr = 0x20 };

// (secondary) Handles IRQs 0x08 -> 0x0f.
const pic2 = Pic{ .addr = 0xa0 };

// Initializes PICs and remaps their vectors to start at 0x20 to avoid ambiguity with IDT
// exception ISRs.
pub fn init() void {
    // ICW1: Start init.
    io.outb(pic1.cmd(), InitControlWord1.init | InitControlWord1.icw4);
    io.wait();
    io.outb(pic2.cmd(), InitControlWord1.init | InitControlWord1.icw4);
    io.wait();

    // ICW2: Set vector table offsets.
    io.outb(pic1.cmd(), 0x20);
    io.wait();
    io.outb(pic2.cmd(), 0x28);
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
}

pub inline fn eoi(irq: u8) void {
    if (irq >= 8) {
        io.outb(pic2.cmd(), @intFromEnum(PicCmd.eoi));
    }

    io.outb(pic1.cmd(), @intFromEnum(PicCmd.eoi));
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
    pub const init = 0x16;
};

const InitControlWord4 = struct {
    // 8086 mode.
    pub const @"8086Mode" = 0x01;
};
