const std = @import("std");
const fmt = std.fmt;

var width: u32 = 80;
var height: u32 = 30;

var curr_y: usize = 0;
var curr_x: usize = 0;
var curr_colors = ColorPair{
    .fg = Color.LightGray,
    .bg = Color.Black,
};

const BUFFER_ADDR = 0x0b8000;
var buffer = @as([*]volatile u16, @ptrFromInt(BUFFER_ADDR));

pub const writer = std.io.Writer(
    void,
    error{},
    struct {
        pub fn write(_: void, string: []const u8) error{}!usize {
            writeStr(string);
            return string.len;
        }
    }.write,
){
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

const ColorPair = extern struct {
    bg: Color,
    fg: Color,

    pub fn code(self: @This()) u8 {
        return (@intFromEnum(self.bg) << 4) | @intFromEnum(self.fg);
    }
};

const Char = extern struct {
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
    clear();
}

pub fn clear() void {
    @memset(buffer[0..size()], Char.code(.{ .colors = curr_colors, .ch = ' ' }));
}

pub fn writeChAt(ch: Char, x: usize, y: usize) void {
    const index = y * width + x;

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

    curr_x += 1;
    if (curr_x == width) {
        newline();
    }
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

inline fn size() u32 {
    return width * height;
}

inline fn newline() void {
    curr_x = 0;

    curr_y += 1;
    if (curr_y == height) {
        curr_y = 0;
    }
}
