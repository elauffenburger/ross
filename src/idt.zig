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
    // Add handlers.
    for (int_handlers.handlers) |handler| {
        switch (handler.kind) {
            .exc => {
                addIdtEntry(handler.int_num, .trap32bits, .kernel, handler.handler);
            },
            .irq => {
                addIdtEntry(pic.irqOffset + handler.int_num, .interrupt32bits, .kernel, handler.handler);
            },
        }
    }

    // Load IDT.
    loadIdt();
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

fn loadIdt() void {
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

const int_handlers = GenInterruptHandlers(struct {
    // pub fn exc13(err_code: u32) void {
    //     _ = err_code; // autofix
    // }

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

const GeneratedInterruptHandler = struct {
    int_num: u8,
    kind: enum { exc, irq },
    handler: *const fn () callconv(.naked) void,
};

// When an interrupt handler is triggered, it's in a very limit naked context (no stack, no real caller, must return via IRET, etc.).
// That means our handlers can't call functions that aren't inline (and even then, that has some weird repercussions, especially
// when calling inline assembly (mostly because I'm not always 100% sure how to do it correctly based on the context, RIP)).
//
// In order to get around this and use regular Zig in our interrupt handlers (which we'd like to do!), GenInterruptHandlers will
// take a struct that defines our interrupt handlers and return an array of (possibly null) handler functions that wrap the
// interrupt handlers in the provided struct with trampolining from a naked context into a normal Zig context!
//
// The provided struct must contain functions that have one of the following signatures:
//   - `fn excXX() void` where `XX` is the interrupt number
//   - `fn excXX(err_code: u32) void` where `XX` is the interrupt number and err_code is the 32-bit error code that will be popped off the stack.
//   - `fn irqXX() void` where `XX` is the IRQ number (e.g. `irq01` for a keyboard input handler).
//
// TODO: we don't actually have to return an array that has the max size of the table; we could figure out how many fns are on the input struct and only return that many (and use a struct that is basically `struct { intNum: u8, handler: const* fn() void }`).
fn GenInterruptHandlers(orig_handlers: type) type {
    const orig_handlers_type = @typeInfo(orig_handlers).@"struct";

    var generated_handlers = [_]GeneratedInterruptHandler{undefined} ** orig_handlers_type.decls.len;

    for (orig_handlers_type.decls, 0..orig_handlers_type.decls.len) |decl, i| {
        // Check if this is an exception or interrupt handler.
        const exc_or_irq: @FieldType(GeneratedInterruptHandler, "kind") = blk: {
            if (std.mem.startsWith(u8, decl.name, "exc")) {
                break :blk .exc;
            }

            if (std.mem.startsWith(u8, decl.name, "irq")) {
                break :blk .irq;
            }

            @compileError(std.fmt.comptimePrint("found decl in struct that didn't start with exc or irq: {s}", .{decl.name}));
        };

        // Extract the handler number.
        const int_num = std.fmt.parseInt(u8, decl.name[3..], 10) catch |err| {
            @compileError(std.fmt.comptimePrint("error parsing interrupt handler name as int: {s}", .{err}));
        };

        const has_err = blk: {
            switch (@typeInfo(@TypeOf(@field(orig_handlers, decl.name)))) {
                .@"fn" => |func| {
                    switch (exc_or_irq) {
                        .exc => {
                            switch (func.params.len) {
                                0 => break :blk false,
                                1 => {
                                    if (func.params[0].type.? != u32) {
                                        @compileError(std.fmt.comptimePrint("exc handler {s} has a non-u32 param", .{decl.name}));
                                    }

                                    break :blk true;
                                },
                                else => @compileError(std.fmt.comptimePrint("exc handler {s} must have either 0 params or 1 param of type u8", .{decl.name})),
                            }
                        },
                        .irq => {
                            if (func.params.len != 0) {
                                @compileError(std.fmt.comptimePrint("irq handler {s} must have either 0 params", .{decl.name}));
                            }

                            break :blk false;
                        },
                    }
                },
                else => @compileError(std.fmt.comptimePrint("interrupt handler {s} was not a fn", .{decl.name})),
            }
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
                asm volatile (std.fmt.comptimePrint(
                        \\ push $[.after_gen_int_handler_{d}]
                        \\ jmp %[wrapper:P]
                        \\ .after_gen_int_handler_{d}:
                    ,
                        .{ int_num, int_num },
                    )
                    :
                    : [wrapper] "p" (&wrapper),
                      [int_num] "X" (int_num),
                );

                // Restore registers and return from interrupt handler.
                asm volatile (
                    \\ popa
                    \\ iret
                );
            }

            pub fn wrapper() void {
                const args = blk: {
                    if (!has_err) {
                        break :blk .{};
                    }

                    const err = asm volatile (
                        \\ pop %%eax
                        : [err] "={eax}" (-> u32),
                        :
                        : "eax"
                    );

                    break :blk .{err};
                };

                // Call actual handler.
                @call(.auto, @field(orig_handlers, decl.name), args);

                // Trigger EOI on PIC.
                pic.eoi(int_num);
            }
        };

        generated_handlers[i] = .{
            .int_num = int_num,
            .kind = exc_or_irq,
            .handler = Handler.handler,
        };
    }

    const result_handlers = generated_handlers;
    return struct {
        pub var handlers: @TypeOf(generated_handlers) = result_handlers;
    };
}
