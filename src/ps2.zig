// TODO: use enums/consts for command codes.

const std = @import("std");

const io = @import("io.zig");
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

    // Enable scan codes for port1.
    dbg("enabling port1 scan codes...", .{});
    port1.writeData(Device.EnableScanning.C);

    // Enable typematic for port1.
    dbg("enabling port1 typematic settings...", .{});
    port1.writeData(Device.SetTypematic.C);
    port1.writeData(@bitCast(
        Device.SetTypematic.D{
            .repeat_rate = 31,
            .delay = .@"750ms",
        },
    ));
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
            vga.printf("ps/2 self-test: pass!\n", .{});
        } else {
            vga.printf("ps/2 self-test: fail! ({b})\n", .{res});
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
                vga.printf("ps/2 interface 1 test: pass!\n", .{});
            } else {
                vga.printf("ps/2 interface 1 test: fail! ({b})\n", .{res});
            }
        }

        // Test Port 2.
        if (port2.verified) {
            ctrl.sendCmd(Ctrl.TestPort2.C);

            const res = ctrl.pollData();
            if (res == @intFromEnum(Ctrl.TestPort2.R.passed)) {
                vga.printf("ps/2 interface 2 test: pass!\n", .{});
            } else {
                vga.printf("ps/2 interface 2 test: fail! ({b})\n", .{res});
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

fn Port(comptime port: enum { one, two }) type {
    return struct {
        const Self = @This();

        port_num: @TypeOf(port) = port,
        dev_id: ?u8 = null,

        verified: bool = false,
        healthy: bool = false,

        // HACK: okay, I'm not even sure this is what's happening, but port2 seems to send a null terminator after it sends the health codes; this is basically a hack to still have it report healthy.
        health_check_sends_null_terminator: bool = false,

        // NOTE: this operates as a downwards-growing stack.
        buffer: [128]u8 = undefined,
        buffer_head: usize = @typeInfo(@FieldType(Self, "buffer")).array.len,

        buf_reader: std.io.AnyReader = undefined,

        pub fn init(self: *Self) void {
            self.buf_reader = std.io.AnyReader{
                .context = @ptrCast(self),
                .readFn = &readBuf,
            };
        }

        pub fn writeDataNoAck(_: *Self, byte: u8) void {
            switch (port) {
                .one => {},
                .two => {
                    // Tell the controller we're going to write to port two.
                    ctrl.sendCmd(Ctrl.WritePort2InputBuf.C);
                },
            }

            // Wait for the input buffer to be clear.
            while (ctrl.status().input_buf_full) {
                dbgv("waiting on input buffer...\n", .{});
            }

            // Write our byte.
            io.outb(IOPort.data, byte);
        }

        pub fn writeData(self: *Self, byte: u8) void {
            self.writeDataNoAck(byte);

            // Wait for an ACK.
            if (port1.waitAck()) {
                dbg("ok!\n", .{});
            } else |e| {
                dbg("failed to ack: {any}\n", .{e});
            }
        }

        pub fn recv(self: *Self) void {
            const byte = io.inb(IOPort.data);

            // TODO: is it okay to just drop a byte like this?
            if (self.buffer_head == 0) {
                return;
            }

            self.buffer_head -= 1;
            self.buffer[self.buffer_head] = byte;
        }

        const AckErr = error{NotAck};

        pub fn waitAck(self: *Self) !void {
            // Wait for some data to become available.
            while (self.buffer_head == self.buffer.len) {}

            // HACK: we shouldn't have to allocate this much memory each time since an ack _should_ only be 1 byte! Optimize later.
            var buf: @TypeOf(self.buffer) = undefined;
            const n = try self.buf_reader.readAll(&buf);

            if (!std.mem.eql(u8, buf[0..n], &[_]u8{0xfa})) {
                return error.NotAck;
            }
        }

        // TODO: surface errors better.
        pub fn reset(self: *Self) !void {
            // Send reset.
            self.writeDataNoAck(Device.ResetAndSelfTest.C);

            // Read response.
            var buf: @TypeOf(self.buffer) = undefined;
            const n = try self.buf_reader.read(&buf);

            chk: switch (n) {
                0 => unreachable,
                1 => switch (buf[0]) {
                    0xfc => dbg("health check failed for ps/2 port {s}\n", .{@tagName(self.port_num)}),
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
                            dbg("ps/2 port {s} healthy!\n", .{@tagName(self.port_num)});

                            return;
                        }
                    }
                },
                else => break :chk,
            }

            dbg("unexpected response code for ps/2 port {s}:", .{@tagName(self.port_num)});
            for (buf[0..n]) |byte| {
                dbg(" 0x{x}", .{byte});
            }
            dbg("\n", .{});
        }

        pub fn readBuf(context: *const anyopaque, buffer: []u8) anyerror!usize {
            var self: *Self = @constCast(@ptrCast(@alignCast(context)));

            const self_buf_len: usize = self.buffer.len - self.buffer_head;
            const n = if (buffer.len > self_buf_len) self_buf_len else buffer.len;

            const result = self.buffer[self.buffer_head .. self.buffer_head + n];
            std.mem.reverse(u8, result);

            @memcpy(buffer[0..n], result);
            self.buffer_head += n;

            return n;
        }
    };
}

pub var port1 = Port(.one){ .verified = true };
pub var port2 = Port(.two){ .verified = false, .health_check_sends_null_terminator = true };

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
            dbgv("waiting for polled byte...\n", .{});
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

const F1 = Key([_]u8{0x05}, "F1", null);
const F2 = Key([_]u8{0x06}, "F2", null);
const F3 = Key([_]u8{0x04}, "F3", null);
const F4 = Key([_]u8{0x0C}, "F4", null);
const F5 = Key([_]u8{0x03}, "F5", null);
const F6 = Key([_]u8{0x0B}, "F6", null);
const F7 = Key([_]u8{0x83}, "F7", null);
const F8 = Key([_]u8{0x0A}, "F8", null);
const F9 = Key([_]u8{0x01}, "F9", null);
const F10 = Key([_]u8{0x09}, "F10", null);
const F11 = Key([_]u8{0x78}, "F11", null);
const F12 = Key([_]u8{0x07}, "F12", null);

const @"`" = Key([_]u8{0x0E}, "`", "~");
const @"1" = Key([_]u8{0x16}, "1", "!");
const @"2" = Key([_]u8{0x1E}, "2", "@");
const @"3" = Key([_]u8{0x26}, "3", "#");
const @"4" = Key([_]u8{0x25}, "4", "$");
const @"5" = Key([_]u8{0x2E}, "5", "%");
const @"6" = Key([_]u8{0x36}, "6", "^");
const @"7" = Key([_]u8{0x3D}, "7", "&");
const @"8" = Key([_]u8{0x3E}, "8", "*");
const @"9" = Key([_]u8{0x46}, "9", "(");
const @"0" = Key([_]u8{0x45}, "0", ")");
const @"-" = Key([_]u8{0x4E}, "-", "_");
const @"=" = Key([_]u8{0x55}, "=", "+");

const space = Key([_]u8{0x29}, "space", null);
const tab = Key([_]u8{0x0D}, "tab", null);
const enter = Key([_]u8{0x5A}, "enter", null);
const escape = Key([_]u8{0x76}, "escape", null);
const backspace = Key([_]u8{0x66}, "backspace", null);

const @"[" = Key([_]u8{0x54}, "[", "{");
const @"]" = Key([_]u8{0x5B}, "]", "}");
const @"\\" = Key([_]u8{0x5D}, "\\", "|");
const @";" = Key([_]u8{0x4C}, ";", ":");
const @"'" = Key([_]u8{0x52}, "'", "\"");
const @"," = Key([_]u8{0x41}, ",", "<");
const @"." = Key([_]u8{0x49}, ".", ">");
const @"/" = Key([_]u8{0x4A}, "/", "?");

const a = Key([_]u8{0x1C}, "a", "A");
const b = Key([_]u8{0x32}, "b", "B");
const c = Key([_]u8{0x21}, "c", "C");
const d = Key([_]u8{0x23}, "d", "D");
const e = Key([_]u8{0x24}, "e", "E");
const f = Key([_]u8{0x2B}, "f", "F");
const g = Key([_]u8{0x34}, "g", "G");
const h = Key([_]u8{0x33}, "h", "H");
const i = Key([_]u8{0x43}, "i", "I");
const j = Key([_]u8{0x3B}, "j", "J");
const k = Key([_]u8{0x42}, "k", "K");
const l = Key([_]u8{0x4B}, "l", "L");
const m = Key([_]u8{0x3A}, "m", "M");
const n = Key([_]u8{0x31}, "n", "N");
const o = Key([_]u8{0x44}, "o", "O");
const p = Key([_]u8{0x4D}, "p", "P");
const q = Key([_]u8{0x15}, "q", "Q");
const r = Key([_]u8{0x2D}, "r", "R");
const s = Key([_]u8{0x1B}, "s", "S");
const t = Key([_]u8{0x2C}, "t", "T");
const u = Key([_]u8{0x3C}, "u", "U");
const v = Key([_]u8{0x2A}, "v", "V");
const w = Key([_]u8{0x1D}, "w", "W");
const x = Key([_]u8{0x22}, "x", "X");
const y = Key([_]u8{0x35}, "y", "Y");
const z = Key([_]u8{0x1A}, "z", "Z");

const @"right alt" = Key([_]u8{ 0xE0, 0x11 }, "right alt", null);
const @"right shift" = Key([_]u8{0x59}, "right shift", null);
const @"right control" = Key([_]u8{ 0xE0, 0x14 }, "right control", null);
const @"right GUI" = Key([_]u8{ 0xE0, 0x27 }, "right GUI", null);

const @"left alt" = Key([_]u8{0x11}, "left alt", null);
const @"left shift" = Key([_]u8{0x12}, "left shift", null);
const @"left control" = Key([_]u8{0x14}, "left control", null);
const @"left GUI" = Key([_]u8{ 0xE0, 0x1F }, "left GUI", null);

const @"cursor up" = Key([_]u8{ 0xE0, 0x75 }, "cursor up", null);
const @"cursor right" = Key([_]u8{ 0xE0, 0x74 }, "cursor right", null);
const @"cursor down" = Key([_]u8{ 0xE0, 0x72 }, "cursor down", null);
const @"cursor left" = Key([_]u8{ 0xE0, 0x6B }, "cursor left", null);

const KeyName = enum {
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,

    @"`",
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    @"0",
    @"-",
    @"=",

    space,
    tab,
    enter,
    escape,
    backspace,

    @"[",
    @"]",
    @"\\",
    @";",
    @"'",
    @",",
    @".",
    @"/",

    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,

    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,

    @"right alt",
    @"right shift",
    @"right control",
    @"right GUI",

    @"left alt",
    @"left shift",
    @"left control",
    @"left GUI",

    @"cursor up",
    @"cursor right",
    @"cursor down",
    @"cursor left",

    @"~",
    @"!",
    @"@",
    @"#",
    @"$",
    @"%",
    @"^",
    @"&",
    @"*",
    @"(",
    @")",
    @"_",
    @"+",

    @"{",
    @"}",
    @"|",
    @":",
    @"\"",
    @"<",
    @">",
    @"?",
};
