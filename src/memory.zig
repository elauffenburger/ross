const std = @import("std");

// See https://wiki.osdev.org/Paging#32-bit_Paging_(Protected_Mode) for more info!
pub const PageDirectoryEntry = packed struct(u32) {
    // Each page in the page directory manages 4MiB (since there are 1024 entries to cover a 4GiB space).
    const NumBytesManaged: u32 = 0x400000;

    present: bool,
    rw: bool,
    userAccessible: bool,
    pwt: enum(u1) {
        writeBack = 0,
        writeThrough = 1,
    },
    cacheDisable: bool,
    accessed: bool,
    _r1: u1,
    pageSize: PageSize = .size4KiB,
    meta: u4,
    addr: u20,

    // NOTE: Technically this could be a 4KiB or 4MiB entry, but we're just going to support 4KiB for now so we have a page table.
    pub const PageSize = enum(u1) {
        size4KiB = 0,
        size4MiB = 1,
    };
};

pub const PageTableEntry = packed struct(u32) {
    // Each page in the page table manages 4KiB (since there are 1024 entries to cover a 4MiB page dir entry).
    const NumBytesManaged: u32 = 0x1000;

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
    meta: u3,
    addr: u20,
};

pub const Process = struct {
    id: u32,
    vm: VirtualMemory,

    pub const VirtualMemory = struct {
        // Each process gets its own page directory.
        pageDirectory: [1024]PageDirectoryEntry = [_]PageDirectoryEntry{@bitCast(@as(u32, 0))} ** 1024,

        // Each entry in the directory maps to a page table.
        pageTables: [1024]PageTable = [_]PageTable{.{}} ** 1024,

        pub const PageTable = struct {
            // Each entry in a page table is initially marked not present.
            pages: [1024]PageTableEntry = [_]PageTableEntry{@bitCast(@as(u32, 0))} ** 1024,
        };
    };
};

const MaxAddress: u32 = 0xffffffff;

const NumPageDirEntries = @typeInfo(@FieldType(Process.VirtualMemory, "pageDirectories")).array.len;
const NumPagesPerTable = @typeInfo(@FieldType(Process.VirtualMemory.PageTable, "pages")).array.len;

extern var __kernel_size: u32;

// HACK: this just exists so we can set up paging during kernel boostrapping; once we enter protected mode and get all wired up, this
// be moved into the Processes map and be undefined (so you almost certainly don't care about this).
//
// TODO: this really should be a pointer, but we need to set up a heap first...
var __pagerProcFromInit: Process = undefined;

pub inline fn init() void {
    __pagerProcFromInit = .{
        .id = 0,
        .vm = .{},
    };
}

inline fn mapKernelPage(vm: *Process.VirtualMemory, start_phys_addr: u32, start_virt_addr: u32) void {
    const topLevelTableIndex = topLevelTableIndexForVirtAddr(start_virt_addr);

    const pageTable = &vm.pageTables[topLevelTableIndex];

    const dirEntry = &vm.pageDirectory[topLevelTableIndex];
    dirEntry.* = .{
        .present = true,
        .rw = true,
        .userAccessible = false,
        .pwt = .writeThrough,
        .cacheDisable = false,
        .accessed = false,
        .pageSize = .size4KiB,
        .addr = @intFromPtr(pageTable),
    };

    // Fill in all entries in the page table.
    for (0..NumPagesPerTable) |i| {
        pageTable.pages[i] = PageTableEntry{
            .present = true,
            .rw = true,
            .userAccessible = true,
            .pwt = .writeThrough,
            .cacheDisable = false,
            .accessed = false,
            .dirty = false,
            .pat = false,
            .addr = start_phys_addr + (i * PageTableEntry.NumBytesManaged),
        };
    }
}

inline fn topLevelTableIndexForVirtAddr(virt_addr: u32) u32 {
    return @ceil((virt_addr / MaxAddress) * NumPageDirEntries) - 1;
}

// 10 units (0-9)
// 3 pages
// 3.33 units per page
// i want unit 0
//   -> (1 / 10) * num_pages -> .1 * 3 -> 0.3 -> 0
//
// i want unit 2
//   -> (3 / 10) * num_pages -> .3 * 3 -> 0.9 -> 0
//
// i want unit 3
//   -> (4 / 10) * num_pages -> .4 * 3 -> 1.3 -> 1
//
// i want unit 9
//   -> (10 / 10) * num_pages -> 1 * 3 -> 3 -> 2
//
// so, ceil((unit / num_units) * numPages) - 1
