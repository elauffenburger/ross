const vga = @import("vga.zig");

const MultibootHeader = extern struct {
    const Self = @This();

    const Magic = 0x1BADB002;

    const Flags = struct {
        const Align: u32 = 1 << 0;
        const MemInfo: u32 = 1 << 1;
        const VideoMode: u32 = 1 << 2;
    };

    const VideoMode = extern struct {
        modeType: u32,
        width: u32,
        height: u32,
        depth: u32,
    };

    magicNumber: i32 = Self.Magic,
    flags: i32,
    checksum: i32,
    rawAddrInfo: [4]u32 = undefined,
    video: VideoMode = undefined,
};

// Write multiboot header.
export var multiboot_header align(4) linksection(".multiboot") = blk: {
    const flags = MultibootHeader.Flags.Align | MultibootHeader.Flags.MemInfo | MultibootHeader.Flags.VideoMode;

    break :blk MultibootHeader{
        .flags = flags,
        .checksum = chk: {
            const checksum_magic: i64 = @intCast(MultibootHeader.Magic);
            const checksum_flags: i64 = @intCast(flags);

            break :chk -(checksum_magic + checksum_flags);
        },
    };
};

const STACK_SIZE = 16 * 1024;
var stack_bytes: [STACK_SIZE]u8 align(16) linksection(".bss") = undefined;

pub export fn _kmain() callconv(.naked) noreturn {
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        \\ call %[kmain:P]
        :
        : [stack_top] "i" (@as([*]align(16) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
          [kmain] "X" (&kmain),
    );
}

pub fn kmain() callconv(.c) void {
    vga.initialize();
    vga.puts("hello, world!");

    while (true) {}
}
