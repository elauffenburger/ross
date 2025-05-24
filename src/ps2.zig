const std = @import("std");

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
    // TODO: initialize USB controllers.

    // TODO: make sure PS/2 controller exists.

    // Disable both ports.
    io.outb(Ports.cmd, 0xad);
    io.outb(Ports.cmd, 0xa7);

    // Flush output buffer.
    _ = io.inb(Ports.data);

    // Set controller config.
    {
        // Get the PS/2 controller config and set things up so we can run tests.
        var config = controller.config();
        config.port1InterruptsEnabled = false;
        config.port1ClockDisabled = false;
        config.port2TranslationEnabled = false;

        // Write the config back
        io.outb(Ports.cmd, 0x60);
        io.outb(Ports.cmd, @bitCast(config));
    }

    // Perform controller self-test.
    {
        io.outb(Ports.cmd, 0xaa);

        const res = controller.pollResponse();
        if (res == 0x55) {
            vga.printf("ps/2 self-test: pass!\n", .{});
        } else {
            vga.printf("ps/2 self-test: fail! ({b})\n", .{res});
        }
    }

    // Check if there's a second channel.
    {
        // Enable the second port.
        io.outb(Ports.cmd, 0xa8);

        // Get the config byte to see if the second port clock is disabled; if it is, then there isn't a second port.
        const config = controller.config();
        dev2.verified = !config.port2ClockDisabled;
    }

    // Perform interface test.
    {
        io.outb(Ports.cmd, 0xab);

        const res = controller.pollResponse();
        if (res == 0x00) {
            vga.printf("ps/2 interface test: pass!\n", .{});
        } else {
            vga.printf("ps/2 interface test: fail! ({b})\n", .{res});
        }
    }

    // Re-enable devices and reset.
    {
        // Enable port 1.
        io.outb(Ports.cmd, 0xae);

        // Enable port 2 if it exists.
        if (dev2.verified) {
            io.outb(Ports.cmd, 0xa8);
        }

        // Get the PS/2 controller config and re-enable interrupts
        var config = controller.config();
        config.port1InterruptsEnabled = true;
        config.port2InterruptsEnabled = true;

        // Write the config back
        io.outb(Ports.cmd, 0x60);
        io.outb(Ports.cmd, @bitCast(config));
    }

    // Reset devices.
    {
        resetDevice(dev1);
        resetDevice(dev2);
    }

    vga.writeStr("ps/2 interface 1 OK!\n");
    if (dev2.verified) {
        vga.writeStr("ps/2 interface 2 OK!\n");
    }
}

fn resetDevice(dev: anytype) void {
    // Send reset.
    dev.writeData(0xff);

    switch (dev.waitForByte()) {
        0xfa => {
            switch (dev.waitForByte()) {
                0xaa => {
                    const dev_id = dev.waitForByte();
                    _ = dev_id; // autofix
                },
                else => {
                    // TODO: unknown
                },
            }
        },
        0xaa => {
            switch (dev.waitForByte()) {
                0xfa => {
                    const dev_id = dev.waitForByte();
                    _ = dev_id; // autofix
                },
                else => {
                    // TODO: unknown
                },
            }
        },
        0xfc => {
            // TODO: fail
        },
        else => {
            // TODO: not populated
        },
    }
}

fn Device(comptime dev: enum { one, two }, assumeVerified: bool) type {
    return struct {
        const Self = @This();

        verified: bool = assumeVerified,

        var queued: ?u8 = null;

        pub fn writeData(_: Self, byte: u8) void {
            switch (dev) {
                .one => {},
                .two => {
                    // Tell the controller we're going to write to port two.
                    io.outb(Ports.cmd, 0xd4);
                },
            }

            // Wait for the input buffer to be clear.
            while (controller.status().inputBufferFull) {}

            // Write our byte.
            io.outb(Ports.data, byte);
        }

        pub fn waitForByte(_: Self) u8 {
            while (queued == null) {}

            return queued.?;
        }

        pub inline fn recv(_: Self) void {
            if (queued != null) {
                // TODO: what do?
            }

            queued = io.inb(Ports.data);
        }
    };
}

pub var dev1 = Device(.one, true){};
pub var dev2 = Device(.two, false){};

const controller = struct {
    const Self = @This();

    pub fn status() StatusRegister {
        return @bitCast(io.inb(Ports.cmd));
    }

    pub fn config() ControllerConfig {
        // Request config byte.
        io.outb(Ports.cmd, 0x20);

        // Read the response as our struct.
        return @bitCast(pollResponse());
    }

    pub fn pollResponse() u8 {
        // Wait for the controller to write the response.
        while (!status().outputBufferFull) {}

        // Read the response.
        return io.inb(Ports.data);
    }
};
