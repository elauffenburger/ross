pub const PrivilegeLevel = enum(u2) {
    kernel = 0,
    ring1 = 1,
    ring2 = 2,
    userspace = 3,
};

pub const EFlags = packed struct(u32) {
    carry: bool,
    _r1: u1 = 0,
    parityEven: bool,
    _r2: u1 = undefined,
    auxCarry: bool,
    _r3: u1 = undefined,
    zero: bool,
    sign: enum(u1) {
        positive = 0,
        negative = 1,
    },
    trap: bool,
    interruptEnable: bool,
    direction: enum(u1) {
        up = 0,
        down = 1,
    },
    overflow: bool,
    ioPrivilege: PrivilegeLevel,
    nestedTask: bool = true,
    mode: enum(u1) {
        emulation = 0,
        native = 1,
    },
    @"resume": bool,
    virtual8086: bool,
    alignmentCheck: bool,
    virtualInterrupt: bool,
    virtualInterruptPending: bool,
    cpuId: bool,
    _r4: u8 = undefined,
    aesKeyScheduleLoaded: bool,
    altInstructionSetEnabled: bool,
};
