// See https://wiki.osdev.org/Paging#32-bit_Paging_(Protected_Mode) for more info!
pub const PageDirectoryEntry = packed struct(u32) {
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

pub const ProcessPageDirectory = extern struct {
    // Each process gets its own page directory.
    pageDirectory: [1024]PageDirectoryEntry,

    // Each entry in the directory maps to a page table.
    pageTables: [1024]PageTable,

    pub const PageTable = extern struct {
        // Each entry in a page table is initially marked not present.
        pageTable: [1024]PageTableEntry = [_]PageTableEntry{@bitCast(@as(u32, 0))} ** 1024,
    };
};
