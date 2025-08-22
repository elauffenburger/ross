const std = @import("std");

const kstd = @import("../../../kstd.zig");
const vga = @import("../vga.zig");
const FrameBuffer = @import("FrameBuffer.zig");
const regs = @import("registers.zig");

const Self = @This();

allocator: std.mem.Allocator,
temp_buf: []u16,

fb: *FrameBuffer,

target: FrameBuffer.FrameBufferTarget,

pub fn create(allocator: std.mem.Allocator, fb: *FrameBuffer) !*Self {
    const self = try allocator.create(Self);
    self.* = .{
        .allocator = allocator,
        .temp_buf = try allocator.alloc(u16, fb.width * fb.height - bufIndexInternal(0, fb.text.font.char_info.height, fb.pitch, fb.pixel_width)),

        .fb = fb,

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

pub fn scroll(ctx: *const anyopaque) void {
    const self = fromCtx(ctx);

    const text_dims = self.fb.textGridDimensions();

    const line_2_index = self.bufIndex(0, self.fb.text.font.char_info.height);
    const last_line_index = self.bufIndex(0, (text_dims.@"1" - 1) * self.fb.text.font.char_info.height);

    // Copy the screen buffer starting at line 2 to the temp buffer.
    const buf = self.fb.bufferSlice();
    @memcpy(self.temp_buf, buf[line_2_index..]);

    // Write temp buffer back to real buffer.
    @memcpy(buf[0 .. buf.len - line_2_index], self.temp_buf);

    // Clear last line.
    @memset(
        @as([]volatile u32, @alignCast(@ptrCast(buf)))[(last_line_index / 2)..],
        @bitCast(RGBColor.fromVGA(self.fb.text.colors.bg)),
    );
}

pub fn posBufIndex(ctx: *const anyopaque, pos: vga.Position) u32 {
    const self = fromCtx(ctx);
    return self.bufIndex(pos.x, pos.y);
}

pub fn drawPixel(self: *Self, pos: vga.Position, color: vga.TextColor) void {
    const index = self.bufIndex(pos.x, pos.y);
    const pixel: *u32 = @ptrFromInt(self.fb.addr + index);

    pixel.* = @bitCast(RGBColor.fromVGA(color));
}

inline fn bufIndex(self: *Self, x: u32, y: u32) u32 {
    return bufIndexInternal(x, y, self.fb.pitch, self.fb.pixel_width);
}

inline fn bufIndexInternal(x: u32, y: u32, fb_pitch: u32, fb_pixel_width: u32) u32 {
    return y * fb_pitch + x * fb_pixel_width;
}

fn bufferSlice(self: *Self) []volatile u32 {
    const buf: [*]volatile u32 = @ptrFromInt(self.fb.addr);
    return buf[0 .. self.bufIndex(self.fb.width, self.fb.height) + 1];
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
            .black => .{ .red = 0xff, .green = 0xff, .blue = 0xff },
            .red => .{ .red = 0xff },
            .green => .{ .green = 0xff },
            .blue => .{ .blue = 0xff },
            else => std.debug.panic("unimplemented!", .{}),
        };
    }
};
