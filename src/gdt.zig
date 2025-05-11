pub const SegmentDescriptor = packed struct(u64) {
    const Self = @This();

    limitLow: u16,
    baseLow: u24,
    access: Access,
    limitHigh: u4,
    flags: Flags,
    baseHigh: u8,

    pub inline fn new(args: struct { base: u32, limit: u20, access: Access, flags: Flags }) Self {
        return .{
            .limitLow = @intCast(args.limit & 0x0000_ffff),
            .baseLow = @intCast(args.base & 0x00ff_ffff),
            .access = args.access,
            .limitHigh = @intCast(args.limit & 0x000f_0000 >> 16),
            .flags = args.flags,
            .baseHigh = @intCast(args.base & 0xff00_0000 >> 24),
        };
    }

    // The linear address where the segment begins.
    pub fn base(self: Self) u32 {
        return (self.baseHigh << 24) & self.baseLow;
    }

    // The maximum addressable unit in either 1B units or 4KiB pages.
    pub fn limit(self: Self) u20 {
        return (self.limitHigh << 16) & self.limitLow;
    }

    pub const Access = packed union {
        system: packed struct(u8) {
            // Type information specific to System Segments.
            sysSegmentType: SystemSegmentType,

            // The type of the segment.
            typ: SegmentType = .system,

            // The privilege level of the segment.
            privilegeLevel: PrivilegeLevel,

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
            privilegeLevel: PrivilegeLevel,
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
            privilegeLevel: PrivilegeLevel,
            present: bool = true,
        },

        pub const SegmentType = enum(u1) {
            system = 0,
            codeOrData = 1,
        };

        pub const PrivilegeLevel = enum(u2) {
            kernel = 0,
            ring1 = 1,
            ring2 = 2,
            userspace = 3,
        };

        pub const SystemSegmentType = enum(u4) {
            // A 16-bit available Task State Segment (TSS).
            bits16TssAvailable = 1,

            // A Local Descriptor Table.
            ldt = 2,

            // A 16-bit busy TSS.
            bits16TssBusy = 3,

            // A 32-bit available TSS.
            bits32TssAvailable = 9,

            // A 32-bit busy TSS.
            bits32TssBusy = 11,
        };

        pub const SystemSegment = @FieldType(Self, "system");
        pub const CodeSegment = @FieldType(Self, "code");
        pub const DataSegment = @FieldType(Self, "data");
    };

    pub const Flags = packed struct(u4) {
        // Reserved.
        _: bool = false,

        // If true, 64bit (we're not).
        longMode: u1 = 0,

        // The size mode of the segment (16-bit or 32-bit).
        size: SegmentSizeMode,

        // The size the limit value is scaled by (either 1B or 4KiB block sizes).
        granularity: Granularity,

        // The size mode of a segment (16-bit or 32-bit).
        pub const SegmentSizeMode = enum(u1) {
            bits16 = 0,
            bits32 = 1,
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

// See [the docs](https://wiki.osdev.org/Task_State_Segment) for more details.
pub const TaskStateSegment = packed struct(u864) {
    link: u16,
    _r1: u16,

    esp0: u32,

    ss0: u16,
    _r2: u16,

    esp1: u32,

    ss1: u16,
    _r3: u16,

    esp2: u32,

    ss2: u16,
    _r4: u16,

    cr3: u32,
    eip: u32,
    eflags: u32,
    eax: u32,
    ecx: u32,
    edx: u32,
    ebx: u32,
    esp: u32,
    ebp: u32,
    esi: u32,
    edi: u32,

    es: u16,
    _r5: u16,

    cs: u16,
    _r6: u16,

    ss: u16,
    _r7: u16,

    ds: u16,
    _r8: u16,

    fs: u16,
    _r9: u16,

    gs: u16,
    _r10: u16,

    ldtr: u16,
    _r11: u16,

    _r12: u16,
    iopb: u16,

    ssp: u32,
};
