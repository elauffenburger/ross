const std = @import("std");

const cpu = @import("cpu.zig");
const pic = @import("pic.zig");
const ps2 = @import("ps2.zig");
const rtc = @import("rtc.zig");
const tables = @import("tables.zig");

// Allocate space for the IDT.
var idt align(4) = [_]tables.InterruptDescriptor{@bitCast(@as(u64, 0))} ** 256;

// Allocate a pointer to the memory location we pass to lidt.
var idtr: tables.IdtDescriptor align(4) = @bitCast(@as(u48, 0));

pub fn init() void {
    // Add IRQ handlers.
    for (irqHandlers, 0..irqHandlers.len) |handler, irq_num| {
        if (handler != null) {
            const entry_index: u8 = @intCast(irq_num + pic.irqOffset);
            addIdtEntry(entry_index, .interrupt32bits, .kernel, handler.?);
        }
    }

    loadIdtr();
}

fn loadIdtr() void {
    idtr = .{
        .limit = (idt.len * @sizeOf(tables.InterruptDescriptor)) - 1,
        .addr = @intFromPtr(&idt),
    };

    asm volatile (
        \\ cli
        \\ lidt %[idtr_addr]
        \\ sti
        :
        : [idtr_addr] "p" (@intFromPtr(&idtr)),
    );
}

fn addIdtEntry(index: u8, gateType: tables.InterruptDescriptor.GateType, privilegeLevel: cpu.PrivilegeLevel, handler: *const fn () callconv(.naked) void) void {
    const handler_addr = @intFromPtr(handler);

    idt[index] = tables.InterruptDescriptor{
        .offset1 = @truncate(handler_addr),
        .offset2 = @truncate(handler_addr >> 16),
        .selector = .{
            // .index = @intFromEnum(GdtSegment.kernelCode),
            .index = 1,
            .rpl = .kernel,
            .ti = .gdt,
        },
        .gateType = gateType,
        .dpl = privilegeLevel,
    };
}

const irqHandlers = GenIrqHandlers(struct {
    pub fn irq0() void {}

    pub fn irq1() void {
        ps2.port1.recv();
    }

    pub fn irq8() void {
        rtc.tick();

        // We have to read from register C even if we don't use the value or the RTC won't fire the IRQ again!
        _ = rtc.regc();
    }

    pub fn irq12() void {
        ps2.port2.recv();
    }
});

// When an IRQ handler is triggered, it's in a very limit naked context (no stack, no real caller, must return via IRET, etc.).
// That means our handlers can't call functions that aren't inline (and even then, that has some weird repercussions, especially
// when calling inline assembly (mostly because I'm not always 100% sure how to do it correctly based on the context, RIP)).
//
// In order to get around this and use regular Zig in our interrupt handlers (which we'd like to do!), GenIrqHandlers will
// take a struct that defines our interrupt handlers and return an array of (possibly null) handler functions that wrap the
// IRQ handlers in the provided struct with trampolining from a naked context into a normal Zig context!
//
// The provided struct must contain functions that have the signature `fn irqXX() void` where `XX` is the IRQ number (e.g. `irq01`
// for a keyboard input handler).
//
// TODO: verify there are only irqXX fns in the struct.
// TODO: verify the signatures of the fns.
// TODO: we don't actually have to return an array that has the max size of IRQs; we could figure out how many fns are on the input struct and only return that many (and use a struct that is basically `struct { irqNum: u8, handler: const* fn() void }`).
fn GenIrqHandlers(origIrqs: type) [256 - 32]?*const fn () callconv(.naked) void {
    var handlers = [_]?*const fn () callconv(.naked) void{null} ** (256 - 32);

    const orig_irqs_type = @typeInfo(origIrqs);
    for (orig_irqs_type.@"struct".decls) |decl| {
        if (!std.mem.startsWith(u8, decl.name, "irq")) {
            @compileError(std.fmt.comptimePrint("found decl in struct that didn't start with irq: {s}", .{decl.name}));
        }

        const irq_num = std.fmt.parseInt(u8, decl.name[3..], 10) catch |err| {
            @compileError(std.fmt.comptimePrint("error parsing irq handler name as int: {s}", .{err}));
        };

        const Handler = struct {
            pub fn handler() callconv(.naked) void {
                // Save registers before calling handler.
                //
                // NOTE: the direction flag must be clear on entry for SYS V calling conv.
                asm volatile (
                    \\ pusha
                    \\ cld
                );

                // Call actual handler.
                asm volatile (
                    \\ call %[wrapper:P]
                    :
                    : [wrapper] "X" (&wrapper),
                );

                // Restore registers and return from INT handler.
                asm volatile (
                    \\ popa
                    \\ iret
                );
            }

            pub fn wrapper() void {
                // Call actual handler.
                @call(.auto, &@field(origIrqs, decl.name), .{});

                // Trigger EOI on PIC.
                pic.eoi(irq_num);
            }
        };

        handlers[irq_num] = &Handler.handler;
    }

    return handlers;
}
