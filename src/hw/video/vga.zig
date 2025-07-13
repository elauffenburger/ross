const std = @import("std");

const multiboot2 = @import("../../boot/multiboot2.zig");
const regs = @import("vga/registers.zig");

// var buffer = @as([*]volatile u16, );
// var buffer_addr: u32 = 0;

// SAFETY: set in init.
var frame_buffer: FrameBuffer = undefined;

pub fn writer() anyopaque {}

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

pub fn init(frame_buffer_info: multiboot2.boot_info.FrameBufferInfo) void {
    // Save frame buffer info.
    frame_buffer = .{
        .addr = @intCast(frame_buffer_info.framebuffer_addr),

        .width = frame_buffer_info.framebuffer_width,
        .height = frame_buffer_info.framebuffer_height,
        .pitch = frame_buffer_info.framebuffer_pitch,
        .pixel_width = 8 * frame_buffer_info.framebuffer_bpp,

        .colors = ColorPair{
            .fg = Color.LightGray,
            .bg = Color.Black,
        },

        .target = blk: {
            switch (frame_buffer_info.framebuffer_type) {
                .ega => break :blk TextModeFrameBufferTarget(80, 20).target(),
                else => std.debug.panic("unsupported framebuffer type: {}", .{frame_buffer_info.framebuffer_type}),
            }
        },
    };

    // Set IO addr select register.
    regs.misc_out.write(blk: {
        var reg = regs.misc_out.read();
        reg.io_addr_select = .color;

        break :blk reg;
    });

    // Clear screen.
    clear();
}

pub fn clear() void {
    frame_buffer.clear();
}

pub fn writeCh(ch: u8) void {
    frame_buffer.writeCh(ch);
}

pub fn writeStr(data: []const u8) void {
    frame_buffer.writeStr(data);
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    frame_buffer.printf(format, args);
}

const Position = struct {
    x: u32,
    y: u32,
};

const FrameBuffer = struct {
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

    pos: Position = .{ .x = 0, .y = 0 },
    colors: ColorPair,

    target: FrameBufferTarget,

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

    fn setCursor(self: *Self, x: u32, y: u32) void {
        self.pos.x = x;
        self.pos.y = y;

        if (self.pos.x == self.width) {
            self.newline();
            return;
        }

        if (self.pos.y == self.height) {
            self.target.scroll(self.target.context, self);
            return;
        }
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
};

const FrameBufferTarget = struct {
    context: *anyopaque,
    clearRaw: *const fn (ctx: *const anyopaque, *FrameBuffer) void,
    writeChAt: *const fn (ctx: *const anyopaque, *FrameBuffer, ch: Char, x: u32, y: u32) void,
    scroll: *const fn (ctx: *const anyopaque, *FrameBuffer) void,
    syncCursor: *const fn (ctx: *const anyopaque, *FrameBuffer) void,
};

fn TextModeFrameBufferTarget(buf_width: u32, buf_height: u32) type {
    return struct {
        const Self = @This();

        const width = buf_width;
        const height = buf_height;

        var temp_buf: [width * height]u16 = .{0} ** (width * height);

        pub fn target() FrameBufferTarget {
            return .{
                // SAFETY: unused
                .context = undefined,

                .clearRaw = clearRaw,
                .writeChAt = writeChAt,
                .scroll = scroll,
                .syncCursor = syncCursor,
            };
        }

        pub fn clearRaw(_: *const anyopaque, frame_buf: *FrameBuffer) void {
            const buf = bufferSlice(frame_buf);

            @memset(buf, Char.code(.{ .colors = frame_buf.colors, .ch = ' ' }));
            frame_buf.setCursor(0, 0);
        }

        pub fn writeChAt(_: *const anyopaque, frame_buf: *FrameBuffer, ch: Char, x: u32, y: u32) void {
            const index = bufIndex(x, y);

            var code: u16 = @intCast(ch.colors.code());
            code <<= 8;
            code |= ch.ch;

            const buffer = bufferSlice(frame_buf);
            buffer[index] = code;
        }

        pub fn scroll(_: *const anyopaque, frame_buf: *FrameBuffer) void {
            const buffer = bufferSlice(frame_buf);

            // Copy vga buffer to temp buffer offset by one line.
            const tmp_buf = temp_buf[0..(width * height - width)];
            @memcpy(tmp_buf, buffer[width..(width * height)]);

            // Copy tmp buf back to vga buf and clear the last line.
            @memcpy(buffer[0 .. (width * height) - width], tmp_buf);
            @memcpy(buffer[(width * height) - width ..], &([_]u16{Char.Empty.code()} ** width));

            frame_buf.setCursor(0, height - 1);
        }

        pub fn syncCursor(_: *const anyopaque, frame_buf: *FrameBuffer) void {
            const loc_reg = regs.crt_ctrl.cursor_location;
            const cursor_index = @as(u16, @intCast(bufIndex(frame_buf.pos.x, frame_buf.pos.y)));

            regs.crt_ctrl.write(loc_reg.lo, @intCast(cursor_index & 0xff));
            regs.crt_ctrl.write(loc_reg.hi, @intCast((cursor_index >> 8) & 0xff));
        }

        inline fn bufIndex(x: u32, y: u32) u32 {
            return y * width + x;
        }

        fn bufferSlice(frame_buf: *FrameBuffer) []volatile u16 {
            const buf: [*]volatile u16 = @ptrFromInt(frame_buf.addr);
            return buf[0..(width * height)];
        }
    };
}
