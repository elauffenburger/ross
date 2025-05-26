const std = @import("std");

const cmos = @import("cmos.zig");
const cpu = @import("cpu.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const kstd = @import("kstd.zig");
const multiboot = @import("multiboot.zig");
const pic = @import("pic.zig");
const ps2 = @import("ps2.zig");
const rtc = @import("rtc.zig");
const stack = @import("stack.zig");
const tables = @import("tables.zig");
const vga = @import("vga.zig");
const vmem = @import("vmem.zig");

// Write multiboot header before we do anything.
pub export var multiboot_header align(4) linksection(".multiboot") = blk: {
    const flags = multiboot.Header.Flags.Align | multiboot.Header.Flags.MemInfo | multiboot.Header.Flags.VideoMode;

    break :blk multiboot.Header{
        .flags = flags,
        .checksum = chk: {
            const checksum_magic: i32 = @intCast(multiboot.Header.Magic);
            const checksum_flags: i32 = @intCast(flags);

            break :chk @bitCast(-(checksum_magic + checksum_flags));
        },
    };
};

pub export fn _kmain() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    // Set up kernel stack.
    stack.resetTo(&stack.kernel_stack_bytes);

    // Bootstrap IDT.
    idt.init();

    // Bootstrap GDT/TSS.
    gdt.init();
    gdt.loadTss(.{
        .segment = gdt.GdtSegment.kernelData,
        .handle = &stack.kernel_stack_bytes,
    });

    // Reset kernel stack.
    stack.resetTo(&stack.kernel_stack_bytes);

    // Transfer to kmain.
    asm volatile (
        \\ jmp %[kmain:P]
        :
        : [kmain] "X" (&kmain),
    );
}

pub fn kmain() void {
    // Init VGA first so we can debug to screen.
    vga.init();

    // Init internals.
    pic.init();
    ps2.init();
    rtc.init();

    // Enable virtual memory.
    vmem.init();

    vga.writeStr("hello, zig!\n");

    // HACK: disable timers.
    pic.maskIRQ(0);

    while (true) {
        asm volatile ("hlt");
    }
}
