pub const PrivilegeLevel = enum(u2) {
    kernel = 0,
    ring1 = 1,
    ring2 = 2,
    userspace = 3,
};

pub const EFlags = packed struct(u32) {
    carry: bool,
    _r1: u1 = 0,
    parity_even: bool,
    _r2: u1 = undefined,
    aux_carry: bool,
    _r3: u1 = undefined,
    zero: bool,
    sign: enum(u1) {
        positive = 0,
        negative = 1,
    },
    trap: bool,
    interrupt_enable: bool,
    direction: enum(u1) {
        up = 0,
        down = 1,
    },
    overflow: bool,
    io_priv: PrivilegeLevel,
    nested_task: bool = true,
    mode: enum(u1) {
        emulation = 0,
        native = 1,
    },
    @"resume": bool,
    virtual_8086: bool,
    alignment_check: bool,
    virt_interrupt: bool,
    virtual_interrupt_pending: bool,
    cpu_id: bool,
    _r4: u8 = undefined,
    aes_key_schedule_loaded: bool,
    alt_instruction_set_enabled: bool,
};
