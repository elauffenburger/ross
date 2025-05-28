const cmos = @import("cmos.zig");
const io = @import("io.zig");

// The default value set by the BIOS is 1Khz, which is ~976us; we're going to just call that _roughly_ close to 1ms!
var tickMs: u8 = 1;

pub fn tick() void {
    // TODO: actually do something here!
}

pub fn regc() RegisterC {
    return reg(RegisterC, 0x0C, true);
}

fn reg(T: type, regAddr: u8, restoreNmis: bool) T {
    const nmisMasked = if (restoreNmis) cmos.areNMIsMasked() else undefined;

    // Get register and mask NMIs since the RTC can go into an undefined state if an interrupt triggers right now.
    //
    // NOTE: we're masking NMIs while we're changing the index by setting bit 7 (NMIs share an IO port with CMOS).
    cmos.writeIndex(0x80 | regAddr);
    const result: T = @bitCast(cmos.readData());

    // If restoreNmis is true, unmask NMIs if they were previously unmasked.
    if (restoreNmis and !nmisMasked) {
        cmos.unmaskNMIs();
    }

    return result;
}

pub fn init() void {
    // Configure RTC interrupts.
    //
    // NOTE: we're getting register b with NMIs masked and not unmasking until we're done initializing the kernel.
    var reg_b = reg(RegisterB, 0x0B, false);
    reg_b.periodicInterruptsEnabled = true;

    cmos.writeIndex(0x8B);
    cmos.writeData(@bitCast(reg_b));
}

pub const RegisterA = packed struct(u8) {
    uip: bool,
    divider: u3,
    rate: u4,
};

pub const RegisterB = packed struct(u8) {
    daylightSavingsEnabled: bool,
    hours: enum(u1) {
        @"12hr" = 0,
        @"24hr" = 1,
    },
    dataMode: enum(u1) {
        bcd = 0,
        binary = 1,
    },
    squareWaveEnabled: bool,
    updateEndedInterruptsEnabled: bool,
    alarmInterruptsEnabled: bool,
    periodicInterruptsEnabled: bool,
    abortUpdate: bool,
};

pub const RegisterC = packed struct(u8) {
    _r1: u4,

    updateEndedInterrupt: bool,
    alarmInterrtup: bool,
    periodicInterrtup: bool,
    interruptRequest: bool,
};
