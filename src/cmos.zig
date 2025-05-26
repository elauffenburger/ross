const io = @import("io.zig");

const IOPorts = struct {
    pub const index: u16 = 0x70;
    pub const data: u16 = 0x71;
};

pub fn unmaskNMIs() void {
    const status = readIndex();
    writeData(0x7f & status);
}

pub fn maskNMIs() void {
    const status = readIndex();
    writeData(0x80 | status);
}

pub fn areNMIsMasked() bool {
    return readIndex() >> 7 == 1;
}

pub fn readIndex() u8 {
    const val = io.inb(IOPorts.index);
    io.wait();

    return val;
}

pub fn writeIndex(val: u8) void {
    io.outb(IOPorts.index, val);
    io.wait();
}

pub fn readData() u8 {
    const val = io.inb(IOPorts.data);
    io.wait();

    return val;
}

pub fn writeData(val: u8) void {
    io.outb(IOPorts.data, val);
    io.wait();

    // Mandatory read from index port after write to data port.
    _ = io.inb(IOPorts.index);
}
