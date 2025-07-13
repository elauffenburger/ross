const std = @import("std");

pub const BootInfoStart = packed struct {
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

    // NOTE: the actual content is a c-style null-terminated string.
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

pub const BootInfo = struct {
    cmd_line: ?*BootCommandLineInfo = null,
    frame_buffer: ?*FrameBufferInfo = null,
};

pub fn parse(info_addr: usize) BootInfo {
    const info_start: *BootInfoStart = @ptrFromInt(info_addr);

    const start = info_addr;
    const end = start + @as(usize, @intCast(info_start.total_size));

    var result: BootInfo = .{};

    var head: u32 = @intFromPtr(info_start) + 8;
    while (head < end) {
        const header: *TagHeader = @ptrFromInt(head);
        const block_type = header.type;
        switch (block_type) {
            BootCommandLineInfo.Type => {
                result.cmd_line = @ptrFromInt(head);
            },
            FrameBufferInfo.Type => {
                result.frame_buffer = @ptrFromInt(head);
            },
            0 => break,
            else => {
                if (block_type < 0 or block_type > 22) {
                    std.debug.panic("unknown boot info tag type: {d}", .{block_type});
                }
            },
        }

        head += header.size;
    }

    return result;
}
