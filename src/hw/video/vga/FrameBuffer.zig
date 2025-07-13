const std = @import("std");

const vga = @import("../vga.zig");
const FrameBuffer = @import("FrameBuffer.zig");

pub const FrameBufferTarget = struct {
    context: *anyopaque,
    clearRaw: *const fn (ctx: *const anyopaque, *FrameBuffer) void,
    writeChAt: *const fn (ctx: *const anyopaque, *FrameBuffer, ch: vga.Char, x: u32, y: u32) void,
    scroll: *const fn (ctx: *const anyopaque, *FrameBuffer) void,
    syncCursor: *const fn (ctx: *const anyopaque, *FrameBuffer) void,
    posBufIndex: *const fn (ctx: *const anyopaque, *FrameBuffer, vga.Position) u32,
};

const Self = @This();

addr: u32,

width: u32,
height: u32,

// pitch is the number of bytes in VRAM you should skip to down down one pixel.
//
// I guess this is used for in-hardware 2D horizontal scrolling?
// see: https://wiki.osdev.org/Drawing_In_a_Linear_Framebuffer#Plotting_Pixels
pitch: u32,

// pixel_width is the number of bytes in VRAM a pixel occupies.
pixel_width: u32,

pos: vga.Position = .{ .x = 0, .y = 0 },
colors: vga.ColorPair,

// NOTE: if we change any properties like width, height, etc., we _must_ recreate the target!
target: *FrameBufferTarget,

pub fn init() Self {}

pub fn writer(self: *Self) anyopaque {
    return std.io.AnyWriter{
        .context = self,
        .writeFn = struct {
            fn write(ctx: *const anyopaque, buf: []const u8) anyerror!usize {
                var ctx_self: *Self = @alignCast(@constCast(@ptrCast(ctx)));
                ctx_self.writeStr(buf);

                return buf.len;
            }
        }.write,
    };
}

pub fn clear(self: *Self) void {
    self.target.clearRaw(self.target.context, self);
    self.setCursor(0, 0);
    self.target.syncCursor(self.target.context, self);
}

pub fn writeCh(self: *Self, ch: u8) void {
    self.writeChInternal(ch);
    self.target.syncCursor(self.target.context, self);
}

pub fn writeStr(self: *Self, data: []const u8) void {
    for (data) |c| {
        if (c == 0) {
            return;
        }

        self.writeChInternal(c);
    }

    self.target.syncCursor(self.target.context, self);
}

pub fn printf(self: *Self, comptime format: []const u8, args: anytype) void {
    // TODO: use a shared instance.
    var buf = std.mem.zeroes([256]u8);
    const fmtd = std.fmt.bufPrint(&buf, format, args) catch {
        return;
    };

    self.writeStr(fmtd);
}

pub fn setCursor(self: *Self, x: u32, y: u32) void {
    self.pos.x = x;
    self.pos.y = y;

    if (self.pos.x == self.width) {
        self.newline();
        return;
    }

    if (self.pos.y == self.height) {
        self.target.scroll(self.target.context, self);
        self.setCursor(0, self.height - 1);

        return;
    }
}

pub fn bufferSlice(self: *Self) []volatile u16 {
    const buf: [*]volatile u16 = @ptrFromInt(self.addr);
    return buf[0..(self.width * self.height)];
}

fn writeChInternal(self: *Self, ch: u8) void {
    if (ch == '\n') {
        self.newline();
        return;
    }

    self.target.writeChAt(self.target.context, self, .{ .ch = ch, .colors = self.colors }, self.pos.x, self.pos.y);
    self.setCursor(self.pos.x + 1, self.pos.y);
}

fn newline(self: *Self) void {
    self.setCursor(0, self.pos.y + 1);
}
