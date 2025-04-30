const kstd = @import("kstd.zig");
const vga = @import("vga.zig");
const multiboot = @import("multiboot.zig");
const descriptors = @import("descriptors.zig");

// Write multiboot header before we do anything.
export var multiboot_header align(4) linksection(".multiboot") = blk: {
    const flags = multiboot.MultibootHeader.Flags.Align | multiboot.MultibootHeader.Flags.MemInfo | multiboot.MultibootHeader.Flags.VideoMode;

    break :blk multiboot.MultibootHeader{
        .flags = flags,
        .checksum = chk: {
            const checksum_magic: i64 = @intCast(multiboot.MultibootHeader.Magic);
            const checksum_flags: i64 = @intCast(flags);

            break :chk -(checksum_magic + checksum_flags);
        },
    };
};

// Reserve 16K for the stack in the .bss section.
const STACK_SIZE = 16 * 1024;
var stack_bytes: [STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

// Create the GDT.
var gdt = descriptors.Gdt{};

inline fn initStack() void {
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        :
        : [stack_top] "i" (@as([*]align(4) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes))),
    );
}

pub export fn _kmain() callconv(.naked) noreturn {
    initStack();

    asm volatile (
        \\ call %[kmain:P]
        :
        : [kmain] "X" (&kmain),
    );
}

fn kmain() callconv(.c) void {
    vga.init();

    vga.writeStr("hello, zig!\n");

    while (true) {}
}
