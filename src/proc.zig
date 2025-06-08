const std = @import("std");

const cpu = @import("cpu.zig");
const kstd = @import("kstd.zig");
const vmem = @import("vmem.zig");

pub const Process = packed struct {
    // +0
    id: u32,

    // +4
    vm: *vmem.ProcessVirtualMemory,

    // +8
    state: ProcessState,

    // +9
    esp: u32,

    // +13
    esp0: u32,

    // +17
    cr3: u32,

    const SavedRegisters = @FieldType(@This(), "saved_registers");
};

pub const ProcessState = enum(u8) {
    running = 0,
    stopped = 1,
    killed = 2,
};

const max_procs = 256;

const procs = kstd.collections.BufferQueue(*Process, max_procs);

var next_pid: u32 = 1;

pub var kernel_proc: *Process = undefined;

export var curr_proc: *Process = undefined;
extern fn switch_to_proc(proc: *Process) callconv(.{ .x86_sysv = .{} }) void;

pub fn init() !void {
    // Init the kernel_proc.
    kernel_proc = try kstd.mem.kernel_heap_allocator.create(Process);
    kernel_proc.* = .{
        .id = nextPID(),
        .vm = try kstd.mem.kernel_heap_allocator.create(vmem.ProcessVirtualMemory),
        .state = .running,

        // TODO: is this right?
        .esp = undefined,
        .esp0 = undefined,
        .cr3 = undefined,
    };
}

pub fn startKProc(proc_main: *const fn () anyerror!void) !void {
    // Reuse or create a new proc for this kproc.
    const proc = try kstd.mem.kernel_heap_allocator.create(Process);
    proc.* = .{
        .id = nextPID(),
        .state = .running,

        // Allocate a new kernel stack with:
        //   - ebx (0)
        //   - esi (0)
        //   - edi (0)
        //   - ebp (0)
        //   - eip (&proc_main)
        .esp0 = blk: {
            const stack = try kstd.mem.kernel_heap_allocator.alloc(u8, kstd.mem.stack.stack_bytes.len);
            const helpers = struct {
                var offset: usize = 0;

                fn push(s: []u8, val: anytype) void {
                    const bytes = std.mem.toBytes(val);
                    const n = bytes.len;

                    for (bytes, 0..n) |byte, i| {
                        s[s.len - offset - n + i + 1] = byte;
                    }

                    offset += n;
                }
            };

            helpers.push(stack, @as(u32, 0));
            helpers.push(stack, @as(u32, 0));
            helpers.push(stack, @as(u32, 0));
            helpers.push(stack, @as(u32, 0));
            helpers.push(stack, @intFromPtr(proc_main));

            break :blk @intFromPtr(stack.ptr) - helpers.offset;
        },
        .esp = proc.esp0,

        // TODO: create new page dir for proc.
        .vm = undefined,
        .cr3 = undefined,
    };

    switch_to_proc(proc);
}

pub fn yield() void {
    switch_to_proc(kernel_proc);
}

fn nextPID() u32 {
    const pid = next_pid;
    next_pid += 1;

    return pid;
}
