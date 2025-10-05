const std = @import("std");

const kstd = @import("../kstd.zig");
const pic = @import("pic.zig");

const user_proc_kernel_start_virt_addr: VirtualAddress = .{ .addr = 0xc0000000 };

extern const __kernel_start: u8;
fn kernelStartPhysAddr() u32 {
    return @as(u32, @intFromPtr(&__kernel_start));
}

extern const __kernel_size: u8;
fn kernelSize() u32 {
    return @as(u32, @intFromPtr(&__kernel_size));
}

pub const ProcessVirtualMemory = struct {
    // Each process gets its own page directory and each page dir entry has an associated page table.
    //
    //   Page Directory -> Page Table Entry (Page) -> Offset in Page
    //   4MiB chunk     -> 4KiB slice of 4MiB      -> Offset into 4KiB
    //   City           -> Street                  -> Number on street
    page_dir: PageDirectory align(4096) = [_]PageDirectoryEntry{PageDirectoryEntry{ .rw = true }} ** 1024,

    page_tables: [1024]?*PageTable = [_]?*PageTable{null} ** 1024,
};

const VirtualAddress = packed struct(u32) {
    const Self = @This();

    addr: u32,

    pub fn table(self: Self) u10 {
        return @truncate(self.addr >> 22);
    }

    pub fn page(self: Self) u10 {
        return @truncate((self.addr >> 12) & 0x03ff);
    }

    pub fn offset(self: Self) u12 {
        return @truncate(self.addr & 0x00000fff);
    }
};

const PageDirectory = [1024]PageDirectoryEntry;
const PageTable = [1024]Page;

// See https://wiki.osdev.org/Paging#32-bit_Paging_(Protected_Mode) for more info!
const PageDirectoryEntry = packed struct(u32) {
    // Each page in the page directory manages 4MiB (since there are 1024 entries to cover a 4GiB space).
    pub const NUM_BYTES_MANAGED: u32 = 0x400000;

    present: bool = false,
    rw: bool = false,
    user_accessible: bool = false,
    pwt: enum(u1) {
        writeBack = 0,
        writeThrough = 1,
    } = .writeBack,
    cache_disable: bool = false,
    accessed: bool = false,
    _r1: u1 = 0,
    page_size: PageSize = .@"4KiB",
    meta: u4 = 0,
    addr: u20 = 0,

    // NOTE: Technically this could be a 4KiB or 4MiB entry, but we're just going to support 4KiB for now so we have a page table.
    pub const PageSize = enum(u1) {
        @"4KiB" = 0,
        @"4MiB" = 1,
    };

    pub inline fn pageTable(self: @This()) *PageTable {
        return @ptrFromInt(@as(u32, self.addr) << 12);
    }
};

const Page = packed struct(u32) {
    // Each page in the page table manages 4KiB (since there are 1024 entries to cover a 4MiB page dir entry).
    pub const NUM_BYES_MANAGED: u32 = 0x1000;

    present: bool = false,
    rw: bool = false,
    user_accessible: bool = false,
    pwt: enum(u1) {
        writeBack = 0,
        writeThrough = 1,
    } = .writeBack,
    cache_disable: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    pat: bool = false,
    global: bool = false,
    meta: u3 = 0,
    addr: u20 = 0,

    test "0x00801004" {
        const addr = VirtualAddress{ .addr = 0x00801004 };

        try std.testing.expect(addr.table() == 0x2);
        try std.testing.expect(addr.page() == 0x1);
        try std.testing.expect(addr.offset() == 0x4);
    }

    test "0x00132251" {
        const addr = VirtualAddress{ .addr = 0x00132251 };

        try std.testing.expect(addr.table() == 0x000);
        try std.testing.expect(addr.page() == 0x132);
        try std.testing.expect(addr.offset() == 0x251);
    }
};
