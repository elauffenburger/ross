const std = @import("std");

const vga = @import("vga.zig");

// See https://wiki.osdev.org/Paging#32-bit_Paging_(Protected_Mode) for more info!
pub const PageDirectoryEntry = packed struct(u32) {
    // Each page in the page directory manages 4MiB (since there are 1024 entries to cover a 4GiB space).
    pub const NumBytesManaged: u32 = 0x400000;

    present: bool,
    rw: bool,
    userAccessible: bool,
    pwt: enum(u1) {
        writeBack = 0,
        writeThrough = 1,
    },
    cacheDisable: bool,
    accessed: bool,
    _r1: u1 = undefined,
    pageSize: PageSize = .@"4KiB",
    meta: u4 = undefined,
    addr: u20,

    // NOTE: Technically this could be a 4KiB or 4MiB entry, but we're just going to support 4KiB for now so we have a page table.
    pub const PageSize = enum(u1) {
        @"4KiB" = 0,
        @"4MiB" = 1,
    };
};

pub const PageTableEntry = packed struct(u32) {
    // Each page in the page table manages 4KiB (since there are 1024 entries to cover a 4MiB page dir entry).
    pub const NumBytesManaged: u32 = 0x1000;

    present: bool,
    rw: bool,
    userAccessible: bool,
    pwt: enum(u1) {
        writeBack = 0,
        writeThrough = 1,
    },
    cacheDisable: bool,
    accessed: bool,
    dirty: bool,
    pat: bool,
    global: bool,
    meta: u3 = undefined,
    addr: u20,
};

pub const ProcessVirtualMemory = struct {
    // Each process gets its own page directory and each page dir entry has an associated page table.
    pageDirectory: [1024]PageDirectoryEntry = [_]PageDirectoryEntry{@bitCast(@as(u32, 0))} ** 1024,
    pageTables: [1024]PageTable = [_]PageTable{.{}} ** 1024,

    pub const PageTable = struct {
        // Each entry in a page table is initially marked not present.
        pages: [1024]PageTableEntry = [_]PageTableEntry{@bitCast(@as(u32, 0))} ** 1024,
    };
};

const MaxAddress: u32 = 0xffffffff;

const NumPageDirEntries = @typeInfo(@FieldType(ProcessVirtualMemory, "pageDirectory")).array.len;
const NumPageTableEntries = @typeInfo(@FieldType(ProcessVirtualMemory.PageTable, "pages")).array.len;

pub fn mapKernelPages(vm: *ProcessVirtualMemory, start_phys_addr: u32, start_virt_addr: VirtualAddress, num_pages: u32) void {
    const end_virt_addr = VirtualAddress{ .addr = start_virt_addr.addr + (num_pages * PageTableEntry.NumBytesManaged) };

    const start_page_dir, const end_page_dir = .{ start_virt_addr.pageDir(), end_virt_addr.pageDir() };
    for (start_page_dir..end_page_dir + 1) |page_dir_i| {
        const page_table = &vm.pageTables[page_dir_i];

        const dir_entry = &vm.pageDirectory[page_dir_i];
        dir_entry.* = .{
            .present = true,
            .rw = true,
            .userAccessible = false,
            .pwt = .writeThrough,
            .cacheDisable = false,
            .accessed = false,
            .pageSize = .@"4KiB",
            .addr = @truncate(@intFromPtr(page_table) >> 12),
        };

        // Figure out how many pages we need to write for this table; if we're not at the last table, then write a full
        // table's amount; otherwise, write the remainder of the pages.
        const num_pages_for_table = blk: {
            if (page_dir_i == end_page_dir) {
                break :blk @mod(num_pages, NumPageTableEntries);
            } else {
                break :blk NumPageTableEntries;
            }
        };

        for (0..num_pages_for_table) |page_i| {
            const addr = start_phys_addr + ((page_i + NumPageTableEntries) * PageTableEntry.NumBytesManaged);

            page_table.pages[page_i] = PageTableEntry{
                .present = true,
                .rw = true,
                .userAccessible = true,
                .pwt = .writeThrough,
                .cacheDisable = false,
                .accessed = false,
                .dirty = false,
                .pat = false,
                .global = false,
                .addr = @truncate(addr >> 12),
            };
        }
    }
}

pub const VirtualAddress = packed struct(u32) {
    const Self = @This();

    addr: u32,

    pub inline fn pageDir(self: Self) u10 {
        return @truncate(self.addr >> 22);
    }

    pub inline fn pageTableEntry(self: Self) u10 {
        return @truncate((self.addr >> 12) & 0x03FF);
    }

    pub inline fn offset(self: Self) u12 {
        return @truncate(self.addr & 0x0000_07ff);
    }

    test "0xC0011222" {
        const addr = VirtualAddress{ .addr = 0xC0011222 };

        try std.testing.expect(addr.pageDir() == 768);
        try std.testing.expect(addr.pageTableEntry() == 17);
        try std.testing.expect(addr.offset() == 546);
    }
};
