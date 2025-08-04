const std = @import("std");

const multiboot2 = @import("../../boot/multiboot2.zig");
const kstd = @import("../../kstd.zig");
pub const DirectModeFrameBufferTarget = @import("vga/DirectModeFrameBufferTarget.zig");
pub const FrameBuffer = @import("vga/FrameBuffer.zig");
pub const regs = @import("vga/registers.zig");
pub const psf = @import("vga/text/psf.zig");
pub const TextModeFrameBufferTarget = @import("vga/TextModeFrameBufferTarget.zig");

// SAFETY: set in init.
pub var frame_buffer: FrameBuffer = undefined;

pub fn init(allocator: std.mem.Allocator, mb2_frame_buffer: *multiboot2.boot_info.FrameBufferInfo) !void {
    const width, const height = .{ mb2_frame_buffer.width, mb2_frame_buffer.height };

    // Save frame buffer info.
    {
        frame_buffer = .{
            .addr = @intCast(mb2_frame_buffer.addr),

            .width = width,
            .height = height,

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
                    const target = try TextModeFrameBufferTarget.create(allocator, &frame_buffer);
                    break :blk &target.target;
                },
                .direct => {
                    const target = try DirectModeFrameBufferTarget.create(allocator, &frame_buffer);
                    break :blk &target.target;
                },
                else => std.debug.panic("unsupported framebuffer type: {}", .{mb2_frame_buffer.framebuffer_type}),
            },
        };
    }

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

pub const Position = struct { x: u32, y: u32 };

pub const TextColor = enum(u8) {
    black,
    blue,
    green,
    cyan,
    red,
    magenta,
    brown,
    lightGray,
    darkGray,
    lightBlue,
    lightGreen,
    lightCyan,
    lightRed,
    lightMagenta,
    lightBrown,
    white,
};

pub const TextColorPair = struct { fg: TextColor, bg: TextColor };
