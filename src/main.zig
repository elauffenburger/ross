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

// Write multiboot header to .multiboot section.
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
    // Set up kernel stack.
    stack.resetTo(&stack.kernel_stack_bytes);

    // Set up GDT and virtual memory before jumping into kmain since we need to map kernel space to the appropriate
    // segments and pages before we jump into it (or else our segment registers will be screwed up)!
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

    // Set up virtual memory.
    //
    // NOTE: we're identity-mapping the kernel so it's okay to set this up outside of _kmain (the physical and virtual addresses
    // of kernel code/data will be identical, so anything we've already set up by this point won't be invalidated).
    vmem.init();

    // Set up PIC before setting up IDT since we're going to use an offset for IRQ handlers
    //
    // e.g. if we were to receive an IRQ 0x08 between setting up the IDT and setting up the PIC, then we'd triple-fault because we'd
    //      actually have the handler registered at 0x28 (if our offset is 0x20).
    pic.init();

    // Register interrupt handlers before we init components that rely on them.
    idt.init();

    // Init components.
    ps2.init();
    rtc.init();

    vga.writeStr("hello, zig!\n");

    while (true) {
        asm volatile ("hlt");
    }
}
