const io = @import("io.zig");
const pic = @import("pic.zig");
const vga = @import("vga.zig");

const Ports = struct {
    // Read: data from device
    // Write: data to device
    pub const data = 0x60;

    // Read: status register.
    // Write: command register (sends commands to controller).
    pub const cmd = 0x64;
};

const StatusRegister = packed struct(u8) {
    // Must be set before attempting to read from IO port.
    outputBufferFull: bool,

    // Must be clear before attempting to write to IO port.
    inputBufferFull: bool,

    _r1: u1,

    inputFor: enum(u1) {
        // Data in input buffer is for ps/2 device.
        data = 0,

        // Data in input buffer is for ps/2 controller command.
        command = 1,
    },

    _r2: u1,
    _r3: u1,

    timeoutErr: bool,
    parityError: bool,
};

const ControllerConfig = packed struct(u8) {
    port1InterruptsEnabled: bool,
    port2InterruptsEnabled: bool,
    systemPOSTed: bool,
    _r1: u1 = 0,
    port1ClockDisabled: bool,
    port2ClockDisabled: bool,

    // Translates scan codes to scan code 1 for compatibility reasons.
    port2TranslationEnabled: bool,

    // NOTE: this must be zero. don't know why.
    _r2: u1 = 0,
};

// See https://wiki.osdev.org/I8042_PS/2_Controller#Initialising_the_PS/2_Controller
//
// NOTE: there's a bunch of stuff we _should_ do...and we're not going to do any of it for now because it requires ACPI and stuff :)
pub fn init() void {
    // Disable both ports.
    io.outb(Ports.cmd, 0xad);
    io.outb(Ports.cmd, 0xa7);

    // Flush output buffer.
    _ = io.inb(Ports.data);

    // Set controller config.
    {
        // Save the PIC mask before we disable all interrupts.
        const pic_mask = pic.getMask();

        // Disable PIC interrupts before we work with the PS/2 controller.
        pic.setMask(0xffff);

        // Get the PS/2 controller config and disable .
        var config = getControllerConfig();
        config.port1InterruptsEnabled = false;
        config.port1ClockDisabled = false;
        config.port2TranslationEnabled = false;

        // TODO: is this right?
        config.port2InterruptsEnabled = false;

        // Write the config back
        io.outb(Ports.cmd, 0x60);
        io.outb(Ports.cmd, @bitCast(config));

        // Restore the PIC mask.
        pic.setMask(pic_mask);
    }

    // Perform self-test.
    {
        io.outb(Ports.cmd, 0xaa);

        const res = waitForData();
        if (res == 0x55) {
            vga.printf("ps/2 self-test: pass!\n", .{});
        } else {
            vga.printf("ps/2 self-test: fail! ({b})\n", .{res});
        }
    }

    // Perform interface test.
    {
        io.outb(Ports.cmd, 0xab);

        const res = waitForData();
        if (res == 0x00) {
            vga.printf("ps/2 interface test: pass!\n", .{});
        } else {
            vga.printf("ps/2 interface test: fail! ({b})\n", .{res});
        }
    }
}

fn getStatus() StatusRegister {
    return @bitCast(io.inb(Ports.cmd));
}

fn getControllerConfig() ControllerConfig {
    // Request config byte.
    io.outb(Ports.cmd, 0x20);

    // Read the config byte as our struct.
    return @bitCast(waitForData());
}

fn waitForData() u8 {
    // Wait for the output buffer bit to be flipped.
    while (!getStatus().outputBufferFull) {}

    // Read the config byte as our struct.
    return io.inb(Ports.data);
}
