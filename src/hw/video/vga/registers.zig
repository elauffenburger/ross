const io = @import("../../io.zig");

pub const misc_out = struct {
    // SAFETY: set in init
    pub var reg_val: Register = undefined;

    pub const io_port_r = 0x3cc;
    pub const io_port_w = 0x3c2;

    pub const Register = packed struct(u8) {
        vsyncp: u1 = 0,
        hsyncp: u1 = 0,
        oe_page: enum(u1) {
            lo = 0,
            hi = 1,
        } = .lo,
        _r1: u1,
        clock_select: enum(u2) {
            @"25Mhz" = 0,
            @"28Mhz" = 1,
        } = .@"25Mhz",
        ram_enable: bool,
        io_addr_select: enum(u1) {
            // crt controller addrs: 0x03bx, io status reg 1 addr: 0x03ba
            mono = 0,

            // crt controller addrs: 0x03dx, io status reg 1 addr: 0x03da
            color = 1,
        } = .mono,
    };

    pub fn read() Register {
        return @bitCast(io.inb(io_port_r));
    }

    pub fn write(reg: Register) void {
        // Write register value.
        io.outb(io_port_w, @bitCast(reg));

        // Update saved values.
        reg_val = reg;
        crt_ctrl.reg_addrs = crt_ctrl.regAddrs();
    }
};

pub const crt_ctrl = struct {
    pub const RegisterAddrs = struct {
        addr: u16,
        data: u16,
    };

    // SAFETY: set in init.
    pub var reg_addrs: RegisterAddrs = undefined;

    pub const cursor_location = struct {
        pub const hi = struct {
            pub const index = 0xe;

            pub const Register = u8;
        };

        pub const lo = struct {
            pub const index = 0xf;

            pub const Register = u8;
        };
    };

    pub const cursor_start = struct {
        pub const index = 0xa;

        pub const Register = packed struct(u8) {
            cursort_scanline_start: u5 = 0,
            cursor_disable: bool = false,
            _r1: u2 = 0,
        };
    };

    pub fn regAddrs() RegisterAddrs {
        switch (misc_out.reg_val.io_addr_select) {
            .mono => return .{ .addr = 0x3b4, .data = 0x3b5 },
            .color => return .{ .addr = 0x3d4, .data = 0x3d5 },
        }
    }

    pub fn read(reg: anytype) reg.Register {
        // Get the current register index.
        const orig_index = io.inb(reg_addrs.addr);

        // Set the input register index for this register.
        io.outb(reg_addrs.addr, reg.index);

        // Read the register data.
        const res = io.inb(reg_addrs.data);

        // Restore the original index.
        io.outb(reg_addrs.addr, orig_index);

        return @bitCast(res);
    }

    pub fn write(reg: anytype, val: reg.Register) void {
        // Get the current register index.
        const orig_index = io.inb(reg_addrs.addr);

        // Set the output register index for this register.
        io.outb(reg_addrs.addr, reg.index);

        // Write the register data.
        io.outb(reg_addrs.data, @bitCast(val));

        // Restore the original index.
        io.outb(reg_addrs.addr, orig_index);
    }
};
