const std = @import("std");

const hw = @import("hw.zig");
const vga = hw.video.vga;
const kstd = @import("kstd.zig");
const proc = @import("kstd/proc.zig");
const multiboot2 = @import("multiboot2.zig");
const proc_kbd = @import("procs/kbd.zig");
const proc_term = @import("procs/term.zig");

// Write multiboot2 header to .multiboot section.
// pub export var multiboot_header align(4) linksection(".multiboot") = blk: {
//     const flags = multiboot.Header.Flags.Align | multiboot.Header.Flags.MemInfo | multiboot.Header.Flags.VideoMode;

//     break :blk multiboot.Header{
//         .flags = flags,
//         .checksum = chk: {
//             const checksum_magic: i32 = @intCast(multiboot.Header.Magic);
//             const checksum_flags: i32 = @intCast(flags);

//             break :chk @bitCast(-(checksum_magic + checksum_flags));
//         },
//     };
// };
pub export var multiboot_header align(4) linksection(".multiboot") = multiboot2.Header(&[_]multiboot2.Tag{
    multiboot2.Tag{ .module_alignment = .{} },
    multiboot2.Tag{
        .framebuffer = .{
            .width = 1920,
            .height = 1080,
        },
    },
});

pub export fn _kmain() callconv(.naked) noreturn {
    // Set up kernel stack.
    kstd.mem.stack.reset();

    // Set up GDT and virtual memory before jumping into kmain since we need to map kernel space to the appropriate
    // segments and pages before we jump into it (or else our segment registers will be screwed up)!
    hw.gdt.init();

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
        hw.video.vga.printf("0x{x}\n", .{first_trace_addr.?});
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
    // Init kernel memory management.
    kstd.mem.init();

    // Init serial first so we can debug to screen.
    const serial_proof = try hw.io.serial.init();

    // Init kernel logging.
    try kstd.log.init(serial_proof);

    // Init VGA.
    vga.init();

    // Disable interrupts while we init components that configure interrupts.
    asm volatile ("cli");
    hw.cmos.maskNMIs();

    // Set up interrupts.
    const idt_proof = try hw.idt.init();
    const pic_proof = try hw.pic.init(idt_proof);

    // Init timers.
    try hw.timers.rtc.init(pic_proof);
    try hw.timers.pit.init(pic_proof);

    // Re-enable interrupts.
    hw.cmos.unmaskNMIs();
    asm volatile ("sti");

    // Enable PS/2 interfaces.
    try hw.io.ps2.init(pic_proof);

    // Init process control.
    const proc_proof = try proc.init();

    // Set up virtual memory.
    //
    // NOTE: we're identity-mapping the kernel so it's okay to set this up outside of _kmain (the physical and virtual addresses
    // of kernel code/data will be identical, so anything we've already set up by this point won't be invalidated).
    //
    // NOTE: a GPF will fire as soon as we enable paging, so this has to happen after we've set up interrupts!
    try hw.vmem.init(pic_proof, proc_proof);

    // Start up kernel processes.
    try proc.startKProc(&proc_kbd.main);
    try proc.startKProc(&proc_term.main);

    // Turn on process control.
    proc.start();

    while (true) {
        asm volatile ("hlt");
    }
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
