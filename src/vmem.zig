const std = @import("std");

const kstd = @import("kstd.zig");
const proc = @import("proc.zig");
const vga = @import("vga.zig");

extern const __kernel_start: u8;
fn kernelStartPhysAddr() u32 {
    return @as(u32, @intFromPtr(&__kernel_start));
}

extern const __kernel_size: u8;
fn kernelSize() u32 {
    return @as(u32, @intFromPtr(&__kernel_size));
}

var kernel_start_virt_addr: VirtualAddress = .{ .addr = 0xC0000000 };

// HACK: this should just be proc 0 in our processes lookup!
var kernel_proc: proc.Process = .{
    .id = 0,
    .vm = .{},
};

var shared_proc_vm = ProcessVirtualMemory{};

var kernel_first_page_table: [1024]Page align(4096) = undefined;

pub fn init() !void {
    vga.printf("page_dir_addr: 0x{x}.....................\n", .{@intFromPtr(&kernel_proc.vm.page_dir)});

    var kernel_page_dir = &kernel_proc.vm.page_dir;
    kernel_proc.vm.page_tables[0] = &kernel_first_page_table;

    // Create page directory.
    for (0..kernel_page_dir.len) |i| {
        kernel_page_dir[i] = .{
            .rw = true,
        };
    }

    // Create first page table.
    for (0..kernel_first_page_table.len) |i| {
        const addr = @as(u32, @intCast(i)) * 4096;

        kernel_first_page_table[i] = .{
            .present = true,
            .rw = true,
            .addr = @as(u20, @intCast(addr >> 12)),
        };
    }

    // Load the first page table into the page dir.
    kernel_page_dir[0] = .{
        .present = true,
        .rw = true,
        .addr = @as(u20, @truncate(@as(u32, @intFromPtr(&kernel_first_page_table)) >> 12)),
    };

    // Enable paging!
    enablePaging(&kernel_proc.vm);
}

pub fn enablePaging(vm: *ProcessVirtualMemory) void {
    asm volatile (
        \\ mov %[pdt_addr], %%cr3
        \\
        \\ mov %%cr0, %%eax
        \\ or $0x80000000, %%eax
        \\ mov %%eax, %%cr0
        :
        : [pdt_addr] "r" (@intFromPtr(&vm.page_dir)),
        : "eax", "cr0", "cr3"
    );
}

// See https://wiki.osdev.org/Paging#32-bit_Paging_(Protected_Mode) for more info!
pub const PageDirectoryEntry = packed struct(u32) {
    // Each page in the page directory manages 4MiB (since there are 1024 entries to cover a 4GiB space).
    pub const NumBytesManaged: u32 = 0x400000;

    present: bool = false,
    rw: bool = false,
    userAccessible: bool = false,
    pwt: enum(u1) {
        writeBack = 0,
        writeThrough = 1,
    } = .writeBack,
    cacheDisable: bool = false,
    accessed: bool = false,
    _r1: u1 = 0,
    pageSize: PageSize = .@"4KiB",
    meta: u4 = 0,
    addr: u20 = 0,

    // NOTE: Technically this could be a 4KiB or 4MiB entry, but we're just going to support 4KiB for now so we have a page table.
    pub const PageSize = enum(u1) {
        @"4KiB" = 0,
        @"4MiB" = 1,
    };

    pub fn pageTable(self: @This()) *[1024]Page {
        return @ptrFromInt(@as(u32, self.addr) << 12);
    }
};

pub const Page = packed struct(u32) {
    // Each page in the page table manages 4KiB (since there are 1024 entries to cover a 4MiB page dir entry).
    pub const NumBytesManaged: u32 = 0x1000;

    present: bool = false,
    rw: bool = false,
    userAccessible: bool = false,
    pwt: enum(u1) {
        writeBack = 0,
        writeThrough = 1,
    } = .writeBack,
    cacheDisable: bool = false,
    accessed: bool = false,
    dirty: bool = false,
    pat: bool = false,
    global: bool = false,
    meta: u3 = 0,
    addr: u20,
};

pub const ProcessVirtualMemory = struct {
    // Each process gets its own page directory and each page dir entry has an associated page table.
    //
    //   Page Directory -> Page Table Entry (Page) -> Offset in Page
    //   4MiB chunk     -> 4KiB slice of 4MiB      -> Offset into 4KiB
    //   City           -> Street                  -> Number on street
    page_dir: [1024]PageDirectoryEntry align(4096) = undefined,
    page_tables: [1024]*[1024]Page = undefined,
};

pub const VirtualAddress = packed struct(u32) {
    const Self = @This();

    addr: u32,

    pub fn dir(self: Self) u10 {
        return @truncate(self.addr >> 22);
    }

    pub fn page(self: Self) u10 {
        return @truncate((self.addr >> 12) & 0x03ff);
    }

    pub fn offset(self: Self) u12 {
        return @truncate(self.addr & 0x00000fff);
    }
};

test "virtual Address 0x00801004" {
    const addr = VirtualAddress{ .addr = 0x00801004 };

    try std.testing.expect(addr.dir() == 0x2);
    try std.testing.expect(addr.page() == 0x1);
    try std.testing.expect(addr.offset() == 0x4);
}

test "virtual Address 0x00132251" {
    const addr = VirtualAddress{ .addr = 0x00132251 };

    try std.testing.expect(addr.dir() == 0x000);
    try std.testing.expect(addr.page() == 0x132);
    try std.testing.expect(addr.offset() == 0x251);
}
