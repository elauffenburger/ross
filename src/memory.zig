const std = @import("std");

const vga = @import("vga.zig");

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
    _r1: u1 = undefined,
    pageSize: PageSize = .size4KiB,
    meta: u4 = undefined,
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
    meta: u3 = undefined,
    addr: u20,
};

pub const Process = struct {
    id: u32,
    vm: VirtualMemory,

    pub const VirtualMemory = struct {
        // Each process gets its own page directory and each page dir entry has an associated page table.
        pageDirectory: [1024]PageDirectoryEntry = [_]PageDirectoryEntry{@bitCast(@as(u32, 0))} ** 1024,
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

extern const __kernel_size: u8;

inline fn kernelSize() u32 {
    return @as(u32, @intFromPtr(&__kernel_size));
}

// HACK: this just exists so we can set up paging during kernel boostrapping; once we enter protected mode and get all wired up, this
// be moved into the Processes map and be undefined (so you almost certainly don't care about this).
//
// TODO: this really should be a pointer, but we need to set up a heap first...
var __pagerProcFromInit: Process = .{
    .id = 0,
    .vm = .{},
};

pub fn init(foo: u32) void {
    _ = foo; // autofix
    // Identity Map the first 1MiB.
    mapKernelPages(&__pagerProcFromInit.vm, 0, .{ .addr = 0 }, 0x400);

    // Map the Kernel into the higher half of memory.
    {
        const kernel_size: f32 = @floatFromInt(kernelSize());
        const bytes_per_page: f32 = @floatFromInt(PageTableEntry.NumBytesManaged);

        const num_pages_for_kernel: u32 = @intFromFloat(@ceil(kernel_size / bytes_per_page));
        vga.printf(
            \\ kernel_size: {x}
            \\ bytes_per_page: {x}
            \\ num_pages_for_kernel: {d}
        , .{
            @as(u32, @intFromFloat(kernel_size)),
            @as(u32, @intFromFloat(bytes_per_page)),
            num_pages_for_kernel,
        });

        // mapKernelPages(&__pagerProcFromInit.vm, 0x100000, .{ .addr = 0xC0000000 }, num_pages_for_kernel);

        // asm volatile ("hlt");
    }
}

fn mapKernelPages(vm: *Process.VirtualMemory, start_phys_addr: u32, start_virt_addr: VirtualAddress, num_pages: u32) void {
    const end_virt_addr = VirtualAddress{ .addr = start_virt_addr.addr + (num_pages * PageTableEntry.NumBytesManaged) };

    for (start_virt_addr.pageDir()..end_virt_addr.pageDir()) |top_level_table_index| {
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
            .addr = @truncate(@intFromPtr(page_table) >> 12),
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
};

test "0xC0011222" {
    const addr = VirtualAddress{ .addr = 0xC0011222 };

    try std.testing.expect(addr.pageDir() == 768);
    try std.testing.expect(addr.pageTableEntry() == 17);
    try std.testing.expect(addr.offset() == 546);
}
