const std = @import("std");

const cpu = @import("cpu.zig");
const pic = @import("pic.zig");
const ps2 = @import("ps2.zig");
const rtc = @import("rtc.zig");
const tables = @import("tables.zig");

// Allocate space for the IDT.
var idt = [_]tables.InterruptDescriptor{@bitCast(@as(u64, 0))} ** 256;

// Allocate a pointer to the memory location we pass to lidt.
var idtr: *tables.IdtDescriptor = undefined;

pub inline fn init() void {
    @setRuntimeSafety(false);

    // Add IRQ handlers.
    inline for (irqHandlers, 0..irqHandlers.len) |handler, irq_num| {
        if (handler != null) {
            const entry_index = irq_num + pic.irqOffset;
            addIdtEntry(entry_index, .interrupt32bits, .kernel, handler.?);
        }
    }

    // Load the IDT.
    const idtr_addr = asm volatile (
        \\ push %[idt_size]
        \\ push %[idt_addr]
        \\ call load_idtr
        : [idtr_addr] "={eax}" (-> u32),
        : [idt_addr] "X" (@intFromPtr(&idt)),
          [idt_size] "X" ((idt.len * @sizeOf(tables.InterruptDescriptor)) - 1),
    );

    idtr = @ptrFromInt(idtr_addr);
}

inline fn addIdtEntry(index: u8, gateType: tables.InterruptDescriptor.GateType, privilegeLevel: cpu.PrivilegeLevel, handler: *const fn () callconv(.naked) void) void {
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

const NumIrqHandlers = 256 - 32;
fn GenIrqHandlers(origIrqs: type) [NumIrqHandlers]?*const fn () callconv(.naked) void {
    var handlers = [_]?*const fn () callconv(.naked) void{null} ** NumIrqHandlers;

    const orig_irqs_type = @typeInfo(origIrqs);
    for (orig_irqs_type.@"struct".decls) |decl| {
        if (!std.mem.startsWith(u8, decl.name, "irq")) {
            continue;
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
                    \\ call %[func:P]
                    :
                    : [func] "X" (&@field(origIrqs, decl.name)),
                );

                // Trigger EOI on PIC.
                pic.eoi(irq_num);

                // Restore registers and return from INT handler.
                asm volatile (
                    \\ popa
                    \\ iret
                );
            }
        };

        handlers[irq_num] = &Handler.handler;
    }

    return handlers;
}
