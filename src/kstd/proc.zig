const std = @import("std");

const hw = @import("../hw.zig");
const kstd = @import("../kstd.zig");

pub extern fn yield_to_proc() callconv(.{ .x86_sysv = .{} }) void;
pub extern fn irq_switch_to_proc() callconv(.naked) void;

const ProcessTreap = std.Treap(
    *Process,
    struct {
        fn compare(l: *Process, r: *Process) std.math.Order {
            if (l.id > r.id) {
                return .gt;
            } else if (l.id < r.id) {
                return .lt;
            }

            return .eq;
        }
    }.compare,
);

var procs = ProcessTreap{};

// SAFETY: set in init.
var kernel_proc: *Process = undefined;
// SAFETY: not actually safe, but needs to be type *Process and not ?*Process for interop w/ asm.
pub export var curr_proc: *Process = undefined;
// SAFETY: set in init.
export var last_created_proc: *Process = undefined;

// SAFETY: set in init.
var proc_int_timer = kstd.time.Timer{};
pub var ints_enabled = false;
const max_proc_time_slice_ms = 10;

pub const InitProof = kstd.types.UniqueProof();
pub fn init() !InitProof {
    const proof = try InitProof.new();

    // Init the process timer.
    try kstd.time.registerTimer(&proc_int_timer);

    // Init the kernel_proc.
    {
        const vm = try kstd.mem.kernel_heap_allocator.create(hw.vmem.ProcessVirtualMemory);

        kernel_proc = try kstd.mem.kernel_heap_allocator.create(Process);
        kernel_proc.* = .{
            .saved_registers = .{
                .esp = 0,
                .esp0 = 0,
                .cr3 = @intFromPtr(&vm.page_dir),
            },

            .id = nextPID(),
            .state = .running,
            .parent = null,
            .next = kernel_proc,

            .vm = vm,
        };
    }

    curr_proc = kernel_proc;
    last_created_proc = kernel_proc;

    return proof;
}

pub fn kernelProc() *const Process {
    return kernel_proc;
}

pub fn start() void {
    ints_enabled = true;

    proc_int_timer.elapsed_ms = 0;
    proc_int_timer.state = .started;
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

        .parent = kernel_proc,
        .next = kernel_proc,

        // Use the same page dir as the main kernel process.
        .vm = kernel_proc.vm,
    };

    // Add the proc to the proc treap.
    {
        // Get an entry for this process by id.
        var proc_entry = procs.getEntryFor(proc);

        // If there's already a node, someothing went really wrong!
        if (proc_entry.node) |_| {
            return error.ProcessLookupStateError;
        }

        // ...otherwise, create a new node for this entry.
        proc_entry.set(try kstd.mem.kernel_heap_allocator.create(ProcessTreap.Node));
    }

    // Update the last created proc's next to be this proc and mark this the last created proc.
    last_created_proc.next = proc;
    last_created_proc = proc;

    // Finally switch to this proc!
    yield();
}

pub fn yield() void {
    kstd.log.dbgf("curr: {d}, next: {d}\n", .{ curr_proc.id, curr_proc.next.id });

    proc_int_timer.elapsed_ms = 0;
    yield_to_proc();
}

var next_pid: u32 = 1;
fn nextPID() u32 {
    const pid = next_pid;
    next_pid += 1;

    return pid;
}

const ProcessStackBuilder = struct {
    const Self = @This();

    buf: []u8 = &[_]u8{},
    head: usize = 0,

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

pub const Process = packed struct(u232) {
    saved_registers: packed struct {
        esp: u32,
        esp0: u32,
        cr3: u32,
    },

    id: u32,
    state: enum(u8) {
        stopped = 0,
        running = 1,
        killed = 2,
    },

    parent: ?*Process,
    next: *Process,

    // TODO: implement.
    vm: *hw.vmem.ProcessVirtualMemory,
};
