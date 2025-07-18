const std = @import("std");

const hw = @import("../hw.zig");
const kstd = @import("../kstd.zig");
const cpu = @import("cpu.zig");
const io = @import("io.zig");
const pic = @import("pic.zig");
const rtc = @import("timers.zig").rtc;

extern fn irq0_handler() callconv(.naked) void;

// Allocate space for the IDT.
var idt align(4) = [_]InterruptDescriptor{@bitCast(@as(u64, 0))} ** 256;

// Allocate a pointer to the memory location we pass to lidt.
var idtr: IdtDescriptor align(4) = @bitCast(@as(u48, 0));

pub const InitProof = kstd.types.UniqueProof();

pub fn init() !InitProof {
    const proof = try InitProof.new();

    // Add handlers.
    for (int_handlers) |handler| {
        switch (handler.kind) {
            .exc => {
                addIdtEntry(handler.int_num, .trap32bits, .kernel, handler.handler);
            },
            .irq => {
                addIdtEntry(pic.irq_offset + handler.int_num, .interrupt32bits, .kernel, handler.handler);
            },
        }
    }

    // Add native handlers.
    for (native_irq_handlers) |handler| {
        addIdtEntry(pic.irq_offset + handler.int_num, .interrupt32bits, .kernel, handler.handler);
    }

    // Load IDT.
    loadIdt();

    return proof;
}

fn addIdtEntry(index: u8, gate_type: @FieldType(InterruptDescriptor, "gate_type"), privilegeLevel: cpu.PrivilegeLevel, handler: *const fn () callconv(.naked) void) void {
    const handler_addr = @intFromPtr(handler);

    idt[index] = InterruptDescriptor{
        .offset1 = @truncate(handler_addr),
        .offset2 = @truncate(handler_addr >> 16),
        .selector = .{
            .index = @intFromEnum(hw.gdt.GdtSegment.kernelCode),
            .rpl = .kernel,
            .ti = .gdt,
        },
        .gate_type = gate_type,
        .dpl = privilegeLevel,
    };
}

fn loadIdt() void {
    idtr = .{
        .limit = (idt.len * @sizeOf(InterruptDescriptor)) - 1,
        .addr = @intFromPtr(&idt),
    };

    asm volatile (
        \\ lidt %[idtr_addr]
        :
        : [idtr_addr] "p" (@intFromPtr(&idtr)),
    );
}

const native_irq_handlers = [_]struct {
    int_num: u8,
    handler: *const fn () callconv(.naked) void,
}{
    .{
        .int_num = 0,
        .handler = irq0_handler,
    },
};

// PIT
export fn on_irq0() void {
    kstd.time.tick();
    kstd.proc.tick();

    pic.eoi(0);
}

const int_handlers = GenInterruptHandlers(struct {
    pub fn exc05() void {
        kstd.log.dbg("shit");
    }

    // Double Fault
    pub fn exc08(err_code: u32) void {
        kstd.log.dbgf("double shit: {any}", .{err_code});
    }

    // General Protection Fault
    pub fn exc13(err_code: u32) void {
        _ = err_code; // autofix
    }

    // Page Fault
    pub fn exc14(err_code: u32) void {
        _ = err_code; // autofix
    }

    // PS/2 keyboard
    pub fn irq1() void {
        // TODO: handle this better.
        io.ps2.port1.recv() catch {};
    }

    // Serial: COM2, COM4
    pub fn irq3() void {
        io.serial.onIrq(.com2com4);
    }

    // Serial: COM1, COM3
    pub fn irq4() void {
        io.serial.onIrq(.com1com3);
    }

    // RTC
    pub fn irq8() void {
        rtc.tick();

        // We have to read from register C even if we don't use the value or the RTC won't fire the IRQ again!
        _ = rtc.regc();
    }

    // PS/2 mouse
    pub fn irq12() void {
        // TODO: handle this better.
        io.ps2.port2.recv() catch {};
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
fn GenInterruptHandlers(orig_handlers: type) [@typeInfo(orig_handlers).@"struct".decls.len]GeneratedInterruptHandler {
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

        // Extract the handler fn args from fn name.
        const int_num = std.fmt.parseInt(u8, decl.name[3..], 10) catch {
            @compileError(std.fmt.comptimePrint("error parsing interrupt handler name as int: {s}", .{decl.name}));
        };

        const fn_has_err_param = blk: {
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

        // Figure out if the interrupt handler should have an error parameter.
        switch (exc_or_irq) {
            .exc => {
                switch (int_num) {
                    8, 10...14, 17, 21 => {
                        if (!fn_has_err_param) {
                            @compileError(std.fmt.comptimePrint("exception handler {d} does not have an error parameter but the interrupt number receives one", .{int_num}));
                        }
                    },
                    else => {
                        if (fn_has_err_param) {
                            @compileError(std.fmt.comptimePrint("exception handler {d| has an error parameter but the interrupt number does not receive an error code", .{int_num}));
                        }
                    },
                }
            },
            .irq => {
                if (fn_has_err_param) {
                    @compileError(std.fmt.comptimePrint("irq handler {d} has an error parameter but irq handlers do not receive error codes", .{int_num}));
                }
            },
        }

        const Wrapper = blk: {
            if (!fn_has_err_param) {
                break :blk struct {
                    pub fn wrapper() void {
                        // Call actual handler.
                        @call(.auto, @field(orig_handlers, decl.name), .{});

                        // Trigger EOI on PIC.
                        pic.eoi(int_num);
                    }
                };
            }

            break :blk struct {
                pub fn wrapper() void {
                    const err = asm volatile (
                        \\ pop %%eax
                        : [err] "={eax}" (-> u32),
                        :
                        : "eax"
                    );

                    // Call actual handler.
                    @call(.auto, @field(orig_handlers, decl.name), .{err});

                    // Trigger EOI on PIC.
                    pic.eoi(int_num);
                }
            };
        };

        // HACK: we're going to hardcode how to handle PIT interrupts, but let's, uh, not do that forever.
        comptime ({
            const Handler = blk: {
                if (int_num == 0) {
                    break :blk struct {
                        pub fn handler() callconv(.naked) void {
                            // Save registers before calling handler.
                            //
                            // NOTE: the direction flag must be clear on entry for SYS V calling conv.
                            asm volatile (
                                \\ pusha
                                \\ cld
                                ::: "eax", "ecx", "edx", "ebx", "esi", "edi", "memory");

                            // Call actual handler.
                            asm volatile (std.fmt.comptimePrint(
                                    \\ push $[.after_gen_int_handler_{s}]
                                    \\ jmp %[wrapper:P]
                                    \\ .after_gen_int_handler_{s}:
                                ,
                                    .{ decl.name, decl.name },
                                )
                                :
                                : [wrapper] "p" (&Wrapper.wrapper),
                                  [int_num] "X" (int_num),
                            );

                            // Restore registers, modify eflags, and return from interrupt handler.
                            asm volatile (
                                \\ popa
                                \\ iret
                                ::: "eax", "ecx", "edx", "ebx", "esi", "edi", "memory");
                        }
                    };
                }

                break :blk struct {
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
                                \\ push $[.after_gen_int_handler_{s}]
                                \\ jmp %[wrapper:P]
                                \\ .after_gen_int_handler_{s}:
                            ,
                                .{ decl.name, decl.name },
                            )
                            :
                            : [wrapper] "p" (&Wrapper.wrapper),
                              [int_num] "X" (int_num),
                        );

                        // Restore registers and return from interrupt handler.
                        asm volatile (
                            \\ popa
                            \\ iret
                        );
                    }
                };
            };

            generated_handlers[i] = .{
                .int_num = int_num,
                .kind = exc_or_irq,
                .handler = Handler.handler,
            };
        });
    }

    return generated_handlers;
}

pub const InterruptDescriptor = packed struct(u64) {
    offset1: u16,
    selector: cpu.SegmentSelector,
    _r1: u8 = 0,
    gate_type: enum(u4) {
        task = 5,
        interrupt16bits = 6,
        trap16bits = 7,
        interrupt32bits = 14,
        trap32bits = 15,
    },
    _r2: u1 = 0,
    dpl: cpu.PrivilegeLevel,
    present: bool = true,
    offset2: u16,
};

pub const IdtDescriptor = packed struct(u48) {
    limit: u16,
    addr: u32,
};
