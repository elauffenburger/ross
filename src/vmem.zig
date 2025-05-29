const std = @import("std");

const kstd = @import("kstd.zig");
const proc = @import("proc.zig");
const vga = @import("vga.zig");

// Declare a hook to grab __kernel_size from the linker script.
extern const __kernel_size: u8;
fn kernelSize() u32 {
    return @as(u32, @intFromPtr(&__kernel_size));
}

var kernel_start_virt_addr: VirtualAddress = .{ .addr = 0xC0000000 };
var kernel_end_virt_addr: VirtualAddress = undefined;

// HACK: this should just be proc 0 in our processes lookup, but we don't have a heap yet, so we're going to punt on that!
var pagerProc: proc.Process = .{
    .id = 0,
    .vm = .{},
};

pub fn init() !void {
    kernel_end_virt_addr = .{ .addr = kernel_start_virt_addr.addr + kernelSize() };

    const num_kernel_pages: u32 = blk: {
        const kernel_size: f32 = @floatFromInt(kernelSize());
        const bytes_per_page: f32 = @floatFromInt(Page.NumBytesManaged);

        break :blk @intFromFloat(@ceil(kernel_size / bytes_per_page));
    };

    // Identity Map the first 1MiB.
    try mapPages(&pagerProc.vm, .kernel, 0, .{ .addr = 0 }, 0x400);

    // Map the Kernel into the higher half of memory.
    try mapPages(&pagerProc.vm, .kernel, 0x100000, kernel_start_virt_addr, num_kernel_pages);

    // Enable paging!
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

pub fn mapKernelIntoProcessVM(vm: *ProcessVirtualMemory) void {
    const kernel_start_table, const kernel_end_table = .{ kernel_start_virt_addr.table(), kernel_start_virt_addr.table() };
    const num_tables = kernel_end_table - kernel_start_table;

    for (0..num_tables) |i| {
        // Map in the existing kernel tables from the pager process.
        vm.pageDirectory[i] = pagerProc.vm.pageDirectory[kernel_start_table + i];
        vm.pageTables[i] = pagerProc.vm.pageTables[kernel_start_table + 1];
    }
}

pub fn mapPages(vm: *ProcessVirtualMemory, privilege: enum { kernel, userspace }, start_phys_addr: u32, start_virt_addr: VirtualAddress, num_pages: u32) !void {
    var curr_table_index = start_virt_addr.table();
    var curr_table_page_index = start_virt_addr.page();

    var num_pages_written: usize = 0;
    dir_loop: while (true) {
        // Create a page table if it's not already present.
        //
        // NOTE: for future Eric: this is probably your bug!! Page table addresses need to be 4KiB aligned, and I'm betting this isn't since we switched to pointers so we need to implement alignment in the heap to actually align this at 4KiB boundaries.
        // I started fixing this, but we're panicking because the alignment isn't correct (because we're not aligning in kmalloc), so let's fix that and see if it fixes this!
        if (vm.pageTables[curr_table_index] == null) {
            vm.pageTables[curr_table_index] = @ptrCast((try kstd.mem.kernel_heap_allocator.alignedAlloc(PageTable, 0x20000, 1)).ptr);
        }

        const page_table = vm.pageTables[curr_table_index].?;

        const page_table_addr: u20 = @truncate(@intFromPtr(page_table) >> 12);

        const dir_entry = &vm.pageDirectory[curr_table_index];
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

        for (curr_table_page_index..PageTable.NumPages) |page_i| {
            // If we've written the number of pages we were supposed to, bail!
            if (num_pages_written == num_pages) {
                break :dir_loop;
            }

            const addr = start_phys_addr + (num_pages_written * Page.NumBytesManaged);
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

            num_pages_written += 1;
        }

        // Looks like we wrote the entire page table; go to the next one!
        curr_table_index += 1;
        curr_table_page_index = 0;
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

pub const Page = packed struct(u32) {
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
    // NOTE: we allocate the page directory up-front (4KiB/process) since that _has_ to be present, but we only allocate page tables as-needed.
    // NOTE: (WIP) the first N page tables are shared pointers to kernel page table entries so we don't have to reallocate for each process.
    //
    // To visualize:
    //   Page Directory -> Page Table Entry (Page) -> Offset in Page
    //   4MiB chunk     -> 4KiB slice of 4MiB      -> Offset into 4KiB
    //   City           -> Street                  -> Number on street
    pageDirectory: [1024]PageDirectoryEntry = [_]PageDirectoryEntry{@bitCast(@as(u32, 0))} ** 1024,
    pageTables: [1024]?*PageTable = [_]?*PageTable{null} ** 1024,
};

pub const PageTable = struct {
    pub const NumPages = 1024;

    // Each entry in a page table is initially marked not present.
    pages: [NumPages]Page = [_]Page{@bitCast(@as(u32, 0))} ** NumPages,
};

pub const VirtualAddress = packed struct(u32) {
    const Self = @This();

    addr: u32,

    pub fn table(self: Self) u10 {
        return @truncate(self.addr >> 22);
    }

    pub fn page(self: Self) u10 {
        return @truncate((self.addr >> 12) & 0x03FF);
    }

    pub fn offset(self: Self) u12 {
        return @truncate(self.addr & 0x0000_07ff);
    }

    test "0xC0011222" {
        const addr = VirtualAddress{ .addr = 0xC0011222 };

        try std.testing.expect(addr.table() == 768);
        try std.testing.expect(addr.page() == 17);
        try std.testing.expect(addr.offset() == 546);
    }
};
