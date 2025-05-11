const kstd = @import("kstd.zig");
const vga = @import("vga.zig");
const multiboot = @import("multiboot.zig");
const gdt = @import("gdt.zig");

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

    // Task State Segment
    // NOTE: this will be created for real when we init the GDT.
    @bitCast(@as(u64, 0)),
};

var task_state_segment: gdt.TaskStateSegment = @bitCast(0);

var gdtr: *gdt.GdtDescriptor align(4) = undefined;

// Reserve 16K for the general stack in the .bss section.
const STACK_SIZE = 16 * 1024;
var stack_bytes: [STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

// Reserve 16K for the dedicated kernel stack in the .bss section.
const KERNEL_STACK_SIZE = 16 * 1024;
var kernel_stack_bytes: [KERNEL_STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

pub export fn _kmain() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    // Set up GDT.
    {
        // Create the TSS.
        global_descriptor_table[global_descriptor_table.len - 1] = gdt.SegmentDescriptor.new(.{
            .base = @intFromPtr(&task_state_segment),
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

    // Set up TSS.
    {
        // Mark what the kernel data segment offset is.
        task_state_segment.ss0 = @bitSizeOf(gdt.SegmentDescriptor) * 2;

        // Set the size of the TSS struct.
        task_state_segment.iopb = @bitSizeOf(gdt.TaskStateSegment);

        // NOTE: we're sharing a single TSS right now, so we need to disable multitasking
        // during a syscall or else the same stack pointer could end up being used for both stacks
        // (which would be bad).
        task_state_segment.esp0 = @intFromPtr(&kernel_stack_bytes);

        asm volatile (
            \\ mov %[tss_gdt_offset], %ax
            \\ ltr %ax
            :
            : [tss_gdt_offset] "X" (8 * (global_descriptor_table.len - 1)),
        );
    }

    // Set up stack.
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        :
        : [stack_top] "i" (@as([*]align(4) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
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
