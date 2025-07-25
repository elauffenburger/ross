const std = @import("std");

const multiboot2 = @import("../../boot/multiboot2.zig");
const kstd = @import("../../kstd.zig");
const DirectModeFrameBufferTarget = @import("vga/DirectModeFrameBufferTarget.zig");
const FrameBuffer = @import("vga/FrameBuffer.zig");
pub const regs = @import("vga/registers.zig");
const psf = @import("vga/text/psf.zig");
const TextModeFrameBufferTarget = @import("vga/TextModeFrameBufferTarget.zig");

// SAFETY: set in init.
var frame_buffer: FrameBuffer = undefined;

pub fn init(allocator: std.mem.Allocator, frame_buffer_info: *multiboot2.boot_info.FrameBufferInfo) !void {
    const width, const height = .{ frame_buffer_info.width, frame_buffer_info.height };

    const color_info = frame_buffer_info.color_info;
    kstd.log.dbgf(
        \\ addr: 0x{x}
        \\ bpp: {}
        \\ red_field_position: {}
        \\ red_mask_size: {}
        \\ green_field_position: {}
        \\ green_mask_size: {}
        \\ blue_field_position: {}
        \\ blue_mask_size: {}
        \\
    ,
        .{
            frame_buffer_info.addr,
            frame_buffer_info.bpp,
            color_info.direct.red_field_position,
            color_info.direct.red_mask_size,
            color_info.direct.green_field_position,
            color_info.direct.green_mask_size,
            color_info.direct.blue_field_position,
            color_info.direct.blue_mask_size,
        },
    );

    // Save frame buffer info.
    frame_buffer = .{
        .addr = @intCast(frame_buffer_info.addr),

        .width = width,
        .height = height,

        .pitch = frame_buffer_info.pitch,
        .pixel_width = @as(u32, frame_buffer_info.bpp) / 8,

        .colors = ColorPair{
            .fg = Color.LightGray,
            .bg = Color.Black,
        },

        .font = psf.Fonts.@"Uni1-Fixed16",

        .target = blk: {
            switch (frame_buffer_info.framebuffer_type) {
                .ega => {
                    const target = try TextModeFrameBufferTarget.create(allocator, width, height);
                    break :blk &target.target;
                },
                .direct => {
                    const target = try DirectModeFrameBufferTarget.create(allocator, width, height);
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

    // HACK: test
    const t = @as(*DirectModeFrameBufferTarget, @alignCast(@constCast(@ptrCast(frame_buffer.target.context))));
    for (0..100, 0..100) |x, y| {
        // const red = 0x00ff0000;

        // const addr = frame_buffer.addr + (x * frame_buffer.pixel_width) + (y * frame_buffer.pitch);
        // const pixel: *u32 = @ptrFromInt(addr);
        // pixel.* = red;

        t.drawPixel(
            &frame_buffer,
            .{ .x = x, .y = y },
            .{ .green = 0xff },
        );
    }
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

pub const Position = struct {
    x: u32,
    y: u32,
};

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
