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

const NumPageDirEntries = @typeInfo(@FieldType(Process.VirtualMemory, "pageDirectory")).array.len;
const NumPageTableEntries = @typeInfo(@FieldType(Process.VirtualMemory.PageTable, "pages")).array.len;

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

    comptime {
        // Identity Map the first 1MiB.
        mapKernelPage(&__pagerProcFromInit, 0, 0, 0x400);

        // Map the Kernel into the higher half of memory.
    }
}

inline fn mapKernelPage(vm: *Process.VirtualMemory, start_phys_addr: u32, start_virt_addr: u32, num_pages: u32) void {
    const end_virt_addr = start_virt_addr + (num_pages / PageTableEntry.NumBytesManaged);

    for (topLevelTableIndexForVirtAddr(start_virt_addr)..topLevelTableIndexForVirtAddr(end_virt_addr)) |top_level_table_index| {
        const page_table = &vm.pageTables[top_level_table_index];

        const dir_entry = &vm.pageDirectory[top_level_table_index];
        dir_entry.* = .{
            .present = true,
            .rw = true,
            .userAccessible = false,
            .pwt = .writeThrough,
            .cacheDisable = false,
            .accessed = false,
            .pageSize = .size4KiB,
            .addr = @intFromPtr(page_table),
        };

        // Figure out how many pages we need to write for this table based on how many we've written already.
        const num_pages_written = top_level_table_index * NumPageTableEntries;
        const num_pages_for_table = num_pages - num_pages_written;

        for (0..num_pages_for_table) |i| {
            const addr = start_phys_addr + ((i + num_pages_written) * PageTableEntry.NumBytesManaged);

            page_table.pages[i] = PageTableEntry{
                .present = true,
                .rw = true,
                .userAccessible = true,
                .pwt = .writeThrough,
                .cacheDisable = false,
                .accessed = false,
                .dirty = false,
                .pat = false,
                .addr = addr,
            };
        }
    }
}

inline fn topLevelTableIndexForVirtAddr(virt_addr: u32) u32 {
    const page_dir_index = virt_addr >> 22;
    _ = page_dir_index; // autofix
}

test "topLevelIndexForVirtAddr should map 0x100000 to 768" {
    try std.testing.expect(topLevelTableIndexForVirtAddr(0x100000) == 768);
}
