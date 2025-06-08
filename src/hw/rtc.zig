const cmos = @import("cmos.zig");
const pic = @import("pic.zig");

// The default value set by the BIOS is 1Khz, which is ~976us; we're going to just call that _roughly_ close to 1ms!
var tick_ms: u8 = 1;

pub fn tick() void {
    // TODO: actually do something here!
}

pub fn regc() RegisterC {
    return reg(RegisterC, 0x0C, true);
}

fn reg(T: type, regAddr: u8, restore_nmis: bool) T {
    const nmis_masked = if (restore_nmis) cmos.areNMIsMasked() else false;

    // Get register and mask NMIs since the RTC can go into an undefined state if an interrupt triggers right now.
    //
    // NOTE: we're masking NMIs while we're changing the index by setting bit 7 (NMIs share an IO port with CMOS).
    cmos.writeIndex(0x80 | regAddr);
    const result: T = @bitCast(cmos.readData());

    // If restoreNmis is true, unmask NMIs if they were previously unmasked.
    if (restore_nmis and !nmis_masked) {
        cmos.unmaskNMIs();
    }

    return result;
}

pub fn init(pic_proof: pic.InitProof) !void {
    try pic_proof.prove();

    // Configure RTC interrupts.
    //
    // NOTE: we're getting register b with NMIs masked and not unmasking until we're done initializing the kernel.
    var reg_b = reg(RegisterB, 0x0B, false);
    reg_b.periodic_interrupts_enabled = true;

    cmos.writeIndex(0x8B);
    cmos.writeData(@bitCast(reg_b));
}

pub const RegisterA = packed struct(u8) {
    uip: bool,
    divider: u3,
    rate: u4,
};

pub const RegisterB = packed struct(u8) {
    daylight_savings_enabled: bool,
    hours: enum(u1) {
        @"12hr" = 0,
        @"24hr" = 1,
    },
    data_mode: enum(u1) {
        bcd = 0,
        binary = 1,
    },
    square_wave_enabled: bool,
    update_ended_interrupts_enabled: bool,
    alarm_interrupts_enabled: bool,
    periodic_interrupts_enabled: bool,
    abort_update: bool,
};

pub const RegisterC = packed struct(u8) {
    _r1: u4,

    update_ended_interrupt: bool,
    alarm_interrupt: bool,
    periodic_interrupt: bool,
    interrupt_request: bool,
};
