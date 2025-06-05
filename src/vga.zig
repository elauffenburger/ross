const std = @import("std");

const io = @import("io.zig");
const regs = @import("vga/registers.zig");

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

pub const writer = std.io.AnyWriter{
    .context = undefined,
    .writeFn = struct {
        fn write(_: *const anyopaque, buf: []const u8) anyerror!usize {
            writeStr(buf);
            return buf.len;
        }
    }.write,
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
        regs.misc_out.write(blk: {
            var reg = regs.misc_out.read();
            reg.io_addr_select = .color;

            break :blk reg;
        });
    }

    // Clear screen.
    clear();
}

pub fn clear() void {
    @memset(buffer[0..(width * height)], Char.code(.{ .colors = curr_colors, .ch = ' ' }));

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

    const loc_reg = regs.crt_ctrl.cursor_location;
    const cursor_index = @as(u16, @intCast(bufIndex(curr_x, curr_y)));

    regs.crt_ctrl.write(loc_reg.lo, @truncate(cursor_index));
    regs.crt_ctrl.write(loc_reg.hi, @truncate(cursor_index >> 8));
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
    const fmtd = std.fmt.bufPrint(&buf, format, args) catch {
        return;
    };

    writeStr(fmtd);
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
