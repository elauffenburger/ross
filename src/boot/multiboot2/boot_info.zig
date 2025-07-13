const std = @import("std");

const BootInfoStart = packed struct {
    total_size: u32,
    reserved: u32 = undefined,
};

pub const TagHeader = packed struct {
    type: u32,
    size: u32,
};

pub const BootCommandLineInfo = packed struct {
    pub const Type = 1;

    header: TagHeader,

    pub fn str(self: *@This()) [*c]u8 {
        return @ptrFromInt(@intFromPtr(self) + (@bitSizeOf(TagHeader) / 8));
    }
};

pub const FrameBufferInfo = packed struct {
    pub const Type = 8;

    header: TagHeader,

    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,

    framebuffer_type: enum(u8) {
        indexed = 0,
        direct = 1,
        ega = 2,
    },

    reserved: u8,

    // NOTE: the remaining content is a variable-size color_info field.
    color_info: packed union {
        indexed: packed struct {
            framebuffer_palette_num_colors: u32,

            // NOTE: the remaining content is an array of color descriptors.
            const ColorDescriptor = packed struct {
                red: u8,
                green: u8,
                blue: u8,
            };
        },

        direct: packed struct {
            framebuffer_red_field_position: u8,
            framebuffer_red_mask_size: u8,
            framebuffer_green_field_position: u8,
            framebuffer_green_mask_size: u8,
            framebuffer_blue_field_position: u8,
            framebuffer_blue_mask_size: u8,
        },

        ega: packed struct {},
    },
};

pub const VBEInfo = packed struct {
    pub const Type = 7;

    header: TagHeader,

    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,
    vbe_control_info: u4096,
    vbe_mode_info: u2048,
};

pub const BootInfo = struct {
    cmd_line: ?*BootCommandLineInfo = null,
    frame_buffer: ?*FrameBufferInfo = null,
    vbe_info: ?*VBEInfo = null,
};

pub fn parse(info_addr: usize) BootInfo {
    // NOTE: here's what we're currently getting:
    // 1 cmd line
    // 2 bootloader name
    // 4 memory info
    // 6 memory map
    // 8 framebuffer
    // 9 ELF
    // 13 efi system table
    // 14 rsdp acpi
    //
    // TODO: we want to use VESA extensions at some point, but the bootloader isn't reporting that to us even though it's not claiming it doesn't support the tag...weird.

    const info_start: *BootInfoStart = @ptrFromInt(info_addr);

    const start = info_addr;
    const end = start + @as(usize, @intCast(info_start.total_size));
    _ = end; // autofix

    var result: BootInfo = .{};

    var head: u32 = @intFromPtr(info_start) + 8;
    // HACK: disabling safety check to see what happens.
    // while (head < end) {
    while (true) {
        const header: *TagHeader = @ptrFromInt(head);
        const block_type = header.type;
        switch (block_type) {
            BootCommandLineInfo.Type => {
                result.cmd_line = @ptrFromInt(head);

                var buf = [_]u8{0} ** 256;

                const cmd_line = std.fmt.bufPrint(&buf, "{s}\n", .{result.cmd_line.?.str()}) catch blk: {
                    break :blk &.{};
                };
                _ = cmd_line; // autofix
            },
            FrameBufferInfo.Type => {
                result.frame_buffer = @ptrFromInt(head);
            },
            VBEInfo.Type => {
                result.vbe_info = @ptrFromInt(head);
            },
            0 => break,
            else => {
                if (block_type < 0 or block_type > 22) {
                    std.debug.panic("unknown boot info tag type: {d}", .{block_type});
                }
            },
        }

        // Skip forward to the end of the block and align to 8 byte boundary.
        head += header.size;

        if (!std.mem.isAligned(head, 8)) {
            head = std.mem.alignForward(u32, head, 8);
        }
    }

    if (result.frame_buffer) |buf_ptr| {
        const buf = buf_ptr.*;
        const addr = buf.framebuffer_addr;
        const typ = buf.framebuffer_type;
        _ = typ; // autofix
        _ = addr; // autofix
    }

    if (result.vbe_info) |vbe_ptr| {
        const vbe = vbe_ptr.*;

        const seg = vbe.vbe_interface_seg;
        _ = seg; // autofix
        const off = vbe.vbe_interface_off;
        _ = off; // autofix
        const len = vbe.vbe_interface_len;
        _ = len; // autofix

        const mode = vbe.vbe_mode;
        _ = mode; // autofix
    }

    return result;
}
