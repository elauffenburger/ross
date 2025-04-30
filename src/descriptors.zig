pub const SegmentDescriptor = packed struct(u64) {
    const Self = @This();

    limitLow: u16,
    baseLow: u24,
    access: Access,
    limitHigh: u4,
    flags: Flags,
    baseHigh: u8,

    pub fn new(args: struct { base: u32, limit: u20, access: Access, flags: Flags }) Self {
        return .{
            .limitLow = args.limit & 0x0000_ffff,
            .baseLow = args.base & 0x00ff_ffff,
            .access = args.access,
            .limitHigh = args.limit & 0x000f_0000 >> 16,
            .flags = args.flags,
            .baseHigh = args.base & 0xff00_0000 >> 24,
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

    pub const Flags = packed struct {
        // Reserved.
        _: bool,

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
            Byte,
            Page,
        };
    };
};

// 0x0000	Null Descriptor	Base = 0
// Limit = 0x00000000
// Access Byte = 0x00
// Flags = 0x0

// 0x0008	Kernel Mode Code Segment	Base = 0
// Limit = 0xFFFFF
// Access Byte = 0x9A
// Flags = 0xC

// 0x0010	Kernel Mode Data Segment	Base = 0
// Limit = 0xFFFFF
// Access Byte = 0x92
// Flags = 0xC

// 0x0018	User Mode Code Segment	Base = 0
// Limit = 0xFFFFF
// Access Byte = 0xFA
// Flags = 0xC

// 0x0020	User Mode Data Segment	Base = 0
// Limit = 0xFFFFF
// Access Byte = 0xF2
// Flags = 0xC

// 0x0028	Task State Segment	Base = &TSS
// Limit = sizeof(TSS)-1
// Access Byte = 0x89
// Flags = 0x0

pub const Gdt = packed struct {
    const Self = @This();

    var segmentDescriptors = [_]SegmentDescriptor{
        // Mandatory null entry.
        @bitCast(0),

        // Kernel Mode Code Segment.
        SegmentDescriptor.new(.{
            .base = 0,
            .limit = 0xf_ffff
            .access = .{

            },
            .flags = .{

            }
        }),
    };

    pub fn gdtDescriptor(self: *Self) GdtDescriptor {
        return .{
            .size = @sizeOf(Self) - 1,
            .addr = self,
        };
    }
};

pub const GdtDescriptor = packed struct(48) {
    size: u16,
    addr: u32,
};
