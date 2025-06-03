const std = @import("std");
const fmt = std.fmt;

const width: u32 = 80;
const height: u32 = 26;

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

fn size() u32 {
    return width * height;
}

fn newline() void {
    curr_x = 0;

    curr_y += 1;
    if (curr_y == height) {
        scroll();
    }
}

fn scroll() void {
    // Copy line 1:n of buffer to line 0:(n-1) of new_buf.
    var new_buf: [width * height]u16 = undefined;
    @memcpy(new_buf[0..((width * height) - width)], buffer[width..]);

    // Zero out the last line of new_buf.
    @memcpy(new_buf[((width * height) - width)..], &([_]u16{0} ** width));

    // Copy new_buf to buf.
    @memcpy(buffer[0 .. width * height], &new_buf);

    curr_x = 0;
    curr_y = height - 1;
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
