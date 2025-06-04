const std = @import("std");

const io = @import("io.zig");

const baud_rate_base: u16 = 115200;

pub var com1 = COMPort(0x3f8){};
pub var com2 = COMPort(0x2f8){};
pub var com3 = COMPort(0x3e8){};
pub var com4 = COMPort(0x2e8){};

pub fn init() !void {
    // try com1.init();
    // try com2.init();
    // try com3.init();
    // try com4.init();
}

fn COMPort(io_port: u16) type {
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
    return struct {
        const Self = @This();

        var input_buf: [2048]u8 = undefined;
        var input_buf_list_allocator = std.heap.FixedBufferAllocator.init(&input_buf);
        var input_buf_list = std.ArrayList(u8).init(input_buf_list_allocator.allocator());

        buf_reader: std.io.AnyReader = .{
            .context = undefined,
            .readFn = &readBuf,
        },

        pub fn init(self: *Self) !void {
            // Disable interrupts.
            io.outb(io_port + 1, @bitCast(InterruptEnableRegister{}));

            // Set baud rate.
            self.setBaud(38400);

            // 8 bits, no parity, one stop bit.
            self.setLineControl(LineControlRegister{ .data_width = .@"8b" });

            // Enable FIFO, clear them, with 14-byte threshold
            io.outb(io_port + 2, @bitCast(FifoRegister{
                .enabled = true,
                .clear_rx_fifo = true,
                .clear_tx_fifo = true,
                .interrupt_trigger_level = .@"14B",
            }));

            // IRQs enabled, RTS/DSR set
            io.outb(io_port + 4, @bitCast(InterruptEnableRegister{}));

            // TODO: Make sure the interface is healthy.
        }

        pub fn setBaud(self: Self, divisor: u16) void {
            var line_control: LineControlRegister = @bitCast(io.inb(io_port + 3));
            const dlab_enabled = line_control.dlab;

            // Enable DLAB on line control register.
            if (!dlab_enabled) {
                line_control.dlab = true;
                self.setLineControl(line_control);
            }

            // Write baud rate divisor.
            io.outb(io_port, @as(u8, @truncate(divisor)) & 0xff);
            io.outb(io_port + 1, @as(u8, @truncate(divisor >> 8)) & 0xff);

            // Restore DLAB value.
            line_control.dlab = dlab_enabled;
            io.outb(io_port + 3, @bitCast(line_control));
        }

        pub fn getLineControl(_: Self) LineControlRegister {
            return @bitCast(io.inb(io_port + 3));
        }

        pub fn setLineControl(_: Self, reg: LineControlRegister) void {
            io.outb(io_port + 3, @bitCast(reg));
        }

        inline fn ioPort(self: Self) u16 {
            return @intFromEnum(self.port);
        }

        fn testInterface(_: Self) error{Unhealthy}!void {
            // TODO: make this work.

            // Set in loopback mode, test the serial chip.
            io.outb(io_port + 4, 0x1e);

            // Test serial chip (send byte 0xAE and check if serial returns same byte)
            io.outb(io_port, 0xae);

            // Check if serial is faulty (i.e: not same byte as sent)
            if (io.inb(io_port) != 0xae) {
                return error.Unhealthy;
            }

            // If serial is not faulty set it in normal operation mode
            // (not-loopback with IRQs enabled and OUT#1 and OUT#2 bits enabled)
            io.outb(io_port + 4, 0x0f);
        }

        fn readBuf(_: *const anyopaque, buffer: []u8) anyerror!usize {
            const n = if (Self.input_buf_list.items.len < buffer.len) Self.input_buf_list.items.len else buffer.len;
            for (0..n) |i| {
                buffer[i] = Self.input_buf_list.items[i];
            }

            if (n == Self.input_buf_list.items.len) {
                return n;
            }

            // HACK: there is no way this is efficient, but that's what we're going with for now!
            const remainder = Self.input_buf_list.items[n..Self.input_buf_list.items.len];
            Self.input_buf_list.clearRetainingCapacity();
            try Self.input_buf_list.appendSlice(remainder);

            return n;
        }
    };
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
