const std = @import("std");

const multiboot2 = @import("../../boot/multiboot2.zig");
const regs = @import("vga/registers.zig");

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

pub fn init(allocator: std.mem.Allocator, frame_buffer_info: multiboot2.boot_info.FrameBufferInfo) void {
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
                .ega => {
                    const target = TextModeFrameBufferTarget.create(
                        allocator,
                        frame_buffer_info.framebuffer_width,
                        frame_buffer_info.framebuffer_height,
                    ) catch |err| {
                        std.debug.panic("unable to create frame buffer target: {}", .{err});
                    };

                    break :blk &target.target;
                },
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

const TextModeFrameBufferTarget = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    width: u32,
    height: u32,

    temp_buf: []u16,
    empty_line: []u16,

    target: FrameBufferTarget,

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
};
