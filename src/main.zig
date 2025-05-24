const cpu = @import("cpu.zig");
const kstd = @import("kstd.zig");
const multiboot = @import("multiboot.zig");
const pic = @import("pic.zig");
const ps2 = @import("ps2.zig");
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

// NOTE: if you rearrange the entries in the GDT, make sure to update GdtSegment!
const GdtSegment = enum(u4) {
    null = 0,
    kernelCode = 1,
    kernelData = 2,
    tss = 3,
    userCode = 4,
    userData = 5,
};

// Create the GDT.
// NOTE: if you rearrange the entries in the GDT, make sure to update GdtSegment!
var gdt align(4) = [_]tables.GdtSegmentDescriptor{
    // Mandatory null entry.
    @bitCast(@as(u64, 0)),

    // Kernel Mode Code Segment.
    tables.GdtSegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .code = @bitCast(@as(u8, 0x9a)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // Kernel Mode Data Segment.
    tables.GdtSegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .data = @bitCast(@as(u8, 0x92)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // Kernel TSS placeholder.
    // NOTE: this will be created for real when we init the GDT.
    @bitCast(@as(u64, 0)),

    // User Mode Code Segment.
    tables.GdtSegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .code = @bitCast(@as(u8, 0xfa)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),

    // User Mode Data Segment.
    tables.GdtSegmentDescriptor.new(.{
        .base = 0,
        .limit = 0xf_ffff,
        // TODO: convert these to structured values.
        .access = .{
            .data = @bitCast(@as(u8, 0xf2)),
        },
        .flags = @bitCast(@as(u4, 0xc)),
    }),
};

// Allocate a pointer to the memory location we pass to lgdt.
var gdtr: *tables.GdtDescriptor = undefined;

// Allocate space for our TSS.
var tss: tables.TaskStateSegment = @bitCast(@as(u864, 0));

// Allocate space for the IDT.
var idt = [_]tables.InterruptDescriptor{@bitCast(@as(u64, 0))} ** 256;

// Allocate a pointer to the memory location we pass to lidt.
var idtr: *tables.IdtDescriptor = undefined;

// Reserve 16K for the kernel stack in the .bss section.
const KERNEL_STACK_SIZE = 16 * 1024;
var kernel_stack_bytes: [KERNEL_STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

// Reserve 16K for the userspace stack in the .bss section.
const STACK_SIZE = 16 * 1024;
var user_stack_bytes: [STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

// Declare a hook to grab __kernel_size from the linker script.
extern const __kernel_size: u8;
inline fn kernelSize() u32 {
    return @as(u32, @intFromPtr(&__kernel_size));
}

pub export fn _kmain() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    // Set up kernel stack.
    {
        asm volatile (
            \\ movl %[stack_top], %%esp
            \\ movl %%esp, %%ebp
            :
            : [stack_top] "X" (stackTop(&kernel_stack_bytes)),
        );
    }

    // Set up GDT.
    {
        // Add TSS entry to GDT.
        gdt[@intFromEnum(GdtSegment.tss)] = tables.GdtSegmentDescriptor.new(.{
            .base = @intFromPtr(&tss),
            .limit = @bitSizeOf(tables.TaskStateSegment),
            // TODO: convert these to structured values.
            .access = .{
                .system = @bitCast(@as(u8, 0x89)),
            },
            .flags = .{
                .size = .@"32bit",
                .granularity = .page,
            },
        });

        // Load GDT!
        const gdtr_pointer = asm volatile (
            \\ push %[limit]
            \\ push %[addr]
            \\ call load_gdtr
            : [gdtr_addr] "={eax}" (-> usize),
            : [addr] "X" (@as(u32, @intFromPtr(&gdt))),
              [limit] "X" (@as(u16, @as(i16, @sizeOf(@TypeOf(gdt))) - 1)),
        );
        gdtr = @ptrFromInt(gdtr_pointer);
    }

    // Load the IDT.
    loadIdt();

    // Load kernel TSS.
    reloadTss(
        GdtSegment.tss,
        .{
            .segment = GdtSegment.kernelData,
            .handle = &kernel_stack_bytes,
        },
    );

    // Reset kernel stack.
    {
        asm volatile (
            \\ movl %[stack_top], %%esp
            \\ movl %%esp, %%ebp
            :
            : [val] "X" (@as(u8, 42)),
              [stack_top] "X" (stackTop(&kernel_stack_bytes)),
        );
    }

    // Transfer to kmain.
    asm volatile (
        \\ jmp %[kmain:P]
        :
        : [kmain] "X" (&kmain),
    );
}

pub fn kmain() void {
    vga.init();

    // Init PICs.
    pic.init();

    // Init PS/2 interface.
    ps2.init();

    // Set up paging.
    {
        const kernel_size: f32 = @floatFromInt(kernelSize());
        const bytes_per_page: f32 = @floatFromInt(vmem.PageTableEntry.NumBytesManaged);
        const num_pages_for_kernel: u32 = @intFromFloat(@ceil(kernel_size / bytes_per_page));

        // Identity Map the first 1MiB.
        vmem.mapKernelPages(&pagerProc.vm, .kernel, 0, .{ .addr = 0 }, 0x400);

        // Map the Kernel into the higher half of memory.
        vmem.mapKernelPages(&pagerProc.vm, .kernel, 0x100000, .{ .addr = 0xC0000000 }, num_pages_for_kernel);
    }

    vga.writeStr("hello, zig!\n");

    vga.printf(
        \\ gdtr:  {{ addr: 0x{x}, limit: 0x{x} }}
        \\ idtr:  {{ addr: 0x{x}, limit: 0x{x} }}
        \\ stack: {{ base: {x}, top: {x} }}
        \\
    ,
        .{
            gdtr.addr,
            gdtr.limit,
            idtr.addr,
            idtr.limit,
            @as(u32, @intFromPtr(&kernel_stack_bytes)),
            stackTop(&kernel_stack_bytes),
        },
    );

    asm volatile ("int $3");

    vga.printf("after int3!\n", .{});

    asm volatile ("int $42");

    while (true) {}
}

inline fn reloadTss(tssSegment: GdtSegment, stack: struct { segment: GdtSegment, handle: []align(4) u8 }) void {
    tss.ss0 = 8 * @as(u32, @intFromEnum(stack.segment));

    // NOTE: we're sharing a single TSS right now, so we need to disable multitasking
    // or else we could end up granting access to the kernel stack in userspace (which would be bad)!
    tss.esp0 = stackTop(stack.handle);

    // Set the offset from the base of the TSS to the IO permission bit map.
    // HACK: I really have no idea _why_ this is even necessary (or when it wouldn't be 104);
    //       we should take a look at this later!
    tss.iopb = 104;

    // Load tss.
    asm volatile (
        \\ mov %[tss_gdt_offset], %%ax
        \\ ltr %%ax
        :
        : [tss_gdt_offset] "X" (8 * @as(u32, @intFromEnum(tssSegment))),
    );

    // TODO: handle switching stacks.
    //
    // I'm guessing this will look something like:
    //   - if already in the requested stack, is that an error?
    //   - if switching to kernel space, _is_ there a stack?
    //   - if swtiching back to userspace, restore previous stack pointers
    //     - is that just esp and ebp?
    //     - does ltr handle segmentation registers?
}

inline fn loadIdt() void {
    @setRuntimeSafety(false);

    addIdtEntry(@intFromEnum(tables.IdtEntry.bp), .interrupt32bits, .kernel, &handleInt3);

    addIrqHandler(0, &handleIrq0);
    addIrqHandler(1, &handleIrq1);
    addIrqHandler(12, &handleIrq12);

    // HACK: just for testings stuff!
    addIdtEntry(42, .interrupt32bits, .kernel, &handleInt42);

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

inline fn addIrqHandler(irq: u8, handler: *const fn () callconv(.naked) void) void {
    const index = irq + pic.irqOffset;

    addIdtEntry(index, .interrupt32bits, .kernel, handler);
}

inline fn addIdtEntry(index: u8, gateType: tables.InterruptDescriptor.GateType, privilegeLevel: cpu.PrivilegeLevel, handler: *const fn () callconv(.naked) void) void {
    const handler_addr = @intFromPtr(handler);

    idt[index] = tables.InterruptDescriptor{
        .offset1 = @truncate(handler_addr),
        .offset2 = @truncate(handler_addr >> 16),
        .selector = .{
            .index = @intFromEnum(GdtSegment.kernelCode),
            .rpl = .kernel,
            .ti = .gdt,
        },
        .gateType = gateType,
        .dpl = privilegeLevel,
    };
}

inline fn intPrologue() void {
    asm volatile (
        \\ pusha
        \\ cld
    );
}

inline fn intReturn() void {
    asm volatile (
        \\ popa
        \\ iret
    );
}

inline fn intPopErrCode() u32 {
    return asm volatile (
        \\ pop %%eax
        : [eax] "={eax}" (-> u32),
    );
}

fn handleIrq0() callconv(.naked) void {
    intPrologue();

    pic.eoi(0);

    intReturn();
}

fn handleIrq1() callconv(.naked) void {
    intPrologue();

    ps2.dev1.recv();

    pic.eoi(1);
    intReturn();
}

fn handleIrq12() callconv(.naked) void {
    intPrologue();

    ps2.dev2.recv();

    pic.eoi(12);
    intReturn();
}

fn handleInt3() callconv(.naked) void {
    intPrologue();
    intReturn();
}

fn handleInt42() callconv(.naked) void {
    intPrologue();

    asm volatile (
        \\ hlt
    );
}

inline fn stackTop(stack: []align(4) u8) u32 {
    return @as(u32, @intFromPtr(stack.ptr)) + (@sizeOf(@TypeOf(kernel_stack_bytes)));
}

// HACK: this should just be proc 0 in our processes lookup, but we don't have a heap yet, so we're going to punt on that!
var pagerProc: Process = .{
    .id = 0,
    .vm = .{},
};

pub const Process = struct {
    id: u32,
    vm: vmem.ProcessVirtualMemory,
};
