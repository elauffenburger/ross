const std = @import("std");

const vga = @import("../vga.zig");
const FrameBuffer = @import("FrameBuffer.zig");
const regs = @import("registers.zig");

const Self = @This();

allocator: std.mem.Allocator,

width: u32,
height: u32,

temp_buf: []u16,
empty_line: []u16,

target: FrameBuffer.FrameBufferTarget,

pub fn create(allocator: std.mem.Allocator, width: u32, height: u32) !*Self {
    const empty_line = try allocator.alloc(u16, width);
    @memset(empty_line, Char.Empty.code());

    const temp_buf = try allocator.alloc(u16, width * height - width);

    const self = try allocator.create(Self);
    self.* = .{
        .allocator = allocator,

        .width = width,
        .height = height,

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

pub fn clearRaw(_: *const anyopaque, frame_buf: *FrameBuffer) void {
    const buf = frame_buf.bufferSlice();

    @memset(buf, Char.code(.{ .colors = ColorPair.fromRGB(frame_buf.colors), .ch = ' ' }));
}

pub fn writeChAt(ctx: *const anyopaque, frame_buf: *FrameBuffer, ch: Char, pos: vga.Position) void {
    const self = fromCtx(ctx);
    const index = self.bufIndex(pos.@"0", pos.@"1");

    var code: u16 = @intCast(ch.colors.code());
    code <<= 8;
    code |= ch.ch;

    const buffer = frame_buf.bufferSlice();
    buffer[index] = code;
}

pub fn scroll(ctx: *const anyopaque, frame_buf: *FrameBuffer) void {
    const self = fromCtx(ctx);

    const width = self.width;
    const height = self.height;

    const buf = frame_buf.bufferSlice();

    // Copy vga buffer to temp buffer offset by one line.
    @memcpy(self.temp_buf, buf[width..(width * height)]);

    // Copy tmp buf back to vga buf and clear the last line.
    @memcpy(buf[0 .. (width * height) - width], self.temp_buf);
    @memcpy(buf[(width * height) - width ..], self.empty_line);
}

pub fn posBufIndex(ctx: *const anyopaque, _: *FrameBuffer, pos: vga.Position) u32 {
    const self = fromCtx(ctx);
    return self.bufIndex(pos.x, pos.y);
}

inline fn bufIndex(self: *Self, x: u32, y: u32) u32 {
    return y * self.width + x;
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

    pub fn fromRGB(color: vga.RGBColor) Color {
        
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
