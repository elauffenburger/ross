const std = @import("std");

const multiboot2 = @import("../../../boot/multiboot2.zig");
const vga = @import("../vga.zig");
const FrameBuffer = @import("FrameBuffer.zig");
const regs = @import("registers.zig");
const psf = @import("text/psf.zig");

pub const FrameBufferTarget = struct {
    context: *anyopaque,

    clearRaw: *const fn (ctx: *const anyopaque) void,
    writeChAt: *const fn (ctx: *const anyopaque, ch: u8, pos: vga.Position) void,
    scroll: *const fn (ctx: *const anyopaque) void,
    u8BufIndex: *const fn (ctx: *const anyopaque, vga.Position) usize,
    syncCursor: ?*const fn (ctx: *const anyopaque) void,
};

const Self = @This();

addr: u32,

width: u32,
height: u32,

// pitch is the number of bytes in VRAM you should skip to go down one pixel.
//
// I guess this is used for in-hardware 2D horizontal scrolling?
// see: https://wiki.osdev.org/Drawing_In_a_Linear_Framebuffer#Plotting_Pixels
pitch: u32,

// pixel_width is the number of bytes in VRAM a pixel occupies.
pixel_width: u32,

text: struct {
    font: psf.Font,
    colors: vga.TextColorPair,
    pos: vga.Position = .{ .x = 0, .y = 0 },
},

// NOTE: if we change any properties like width, height, etc., we _must_ recreate the target!
target: *FrameBufferTarget,

// TODO: decouple this from multiboot2.
pub fn create(allocator: std.mem.Allocator, mb2_frame_buffer: *multiboot2.boot_info.FrameBufferInfo) !*Self {
    const frame_buffer = try allocator.create(Self);
    frame_buffer.* = .{
        .addr = @intCast(mb2_frame_buffer.addr),

        .width = mb2_frame_buffer.width,
        .height = mb2_frame_buffer.height,

        .pitch = mb2_frame_buffer.pitch,
        .pixel_width = @as(u32, mb2_frame_buffer.bpp) / 8,

        .text = .{
            .font = psf.Fonts.@"Uni1-Fixed16",
            .colors = .{
                .fg = .green,
                .bg = .black,
            },
        },

        .target = blk: switch (mb2_frame_buffer.framebuffer_type) {
            .ega => {
                const target = try vga.TextModeFrameBufferTarget.create(allocator, frame_buffer);
                break :blk &target.target;
            },
            .direct => {
                const target = try vga.DirectModeFrameBufferTarget.create(allocator, frame_buffer);
                break :blk &target.target;
            },
            else => std.debug.panic("unsupported framebuffer type: {}", .{mb2_frame_buffer.framebuffer_type}),
        },
    };

    return frame_buffer;
}

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
    self.target.clearRaw(self.target.context);

    self.setCursor(0, 0);

    if (self.target.syncCursor) |sync| {
        sync(self.target.context);
    }
}

pub fn writeCh(self: *Self, ch: u8) void {
    self.writeChInternal(ch);

    if (self.target.syncCursor) |sync| {
        sync(self.target.context);
    }
}

pub fn writeStr(self: *Self, data: []const u8) void {
    for (data) |c| {
        if (c == 0) {
            return;
        }

        self.writeChInternal(c);
    }

    if (self.target.syncCursor) |sync| {
        sync(self.target.context);
    }
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
    self.text.pos = .{ .x = x, .y = y };

    const text_grid = self.textGrid();

    if (self.text.pos.x == text_grid.width) {
        self.newline();
        return;
    }

    if (self.text.pos.y >= text_grid.height) {
        self.scroll();
        return;
    }
}

pub fn bufferSlice(self: *Self) []volatile u16 {
    const buf: [*]volatile u16 = @ptrFromInt(self.addr);
    return buf[0..(self.width * self.height)];
}

fn writeChInternal(self: *Self, ch: u8) void {
    if (ch == '\n') {
        self.setCursor(0, self.text.pos.y + 1);
        return;
    }

    self.target.writeChAt(self.target.context, ch, self.text.pos);
    self.setCursor(self.text.pos.x + 1, self.text.pos.y);
}

fn newline(self: *Self) void {
    self.setCursor(0, self.text.pos.y + 1);
}

// TODO: cache this and make it a field.
pub inline fn textGrid(self: Self) struct { width: u32, height: u32 } {
    const ch_info = self.text.font.char_info;

    return .{
        .width = self.width / ch_info.width,
        .height = self.height / ch_info.height,
    };
}

fn scroll(self: *Self) void {
    self.target.scroll(self.target.context);

    // HACK: testing this out!
    self.text.pos.x = 0;
    self.text.pos.y = self.textGrid().height - 1;
}
