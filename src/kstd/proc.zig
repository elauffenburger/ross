const std = @import("std");

const vmem = @import("../hw/vmem.zig");
const kstd = @import("../kstd.zig");

pub const Process = packed struct {
    // NOTE: these are the only fields accessed by asm; the order is important!
    saved_registers: packed struct {
        esp: u32,
        esp0: u32,
        cr3: u32,
    },

    id: u32,

    // TODO: implement.
    state: enum(u8) {
        running = 0,
        stopped = 1,
        killed = 2,
    },

    // TODO: implement.
    vm: *vmem.ProcessVirtualMemory,
};

const max_procs = 256;

const ProcsList = std.fifo.LinearFifo(*Process, .{ .Static = max_procs });
var procs: ProcsList = ProcsList.init();

var next_pid: u32 = 1;

var kernel_proc: *Process = undefined;
export var curr_proc: *Process = undefined;

extern fn switch_to_proc(proc: *Process) callconv(.{ .x86_sysv = .{} }) void;

pub const InitProof = kstd.types.UniqueProof();

pub fn init() !InitProof {
    const proof = try InitProof.new();

    // Init the kernel_proc.
    {
        const vm = try kstd.mem.kernel_heap_allocator.create(vmem.ProcessVirtualMemory);

        kernel_proc = try kstd.mem.kernel_heap_allocator.create(Process);
        kernel_proc.* = .{
            .saved_registers = .{
                .esp = undefined,
                .esp0 = undefined,
                .cr3 = @intFromPtr(&vm.page_dir),
            },

            .id = nextPID(),
            .vm = vm,
            .state = .running,
        };
    }

    curr_proc = kernel_proc;

    return proof;
}

pub fn kernelProc() *const Process {
    return kernel_proc;
}

pub fn startKProc(proc_main: *const fn () anyerror!void) !void {
    // Reuse or create a new proc for this kproc.
    const proc = try kstd.mem.kernel_heap_allocator.create(Process);
    proc.* = .{
        .saved_registers = blk_regs: {
            // Allocate a new kernel stack with:
            //   - ebx (0)
            //   - esi (0)
            //   - edi (0)
            //   - ebp (0)
            //   - eip (&proc_main)
            const esp0 = blk_esp0: {
                // HACK: this leaks.
                const buf = try kstd.mem.kernel_heap_allocator.alloc(u8, kstd.mem.stack.stack_bytes.len);
                var stack = ProcessStackBuilder.init(buf);

                stack.push(@intFromPtr(proc_main));
                stack.push(@as(u32, 0));
                stack.push(@as(u32, 0));
                stack.push(@as(u32, 0));
                stack.push(@as(u32, 0));

                break :blk_esp0 stack.esp();
            };

            break :blk_regs .{
                .esp0 = esp0,
                .esp = esp0,

                // Use the same page dir as the main kernel process.
                .cr3 = kernel_proc.saved_registers.cr3,
            };
        },

        .id = nextPID(),
        .state = .running,

        // Use the same page dir as the main kernel process.
        .vm = kernel_proc.vm,
    };

    try procs.writeItem(proc);

    switch_to_proc(proc);
}

// HACK: this isn't what we _actually_ want to do (we should drive this on interrupts), but it's a good test.
pub fn tick() void {
    for (0..procs.count) |i| {
        const p: *Process = procs.buf[i];
        switch_to_proc(p);
    }
}

pub fn yield() void {
    switch_to_proc(kernel_proc);
}

fn nextPID() u32 {
    const pid = next_pid;
    next_pid += 1;

    return pid;
}

const ProcessStackBuilder = struct {
    const Self = @This();

    buf: []u8 = undefined,
    head: usize = undefined,

    pub fn init(buf: []u8) Self {
        return .{
            .buf = buf,
            .head = buf.len,
        };
    }

    pub fn push(self: *Self, val: anytype) void {
        const bytes = std.mem.toBytes(val);
        const n = bytes.len;

        @memcpy(self.buf[self.head - bytes.len .. self.head], &bytes);

        self.head -= n;
    }

    pub fn esp(self: *const Self) u32 {
        return @intFromPtr(self.buf.ptr) + self.head;
    }
};
