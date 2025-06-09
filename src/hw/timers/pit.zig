const io = @import("../io.zig");
const pic = @import("../pic.zig");

const base_rate_hz = 1_193_180;
var rate_hz: u32 = 0;

pub fn init(pic_proof: pic.InitProof) !void {
    try pic_proof.prove();

    // Set mode.
    io.outb(
        IOPorts.cmd,
        @bitCast(Mode{
            .count_mode = .@"16bit",
            .operating_mode = .squareWaveGenerator,
            .access_mode = .bothBytes,
            .channel = .ch0,
        }),
    );

    // Set rate.
    setRateHz(100);
}

fn setRateHz(hz: u32) void {
    const divisor: u32 = @divFloor(base_rate_hz, hz);

    // Set divisor lo, then hi.
    io.outb(IOPorts.ch0, @truncate(divisor & 0xff));
    io.outb(IOPorts.ch0, @truncate((divisor & 0xff00) >> 8));

    rate_hz = hz;
}

pub fn rateHz() u32 {
    return rate_hz;
}

const IOPorts = struct {
    pub const ch0: u8 = 0x40;
    pub const ch1: u8 = 0x41;
    pub const ch2: u8 = 0x42;

    pub const cmd: u8 = 0x43;
};

pub const Mode = packed struct(u8) {
    count_mode: enum(u1) {
        // 16-bit binary.
        @"16bit" = 0,

        // Binary Coded Decimal.
        bcd = 1,
    },

    operating_mode: enum(u3) {
        intOnTerminalCount = 0,
        oneShot = 1,
        rateGenerator = 2,
        squareWaveGenerator = 3,
        swTriggeredStrobe = 4,
        hwTriggeredStrobe = 5,

        _mode2Alt = 6,
        _mode3Alt = 7,
    },

    access_mode: enum(u2) {
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
