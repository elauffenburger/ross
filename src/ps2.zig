// TODO: use enums/consts for command codes.

const std = @import("std");

const io = @import("io.zig");
const kstd = @import("kstd.zig");
const pic = @import("pic.zig");
const vga = @import("vga.zig");

// See https://wiki.osdev.org/I8042_PS/2_Controller#Initialising_the_PS/2_Controller
//
// NOTE: there's a bunch of stuff we _should_ do...and we're not going to do any of it for now because it requires ACPI and stuff :)
pub fn init() !void {
    // TODO: initialize USB controllers.
    // TODO: make sure PS/2 controller exists.

    port1.init();
    port2.init();

    // Run tests.
    try testInterface();
}

fn testInterface() !void {
    // Disable both ports.
    ctrl.sendCmd(Ctrl.DisablePort1.C);
    ctrl.sendCmd(Ctrl.DisablePort2.C);

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

    // Perform controller self-test.
    {
        ctrl.sendCmd(Ctrl.TestCtrl.C);

        const res = ctrl.pollData();
        if (res == @intFromEnum(Ctrl.TestCtrl.R.passed)) {
            vga.dbg("ps/2 self-test: pass!\n", .{});
        } else {
            vga.dbg("ps/2 self-test: fail! ({b})\n", .{res});
        }
    }

    // Check if there's a second channel.
    {
        // Enable the second port.
        ctrl.sendCmd(Ctrl.EnablePort2.C);

        // Get the config byte to see if the second port clock is disabled; if it is, then there isn't a second port.
        const config = ctrl.pollConfig();
        port2.verified = !config.port2_clock_disabled;
    }

    // Perform interface test.
    {
        // Test Port 1.
        {
            ctrl.sendCmd(Ctrl.TestPort1.C);

            const res = ctrl.pollData();
            if (res == @intFromEnum(Ctrl.TestPort1.R.passed)) {
                vga.dbg("ps/2 interface 1 test: pass!\n", .{});
            } else {
                vga.dbg("ps/2 interface 1 test: fail! ({b})\n", .{res});
            }
        }

        // Test Port 2.
        if (port2.verified) {
            ctrl.sendCmd(Ctrl.TestPort2.C);

            const res = ctrl.pollData();
            if (res == @intFromEnum(Ctrl.TestPort2.R.passed)) {
                vga.dbg("ps/2 interface 2 test: pass!\n", .{});
            } else {
                vga.dbg("ps/2 interface 2 test: fail! ({b})\n", .{res});
            }
        }
    }

    // Re-enable devices and reset.
    {
        // Enable port 1.
        ctrl.sendCmd(Ctrl.EnablePort1.C);

        // Enable port 2 if it exists.
        if (port2.verified) {
            ctrl.sendCmd(Ctrl.EnablePort2.C);
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
        try port1.reset();

        if (port2.verified) {
            try port2.reset();
        }
    }
}

const Port = struct {
    const Self = @This();

    const Buffer = kstd.collections.BufferQueue(u8, 128);

    port: enum { one, two },
    dev_id: ?u8 = null,

    verified: bool = false,
    healthy: bool = false,

    // HACK: okay, I'm not even sure this is what's happening, but port2 seems to send a null terminator after it sends the health codes; this is basically a hack to still have it report healthy.
    health_check_sends_null_terminator: bool = false,

    buffer: Buffer = .{},
    buf_reader: std.io.AnyReader = undefined,

    pub fn init(self: *Self) void {
        self.buf_reader = std.io.AnyReader{
            .context = @ptrCast(self),
            .readFn = &readBuf,
        };
    }

    pub fn writeDataNoAck(self: *Self, byte: u8) void {
        switch (self.port) {
            .one => {},
            .two => {
                // Tell the controller we're going to write to port two.
                ctrl.sendCmd(Ctrl.WritePort2InputBuf.C);
            },
        }

        // Wait for the input buffer to be clear.
        while (ctrl.status().input_buf_full) {
            vga.dbgv("waiting on input buffer...\n", .{});
        }

        // Write our byte.
        io.outb(IOPort.data, byte);
    }

    pub fn writeData(self: *Self, byte: u8) void {
        self.writeDataNoAck(byte);

        // Wait for an ACK.
        if (port1.waitAck()) {
            vga.dbg("ok!\n", .{});
        } else |e| {
            vga.dbg("failed to ack: {any}\n", .{e});
        }
    }

    pub fn recv(self: *Self) anyerror!void {
        const byte = io.inb(IOPort.data);

        // TODO: is it okay to just drop a byte like this?
        if (self.buffer.items.len == self.buffer.buf.len) {
            return error{OutOfMemory}.OutOfMemory;
        }

        try self.buffer.appendSlice(&[_]u8{byte});
    }

    const AckErr = error{NotAck};

    pub fn waitAck(self: *Self) !void {
        // Wait for some data to become available.
        while (self.buffer.items.len == 0) {}

        // HACK: we shouldn't have to allocate this much memory each time since an ack _should_ only be 1 byte! Optimize later.
        var buf: [1]u8 = undefined;
        _ = try self.buf_reader.readAll(&buf);

        if (buf[0] != 0xfa) {
            return error.NotAck;
        }
    }

    // TODO: surface errors better.
    pub fn reset(self: *Self) !void {
        // Send reset.
        self.writeDataNoAck(Device.ResetAndSelfTest.C);

        // Read response.
        var buf: [3]u8 = undefined;
        const n = try self.buf_reader.read(&buf);

        chk: switch (n) {
            0 => unreachable,
            1 => switch (buf[0]) {
                0xfc => vga.dbg("health check failed for ps/2 port {s}\n", .{@tagName(self.port)}),
                else => break :chk,
            },
            2, 3 => {
                // NOTE: this can come out of order for some reason!
                const options = if (self.health_check_sends_null_terminator)
                    &[_][]const u8{
                        &[_]u8{ 0xfa, 0xaa, 0x00 },
                        &[_]u8{ 0xaa, 0xfa, 0x00 },
                    }
                else
                    &[_][]const u8{
                        &[_]u8{ 0xfa, 0xaa },
                        &[_]u8{ 0xaa, 0xfa },
                    };

                for (options) |opt| {
                    if (std.mem.eql(u8, buf[0..n], opt)) {
                        self.healthy = true;
                        vga.dbg("ps/2 port {s} healthy!\n", .{@tagName(self.port)});

                        return;
                    }
                }
            },
            else => break :chk,
        }

        vga.dbg("unexpected response code for ps/2 port {s}:", .{@tagName(self.port)});
        for (buf[0..n]) |byte| {
            vga.dbg(" 0x{x}", .{byte});
        }
        vga.dbg("\n", .{});
    }

    pub fn readBuf(context: *const anyopaque, buffer: []u8) anyerror!usize {
        var self: *Self = @constCast(@ptrCast(@alignCast(context)));
        return self.buffer.dequeueSlice(buffer);
    }
};

pub var port1 = Port{ .port = .one, .verified = true };
pub var port2 = Port{ .port = .two, .verified = false, .health_check_sends_null_terminator = true };

const ctrl = struct {
    const Self = @This();

    pub fn status() StatusRegister {
        return @bitCast(io.inb(IOPort.cmd));
    }

    pub fn pollConfig() CtrlConfig {
        // Request config byte.
        sendCmd(Ctrl.ReadByte0.C);

        // Poll until we get a response.
        return @bitCast(pollData());
    }

    pub fn waitConfig() CtrlConfig {
        // Request config byte.
        sendCmd(Ctrl.ReadByte0.C);

        // Steal the byte off the dev1 IRQ buffer.
        return @bitCast(port1.waitForByte());
    }

    pub fn writeConfig(config: CtrlConfig) void {
        sendCmd(Ctrl.writeToByteN(0));
        io.outb(IOPort.data, @as(u8, @bitCast(config)));
    }

    pub fn pollData() u8 {
        // Wait for the controller to write the response.
        while (!status().output_buf_full) {
            vga.dbgv("waiting for polled byte...\n", .{});
        }

        // Read the response.
        return io.inb(IOPort.data);
    }

    pub fn sendCmd(cmd: u8) void {
        io.outb(IOPort.cmd, cmd);
    }

    pub fn flushData() void {
        while (status().output_buf_full) {
            const byte = io.inb(IOPort.data);
            vga.dbgv("flushing 0x{x}\n", .{byte});
        }
    }
};

const CtrlOutputPort = packed struct(u8) {
    reset: bool = true,
    a20_gate: bool,
    port2_clock: bool,
    port2_data: bool,
    buf_full_from_port1: bool,
    buf_full_from_port2: bool,
    port1_clock: bool,
    port1_data: bool,
};

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

    _r1: u1 = undefined,

    input_for: enum(u1) {
        // Data in input buffer is for ps/2 device.
        data = 0,

        // Data in input buffer is for ps/2 controller command.
        command = 1,
    },

    _r2: u1 = undefined,
    _r3: u1 = undefined,

    timeout_err: bool,
    parity_err: bool,
};

const CtrlConfig = packed struct(u8) {
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

fn CtrlCmd(cmd: u8, response: ?type) type {
    const helpers = struct {
        fn assertByteEnum(name: []const u8, ty: type) type {
            // Assert ty is an enum.
            switch (@typeInfo(ty)) {
                .@"enum" => |e| {
                    if (e.tag_type != u8) {
                        @compileError(std.fmt.comptimePrint("{s} must be a enum(u8)", .{name}));
                    }
                },
                else => {
                    @compileError(std.fmt.comptimePrint("{s} must be a enum(u8)", .{name}));
                },
            }

            return ty;
        }
    };

    if (response) |res| {
        return struct {
            pub const C: u8 = cmd;
            pub const R = helpers.assertByteEnum("response", res);
        };
    }

    return struct {
        pub const C: u8 = cmd;
    };
}

fn DevCmd(cmd: u8, data: ?type, response: ?type) type {
    const helpers = struct {
        fn assertByteEnum(name: []const u8, ty: type) type {
            // Assert ty is an enum.
            switch (@typeInfo(ty)) {
                .@"enum" => |e| {
                    if (e.tag_type != u8) {
                        @compileError(std.fmt.comptimePrint("{s} must be a enum(u8)", .{name}));
                    }
                },
                else => {
                    @compileError(std.fmt.comptimePrint("{s} must be a enum(u8)", .{name}));
                },
            }

            return ty;
        }
    };

    if (data) |dat| {
        if (response) |res| {
            return struct {
                pub const C: u8 = cmd;
                pub const D = helpers.assertByteEnum("data", dat);
                pub const R = helpers.assertByteEnum("response", res);
            };
        }

        return struct {
            pub const C: u8 = cmd;
            pub const D = helpers.assertByteEnum("data", dat);
            pub const R = enum(u8) {
                ack = 0xfa,
                resend = 0xfe,
                err = 0xff,
            };
        };
    }

    if (response) |res| {
        return struct {
            pub const C: u8 = cmd;
            pub const R = helpers.assertByteEnum("response", res);
        };
    }

    return struct {
        pub const C: u8 = cmd;
        pub const R = enum(u8) {
            ack = 0xfa,
            resend = 0xfe,
            err = 0xff,
        };
    };
}

pub const Ctrl = struct {
    pub const ReadByte0 = struct {
        pub const C: u8 = 0x20;
        pub const R = CtrlConfig;
    };

    pub const DisablePort2 = CtrlCmd(0xa7, null);
    pub const EnablePort2 = CtrlCmd(0xa8, null);
    pub const TestPort2 = CtrlCmd(
        0xa9,
        enum(u8) {
            passed = 0,
            clockLineStuckLow = 1,
            clockLineStuckHigh = 2,
            dataLineStuckLow = 3,
            dataLineStuckHigh = 4,
        },
    );

    pub const DisablePort1 = CtrlCmd(0xad, null);
    pub const EnablePort1 = CtrlCmd(0xad, null);
    pub const TestPort1 = CtrlCmd(
        0xab,
        enum(u8) {
            passed = 0,
            clockLineStuckLow = 1,
            clockLineStuckHigh = 2,
            dataLineStuckLow = 3,
            dataLineStuckHigh = 4,
        },
    );

    pub const TestCtrl = CtrlCmd(
        0xaa,
        enum(u8) {
            passed = 0x55,
            failed = 0xfc,
        },
    );

    // NOTE: the response is all bytes of internal RAM.
    pub const DiagnosticDump = CtrlCmd(0xac, null);

    // NOTE: there is a response, but it's not standardized.
    pub const ReadCtrlInputPort = CtrlCmd(0xc0, null);

    pub const CopyInputPortNibble1ToStatusNibble2 = CtrlCmd(0xc1, null);
    pub const CopyInputPortNibble2ToStatusNibble2 = CtrlCmd(0xc2, null);

    pub const ReadCtrlOutputPort = struct {
        pub const C: u8 = 0xd0;

        pub const R = CtrlOutputPort;
    };

    pub const WriteCtrlOutputPort = CtrlCmd(0xd1, null);

    // NOTE: these commands only apply if there are 2 PS/2 ports supported.
    pub const WritePort1OutputBuf = CtrlCmd(0xd2, null);
    pub const WritePort2OutputBuf = CtrlCmd(0xd3, null);
    pub const WritePort2InputBuf = CtrlCmd(0xd4, null);

    // NOTE: Each bit in the mask is a bool for that line (e.g. 0101 pulses ports 2 and 0).
    pub fn pulseOutputLineLow(mask: u4) u8 {
        return 0xf0 | mask;
    }

    pub fn writeToByteN(n: u5) u8 {
        return @as(u8, n) + 0x60;
    }
};

pub const Device = struct {
    pub const SetLEDs = DevCmd(
        0xed,
        enum(u8) {
            scrollLock = 0,
            numLock = 1,
            capsLock = 2,
        },
        null,
    );

    pub const Echo = DevCmd(
        0xee,
        null,
        enum(u8) {
            echo = 0xee,
            ack = 0xfe,
            err = 0xff,
        },
    );

    pub const ScanCodes = DevCmd(
        0xf0,
        enum(u8) {
            getScanCodeSet = 0,
            setScanCodeSet1 = 1,
            setScanCodeSet2 = 2,
            setScanCodeSet3 = 3,
        },
        enum(u8) {
            ack = 0xfa,
            resend = 0xfe,
            err = 0xff,

            set1 = 0x43,
            set2 = 0x41,
            set3 = 0x3f,
        },
    );

    pub const IdentifyKeyboard = DevCmd(0xf2, null, null);

    pub const SetTypematic = struct {
        pub const C: u8 = 0xf3;

        pub const D = packed struct(u8) {
            repeat_rate: u5 = 0,
            delay: enum(u2) {
                @"250ms" = 0,
                @"500ms" = 1,
                @"750ms" = 2,
                @"1000ms" = 3,
            } = .@"250ms",
            _r1: u1 = 0,
        };

        pub const R = enum(u8) {
            ack = 0xfa,
            resend = 0xfe,
            err = 0xff,
        };
    };

    pub const EnableScanning = DevCmd(0xf4, null, null);

    // NOTE: may restore defaults.
    pub const DisableScanning = DevCmd(0xf5, null, null);

    pub const SetDefaultParams = DevCmd(0xf6, null, null);

    pub const ResendLastByte = DevCmd(0xfe, null, null);

    pub const ResetAndSelfTest = DevCmd(
        0xff,
        null,
        enum(u8) {
            ack = 0xfa,
            resend = 0xfe,
            passed = 0xaa,
            failed = 0xfc,
            alsoFailed = 0xfd,
            err = 0xff,
        },
    );
};
