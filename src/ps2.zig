const std = @import("std");

const io = @import("io.zig");
const pic = @import("pic.zig");
const vga = @import("vga.zig");

const IOPort = struct {
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
    systemPOSTed: bool = true,
    _r1: u1 = 0,
    port1ClockDisabled: bool,
    port2ClockDisabled: bool,

    // Translates scan codes to scan code 1 for compatibility reasons.
    port1TranslationEnabled: bool,

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
    io.outb(IOPort.cmd, 0xad);
    io.outb(IOPort.cmd, 0xa7);

    // Flush output buffer.
    _ = io.inb(IOPort.data);

    // Set controller config.
    {
        // Get the PS/2 controller config and set things up so we can run tests.
        var config = ctrlr.pollConfig();
        config.port1InterruptsEnabled = false;
        config.port1ClockDisabled = false;
        config.port1TranslationEnabled = false;

        // Write the config back
        io.outb(IOPort.cmd, 0x60);
        io.outb(IOPort.cmd, @bitCast(config));
    }

    // Perform controller self-test.
    {
        io.outb(IOPort.cmd, 0xaa);

        const res = ctrlr.pollData();
        if (res == 0x55) {
            vga.printf("ps/2 self-test: pass!\n", .{});
        } else {
            vga.printf("ps/2 self-test: fail! ({b})\n", .{res});
        }
    }

    // Check if there's a second channel.
    {
        // Enable the second port.
        io.outb(IOPort.cmd, 0xa8);

        // Get the config byte to see if the second port clock is disabled; if it is, then there isn't a second port.
        const config = ctrlr.pollConfig();
        port2.verified = !config.port2ClockDisabled;
    }

    // Perform interface test.
    {
        // Test Port 1.
        {
            io.outb(IOPort.cmd, 0xab);

            const res = ctrlr.pollData();
            if (res == 0) {
                vga.printf("ps/2 interface 1 test: pass!\n", .{});
            } else {
                vga.printf("ps/2 interface 1 test: fail! ({b})\n", .{res});
            }
        }

        // Test Port 2.
        if (port2.verified) {
            io.outb(IOPort.cmd, 0xa9);

            const res = ctrlr.pollData();
            if (res == 0) {
                vga.printf("ps/2 interface 2 test: pass!\n", .{});
            } else {
                vga.printf("ps/2 interface 2 test: fail! ({b})\n", .{res});
            }
        }
    }

    // Re-enable devices and reset.
    {
        // Enable port 1.
        io.outb(IOPort.cmd, 0xae);

        // Enable port 2 if it exists.
        if (port2.verified) {
            io.outb(IOPort.cmd, 0xa8);
        }

        // ctrlr.flushData();

        // Get the PS/2 controller config and re-enable interrupts
        var config = ctrlr.waitConfig();
        config.port1InterruptsEnabled = true;
        config.port2InterruptsEnabled = true;
        config.port1ClockDisabled = false;
        config.port2ClockDisabled = false;
        config.port1TranslationEnabled = false;

        // Write the config back
        io.outb(IOPort.cmd, 0x60);
        io.outb(IOPort.cmd, @bitCast(config));
    }

    // Reset devices.
    {
        // resetDevice(&port1);
        resetDevice(&port2);
    }

    ctrlr.flushData();

    // Verify scan code.
    vga.printf("getting scan code...\n", .{});
    port1.writeData(0xf0);
    port1.writeData(0x00);

    vga.printf("scan code: 0x{x}\n", .{port1.waitForByte()});

    vga.printf("setting scan code...\n", .{});
    port1.writeData(0xf0);
    port1.writeData(0x01);

    vga.printf("scan code: 0x{x}\n", .{port1.waitForByte()});
    port1.writeData(0xf0);
    port1.writeData(0x00);

    vga.printf("scan code: 0x{x}\n", .{port1.waitForByte()});
}

fn resetDevice(port: anytype) void {
    // Send reset.
    port.writeData(0xff);

    const ack = ctrlr.pollData();
    switch (ack) {
        0xfa => {
            const health_code = ctrlr.pollData();
            switch (health_code) {
                0xaa => {
                    port.healthy = true;
                    vga.printf("ps/2 port {s} OK!\n", .{@tagName(port.portNum)});
                },
                else => {
                    vga.printf("unexpected health code for ps/2 port {s}: 0x{x}\n", .{ @tagName(port.portNum), health_code });
                },
            }
        },
        0xfc => {
            vga.printf("health check failed for ps/2 port {s}\n", .{@tagName(port.portNum)});
        },
        else => {
            vga.printf("unexpected ack for ps/2 port {s}: 0x{x}\n", .{ @tagName(port.portNum), ack });
        },
    }
}

fn Port(comptime port: enum { one, two }, assumeVerified: bool) type {
    return struct {
        const Self = @This();

        portNum: @TypeOf(port) = port,
        verified: bool = assumeVerified,
        healthy: bool = false,

        devId: u8 = 0,

        buffered: ?u8 = null,

        pub fn writeData(_: *Self, byte: u8) void {
            switch (port) {
                .one => {},
                .two => {
                    // Tell the controller we're going to write to port two.
                    io.outb(IOPort.cmd, 0xd4);
                },
            }

            // Wait for the input buffer to be clear.
            while (ctrlr.status().inputBufferFull) {
                vga.writeStr("waiting on input buffer...\n");
            }

            // Write our byte.
            io.outb(IOPort.data, byte);
        }

        pub fn waitForByte(self: *Self) u8 {
            while (self.buffered == null) {
                // vga.writeStr("waiting for byte in buffer...\n");
            }

            const result = self.buffered.?;
            self.buffered = null;

            return result;
        }

        pub inline fn recv(self: *Self) void {
            if (self.buffered != null) {
                // TODO: what do?
            }

            self.buffered = io.inb(IOPort.data);
        }
    };
}

pub var port1 = Port(.one, true){};
pub var port2 = Port(.two, false){};

const ctrlr = struct {
    const Self = @This();

    pub fn status() StatusRegister {
        return @bitCast(io.inb(IOPort.cmd));
    }

    pub fn pollConfig() ControllerConfig {
        // Request config byte.
        io.outb(IOPort.cmd, 0x20);

        // Poll until we get a response.
        return @bitCast(pollData());
    }

    pub fn waitConfig() ControllerConfig {
        // Request config byte.
        io.outb(IOPort.cmd, 0x20);

        // Steal the byte off the dev1 IRQ buffer.
        return @bitCast(port1.waitForByte());
    }

    pub fn pollData() u8 {
        // Wait for the controller to write the response.
        while (!status().outputBufferFull) {
            // vga.writeStr("waiting for polled byte...\n");
        }

        // Read the response.
        return io.inb(IOPort.data);
    }

    pub fn writeCmd(cmd: u8) void {
        io.outb(IOPort.cmd, cmd);
    }

    pub fn flushData() void {
        while (status().outputBufferFull) {
            const byte = io.inb(IOPort.data);
            vga.printf("flushing 0x{x}\n", .{byte});
        }
    }
};
