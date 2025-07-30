const std = @import("std");

const kstd = @import("../../../kstd.zig");
const vga = @import("../vga.zig");
const Char = vga.Char;
const FrameBuffer = @import("FrameBuffer.zig");
const regs = @import("registers.zig");

const Self = @This();

allocator: std.mem.Allocator,

width: u32,
height: u32,

temp_buf: []u16,

target: FrameBuffer.FrameBufferTarget,

pub fn create(allocator: std.mem.Allocator, width: u32, height: u32) !*Self {
    const temp_buf = try allocator.alloc(u16, width * height - width);

    const self = try allocator.create(Self);
    self.* = .{
        .allocator = allocator,

        .width = width,
        .height = height,

        .temp_buf = temp_buf,

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

pub fn clearRaw(ctx: *const anyopaque, frame_buf: *FrameBuffer) void {
    const self = fromCtx(ctx);
    const buf = self.bufferSlice(frame_buf);

    @memset(buf, 0);
}

pub fn writeChAt(ctx: *const anyopaque, frame_buf: *FrameBuffer, ch: Char, pos: vga.Position) void {
    const self = fromCtx(ctx);

    // HACK: think about how to handle characters that won't fit on the current line
    const font_char = frame_buf.font.chars[ch.ch];
    var i: usize = 0;

    const width = frame_buf.font.char_info.width;
    const height = frame_buf.font.char_info.height;

    for (0..height) |y| {
        const row = font_char.bitmap[y];

        for (0..width) |x| {
            const bit = @as(u8, 1) << (7 - @as(u3, @intCast(x)));
            if (row & bit != 0) {
                kstd.log.dbgf("x", .{});

                self.drawPixel(
                    frame_buf,
                    .{ .x = (pos.x * width) + x, .y = (pos.y * height) + y },
                    .{ .red = 0, .green = 0, .blue = 255 },
                );
            } else {
                kstd.log.dbgf(" ", .{});
            }

            i += 1;
        }

        kstd.log.dbg("");
    }
}

pub fn scroll(ctx: *const anyopaque, frame_buf: *FrameBuffer) void {
    const self = fromCtx(ctx);

    const width = self.width;
    _ = width; // autofix
    const height = self.height;
    _ = height; // autofix

    const buf = self.bufferSlice(frame_buf);
    _ = buf; // autofix

    @panic("unimplemented!");
}

pub fn posBufIndex(_: *const anyopaque, frame_buf: *FrameBuffer, pos: vga.Position) u32 {
    return bufIndex(frame_buf, pos.x, pos.y);
}

pub fn drawPixel(_: *Self, frame_buf: *FrameBuffer, pos: vga.Position, color: RGBColor) void {
    const index = bufIndex(frame_buf, pos.x, pos.y);
    const pixel: *u32 = @ptrFromInt(frame_buf.addr + index);

    pixel.* = @bitCast(color);
}

inline fn bufIndex(frame_buf: *FrameBuffer, x: u32, y: u32) u32 {
    return y * frame_buf.pitch + x * frame_buf.pixel_width;
}

fn bufferSlice(self: *Self, frame_buf: *FrameBuffer) []volatile u32 {
    const buf: [*]volatile u32 = @ptrFromInt(frame_buf.addr);
    return buf[0 .. bufIndex(frame_buf, self.width, self.height) + 1];
}

fn fromCtx(ctx: *const anyopaque) *Self {
    return @alignCast(@constCast(@ptrCast(ctx)));
}

// NOTE: this is 0x00RRGGBB but encoded as little-endian.
pub const RGBColor = packed struct(u32) {
    blue: u8 = 0,
    green: u8 = 0,
    red: u8 = 0,
    _r1: u8 = 0,
};
