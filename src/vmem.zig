const std = @import("std");

const proc = @import("proc.zig");
const vga = @import("vga.zig");

// Declare a hook to grab __kernel_size from the linker script.
extern const __kernel_size: u8;
fn kernelSize() u32 {
    return @as(u32, @intFromPtr(&__kernel_size));
}

// HACK: this should just be proc 0 in our processes lookup, but we don't have a heap yet, so we're going to punt on that!
var pagerProc: proc.Process = .{
    .id = 0,
    .vm = .{},
};

pub fn init() void {
    const kernel_size: f32 = @floatFromInt(kernelSize());
    const bytes_per_page: f32 = @floatFromInt(PageTableEntry.NumBytesManaged);
    const num_pages_for_kernel: u32 = @intFromFloat(@ceil(kernel_size / bytes_per_page));

    // Identity Map the first 1MiB.
    mapKernelPages(&pagerProc.vm, .kernel, 0, .{ .addr = 0 }, 0x400);

    // Map the Kernel into the higher half of memory.
    mapKernelPages(&pagerProc.vm, .kernel, 0x100000, .{ .addr = 0xC0000000 }, num_pages_for_kernel);

    enablePaging(&pagerProc.vm.pageDirectory);
}

pub fn enablePaging(pdt: []PageDirectoryEntry) void {
    asm volatile (
        \\ mov %[pdt_addr], %%eax
        \\ mov %%eax, %%cr3
        \\
        \\ mov %%cr0, %%eax
        \\ or $0x80000001, %%eax
        \\ mov %%eax, %%cr0
        :
        : [pdt_addr] "r" (@as(u32, @intFromPtr(pdt.ptr))),
        : "eax", "cr0"
    );
}

pub fn mapKernelPages(vm: *ProcessVirtualMemory, privilege: enum { kernel, userspace }, start_phys_addr: u32, start_virt_addr: VirtualAddress, num_pages: u32) void {
    const end_virt_addr = VirtualAddress{ .addr = start_virt_addr.addr + (num_pages * PageTableEntry.NumBytesManaged) };

    const start_page_dir, const end_page_dir = .{ start_virt_addr.pageDir(), end_virt_addr.pageDir() };
    for (start_page_dir..end_page_dir + 1) |page_dir_i| {
        const page_table = &vm.pageTables[page_dir_i];
        const page_table_addr: u20 = @truncate(@intFromPtr(page_table) >> 12);

        const dir_entry = &vm.pageDirectory[page_dir_i];
        dir_entry.* = switch (privilege) {
            .kernel => .{
                .present = true,
                .rw = true,
                .userAccessible = false,
                .pwt = .writeThrough,
                .cacheDisable = false,
                .accessed = false,
                .pageSize = .@"4KiB",
                .addr = page_table_addr,
            },
            .userspace => .{
                .present = true,
                .rw = false,
                .userAccessible = true,
                .pwt = .writeThrough,
                .cacheDisable = false,
                .accessed = false,
                .pageSize = .@"4KiB",
                .addr = page_table_addr,
            },
        };

        // Figure out how many pages we need to write for this table; if we're not at the last table, then write a full
        // table's amount; otherwise, write the remainder of the pages.
        const num_pages_for_table = blk: {
            if (page_dir_i == end_page_dir) {
                break :blk @mod(num_pages, ProcessVirtualMemory.PageTable.NumPages);
            } else {
                break :blk ProcessVirtualMemory.PageTable.NumPages;
            }
        };

        for (0..num_pages_for_table) |page_i| {
            const addr = start_phys_addr + ((page_i + ProcessVirtualMemory.PageTable.NumPages) * PageTableEntry.NumBytesManaged);
            const addr_trunc: u20 = @truncate(addr >> 12);

            page_table.pages[page_i] = switch (privilege) {
                .kernel => .{
                    .present = true,
                    .rw = true,
                    .userAccessible = false,
                    .pwt = .writeThrough,
                    .cacheDisable = false,
                    .accessed = false,
                    .dirty = false,
                    .pat = false,
                    .global = false,
                    .addr = addr_trunc,
                },
                .userspace => .{
                    .present = true,
                    .rw = false,
                    .userAccessible = true,
                    .pwt = .writeThrough,
                    .cacheDisable = false,
                    .accessed = false,
                    .dirty = false,
                    .pat = false,
                    .global = true,
                    .addr = addr_trunc,
                },
            };
        }
    }
}

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
    //
    // To visualize:
    //   Page Directory -> Page Table Entry (Page) -> Offset in Page
    //   4MiB chunk     -> 4KiB slice of 4MiB      -> Offset into 4KiB
    //   City           -> Street                  -> Number on street
    pageDirectory: [1024]PageDirectoryEntry = [_]PageDirectoryEntry{@bitCast(@as(u32, 0))} ** 1024,
    pageTables: [1024]PageTable = [_]PageTable{.{}} ** 1024,

    pub const PageTable = struct {
        pub const NumPages = 1024;

        // Each entry in a page table is initially marked not present.
        pages: [NumPages]PageTableEntry = [_]PageTableEntry{@bitCast(@as(u32, 0))} ** NumPages,
    };
};

pub const VirtualAddress = packed struct(u32) {
    const Self = @This();

    addr: u32,

    pub fn pageDir(self: Self) u10 {
        return @truncate(self.addr >> 22);
    }

    pub fn pageTableEntry(self: Self) u10 {
        return @truncate((self.addr >> 12) & 0x03FF);
    }

    pub fn offset(self: Self) u12 {
        return @truncate(self.addr & 0x0000_07ff);
    }

    test "0xC0011222" {
        const addr = VirtualAddress{ .addr = 0xC0011222 };

        try std.testing.expect(addr.pageDir() == 768);
        try std.testing.expect(addr.pageTableEntry() == 17);
        try std.testing.expect(addr.offset() == 546);
    }
};
