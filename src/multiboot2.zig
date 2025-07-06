const std = @import("std");

const kstd = @import("./kstd.zig");

const magic: u32 = 0xE85250D6;
const architecture: u32 = 1;

fn headerBytesLen(tags: []const Tag) usize {
    var tags_len: u32 = 0;
    for (tags) |tag| {
        tags_len += @sizeOf(@FieldType(Tag, @tagName(std.meta.activeTag(tag))));
    }

    // The total len is len(tags) + len(header_fields)
    return tags_len + (4 * 4);
}

pub fn headerBytes(tags: []const Tag) [headerBytesLen(tags)]u8 {
    const header_length = @as(u32, headerBytesLen(tags));
    const checksum: u32 = ~(magic + architecture + header_length);

    const ResultList = std.fifo.LinearFifo(u8, .{ .Static = 4096 });
    var result_bytes: ResultList = ResultList.init();

    try {
        // Write header fields.
        try result_bytes.write(&std.mem.toBytes(magic));
        try result_bytes.write(&std.mem.toBytes(architecture));
        try result_bytes.write(&std.mem.toBytes(header_length));
        try result_bytes.write(&std.mem.toBytes(checksum));

        // Write tag values.
        for (tags) |tag| {
            const tag_val = @field(tag, @tagName(std.meta.activeTag(tag)));
            const tag_val_type = @typeInfo(@TypeOf(tag_val));
            const tag_val_int_type = tag_val_type.@"struct".backing_integer.?;

            try result_bytes.write(&std.mem.toBytes(@as(tag_val_int_type, @bitCast(tag_val))));
        }

        var results = [_]u8{undefined} ** header_length;
        @memcpy(&results, result_bytes.readableSlice(0));

        return results;
    } catch |err| {
        @compileError(std.fmt.comptimePrint("{?}", .{err}));
    };
}

pub const Tag = union(enum) {
    address: SizedTag(struct {
        type: u16 = 2,

        // Contains the address corresponding to the beginning of the Multiboot2 header — the physical memory location at which the magic value is supposed to be loaded.
        // This field serves to synchronize the mapping between OS image offsets and physical memory addresses.
        header_addr: u32,

        // Contains the physical address of the beginning of the text segment. The offset in the OS image file at which to start loading is defined by the offset at which
        // the header was found, minus (header_addr - load_addr).
        //
        // load_addr must be less than or equal to header_addr.
        //
        // Special value -1 means that the file must be loaded from its beginning.
        load_addr: u32,

        // Contains the physical address of the end of the data segment. (load_end_addr - load_addr) specifies how much data to load.
        // This implies that the text and data segments must be consecutive in the OS image; this is true for existing a.out executable formats.
        //
        // If this field is zero, the boot loader assumes that the text and data segments occupy the whole OS image file.
        load_end_addr: u32,

        // Contains the physical address of the end of the bss segment. The boot loader initializes this area to zero, and reserves the memory it occupies to avoid placing
        // boot modules and other data relevant to the operating system in that area.
        //
        // If this field is zero, the boot loader assumes that no bss segment is present.
        bss_end_addr: u32,
    }),

    entry: SizedTag(struct {
        type: u16 = 3,

        // The physical address to which the boot loader should jump in order to start running the operating system.
        entry_addr: u32,
    }),

    efi_i386_entry: SizedTag(struct {
        type: u16 = 8,

        // The physical address to which the boot loader should jump in order to start running EFI i386 compatible operating system code.
        //
        // This tag is taken into account only on EFI i386 platforms when Multiboot2 image header contains EFI boot services tag.
        // Then entry point specified in ELF header and the entry address tag of Multiboot2 header are ignored.
        entry_addr: u32,
    }),

    efi_amd64_entry: SizedTag(struct {
        type: u16 = 9,

        // The physical address to which the boot loader should jump in order to start running EFI amd64 compatible operating system code.
        //
        // This tag is taken into account only on EFI amd64 platforms when Multiboot2 image header contains EFI boot services tag.
        // Then entry point specified in ELF header and the entry address tag of Multiboot2 header are ignored.
        entry_addr: u32,
    }),

    flags: SizedTag(struct {
        type: u16 = 4,

        // If bit 0 is set at least one of supported consoles must be present and information about it must be available in mbi.
        // If bit 1 is set it indicates that the OS image has EGA text support.
        console_flags: u32,
    }),

    // This tag specifies the preferred graphics mode. If this tag is present bootloader assumes that the payload has framebuffer support.
    //
    // Note that that is only a recommended mode by the OS image. Boot loader may choose a different mode if it sees fit.
    framebuffer: SizedTag(struct {
        type: u16 = 5,

        // Contains the number of the columns.
        // This is specified in pixels in a graphics mode, and in characters in a text mode.
        //
        // The value zero indicates that the OS image has no preference.
        width: u32 = 0,

        // Contains the number of the lines.
        // This is specified in pixels in a graphics mode, and in characters in a text mode.
        //
        // The value zero indicates that the OS image has no preference.
        height: u32 = 0,

        // Contains the number of bits per pixel in a graphics mode, and zero in a text mode.
        //
        // The value zero indicates that the OS image has no preference.
        depth: u32 = 0,
    }),

    // If this tag is present modules must be page aligned.
    module_alignment: SizedTag(struct { type: u16 = 6 }),

    // This tag indicates that payload supports starting without terminating boot services.
    efi_boot_services: SizedTag(struct { type: u16 = 7 }),

    relocatable_header: SizedTag(struct {
        type: u16 = 10,

        // Lowest possible physical address at which image should be loaded.
        // The bootloader cannot load any part of image below this address.
        min_addr: u32,

        // Highest possible physical address at which loaded image should end.
        // The bootloader cannot load any part of image above this address.
        max_addr: u32,

        // Image alignment in memory, e.g. 4096.
        @"align": u32,

        // Contains load address placement suggestion for boot loader.
        // Boot loader should follow it.
        preference: enum(u32) {
            // No preference.
            none = 0,

            // Load image at lowest possible address but not lower than min_addr.
            lowest = 1,

            // Load image at highest possible address but not higher than max_addr.
            highest = 2,
        },
    }),
};

fn SizedTag(def: type) type {
    const def_info = @typeInfo(def);

    const @"type" = blk: {
        for (def_info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, "type") and field.type == u16 and field.default_value_ptr != null) {
                break :blk field;
            }
        }

        @compileError(std.fmt.comptimePrint("def requires a \"type\" field of type u16 with a default value, received: {?}", .{def}));
    };

    const Flags = packed struct(u16) {
        required: bool = false,
        flags_data: u15 = 0,
    };

    var fields = [_]std.builtin.Type.StructField{undefined} ** (2 + def_info.@"struct".fields.len);

    // Add the type field.
    fields[0] = .{
        .name = "type",
        .type = u16,
        .default_value_ptr = @"type".default_value_ptr,
        .is_comptime = false,
        .alignment = 0,
    };

    // Add flags field.
    fields[1] = .{
        .name = "flags",
        .type = Flags,
        .default_value_ptr = &Flags{},
        .is_comptime = false,
        .alignment = 0,
    };

    // Calculate the size of the tag by getting the total size of the definition and adding the size of the synthesized flags and size field.
    fields[2] = .{
        .name = "size",
        .type = u32,
        .default_value_ptr = &(@as(u32, (@bitSizeOf(def) + 16 + 16) / 8)),
        .is_comptime = false,
        .alignment = 0,
    };

    // Add the fields from the def (other than type).
    var field_i = 3;
    for (def_info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, "type")) {
            continue;
        }

        fields[field_i] = .{
            .name = field.name,
            .type = field.type,
            .default_value_ptr = field.default_value_ptr,
            .is_comptime = false,
            .alignment = 0,
        };

        field_i += 1;
    }

    return @Type(std.builtin.Type{
        .@"struct" = .{
            .layout = .@"packed",
            .fields = @constCast(&fields),
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

test "Tag: can generate" {
    _ = Tag{
        .address = .{
            .header_addr = 0x00,
            .load_addr = 0x10,
            .load_end_addr = 0x20,
            .bss_end_addr = 0x30,
        },
    };
}

test "Tag: has correct size" {
    const tag = Tag{
        .framebuffer = .{
            .width = 1920,
            .height = 1080,
            .depth = 0,
        },
    };

    std.debug.assert(tag.framebuffer.size == 20);
}
