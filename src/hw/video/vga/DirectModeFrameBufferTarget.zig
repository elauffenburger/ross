const std = @import("std");

const kstd = @import("../../../kstd.zig");
const vga = @import("../vga.zig");
const FrameBuffer = @import("FrameBuffer.zig");
const regs = @import("registers.zig");

const Self = @This();

allocator: std.mem.Allocator,

fb: *FrameBuffer,

target: FrameBuffer.FrameBufferTarget,

pub fn create(allocator: std.mem.Allocator, fb: *FrameBuffer) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .allocator = allocator,

        .fb = fb,

        .target = .{
            .context = self,

            .clearRaw = clearRaw,
            .writeChAt = writeChAt,
            .scroll = scroll,
            .u8BufIndex = u8BufIndex,
            .syncCursor = null,
        },
    };

    return self;
}

pub fn clearRaw(ctx: *const anyopaque) void {
    const self = fromCtx(ctx);
    const buf = self.bufferSlice();

    @memset(buf, 0);
}

pub fn writeChAt(ctx: *const anyopaque, ch: u8, pos: vga.Position) void {
    const self = fromCtx(ctx);

    const font = self.fb.text.font;

    const font_char = font.chars[ch];
    var i: usize = 0;

    // TODO: if a character won't fit into the remaining space on the current line, we need to go down a line first
    const ch_width = font.char_info.width;
    const ch_height = font.char_info.height;

    // TODO: we don't support widths that aren't 8; if they're larger (or smaller?) we need to make some changes to the code below to support that (since now a row could actually span multiple bytes).
    std.debug.assert(ch_width == 8);

    // TODO: drawing individual pixels is fine for now, but we should really be drawing as close to a row at a time as we can.
    for (0..ch_height) |y| {
        const row = font_char.bitmap[y];

        for (0..ch_width) |x| {
            const bit = @as(u8, 1) << (7 - @as(u3, @intCast(x)));
            if (row & bit != 0) {
                self.drawPixel(
                    .{
                        .x = (pos.x * ch_width) + x,
                        .y = (pos.y * ch_height) + y,
                    },
                    self.fb.text.colors.fg,
                );
            }

            i += 1;
        }
    }
}

inline fn bufTextLine(self: *const Self, text_buf: []volatile u32, line: u32) []volatile u32 {
    return text_buf[self.u8BufCharIndex(0, line)..self.u8BufCharIndex(0, line + 1)];
}

pub fn scroll(ctx: *const anyopaque) void {
    const self = fromCtx(ctx);

    const buf = self.bufferSlice();
    const text_buf: []volatile u32 = @alignCast(std.mem.bytesAsSlice(u32, buf));
    const text_grid_dims = self.fb.textGrid();

    for (1..text_grid_dims.height) |line_i| {
        // Copy the current line to the previous line.
        @memcpy(
            self.bufTextLine(text_buf, line_i - 1),
            self.bufTextLine(text_buf, line_i),
        );
    }

    // Clear last line.
    @memset(self.bufTextLine(text_buf, text_grid_dims.height - 1), @bitCast(RGBColor.fromVGA(self.fb.text.colors.bg)));
}

pub fn u8BufIndex(ctx: *const anyopaque, pos: vga.Position) usize {
    const self = fromCtx(ctx);

    return self.u8BufPixelIndex(pos.x, pos.y);
}

pub fn drawPixel(self: *Self, pos: vga.Position, color: vga.TextColor) void {
    const index = self.u8BufPixelIndex(pos.x, pos.y);
    const pixel: *u32 = @ptrFromInt(self.fb.addr + index);

    pixel.* = @bitCast(RGBColor.fromVGA(color));
}

pub fn drawPixelAtIndex(self: *Self, index: usize, color: vga.TextColor) void {
    const pixel: *u32 = @ptrFromInt(self.fb.addr + index);

    pixel.* = @bitCast(RGBColor.fromVGA(color));
}

inline fn u8BufPixelIndex(self: *const Self, x: u32, y: u32) usize {
    return y * self.fb.pitch + x * self.fb.pixel_width;
}

inline fn u8BufCharIndex(self: *const Self, x: u32, y: u32) usize {
    const char_info = self.fb.text.font.char_info;

    // NOTE: we need to convert from character units to pixel units before calling u8BufPixelIndel.
    // additionally, this may not even be the right conversion; do we need to look at charwidth?
    return self.u8BufPixelIndex((x * char_info.width) / 4, (y * char_info.height) / 4);
}

fn bufferSlice(self: *const Self) []volatile u8 {
    const buf: [*]volatile u8 = @ptrFromInt(self.fb.addr);
    return buf[0..self.u8BufPixelIndex(self.fb.width, self.fb.height)];
}

fn fromCtx(ctx: *const anyopaque) *Self {
    return @alignCast(@constCast(@ptrCast(ctx)));
}

// NOTE: this is 0x00RRGGBB but encoded as little-endian.
const RGBColor = packed struct(u32) {
    blue: u8 = 0,
    green: u8 = 0,
    red: u8 = 0,
    _r1: u8 = 0,

    pub fn fromVGA(color: vga.TextColor) @This() {
        // TODO: fully implement
        return switch (color) {
            .black => .{},
            .red => .{ .red = 0xff },
            .green => .{ .green = 0xff },
            .blue => .{ .blue = 0xff },
            else => std.debug.panic("unimplemented!", .{}),
        };
    }
};
