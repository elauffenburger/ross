const std = @import("std");

const cmos = @import("cmos.zig");
const cpu = @import("cpu.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const kb = @import("keyboard.zig");
const kstd = @import("kstd.zig");
const klog = @import("kstd/log.zig");
const multiboot = @import("multiboot.zig");
const pic = @import("pic.zig");
const proc = @import("proc.zig");
const proc_term = @import("procs/term.zig");
const ps2 = @import("ps2.zig");
const rtc = @import("rtc.zig");
const serial = @import("serial.zig");
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
    kstd.mem.stack.reset();

    // Set up GDT and virtual memory before jumping into kmain since we need to map kernel space to the appropriate
    // segments and pages before we jump into it (or else our segment registers will be screwed up)!
    gdt.init();

    // Reset kernel stack.
    kstd.mem.stack.reset();

    // Transfer to kmain.
    asm volatile (
        \\ jmp %[kmain:P]
        :
        : [kmain] "X" (&kmain),
    );
}

pub const panic = std.debug.FullPanic(panicHandler);

fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    vga.writeStr("panic @ ");
    if (first_trace_addr != null) {
        vga.printf("0x{x}\n", .{first_trace_addr.?});
    } else {
        vga.writeStr("??\n");
    }

    vga.writeStr(msg);
    vga.writeCh('\n');

    asm volatile ("cli");
    while (true) {
        asm volatile ("hlt");
    }

    unreachable;
}

pub fn kmain() !void {
    // Init kstd.
    kstd.init();
    klog.init();

    vga.init();

    // Disable interrupts while we init components that configure interrupts.
    asm volatile ("cli");
    cmos.maskNMIs();

    // Set up interrupts.
    idt.init();
    pic.init();

    // Init other components.
    rtc.init();

    // Re-enable interrupts.
    asm volatile ("sti");
    cmos.unmaskNMIs();

    // Init serial first so we can debug to screen.
    try serial.init();

    // Enable PS/2 interfaces.
    try ps2.init();

    try proc.init();

    // Set up virtual memory.
    //
    // NOTE: we're identity-mapping the kernel so it's okay to set this up outside of _kmain (the physical and virtual addresses
    // of kernel code/data will be identical, so anything we've already set up by this point won't be invalidated).
    //
    // NOTE: a GPF will fire as soon as we enable paging, so this has to happen after we've set up interrupts!
    try vmem.init();

    // Init keyboard interface.
    kb.init();

    klog.dbgf("&proc_term.main: 0x{x}\n", .{@intFromPtr(&proc_term.main)});
    // try proc.startKProc(&proc_term.main);

    while (true) {
        tick() catch |e| {
            klog.dbgf("error ticking {any}", .{e});
        };

        asm volatile ("hlt");
    }
}

fn tick() !void {
    try kb.tick();
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
