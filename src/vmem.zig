const std = @import("std");

const kstd = @import("kstd.zig");
const proc = @import("proc.zig");
const types = @import("types.zig");
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

pub fn init() !void {
    vga.printf("page_dir_addr: 0x{x}.....................\n", .{@intFromPtr(&kernel_proc.vm.page_dir)});

    // Identity-map the kernel into the kernel_proc.
    try identityMapKernel(&kernel_proc.vm);

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

fn identityMapKernel(vm: *ProcessVirtualMemory) !void {
    // Init page directory.
    for (0..vm.page_dir.len) |i| {
        vm.page_dir[i] = .{
            .rw = true,
        };
    }

    const kernel_size = kernelSize();

    // Map page tables into the page dir until we've mapped the entire kernel.
    var bytes_mapped: u32 = 0;
    var page_table_i: u32 = 0;
    fill_page_dir: while (true) {
        // Create a new page table and add it to the page dir.
        const page_table = try newPageTable();

        vm.page_tables[page_table_i] = page_table;
        vm.page_dir[page_table_i] = try PageDirectoryEntry.new(.{
            .present = true,
            .rw = true,
            .pageTable = page_table,
        });

        // Fill the page table.
        for (0..1024) |page_i| {
            if (bytes_mapped >= kernel_size) {
                break :fill_page_dir;
            }

            page_table[page_i] = try Page.new(.{
                .present = true,
                .rw = true,
                .addr = page_i * 4096,
            });

            bytes_mapped += 4096;
        }

        page_table_i += 1;
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
    page_dir: PageDirectory align(4096) = undefined,
    page_tables: [1024]*PageTable = undefined,
};

const VirtualAddress = packed struct(u32) {
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

const PageDirectory = [1024]PageDirectoryEntry;
const PageTable = [1024]Page;

// See https://wiki.osdev.org/Paging#32-bit_Paging_(Protected_Mode) for more info!
const PageDirectoryEntry = packed struct(u32) {
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

    pub fn new(
        args: types.And(
            types.Exclude(@This(), .{"addr"}),
            struct { pageTable: *PageTable },
        ),
    ) !@This() {
        const page_table_addr: u32 = @intFromPtr(args.pageTable);

        // Make sure the PageTable address is properly aligned.
        std.debug.assert(try std.math.mod(u32, page_table_addr, 4096) == 0);

        return .{
            .present = args.present,
            .rw = args.rw,
            .userAccessible = args.userAccessible,
            .pwt = args.pwt,
            .cacheDisable = args.cacheDisable,
            .accessed = args.accessed,
            ._r1 = args._r1,
            .pageSize = args.pageSize,
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
            .userAccessible = args.userAccessible,
            .pwt = args.pwt,
            .cacheDisable = args.cacheDisable,
            .accessed = args.accessed,
            .dirty = args.dirty,
            .pat = args.pat,
            .global = args.global,
            .meta = args.meta,
            .addr = @intCast(args.addr >> 12),
        };
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
