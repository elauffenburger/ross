const gdt = @import("gdt.zig");
const kstd = @import("kstd.zig");
const multiboot = @import("multiboot.zig");
const vga = @import("vga.zig");

// Write multiboot header before we do anything.
pub export var multiboot_header align(4) linksection(".multiboot") = blk: {
    const flags = multiboot.Header.Flags.Align | multiboot.Header.Flags.MemInfo | multiboot.Header.Flags.VideoMode;

    break :blk multiboot.Header{
        .flags = flags,
        .checksum = chk: {
            const checksum_magic: i32 = @intCast(multiboot.Header.Magic);
            const checksum_flags: i32 = @intCast(flags);

            break :chk @bitCast(-(checksum_magic + checksum_flags));
        },
    };
};

// NOTE: if you rearrange the entries in the GDT, make sure to update GdtSegment!
const GdtSegment = enum(u4) {
    null = 0,
    kernelCode = 1,
    kernelData = 2,
    tss = 3,
    userCode = 4,
    userData = 5,
};

// Create the GDT.
// NOTE: if you rearrange the entries in the GDT, make sure to update GdtSegment!
var global_descriptor_table align(4) = [_]gdt.SegmentDescriptor{
    // Mandatory null entry.
    @bitCast(@as(u64, 0)),

    // Kernel Mode Code Segment.
    gdt.SegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .code = @bitCast(@as(u8, 0x9a)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // Kernel Mode Data Segment.
    gdt.SegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .data = @bitCast(@as(u8, 0x92)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // Kernel TSS placeholder.
    // NOTE: this will be created for real when we init the GDT.
    @bitCast(@as(u64, 0)),

    // User Mode Code Segment.
    gdt.SegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .code = @bitCast(@as(u8, 0xfa)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // User Mode Data Segment.
    gdt.SegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .data = @bitCast(@as(u8, 0xf2)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),
};

// Allocate a pointer to the memory location we pass to lgdt.
var gdtr: *gdt.GdtDescriptor align(4) = undefined;

var tss: gdt.TaskStateSegment = @bitCast(@as(u864, 0));

// Reserve 16K for the kernel stack in the .bss section.
const KERNEL_STACK_SIZE = 16 * 1024;
var kernel_stack_bytes: [KERNEL_STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

// Reserve 16K for the userspace stack in the .bss section.
const STACK_SIZE = 16 * 1024;
var user_stack_bytes: [STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

pub export fn _kmain() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    // Set up GDT.
    {
        // Add TSS entry to GDT.
        global_descriptor_table[@intFromEnum(GdtSegment.tss)] = gdt.SegmentDescriptor.new(.{
            .base = @intFromPtr(&tss),
            .limit = @bitSizeOf(gdt.TaskStateSegment),
            // TODO: convert these to structured values.
            .access = .{
                .system = @bitCast(@as(u8, 0x89)),
            },
            .flags = .{
                .size = .bits32,
                .granularity = .page,
            },
        });

        // Load GDT!
        const gdtr_pointer = asm volatile (
            \\ push %[limit]
            \\ push %[addr]
            \\ call load_gdtr
            : [gdtr_addr] "={eax}" (-> usize),
            : [addr] "X" (@as(u32, @intFromPtr(&global_descriptor_table))),
              [limit] "X" (@as(u16, @as(i16, @sizeOf(@TypeOf(global_descriptor_table))) - 1)),
        );
        gdtr = @ptrFromInt(gdtr_pointer);
    }

    // Load kernel TSS.
    loadTss(GdtSegment.tss, &kernel_stack_bytes);

    // Set up stack.
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        :
        : [stack_top] "i" (@as([*]align(4) u8, @ptrCast(&user_stack_bytes)) + @sizeOf(@TypeOf(user_stack_bytes))),
    );

    // Transfer to kmain.
    asm volatile (
        \\ call %[kmain:P]
        :
        : [kmain] "X" (&kmain),
    );
}

fn kmain() callconv(.c) void {
    @setRuntimeSafety(true);

    vga.init();

    vga.writeStr("hello, zig!\n");

    vga.printf(
        \\ &gdtr: {*}
        \\ gdtr:
        \\   asm:
        \\     addr:  {x}
        \\     limit: {x}
        \\   zig:
        \\     addr:  {*}
        \\     limit: {x}
        \\
    , .{
        gdtr,
        gdtr.addr,
        gdtr.limit,
        &global_descriptor_table,
        @as(u16, @as(i16, @sizeOf(@TypeOf(global_descriptor_table))) - 1),
    });

    while (true) {}
}

inline fn loadTss(tssSegment: GdtSegment, stack: [*]u8) void {
    // Mark what the kernel data segment offset is.
    tss.ss0 = @intFromEnum(tssSegment);

    // NOTE: we're sharing a single TSS right now, so we need to disable multitasking
    // or else we could end up granting access to the kernel stack in userspace (which would be bad)!
    tss.esp0 = @intFromPtr(stack);

    // Note how large the TSS is (...which is always going to be 104 bytes).
    tss.iopb = @bitSizeOf(gdt.TaskStateSegment) / 8;

    asm volatile (
        \\ mov %[tss_gdt_offset], %ax
        \\ ltr %ax
        :
        : [tss_gdt_offset] "X" (8 * @as(u32, @intCast(@intFromEnum(tssSegment)))),
    );
}
