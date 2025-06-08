const std = @import("std");

const kstd = @import("kstd.zig");
const proc = @import("proc.zig");
const types = @import("types.zig");
const vga = @import("vga.zig");

const user_proc_kernel_start_virt_addr: VirtualAddress = .{ .addr = 0xc0000000 };

extern const __kernel_start: u8;
fn kernelStartPhysAddr() u32 {
    return @as(u32, @intFromPtr(&__kernel_start));
}

extern const __kernel_size: u8;
fn kernelSize() u32 {
    return @as(u32, @intFromPtr(&__kernel_size));
}

var shared_proc_vm = ProcessVirtualMemory{};

pub fn init() !void {
    // Identity-map the kernel into the kernel_proc.
    // try mapPages(proc.kernel_proc.vm, 0, .{ .addr = 0 }, kernelSize());
    // HACK: we're just going to map the entire address space.
    try mapPages(proc.kernel_proc.vm, 0, .{ .addr = 0 }, kernelSize());

    // Map the kernel into the shared process virtual memory.
    try mapPages(&shared_proc_vm, 0, user_proc_kernel_start_virt_addr, 0xffffffff - user_proc_kernel_start_virt_addr.addr);

    // Enable paging!
    enablePaging(proc.kernel_proc.saved_registers.cr3);
}

fn enablePaging(new_cr3: u32) void {
    asm volatile (
        \\ mov %[pdt_addr], %%cr3
        \\
        \\ mov %%cr0, %%eax
        \\ or $0x80000000, %%eax
        \\ mov %%eax, %%cr0
        :
        : [pdt_addr] "r" (new_cr3),
        : "eax", "cr0", "cr3"
    );
}

fn mapPages(vm: *ProcessVirtualMemory, start_phys_addr: u32, start_virt_add: VirtualAddress, num_bytes: u32) !void {
    const num_pages: u32 = @intFromFloat(std.math.ceil(@as(f32, @floatFromInt(num_bytes)) / 4096));
    const num_tables: u32 = @intFromFloat(std.math.ceil(@as(f32, @floatFromInt(num_pages)) / 1024));

    const start_table, const end_table = .{ start_virt_add.table(), start_virt_add.table() + num_tables };

    // Map page tables into the page dir until we've mapped all the bytes.
    var num_pages_mapped: u32 = 0;
    for (start_table..end_table) |page_table_i| {
        // Create a new page table and add it to the page dir.
        const page_table = try newPageTable();

        vm.page_tables[page_table_i] = page_table;
        vm.page_dir[page_table_i] = try PageDirectoryEntry.new(.{
            .present = true,
            .rw = true,
            .page_table = page_table,
        });

        // Fill the page table.
        for (0..page_table.len) |page_i| {
            // If we're done mapping pages, we still need to zero out the rest of the pages in the table.
            if (num_pages_mapped >= num_pages) {
                page_table[page_i] = .{ .present = false };
                continue;
            }

            // ...Otherwise, add a new page!
            page_table[page_i] = try Page.new(.{
                .present = true,
                .rw = true,
                .addr = start_phys_addr + (page_i * Page.NUM_BYES_MANAGED),
            });

            num_pages_mapped += 1;
        }
    }
}

fn newPageTable() !*PageTable {
    return &(try kstd.mem.kernel_heap_allocator.alignedAlloc(PageTable, 4096, 1))[0];
}

pub const ProcessVirtualMemory = struct {
    // Each process gets its own page directory and each page dir entry has an associated page table.
    //
    //   Page Directory -> Page Table Entry (Page) -> Offset in Page
    //   4MiB chunk     -> 4KiB slice of 4MiB      -> Offset into 4KiB
    //   City           -> Street                  -> Number on street
    page_dir: PageDirectory align(4096) = [_]PageDirectoryEntry{PageDirectoryEntry{ .rw = true }} ** 1024,
    page_tables: [1024]*PageTable = undefined,
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

    pub fn new(
        args: types.And(
            types.Exclude(@This(), .{"addr"}),
            struct { page_table: *PageTable },
        ),
    ) !@This() {
        const page_table_addr: u32 = @intFromPtr(args.page_table);

        // Make sure the PageTable address is properly aligned.
        std.debug.assert(try std.math.mod(u32, page_table_addr, 4096) == 0);

        return .{
            .present = args.present,
            .rw = args.rw,
            .user_accessible = args.user_accessible,
            .pwt = args.pwt,
            .cache_disable = args.cache_disable,
            .accessed = args.accessed,
            ._r1 = args._r1,
            .page_size = args.page_size,
            .meta = args.meta,
            .addr = @intCast(page_table_addr >> 12),
        };
    }

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

    pub fn new(
        args: types.And(
            types.Exclude(Page, .{"addr"}),
            struct { addr: u32 },
        ),
    ) !@This() {
        // Make sure the address is properly aligned.
        std.debug.assert(try std.math.mod(u32, args.addr, 4096) == 0);

        return .{
            .present = args.present,
            .rw = args.rw,
            .user_accessible = args.user_accessible,
            .pwt = args.pwt,
            .cache_disable = args.cache_disable,
            .accessed = args.accessed,
            .dirty = args.dirty,
            .pat = args.pat,
            .global = args.global,
            .meta = args.meta,
            .addr = @intCast(args.addr >> 12),
        };
    }

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
