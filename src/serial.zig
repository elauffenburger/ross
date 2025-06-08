const std = @import("std");

const io = @import("io.zig");
const kstd = @import("kstd.zig");
const types = @import("types.zig");

const baud_rate_base: u16 = 115200;

pub var com1: COMPort = .{ .io_port = 0x3f8 };
pub var com2: COMPort = .{ .io_port = 0x2f8 };
pub var com3: COMPort = .{ .io_port = 0x3e8 };
pub var com4: COMPort = .{ .io_port = 0x2e8 };

pub const InitProof = types.UniqueProof();

pub fn init() !InitProof {
    const proof = try InitProof.new();

    try com1.init();
    try com2.init();
    try com3.init();
    try com4.init();

    return proof;
}

// | IO Port Offset | Setting of DLAB | I/O Access | Register mapped to this port |
// +0  0  Read        Receive buffer
// +0  0  Write       Transmit buffer
// +1  0  Read/Write  Interrupt Enable Register
// +0  1  Read/Write  With DLAB set to 1, this is the least significant byte of the divisor value for setting the baud rate
// +1  1  Read/Write  With DLAB set to 1, this is the most significant byte of the divisor value
// +2  -  Read        Interrupt Identification
// +2  -  Write       FIFO control registers
// +3  -  Read/Write  Line Control Register; The most significant bit of this register is the DLAB
// +4  -  Read/Write  Modem Control Register
// +5  -  Read        Line Status Register
// +6  -  Read        Modem Status Register
// +7  -  Read/Write  Scratch Register
pub const COMPort = struct {
    const Self = @This();

    io_port: u16,

    input_buf: std.fifo.LinearFifo(u8, .{ .Static = 2048 }) = undefined,
    buf_reader: std.io.AnyReader = undefined,

    output_buf: std.fifo.LinearFifo(u8, .{ .Static = 2048 }) = undefined,
    buf_writer: std.io.AnyWriter = undefined,

    pub fn init(self: *Self) !void {
        self.input_buf = @TypeOf(self.input_buf).init();
        self.buf_reader = .{
            .context = self,
            .readFn = &read,
        };

        self.output_buf = @TypeOf(self.output_buf).init();
        self.buf_writer = .{
            .context = self,
            .writeFn = &write,
        };

        // Disable interrupts.
        io.outb(self.io_port + 1, @bitCast(InterruptEnableRegister{}));

        // Set baud rate.
        self.setBaud(38400);

        // 8 bits, no parity, one stop bit.
        self.setLineControl(LineControlRegister{
            .data_width = .@"8b",
            .stop = true,
        });

        // Enable FIFO, clear them, with 14-byte threshold
        io.outb(self.io_port + 2, @bitCast(FifoRegister{
            .enabled = true,
            .clear_rx_fifo = true,
            .clear_tx_fifo = true,
            .interrupt_trigger_level = .@"14B",
        }));

        // IRQs enabled, RTS/DSR set
        io.outb(self.io_port + 4, @bitCast(ModemControlRegister{
            .dtr = true,
            .rts = true,
            .out2 = true,
        }));

        // Enable interrupts
        // HACK: is this necessary?
        io.outb(
            self.io_port + 1,
            @bitCast(InterruptEnableRegister{
                .rx_data_available = true,
                .tx_holding_reg_empty = true,
                .rx_line_status = true,
                .modem_status = true,
            }),
        );

        // TODO: Make sure the interface is healthy.
    }

    pub fn setBaud(self: Self, divisor: u16) void {
        var line_control: LineControlRegister = @bitCast(io.inb(self.io_port + 3));
        const dlab_enabled = line_control.dlab;

        // Enable DLAB on line control register.
        if (!dlab_enabled) {
            line_control.dlab = true;
            self.setLineControl(line_control);
        }

        // Write baud rate divisor.
        io.outb(self.io_port, @as(u8, @truncate(divisor)) & 0xff);
        io.outb(self.io_port + 1, @as(u8, @truncate(divisor >> 8)) & 0xff);

        // Restore DLAB value.
        line_control.dlab = dlab_enabled;
        io.outb(self.io_port + 3, @bitCast(line_control));
    }

    pub fn getLineControl(self: Self) LineControlRegister {
        return @bitCast(io.inb(self.io_port + 3));
    }

    pub fn setLineControl(self: Self, reg: LineControlRegister) void {
        io.outb(self.io_port + 3, @bitCast(reg));
    }

    inline fn ioPort(self: Self) u16 {
        return @intFromEnum(self.port);
    }

    fn testInterface(self: Self) error{Unhealthy}!void {
        // TODO: make this work.

        // Set in loopback mode, test the serial chip.
        io.outb(self.io_port + 4, 0x1e);

        // Test serial chip (send byte 0xAE and check if serial returns same byte)
        io.outb(self.io_port, 0xae);

        // Check if serial is faulty (i.e: not same byte as sent)
        if (io.inb(self.io_port) != 0xae) {
            return error.Unhealthy;
        }

        // If serial is not faulty set it in normal operation mode
        // (not-loopback with IRQs enabled and OUT#1 and OUT#2 bits enabled)
        io.outb(self.io_port + 4, 0x0f);
    }

    fn read(ctx: *const anyopaque, buffer: []u8) anyerror!usize {
        var self: *Self = @constCast(@ptrCast(@alignCast(ctx)));
        self.sync();

        return self.input_buf.read(buffer);
    }

    fn write(ctx: *const anyopaque, buffer: []const u8) anyerror!usize {
        var self: *Self = @constCast(@ptrCast(@alignCast(ctx)));

        try self.output_buf.write(buffer);
        self.sync();

        return buffer.len;
    }

    fn sync(self: *Self) void {
        const line_status = self.getLineStatus();

        // If there's data pending on rx, read it!
        if (line_status.data_ready) {
            self.readPort() catch {};
        }

        // If there's data pending in the buffer, write it!
        if (line_status.tx_holding_reg_empty) {
            self.writePortFromBuf();
        }
    }

    fn readPort(self: *Self) !void {
        try self.input_buf.writeItem(io.inb(self.io_port));
    }

    fn writePortFromBuf(self: *Self) void {
        if (self.output_buf.readItem()) |byte| {
            io.outb(self.io_port, byte);
        }
    }

    pub fn getLineStatus(self: Self) LineStatusRegister {
        return @bitCast(io.inb(self.io_port + 5));
    }
};

pub fn onIrq(maybe_port_nums: enum { com1com3, com2com4 }) void {
    const maybe_ports = blk: {
        switch (maybe_port_nums) {
            .com1com3 => break :blk [_]*COMPort{ &com1, &com4 },
            .com2com4 => break :blk [_]*COMPort{ &com1, &com4 },
        }
    };

    for (maybe_ports) |maybe_port| {
        maybe_port.sync();
    }
}

const InterruptIdentificationRegister = packed struct(u8) {
    pending_state: enum(u1) { pending = 0, not_pending = 1 } = .@"0",
    state: enum(u2) {
        // Priority: 4 (lowest)
        modemStatus = 0,

        // Priority: 3
        txHoldingRegEmpty = 1,

        // Priority: 2
        rxDataAvailable = 2,

        // Priority: 1 (highest)
        rxLineStatus = 3,
    } = .modemStatus,
    timeout_interrupt_pending: bool = false,
    _r1: u2 = 0,
    fifo_buffer_state: enum(u2) {
        none = 0,
        unusable = 1,
        enabled = 2,
    },
};

const FifoRegister = packed struct(u8) {
    enabled: bool = false,
    clear_rx_fifo: bool = false,
    clear_tx_fifo: bool = false,
    dma_mode: bool = false,
    _r1: u2 = 0,
    interrupt_trigger_level: enum(u2) {
        @"1B" = 0,
        @"4B" = 1,
        @"8B" = 2,
        @"14B" = 3,
    } = .@"1B",
};

const LineStatusRegister = packed struct(u8) {
    // (DR) Set if there is data that can be read.
    data_ready: bool,

    // (OE) Set if there has been data lost.
    overrun_err: bool,

    // (PE) Set if there was an error in the transmission as detected by parity.
    parity_err: bool,

    // (FE) Set if a stop bit was missing.
    framing_err: bool,

    // (BI) Set if there is a break in data input.
    break_indicator: bool,

    // (THRE) Set if the transmission buffer is empty (i.e. data can be sent).
    tx_holding_reg_empty: bool,

    // (TEMT) Set if the transmitter is not doing anything.
    tx_empty: bool,

    // Set if there is an error with a word in the input buffer.
    impending_err: bool,
};

// NOTE If Bit 4 of the MCR (LOOP bit) is set, the upper 4 bits will mirror the 4 status output lines set in the Modem Control Register.
const ModemStatusRegister = packed struct(u8) {
    // (DCTS) Indicates that CTS input has changed state since the last time it was read.
    delta_clear_to_send: bool,

    // (DDSR) Indicates that DSR input has changed state since the last time it was read.
    delta_data_set_ready: bool,

    // (TERI) Indicates that RI input to the chip has changed from a low to a high state.
    trailing_edge_of_ring_indicator: bool,

    // (DDCD) Indicates that DCD input has changed state since the last time it ware read.
    delta_data_carrier_detect: bool,

    // (CTS) Inverted CTS Signal.
    clear_to_send: bool,

    // (DSR) Inverted DSR Signal.
    data_set_ready: bool,

    // (RI) Inverted RI Signal.
    ring_indicator: bool,

    // (DCD) Inverted DCD Signal.
    data_carrier_detect: bool,
};

const InterruptEnableRegister = packed struct(u8) {
    rx_data_available: bool = false,
    tx_holding_reg_empty: bool = false,
    rx_line_status: bool = false,
    modem_status: bool = false,
    _r1: u4 = 0,
};

const LineControlRegister = packed struct(u8) {
    data_width: enum(u2) {
        @"5b" = 0,
        @"6b" = 1,
        @"7b" = 2,
        @"8b" = 3,
    } = .@"5b",
    stop: bool = false,
    parity: u3 = 0,
    breakEnable: bool = false,
    dlab: bool = false,
};

const ModemControlRegister = packed struct(u8) {
    // Data Terminal Ready pin
    dtr: bool = false,

    // Request to Send
    rts: bool = false,

    // Unused (I guess??)
    out1: bool = false,

    // Enables IRQs
    out2: bool = false,

    // Enables local loopback
    loop: bool = false,

    _r1: u3 = 0,
};
