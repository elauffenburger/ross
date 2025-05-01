const kstd = @import("kstd.zig");
const vga = @import("vga.zig");
const multiboot = @import("multiboot.zig");
const descriptors = @import("descriptors.zig");

// Write multiboot header before we do anything.
export var multiboot_header align(4) linksection(".multiboot") = blk: {
    const flags = multiboot.MultibootHeader.Flags.Align | multiboot.MultibootHeader.Flags.MemInfo | multiboot.MultibootHeader.Flags.VideoMode;

    break :blk multiboot.MultibootHeader{
        .flags = flags,
        .checksum = chk: {
            const checksum_magic: i64 = @intCast(multiboot.MultibootHeader.Magic);
            const checksum_flags: i64 = @intCast(flags);

            break :chk -(checksum_magic + checksum_flags);
        },
    };
};

// Create the GDT.
var gdt align(4) = [_]descriptors.SegmentDescriptor{
    // Mandatory null entry.
    @bitCast(@as(u64, 0)),

    // Kernel Mode Code Segment.
    descriptors.SegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .code = @bitCast(@as(u8, 0x9a)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // User Mode Data Segment.
    descriptors.SegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .data = @bitCast(@as(u8, 0xfa)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // User Mode Code Segment.
    descriptors.SegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .code = @bitCast(@as(u8, 0xf2)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // Kernel Mode Data Segment.
    descriptors.SegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .data = @bitCast(@as(u8, 0x92)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // TODO: Task State Segment.
    @bitCast(@as(u64, 0xc)),
};

var gdtr: [*]descriptors.GdtDescriptor = undefined;

// Reserve 16K for the stack in the .bss section.
const STACK_SIZE = 16 * 1024;
var stack_bytes: [STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

inline fn loadGdtr() void {
    asm volatile (
        \\ push %[limit]
        \\ push %[addr]
        \\ call load_gdtr
        :
        : [limit] "X" (@as(u16, @as(i16, @sizeOf(@TypeOf(gdt))) - 1)),
          [addr] "X" (@as(u32, @intFromPtr(&gdt))),
    );
}

inline fn initStack() void {
    asm volatile (
        \\ movl     %[stack_top], %%esp
        \\ movl     %%esp, %%ebp
        :
        : [stack_top] "i" (@as([*]align(4) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
    );
}

pub export fn _kmain() callconv(.naked) noreturn {
    initStack();

    asm volatile (
        \\ call     %[kmain:P]
        :
        : [kmain] "X" (&kmain),
    );
}

fn kmain() callconv(.c) void {
    vga.init();
    loadGdtr();

    vga.writeStr("hello, zig!\n");

    while (true) {}
}
