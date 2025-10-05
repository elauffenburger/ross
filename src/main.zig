const std = @import("std");

const multiboot2 = @import("boot/multiboot2.zig");
const hw = @import("hw.zig");
const vga = hw.video.vga;
const kstd = @import("kstd.zig");
const proc = @import("kstd/proc.zig");
const proc_kbd = @import("procs/kbd.zig");
const proc_term = @import("procs/term.zig");

// Write multiboot2 header to .multiboot section.
pub export var multiboot2_header align(4) linksection(".multiboot") = blk: {
    const InfoRequest = multiboot2.tag.InformationRequestTag(&.{
        multiboot2.boot_info.FrameBufferInfo.Type,
        multiboot2.boot_info.VBEInfo.Type,
        multiboot2.boot_info.BootCommandLineInfo.Type,
    });

    const tags = &.{
        multiboot2.tag.FramebufferTag{
            .val = .{
                .width = 800,
                .height = 600,
            },
        },
        InfoRequest{
            .val = .{
                .flags = .{ .optional = true },
            },
        },
        multiboot2.tag.ModuleAlignmentTag{ .val = .{} },
        multiboot2.tag.EndTag{ .val = .{} },
    };

    var converted_tags = [_]multiboot2.tag.Tag{undefined} ** tags.len;
    for (tags, 0..) |tag, i| {
        converted_tags[i] = tag.tag();
    }

    break :blk multiboot2.header.headerBytes(&converted_tags);
};

extern var multiboot2_info_addr: u32;

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

pub export fn kmain() !void {
    // TODO: make sure a20 line is enabled; this _should_ happen after serial communication, but we need to make sure.

    // Verify the boot was successful.
    const boot_info = multiboot2.boot_info.parse(multiboot2_info_addr);

    // Init kernel memory management.
    kstd.mem.init();
    const kallocator = kstd.mem.kheap_allocator;

    // Init serial first so we can debug to screen.
    const serial_proof = try hw.io.serial.init();

    // Init kernel logging.
    try kstd.log.init(serial_proof);

    // Init VGA.
    try vga.init(kallocator, boot_info.frame_buffer.?);

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
    _ = try proc.init();

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
