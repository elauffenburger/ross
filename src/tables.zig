const cpu = @import("cpu.zig");

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

pub const SegmentSelector = packed struct(u16) {
    rpl: cpu.PrivilegeLevel,
    ti: TableSelector,
    index: u13,

    const TableSelector = enum(u1) {
        gdt = 0,
        ldt = 1,
    };
};

pub const InterruptDescriptor = packed struct(u64) {
    offset1: u16,
    selector: SegmentSelector,
    _r1: u8 = 0,
    gate_type: GateType,
    _r2: u1 = 0,
    dpl: cpu.PrivilegeLevel,
    present: bool = true,
    offset2: u16,

    pub const GateType = enum(u4) {
        task = 5,
        interrupt16bits = 6,
        trap16bits = 7,
        interrupt32bits = 14,
        trap32bits = 15,
    };
};

pub const IdtEntry = enum(u8) {
    // Divide Error DIV and IDIV instructions.
    de = 0,
    // Debug Exception Instruction, data, and I/O breakpoints; single-step; and others.
    db = 1,
    // NMI Interrupt Nonmaskable external interrupt.
    nmi = 2,
    // Breakpoint INT3 instruction.
    bp = 3,
    // Overflow INTO instruction.
    of = 4,
    // BOUND Range Exceeded BOUND instruction.
    br = 5,
    // Invalid Opcode (Undefined Opcode) UD instruction or reserved opcode.
    ud = 6,
    // Device Not Available (No Math Coprocessor) Floating-point or WAIT/FWAIT instruction.
    nm = 7,
    // (zero) Double Fault Any instruction that can generate an exception, an NMI, or an INTR.
    df = 8,
    // Invalid TSS Task switch or TSS access.
    ts = 10,
    // Segment Not Present Loading segment registers or accessing system segments.
    np = 11,
    // Stack-Segment Fault Stack operations and SS register loads.
    ss = 12,
    // General Protection Any memory reference and other protection checks.
    gp = 13,
    // Page Fault Any memory reference.
    pf = 14,
    // x87 FPU Floating-Point Error (Math Fault) x87 FPU floating-point or WAIT/FWAIT instruction.
    mf = 16,
    // (zero) Alignment Check Any data reference in memory.
    ac = 17,
    // Machine Check Error codes (if any) and source are model dependent.
    mc = 18,
    // SIMD Floating-Point Exception SSE/SSE2/SSE3 floating-point instructions
    xm = 19,
    // Virtualization Exception EPT violations
    ve = 20,
    // Control Protection Exception RET, IRET, RSTORSSP, and SETSSBSY instructions can generate this exception. When CET indirect branch tracking is enabled, this exception can be generated due to a missing ENDBRANCH instruction at target of an indirect call or jump.
    cp = 21,
};

pub const IdtDescriptor = packed struct(u48) {
    limit: u16,
    addr: u32,
};
