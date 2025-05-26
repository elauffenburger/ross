const stack = @import("stack.zig");
const tables = @import("tables.zig");

// NOTE: if you rearrange the entries in the GDT, make sure to update GdtSegment!
pub const GdtSegment = enum(u4) {
    null = 0,
    kernelCode = 1,
    kernelData = 2,
    tss = 3,
    userCode = 4,
    userData = 5,
};

// Create the GDT.
// NOTE: if you rearrange the entries in the GDT, make sure to update GdtSegment!
var gdt align(4) = [_]tables.GdtSegmentDescriptor{
    // Mandatory null entry.
    @bitCast(@as(u64, 0)),

    // Kernel Mode Code Segment.
    tables.GdtSegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .code = @bitCast(@as(u8, 0x9a)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // Kernel Mode Data Segment.
    tables.GdtSegmentDescriptor.new(.{
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
    tables.GdtSegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .code = @bitCast(@as(u8, 0xfa)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // User Mode Data Segment.
    tables.GdtSegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .data = @bitCast(@as(u8, 0xf2)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),
};

// Allocate a var for the GDT descriptor register whose address we'll pass to lgdt.
var gdtr: tables.GdtDescriptor align(4) = @bitCast(@as(u48, 0));

// Allocate space for our TSS.
var tss: tables.TaskStateSegment = @bitCast(@as(u864, 0));

pub inline fn init() void {
    @setRuntimeSafety(false);

    // Add TSS entry to GDT.
    gdt[@intFromEnum(GdtSegment.tss)] = tables.GdtSegmentDescriptor.new(.{
        .base = @intFromPtr(&tss),
        .limit = @bitSizeOf(tables.TaskStateSegment),
        // TODO: convert these to structured values.
        .access = .{
            .system = @bitCast(@as(u8, 0x89)),
        },
        .flags = .{
            .size = .@"32bit",
            .granularity = .page,
        },
    });

    // Load GDT!
    loadGdt();
}

inline fn loadGdt() void {
    gdtr = .{
        .addr = @intFromPtr(&gdt),
        .limit = @as(i16, @sizeOf(@TypeOf(gdt))) - 1,
    };

    // This is pretty weird! The gist of it is we need to enable Protected Mode, load the GDT,
    // and set up the segmentation registers through some black magick.
    //
    // 1. Set the DS register to 0 to tell the CPU we're in segment 0 right now
    //    (and that's where it can find the GDT after our lgdt)
    // 2. Turn on bit 0 of CR0 to enable Protected Mode.
    // 3. Load the GDT.
    // 4. Perform a far jump into our kernel-space code segment (segment 1) to tell the processor we're in segment 1,
    //    so we just jump to a label but with the Kernel Code segment offset set (which will be 8 * offset_num).
    // 5. Set our DS and SS registers
    // 6. Done!
    asm volatile (
        \\ .align 4
        \\
        \\ cli
        \\
        \\ /* set DS to 0 (null segment) to tell the CPU that's where it can find the GDT after lgdt */
        \\ xor %ax, %ax
        \\ mov %ax, %ds
        \\
        \\ /* turn on Protected Mode (...though it should already be on!) */
        \\ mov %cr0, %eax
        \\ or $1, %eax
        \\ mov %eax, %cr0
        \\
        \\ /* load the gdt! */
        \\ lgdt %[gdtr]
        \\
        \\ /* set CS to segment 1 (8 * 1) by far jumping to the local label */
        \\ ljmp $8, $.after_lgdtr
        \\
        \\ .after_lgdtr:
        \\ .align 4
        \\ /* set data segment registers to 16d (segment 2) */
        \\ mov $16, %ax
        \\ mov %ax, %ds
        \\ mov %ax, %es
        \\ mov %ax, %fs
        \\ mov %ax, %gs
        \\ mov %ax, %ss
        \\
        \\ /* restore interrupts */
        \\ sti
        :
        : [gdtr] "p" (@intFromPtr(&gdtr)),
        : "eax", "ds", "cr0", "es", "fs", "gs", "ss"
    );
}

pub inline fn loadTss(stack_info: struct { segment: GdtSegment, handle: []align(4) u8 }) void {
    tss.ss0 = 8 * @as(u16, @intFromEnum(stack_info.segment));

    // NOTE: we're sharing a single TSS right now, so we need to disable multitasking
    // or else we could end up granting access to the kernel stack in userspace (which would be bad)!
    tss.esp0 = stack.top(stack_info.handle);

    // Set the offset from the base of the TSS to the IO permission bit map.
    // HACK: I really have no idea _why_ this is even necessary (or when it wouldn't be 104);
    //       we should take a look at this later!
    tss.iopb = 104;

    // Load tss.
    asm volatile (
        \\ mov %[tss_gdt_offset], %%ax
        \\ ltr %%ax
        :
        : [tss_gdt_offset] "X" (8 * @as(u32, @intFromEnum(GdtSegment.tss))),
    );

    // TODO: handle switching stacks.
    //
    // I'm guessing this will look something like:
    //   - if already in the requested stack, is that an error?
    //   - if switching to kernel space, _is_ there a stack?
    //   - if swtiching back to userspace, restore previous stack pointers
    //     - is that just esp and ebp?
    //     - does ltr handle segmentation registers?
}
