const std = @import("std");

const vga = @import("../vga.zig");
const FrameBuffer = @import("FrameBuffer.zig");
const regs = @import("registers.zig");

const Self = @This();

allocator: std.mem.Allocator,
fb: *FrameBuffer,

temp_buf: []u16,
empty_line: []u16,

target: FrameBuffer.FrameBufferTarget,

pub fn create(allocator: std.mem.Allocator, fb: *FrameBuffer) !*Self {
    const empty_line = try allocator.alloc(u16, fb.width);
    @memset(empty_line, Char.Empty.code());

    const temp_buf = try allocator.alloc(u16, fb.width * fb.height - fb.width);

    const self = try allocator.create(Self);
    self.* = .{
        .allocator = allocator,
        .fb = fb,

        .temp_buf = temp_buf,
        .empty_line = empty_line,

        .target = .{
            .context = self,

            .clearRaw = clearRaw,
            .writeChAt = writeChAt,
            .scroll = scroll,
            .posBufIndex = posBufIndex,
        },
    };

    return self;
}

pub fn clearRaw(ctx: *const anyopaque) void {
    const self = fromCtx(ctx);
    const buf = self.fb.bufferSlice();

    @memset(buf, Char.Empty.code());
}

pub fn writeChAt(ctx: *const anyopaque, ch: u8, pos: vga.Position) void {
    const self = fromCtx(ctx);
    const index = self.bufIndex(pos.x, pos.y);

    const char = Char{
        .ch = ch,

        // TODO: cache this value.
        .colors = .{
            .fg = Color.fromVGA(self.fb.text.colors.fg),
            .bg = Color.fromVGA(self.fb.text.colors.bg),
        },
    };

    const buffer = self.fb.bufferSlice();
    buffer[index] = char.code();
}

pub fn scroll(ctx: *const anyopaque) void {
    const self = fromCtx(ctx);

    const width = self.fb.width;
    const height = self.fb.height;

    const buf = self.fb.bufferSlice();

    // Copy vga buffer to temp buffer offset by one line.
    @memcpy(self.temp_buf, buf[width..(width * height)]);

    // Copy tmp buf back to vga buf and clear the last line.
    @memcpy(buf[0 .. (width * height) - width], self.temp_buf);
    @memcpy(buf[(width * height) - width ..], self.empty_line);
}

pub fn posBufIndex(ctx: *const anyopaque, pos: vga.Position) u32 {
    const self = fromCtx(ctx);
    return self.bufIndex(pos.x, pos.y);
}

inline fn bufIndex(self: *Self, x: u32, y: u32) u32 {
    return y * self.fb.width + x;
}

fn fromCtx(ctx: *const anyopaque) *Self {
    return @alignCast(@constCast(@ptrCast(ctx)));
}

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

    pub fn fromVGA(color: vga.TextColor) Color {
        _ = color; // autofix
        @panic("unimplemented");
    }
};

pub const ColorPair = packed struct {
    bg: Color,
    fg: Color,

    pub fn code(self: @This()) u8 {
        return (@intFromEnum(self.bg) << 4) | @intFromEnum(self.fg);
    }
};

pub const Char = packed struct {
    pub const Empty = Char{
        .ch = ' ',
        .colors = .{
            .fg = Color.Black,
            .bg = Color.Black,
        },
    };

    colors: ColorPair,
    ch: u8,

    pub fn code(self: @This()) u16 {
        var res: u16 = @intCast(self.colors.code());
        res <<= 8;
        res |= self.ch;

        return res;
    }
};
