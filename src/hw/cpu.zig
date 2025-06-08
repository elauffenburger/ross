pub const PrivilegeLevel = enum(u2) {
    kernel = 0,
    ring1 = 1,
    ring2 = 2,
    userspace = 3,
};

pub const EFlags = packed struct(u32) {
    // Carry Flag. Set if the last arithmetic operation carried (addition) or borrowed (subtraction) a bit beyond the
    // size of the register. This is then checked when the operation is followed with an add-with-carry
    // or subtract-with-borrow to deal with values too large for just one register to contain.
    carry: bool,

    _r1: u1 = 1,

    // Parity Flag. Set if the number of set bits in the least significant byte is a multiple of 2.
    pf: bool,

    _r2: u1 = 0,

    // Adjust Flag. Carry of Binary Code Decimal (BCD) numbers arithmetic operations.
    af: bool,

    _r3: u1 = 0,

    // Zero Flag. Set if the result of an operation is Zero (0).
    zf: bool,

    // Sign Flag. Set if the result of an operation is negative.
    sf: enum(u1) {
        positive = 0,
        negative = 1,
    },

    // Trap Flag. Set if step by step debugging.
    tf: bool,

    // Interruption Flag. Set if interrupts are enabled.
    @"if": bool,

    // Direction Flag. Stream direction. If set, string operations will decrement their pointer rather than incrementing it, reading memory backwards.
    df: enum(u1) {
        up = 0,
        down = 1,
    },

    // Overflow Flag. Set if signed arithmetic operations result in a value too large for the register to contain.
    of: bool,

    // IOPL : I/O Privilege Level field (2 bits). I/O Privilege Level of the current process.
    iopl: PrivilegeLevel,

    // Nested Task flag. Controls chaining of interrupts. Set if the current process is linked to the next process.
    nt: bool = true,

    _r4: u1 = 0,

    // Resume Flag. Response to debug exceptions.
    rf: bool,

    // Virtual-8086 Mode. Set if in 8086 compatibility mode.
    vm: enum(u1) {
        off,
        @"8086mode",
    },

    // Alignment Check. Set if alignment checking of memory references is done.
    ac: bool,

    // Virtual Interrupt Flag. Virtual image of IF.
    vif: bool,

    // Virtual Interrupt Pending flag. Set if an interrupt is pending.
    vip: bool,

    // Identification Flag. Support for CPUID instruction if can be set.
    id: bool,

    _r5: u10 = 0,
};

pub const Registers = packed struct {
    eax: u32,
    ecx: u32,
    edx: u32,
    eip: u32,

    ebx: u32,
    esi: u32,
    edi: u32,
    ebp: u32,
    esp: u32,

    ss: u32,
    cs: u32,
    ds: u32,
    es: u32,
    fs: u32,
    gs: u32,

    eflags: packed struct(u32) {
        cf: bool,

        _r1: u1 = 1,

        pf: bool,

        _r2: u1 = 0,

        // Adjust Flag. Carry of Binary Code Decimal (BCD) numbers arithmetic operations.
        af: bool,

        _r3: u1 = 0,

        // Zero Flag. Set if the result of an operation is Zero (0).
        zf: bool,

        // Sign Flag. Set if the result of an operation is negative.
        sf: bool,

        // Trap Flag. Set if step by step debugging.
        tf: bool,

        // Interruption Flag. Set if interrupts are enabled.
        @"if": bool,

        // Direction Flag. Stream direction. If set, string operations will decrement their pointer rather than incrementing it, reading memory backwards.
        df: bool,

        // Overflow Flag. Set if signed arithmetic operations result in a value too large for the register to contain.
        of: bool,

        // IOPL : I/O Privilege Level field (2 bits). I/O Privilege Level of the current process.
        io_priv: PrivilegeLevel,

        // Nested Task flag. Controls chaining of interrupts. Set if the current process is linked to the next process.
        nt: bool,

        // Resume Flag. Response to debug exceptions.
        rf: bool,

        // Virtual-8086 Mode. Set if in 8086 compatibility mode.
        vm: bool,

        // Alignment Check. Set if alignment checking of memory references is done.
        ac: bool,

        // Virtual Interrupt Flag. Virtual image of IF.
        vif: bool,

        // Virtual Interrupt Pending flag. Set if an interrupt is pending.
        vip: bool,

        // Identification Flag. Support for CPUID instruction if can be set.
        id: bool,
    },
};
