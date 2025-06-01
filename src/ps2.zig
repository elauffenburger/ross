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
    output_buf_full: bool,

    // Must be clear before attempting to write to IO port.
    input_buf_full: bool,

    _r1: u1,

    input_for: enum(u1) {
        // Data in input buffer is for ps/2 device.
        data = 0,

        // Data in input buffer is for ps/2 controller command.
        command = 1,
    },

    _r2: u1,
    _r3: u1,

    timeout_err: bool,
    parity_err: bool,
};

const ControllerConfig = packed struct(u8) {
    port1_interrupts_enabled: bool,
    port2_interrupts_enabled: bool,
    systemd_posted: bool,
    _r1: u1,
    port1_clock_disabled: bool,
    port2_clock_disabled: bool,

    // Translates scan codes to scan code 1 for compatibility reasons.
    port1_translation_enabled: bool,

    // NOTE: this must be zero. don't know why. Might be keylock?
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

    // Set controller config up for testing.
    {
        // Get the PS/2 controller config and set things up so we can run tests.
        var config = ctrl.pollConfig();
        config.port1_interrupts_enabled = false;
        config.port1_clock_disabled = false;
        config.port1_translation_enabled = false;

        // Write the config back
        ctrl.writeConfig(config);
    }

    // // Perform controller self-test.
    // {
    //     io.outb(IOPort.cmd, 0xaa);

    //     const res = ctrlr.pollData();
    //     if (res == 0x55) {
    //         vga.printf("ps/2 self-test: pass!\n", .{});
    //     } else {
    //         vga.printf("ps/2 self-test: fail! ({b})\n", .{res});
    //     }
    // }

    // // Check if there's a second channel.
    // {
    //     // Enable the second port.
    //     io.outb(IOPort.cmd, 0xa8);

    //     // Get the config byte to see if the second port clock is disabled; if it is, then there isn't a second port.
    //     const config = ctrlr.pollConfig();
    //     port2.verified = !config.port2ClockDisabled;
    // }

    // // Perform interface test.
    // {
    //     // Test Port 1.
    //     {
    //         io.outb(IOPort.cmd, 0xab);

    //         const res = ctrlr.pollData();
    //         if (res == 0) {
    //             vga.printf("ps/2 interface 1 test: pass!\n", .{});
    //         } else {
    //             vga.printf("ps/2 interface 1 test: fail! ({b})\n", .{res});
    //         }
    //     }

    //     // Test Port 2.
    //     if (port2.verified) {
    //         io.outb(IOPort.cmd, 0xa9);

    //         const res = ctrlr.pollData();
    //         if (res == 0) {
    //             vga.printf("ps/2 interface 2 test: pass!\n", .{});
    //         } else {
    //             vga.printf("ps/2 interface 2 test: fail! ({b})\n", .{res});
    //         }
    //     }
    // }

    // Re-enable devices and reset.
    {
        // Enable port 1.
        io.outb(IOPort.cmd, 0xae);

        // Enable port 2 if it exists.
        if (port2.verified) {
            io.outb(IOPort.cmd, 0xa8);
        }

        // Get the PS/2 controller config and re-enable interrupts
        var config = ctrl.pollConfig();
        config.port1_interrupts_enabled = true;
        config.port2_interrupts_enabled = true;
        config.port1_clock_disabled = false;
        config.port2_clock_disabled = false;
        config.port1_translation_enabled = false;

        // Write the config back
        ctrl.writeConfig(config);
    }

    // Reset devices.
    {
        port1.reset();

        if (port2.verified) {
            port2.reset();
        }
    }

    // Enable scan codes for port1.
    dbg("enabling port1 scan codes\n", .{});
    port1.writeData(0xf4);
    port1.waitAck();
}

fn Port(comptime port: enum { one, two }, assumeVerified: bool) type {
    return struct {
        const Self = @This();

        port_num: @TypeOf(port) = port,
        dev_id: ?u8 = null,

        verified: bool = assumeVerified,
        healthy: ?bool = null,

        buffer: ?u8 = null,

        pub fn writeData(_: *Self, byte: u8) void {
            switch (port) {
                .one => {},
                .two => {
                    // Tell the controller we're going to write to port two.
                    io.outb(IOPort.cmd, 0xd4);
                },
            }

            // Wait for the input buffer to be clear.
            while (ctrl.status().input_buf_full) {
                dbgv("waiting on input buffer...\n", .{});
            }

            // Write our byte.
            io.outb(IOPort.data, byte);
        }

        pub fn waitForByte(self: *Self) u8 {
            while (self.buffer == null) {
                dbgv("waiting for byte in buffer...\n", .{});
            }

            const result = self.buffer.?;
            self.buffer = null;

            return result;
        }

        pub fn waitAck(self: *Self) void {
            // TODO: handle non-ACK byte.
            _ = self.waitForByte();
        }

        pub fn recv(self: *Self) void {
            if (self.buffer != null) {
                // TODO: what do?
            }

            self.buffer = io.inb(IOPort.data);
        }

        // TODO: surface errors better.
        pub fn reset(self: *Self) void {
            // Send reset.
            self.writeData(0xff);

            const ack = self.waitForByte();
            switch (ack) {
                0xfa => {
                    const health_code = self.waitForByte();
                    switch (health_code) {
                        0xaa => {
                            self.healthy = true;
                            dbg("ps/2 port {s} OK!\n", .{@tagName(self.port_num)});
                        },
                        else => {
                            dbg("unexpected health code for ps/2 port {s}: 0x{x}\n", .{ @tagName(self.port_num), health_code });
                        },
                    }
                },
                0xaa => {
                    self.healthy = true;
                    dbg("ps/2 port {s} OK!\n", .{@tagName(self.port_num)});
                },
                0xfc => {
                    dbg("health check failed for ps/2 port {s}\n", .{@tagName(self.port_num)});
                },
                else => {
                    dbg("unexpected ack for ps/2 port {s}: 0x{x}\n", .{ @tagName(self.port_num), ack });
                },
            }
        }
    };
}

pub var port1 = Port(.one, true){};
pub var port2 = Port(.two, false){};

const ctrl = struct {
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

    pub fn writeConfig(config: ControllerConfig) void {
        io.outb(IOPort.cmd, 0x60);
        io.outb(IOPort.data, @as(u8, @bitCast(config)));
    }

    pub fn pollData() u8 {
        // Wait for the controller to write the response.
        while (!status().output_buf_full) {
            dbgv("waiting for polled byte...\n", .{});
        }

        // Read the response.
        return io.inb(IOPort.data);
    }

    pub fn sendCmd(cmd: u8) error{bad_ack}!void {
        io.outb(IOPort.cmd, cmd);

        const ack = port1.waitForByte();
        if (ack != 0xfa) {
            return error.bad_ack;
        }
    }

    pub fn flushData() void {
        while (status().output_buf_full) {
            const byte = io.inb(IOPort.data);
            dbgv("flushing 0x{x}\n", .{byte});
        }
    }
};

fn dbg(comptime format: []const u8, args: anytype) void {
    vga.printf(format, args);
}

fn dbgv(comptime format: []const u8, args: anytype) void {
    vga.printf(format, args);
}
