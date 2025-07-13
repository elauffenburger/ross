const std = @import("std");

const vga = @import("../vga.zig");
const Char = vga.Char;
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
            .syncCursor = syncCursor,
        },
    };

    return self;
}

pub fn clearRaw(ctx: *const anyopaque, frame_buf: *FrameBuffer) void {
    const self = fromCtx(ctx);
    const buf = self.bufferSlice(frame_buf);

    @memset(buf, Char.code(.{ .colors = frame_buf.colors, .ch = ' ' }));
    frame_buf.setCursor(0, 0);
}

pub fn writeChAt(ctx: *const anyopaque, frame_buf: *FrameBuffer, ch: Char, x: u32, y: u32) void {
    const self = fromCtx(ctx);
    const index = self.bufIndex(x, y);

    var code: u16 = @intCast(ch.colors.code());
    code <<= 8;
    code |= ch.ch;

    const buffer = self.bufferSlice(frame_buf);
    buffer[index] = code;
}

pub fn scroll(ctx: *const anyopaque, frame_buf: *FrameBuffer) void {
    const self = fromCtx(ctx);

    const width = self.width;
    const height = self.height;

    const buf = self.bufferSlice(frame_buf);

    // Copy vga buffer to temp buffer offset by one line.
    @memcpy(self.temp_buf, buf[width..(width * height)]);

    // Copy tmp buf back to vga buf and clear the last line.
    @memcpy(buf[0 .. (width * height) - width], self.temp_buf);
    @memcpy(buf[(width * height) - width ..], self.empty_line);

    frame_buf.setCursor(0, height - 1);
}

pub fn syncCursor(ctx: *const anyopaque, frame_buf: *FrameBuffer) void {
    const self = fromCtx(ctx);

    const loc_reg = regs.crt_ctrl.cursor_location;
    const cursor_index = @as(u16, @intCast(self.bufIndex(frame_buf.pos.x, frame_buf.pos.y)));

    regs.crt_ctrl.write(loc_reg.lo, @intCast(cursor_index & 0xff));
    regs.crt_ctrl.write(loc_reg.hi, @intCast((cursor_index >> 8) & 0xff));
}

inline fn bufIndex(self: *Self, x: u32, y: u32) u32 {
    return y * self.width + x;
}

fn bufferSlice(self: *Self, frame_buf: *FrameBuffer) []volatile u16 {
    const buf: [*]volatile u16 = @ptrFromInt(frame_buf.addr);
    return buf[0..(self.width * self.height)];
}

fn fromCtx(ctx: *const anyopaque) *Self {
    return @alignCast(@constCast(@ptrCast(ctx)));
}
