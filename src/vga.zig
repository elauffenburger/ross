const std = @import("std");
const fmt = std.fmt;

const io = @import("io.zig");

const width: u32 = 80;
const height: u32 = 20;

var curr_y: u32 = 0;
var curr_x: u32 = 0;
var curr_colors = ColorPair{
    .fg = Color.LightGray,
    .bg = Color.Black,
};

var buffer = @as([*]volatile u16, @ptrFromInt(buffer_addr));
const buffer_addr = 0x0b8000;

pub const misc_out = struct {
    pub var reg_val: Register = undefined;

    pub const io_port_r = 0x3cc;
    pub const io_port_w = 0x3c2;

    pub const Register = packed struct(u8) {
        vsyncp: u1 = 0,
        hsyncp: u1 = 0,
        oe_page: enum(u1) {
            lo = 0,
            hi = 1,
        } = .lo,
        _r1: u1,
        clock_select: enum(u2) {
            @"25Mhz" = 0,
            @"28Mhz" = 1,
        } = .@"25Mhz",
        ram_enable: bool,
        io_addr_select: enum(u1) {
            // crt controller addrs: 0x03bx, io status reg 1 addr: 0x03ba
            mono = 0,

            // crt controller addrs: 0x03dx, io status reg 1 addr: 0x03da
            color = 1,
        } = .mono,
    };

    pub fn read() Register {
        return @bitCast(io.inb(io_port_r));
    }

    pub fn write(reg: Register) void {
        // Write register value.
        io.outb(io_port_w, @bitCast(reg));

        // Update saved values.
        reg_val = reg;
        crt_ctrl.reg_addrs = crt_ctrl.regAddrs();
    }
};

pub const crt_ctrl = struct {
    pub const RegisterAddrs = struct {
        addr: u16,
        data: u16,
    };

    pub var reg_addrs: RegisterAddrs = undefined;

    pub const cursor_location = struct {
        pub const hi = struct {
            pub const index = 0xe;

            pub const Register = u8;
        };

        pub const lo = struct {
            pub const index = 0xf;

            pub const Register = u8;
        };
    };

    pub const cursor_start = struct {
        pub const index = 0xa;

        pub const Register = packed struct(u8) {
            cursort_scanline_start: u5 = 0,
            cursor_disable: bool = false,
            _r1: u2 = 0,
        };
    };

    pub fn regAddrs() RegisterAddrs {
        switch (misc_out.reg_val.io_addr_select) {
            .mono => return .{ .addr = 0x3b4, .data = 0x3b5 },
            .color => return .{ .addr = 0x3d4, .data = 0x3d5 },
        }
    }

    pub fn read(reg: anytype) reg.Register {
        // Get the current register index.
        const orig_index = io.inb(reg_addrs.addr);

        // Set the input register index for this register.
        io.outb(reg_addrs.addr, reg.index);

        // Read the register data.
        const res = io.inb(reg_addrs.data);

        // Restore the original index.
        io.outb(reg_addrs.addr, orig_index);

        return @bitCast(res);
    }

    pub fn write(reg: anytype, val: reg.Register) void {
        // Get the current register index.
        const orig_index = io.inb(reg_addrs.addr);

        // Set the output register index for this register.
        io.outb(reg_addrs.addr, reg.index);

        // Write the register data.
        io.outb(reg_addrs.data, @bitCast(val));

        // Restore the original index.
        io.outb(reg_addrs.addr, orig_index);
    }
};

const BufferWriter = std.io.Writer(
    void,
    error{},
    struct {
        pub fn write(_: void, string: []const u8) error{}!usize {
            writeStr(string);
            return string.len;
        }
    }.write,
);

pub const writer = BufferWriter{
    .context = {},
};

pub const Color = enum(u8) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    LightBrown = 14,
    White = 15,
};

const ColorPair = packed struct {
    bg: Color,
    fg: Color,

    pub fn code(self: @This()) u8 {
        return (@intFromEnum(self.bg) << 4) | @intFromEnum(self.fg);
    }
};

const Char = packed struct {
    colors: ColorPair,
    ch: u8,

    pub fn code(self: @This()) u16 {
        var res: u16 = @intCast(self.colors.code());
        res <<= 8;
        res |= self.ch;

        return res;
    }
};

pub fn init() void {
    // Init registers.
    {
        // Set IO addr select register.
        misc_out.write(blk: {
            var reg = misc_out.read();
            reg.io_addr_select = .color;

            break :blk reg;
        });
    }

    // Clear screen.
    clear();
}

pub fn clear() void {
    @memset(buffer[0..size()], Char.code(.{ .colors = curr_colors, .ch = ' ' }));

    setCursor(0, 0);
}

pub fn setCursor(x: u32, y: u32) void {
    curr_x = x;
    curr_y = y;

    if (curr_x == width) {
        newline();
        return;
    }

    if (curr_y == height) {
        scroll();
        return;
    }

    const loc_reg = crt_ctrl.cursor_location;
    var cursor_index = @as(u16, @truncate(bufIndex(curr_x, curr_y)));
    if (cursor_index > 1600) {
        cursor_index = 0;
    }

    crt_ctrl.write(loc_reg.lo, @truncate(cursor_index));
    crt_ctrl.write(loc_reg.hi, @truncate(cursor_index >> 8));
}

inline fn bufIndex(x: u32, y: u32) u32 {
    return y * width + x;
}

pub fn writeChAt(ch: Char, x: u32, y: u32) void {
    const index = bufIndex(x, y);

    var code: u16 = @intCast(ch.colors.code());
    code <<= 8;
    code |= ch.ch;

    buffer[index] = code;
}

pub fn writeCh(ch: u8) void {
    if (ch == '\n') {
        newline();
        return;
    }

    writeChAt(.{ .ch = ch, .colors = curr_colors }, curr_x, curr_y);

    setCursor(curr_x + 1, curr_y);
}

pub fn writeStr(data: []const u8) void {
    for (data) |c| {
        if (c == 0) {
            return;
        }

        writeCh(c);
    }
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    var buf = std.mem.zeroes([256]u8);
    const fmtd = fmt.bufPrint(&buf, format, args) catch {
        return;
    };

    writeStr(fmtd);
}

fn size() u32 {
    return width * height;
}

fn newline() void {
    setCursor(0, curr_y + 1);
}

fn scroll() void {
    // Copy line 1:n of buffer to line 0:(n-1) of new_buf.
    var new_buf: [width * height]u16 = undefined;
    @memcpy(new_buf[0..((width * height) - width)], buffer[width..]);

    // Zero out the last line of new_buf.
    @memcpy(new_buf[((width * height) - width)..], &([_]u16{0} ** width));

    // Copy new_buf to buf.
    @memcpy(buffer[0 .. width * height], &new_buf);

    setCursor(0, height - 1);
}

pub var debugVerbosity: enum(u8) { none, debug, v } = .v;

pub fn dbg(comptime format: []const u8, args: anytype) void {
    debugLog(format, args, .debug);
}

pub fn dbgv(comptime format: []const u8, args: anytype) void {
    debugLog(format, args, .v);
}

pub fn debugLog(comptime format: []const u8, args: anytype, verbosity: @TypeOf(debugVerbosity)) void {
    if (@intFromEnum(debugVerbosity) >= @intFromEnum(verbosity)) {
        printf(format, args);
    }
}
