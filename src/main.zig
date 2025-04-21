const MultibootHeader = extern struct {
    const Self = @This();

    const Magic = 0x1BADB002;

    const Flags = struct {
        const Align: u32 = 1 << 0;
        const MemInfo: u32 = 1 << 1;
    };

    magicNumber: u32 = Self.Magic,
    flags: u32,
    checksum: u32,
};

// Write multiboot header.
export var multiboot_header align(4) linksection(".multiboot") = blk: {
    const flags = MultibootHeader.Flags.Align | MultibootHeader.Flags.MemInfo;

    break :blk MultibootHeader{
        .flags = flags,
        .checksum = chk: {
            const checksum_magic: i64 = @intCast(MultibootHeader.Magic);
            const checksum_flags: i64 = @intCast(flags);

            break :chk @intCast(((-(checksum_magic + checksum_flags)) & 0xFFFFFFFF));
        },
    };
};

pub export fn _kmain() callconv(.naked) noreturn {
    asm volatile (
        \\ push %ebp
        \\ jmp %[func:P]
        :
        : [func] "X" (&main),
    );
}

pub fn main() void {
    asm volatile (
        \\ mov ax "H"
        \\ int 10h
    );

    while (true) {}
}
