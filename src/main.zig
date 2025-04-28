const kstd = @import("kstd.zig");
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

// Write multiboot header before we do anything.
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

// Reserve 16K for the stack in the .bss section.
const STACK_SIZE = 16 * 1024;
var stack_bytes: [STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

pub export fn _kmain() callconv(.naked) noreturn {
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        \\ call %[kmain:P]
        :
        : [stack_top] "i" (@as([*]align(4) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
          [kmain] "X" (&kmain),
    );
}

pub fn kmain() callconv(.c) void {
    vga.init();

    vga.writeStr("hello, world!\n");

    {
        const old_eflags: u32 = asm volatile (
            \\ pushf
            \\ pop %%eax
            : [ret] "={eax}" (-> u32),
        );

        vga.printf("flags: {b}\n", .{old_eflags});

        const new_eflags: u32 = asm volatile (
            \\ pushf
            \\ pop %%eax
            \\ orl $0x0400, %%eax
            \\ push %%eax
            \\ popf
            : [ret] "={eax}" (-> u32),
        );

        vga.printf("new flags: {b}\n", .{new_eflags});

        asm volatile (
            \\ movb $0x00, %%ah
            \\ movb $0x11, %%al
            \\ int $0x10
        );
    }

    {
        const asm_res = asm volatile (
            \\ movl %%cr0, %%eax
            : [ret] "={eax}" (-> u32),
        );

        var asm_res_str: [16]u8 = undefined;
        @memset(&asm_res_str, 0);
        kstd.c.itoa(asm_res, &asm_res_str);

        vga.printf("vga mode: {s}", .{asm_res_str});
    }

    while (true) {}
}
