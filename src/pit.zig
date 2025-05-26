const io = @import("io.zig");

const IOPorts = struct {
    pub const ch0: u8 = 0x40;
    pub const ch1: u8 = 0x41;
    pub const ch2: u8 = 0x42;

    pub const cmd: u8 = 0x43;
};

pub const Mode = packed struct(u8) {
    countMode: enum(u1) {
        // 16-bit binary.
        @"16bit" = 0,

        // Binary Coded Decimal.
        bcd = 1,
    },

    operatingMode: enum(u3) {
        intOnTerminalCount = 0,
        oneShot = 1,
        rateGenerator = 2,
        squareWaveGenerator = 3,
        swTriggeredStrobe = 4,
        hwTriggeredStrobe = 5,

        _mode2Alt = 6,
        _mode3Alt = 7,
    },

    accessMode: enum(u2) {
        latchCountValueCmd = 0,
        lowByte = 1,
        highByte = 2,
        bothBytes = 3,
    },

    channel: enum(u2) {
        ch0 = 0,
        ch1 = 1,
        ch2 = 2,
    },
};

pub fn latch(channel: u2) Mode {
    io.outb(channel, @as(u8, channel << 6));
}
