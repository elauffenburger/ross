const kstd = @import("../kstd.zig");
const cpu = @import("cpu.zig");

// NOTE: if you rearrange the entries in the GDT, make sure to update GdtSegment!
pub const GdtSegment = enum(u4) {
    null = 0,
    kernelCode = 1,
    kernelData = 2,
    kernelTss = 3,
    userCode = 4,
    userData = 5,
    userTss = 6,
};

// Create the GDT.
// NOTE: if you rearrange the entries in the GDT, make sure to update GdtSegment!
var gdt: [@typeInfo(GdtSegment).@"enum".fields.len]GdtSegmentDescriptor align(4) = undefined;

// Allocate a var for the GDT descriptor register whose address we'll pass to lgdt.
var gdtr: GdtDescriptor align(4) = @bitCast(@as(u48, 0));

// Allocate space for our TSS.
// SAFETY: set during init.
var kernel_tss: TaskStateSegment = undefined;

pub inline fn init() void {
    @setRuntimeSafety(false);

    gdt = [_]GdtSegmentDescriptor{
        // Mandatory null entry.
        @bitCast(@as(u64, 0)),

        // Kernel Mode Code Segment.
        GdtSegmentDescriptor.new(.{
            .base = 0,
            .limit = 0xf_ffff,
            // TODO: convert these to structured values.
            .access = .{
                .code = @bitCast(@as(u8, 0x9a)),
            },
            .flags = @bitCast(@as(u4, 0xc)),
        }),

        // Kernel Mode Data Segment.
        GdtSegmentDescriptor.new(.{
            .base = 0,
            .limit = 0xf_ffff,
            // TODO: convert these to structured values.
            .access = .{
                .data = @bitCast(@as(u8, 0x92)),
            },
            .flags = @bitCast(@as(u4, 0xc)),
        }),

        // Kernel TSS Segment.
        GdtSegmentDescriptor.new(.{
            .base = @intFromPtr(&kernel_tss),
            .limit = @bitSizeOf(TaskStateSegment),
            // TODO: convert these to structured values.
            .access = .{
                .system = @bitCast(@as(u8, 0x89)),
            },
            .flags = .{
                .size = .@"32bit",
                .granularity = .page,
            },
        }),

        // User Mode Code Segment.
        GdtSegmentDescriptor.new(.{
            .base = 0,
            .limit = 0xf_ffff,
            // TODO: convert these to structured values.
            .access = .{
                .code = @bitCast(@as(u8, 0xfa)),
            },
            .flags = @bitCast(@as(u4, 0xc)),
        }),

        // User Mode Data Segment.
        GdtSegmentDescriptor.new(.{
            .base = 0,
            .limit = 0xf_ffff,
            // TODO: convert these to structured values.
            .access = .{
                .data = @bitCast(@as(u8, 0xf2)),
            },
            .flags = @bitCast(@as(u4, 0xc)),
        }),

        // User TSS Segment.
        GdtSegmentDescriptor.new(.{
            .base = @intFromPtr(&kernel_tss),
            .limit = @bitSizeOf(TaskStateSegment),
            // TODO: convert these to structured values.
            .access = .{
                .system = .{
                    .sys_seg_type = .tssAvailable32Bit,
                    .priv_level = .userspace,
                },
            },
            .flags = .{
                .size = .@"32bit",
                .granularity = .page,
            },
        }),
    };

    // Load GDT.
    loadGdt();

    // Load Tss.
    {
        kernel_tss = .{
            .ss0 = 8 * @as(u16, @intFromEnum(GdtSegment.kernelTss)),
            .esp0 = kstd.mem.stack.top(),
        };

        loadTss(.kernelTss);
    }
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
        \\ /* clear interrupts */
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

pub inline fn loadTss(tss_segment: GdtSegment) void {
    // Load tss.
    asm volatile (
        \\ mov %[tss_gdt_offset], %%ax
        \\ ltr %%ax
        :
        : [tss_gdt_offset] "X" (8 * @as(u32, @intFromEnum(tss_segment))),
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

// See [the docs](https://wiki.osdev.org/Task_State_Segment) for more details.
pub const TaskStateSegment = packed struct(u864) {
    link: u16 = 0,
    _r1: u16 = 0,

    esp0: u32 = 0,

    ss0: u16 = 0,
    _r2: u16 = 0,

    esp1: u32 = 0,

    ss1: u16 = 0,
    _r3: u16 = 0,

    esp2: u32 = 0,

    ss2: u16 = 0,
    _r4: u16 = 0,

    cr3: u32 = 0,
    eip: u32 = 0,
    eflags: u32 = 0,
    eax: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
    ebx: u32 = 0,
    esp: u32 = 0,
    ebp: u32 = 0,
    esi: u32 = 0,
    edi: u32 = 0,

    es: u16 = 0,
    _r5: u16 = 0,

    cs: u16 = 0,
    _r6: u16 = 0,

    ss: u16 = 0,
    _r7: u16 = 0,

    ds: u16 = 0,
    _r8: u16 = 0,

    fs: u16 = 0,
    _r9: u16 = 0,

    gs: u16 = 0,
    _r10: u16 = 0,

    ldtr: u16 = 0,
    _r11: u16 = 0,

    _r12: u16 = 0,

    // Set the offset from the base of the TSS to the IO permission bit map.
    // HACK: I really have no idea _why_ this is even necessary (or when it wouldn't be 104);
    //       we should take a look at this later!
    iopb: u16 = 104,

    ssp: u32 = 0,
};

pub const GdtSegmentDescriptor = packed struct(u64) {
    const Self = @This();

    limit_low: u16,
    base_low: u24,
    access: Access,
    limit_high: u4,
    flags: Flags,
    base_high: u8,

    pub inline fn new(args: struct { base: u32, limit: u20, access: Access, flags: Flags }) Self {
        return .{
            .limit_low = @intCast(args.limit & 0x0000_ffff),
            .base_low = @intCast(args.base & 0x00ff_ffff),
            .access = args.access,
            .limit_high = @intCast(args.limit & 0x000f_0000 >> 16),
            .flags = args.flags,
            .base_high = @intCast(args.base & 0xff00_0000 >> 24),
        };
    }

    // The linear address where the segment begins.
    pub fn base(self: Self) u32 {
        return (self.base_high << 24) & self.base_low;
    }

    // The maximum addressable unit in either 1B units or 4KiB pages.
    pub fn limit(self: Self) u20 {
        return (self.limit_high << 16) & self.limit_low;
    }

    pub const Access = packed union {
        system: packed struct(u8) {
            // Type information specific to System Segments.
            sys_seg_type: SystemSegmentType,

            // The type of the segment.
            typ: SegmentType = .system,

            // The privilege level of the segment.
            priv_level: cpu.PrivilegeLevel,

            // True if this is a valid segment.
            present: bool = true,
        },
        code: packed struct(u8) {
            accessed: bool = true,

            // True if this segment is readable; it is never writable.
            readable: bool,

            // If true, code in this segment can be executed from a ring of equal or lower privilege level; otherwise the privilege levels must match.
            conforming: bool,

            // If true, this segment contains code that can be executed (since this is a code segement, it does).
            exe: bool = true,

            typ: u1 = 1,
            priv_level: cpu.PrivilegeLevel,
            present: bool = true,
        },
        data: packed struct(u8) {
            accessed: bool = true,

            // True if this segment is writable; it is always readable.
            writable: bool,

            // True if this segment grows down; grows up otherwise.
            direction: bool,

            exe: bool = false,
            typ: u1 = 1,
            priv_level: cpu.PrivilegeLevel,
            present: bool = true,
        },

        pub const SegmentType = enum(u1) {
            system = 0,
            codeOrData = 1,
        };

        pub const SystemSegmentType = enum(u4) {
            // A 16-bit available Task State Segment (TSS).
            tssAvailable16Bit = 1,

            // A Local Descriptor Table.
            ldt = 2,

            // A 16-bit busy TSS.
            tssBusy16Bit = 3,

            // A 32-bit available TSS.
            tssAvailable32Bit = 9,

            // A 32-bit busy TSS.
            tssBusy32Bit = 11,
        };

        pub const SystemSegment = @FieldType(Self, "system");
        pub const CodeSegment = @FieldType(Self, "code");
        pub const DataSegment = @FieldType(Self, "data");
    };

    pub const Flags = packed struct(u4) {
        // Reserved.
        _: bool = false,

        // If true, 64bit (we're not).
        long_mode: bool = false,

        // The size mode of the segment (16-bit or 32-bit).
        size: SegmentSizeMode,

        // The size the limit value is scaled by (either 1B or 4KiB block sizes).
        granularity: Granularity,

        // The size mode of a segment (16-bit or 32-bit).
        pub const SegmentSizeMode = enum(u1) {
            @"16bit" = 0,
            @"32bit" = 1,
        };

        // The unit for limit (either 1B units or 4KiB pages).
        pub const Granularity = enum(u1) {
            byte,
            page,
        };
    };
};

pub const GdtDescriptor = packed struct(u48) {
    limit: u16,
    addr: u32,
};
