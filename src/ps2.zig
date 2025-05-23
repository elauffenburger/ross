const io = @import("io.zig");
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
    port1IntEnabled: bool,
    port2IntEnabled: bool,
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
        // NOTE: to future Eric: this is triple faulting because we need to disable the PICs
        // before doing this or IRQs will still fire!
        var config = getControllerConfig();
        config.port1IntEnabled = false;
        config.port2TranslationEnabled = false;
        config.port1ClockDisabled = false;

        // Write the config back
        io.outb(Ports.cmd, 0x60);
        io.outb(Ports.cmd, @bitCast(config));
    }

    // Perform self-test.
    io.outb(Ports.cmd, 0xaa);
}

fn getStatus() StatusRegister {
    return @bitCast(io.inb(Ports.cmd));
}

fn getControllerConfig() ControllerConfig {
    // Request config byte.
    io.outb(Ports.cmd, 0x20);

    // Wait for the output buffer bit to be flipped.
    while (!getStatus().outputBufferFull) {}

    // Read the config byte as our struct.
    return @bitCast(io.inb(Ports.data));
}
