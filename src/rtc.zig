const cmos = @import("cmos.zig");
const io = @import("io.zig");

// The default value set by the BIOS is 1Khz, which is ~976us.
var tickMs: f32 = 0.976;

pub inline fn tick() void {}

pub inline fn readRegC() u8 {
    cmos.writeIndex(0x0C);
    return cmos.readData();
}

pub fn init() void {
    // Disable interrupts.
    asm volatile ("cli");

    // Configure RTC interrupts.
    //
    // NOTE: we're masking NMIs while we're changing the index by setting bit 7 (NMIs share an IO port with CMOS).
    cmos.writeIndex(0x8B);
    var reg_b_val: RegisterB = @bitCast(cmos.readIndex());
    reg_b_val.periodicInterruptsEnabled = true;

    cmos.writeIndex(0x8B);
    cmos.writeData(@bitCast(reg_b_val));

    // Re-enable interrupts.
    asm volatile ("sti");
    cmos.nmiEnable();
}

const RegisterA = packed struct(u8) {
    uip: bool,
    divider: u3,
    rate: u4,
};

const RegisterB = packed struct(u8) {
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

const RegisterC = packed struct(u8) {
    _r1: u4,

    updateEndedInterrupt: bool,
    alarmInterrtup: bool,
    periodicInterrtup: bool,
    interruptRequest: bool,
};
