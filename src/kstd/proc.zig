const std = @import("std");

const hw = @import("../hw.zig");
const kstd = @import("../kstd.zig");

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

// SAFETY: set in init.
export var last_created_proc: *Process = undefined;
// SAFETY: set in init.
export var curr_proc: *Process = undefined;

var proc_int_timer = kstd.time.Timer{
    .on_tick = struct {
        fn tick(self: kstd.time.Timer) void {
            curr_proc_time_slice_ms = self.elapsed_ms;
        }
    }.tick,
};

var proc_irq_switching_enabled = false;
var curr_proc_time_slice_ms: u32 = 0;

extern fn switch_proc(in_irq: bool) void;

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
            .esp = 0,
            .esp0 = 0,
            .cr3 = @intFromPtr(&vm.page_dir),

            .id = 0,
            .state = .running,
            .parent = null,
            .next = null,

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
    asm volatile ("cli");
    proc_irq_switching_enabled = true;

    proc_int_timer.elapsed_ms = 0;
    proc_int_timer.state = .started;
    asm volatile ("sti");
}

pub fn startKProc(proc_main: *const fn () anyerror!void) !void {
    asm volatile ("cli");

    // Reuse or create a new proc for this kproc.
    const proc = try kstd.mem.kernel_heap_allocator.create(Process);
    proc.* = blk_proc: {
        // Allocate a new kernel stack such that registers will be popped in the following order:
        const esp0 = blk_esp0: {
            // HACK: this leaks.
            const buf = try kstd.mem.kernel_heap_allocator.alloc(u8, kstd.mem.stack.stack_bytes.len);
            var stack = ProcessStackBuilder.init(buf);

            // New ESP
            stack.pushu32(@intFromPtr(buf.ptr));

            // The value of the EFLAGS register to load.
            //
            // HACK: we'll just use the current value (with interrupts turned on), but is that correct??
            stack.pushu32(asm volatile (
                \\ pushf
                \\ pop %%eax
                \\ or 0x0200, %%eax
                : [eflags] "={eax}" (-> u32),
                :
                : "eax", "memory"
            ));

            // The code segment selector to change to
            stack.pushu32(
                @as(u16, @bitCast(hw.cpu.SegmentSelector{
                    .index = @intFromEnum(hw.gdt.GdtSegment.kernelCode),
                    .ti = .gdt,
                    .rpl = .kernel,
                })),
            );

            // eip
            stack.pushu32(@intFromPtr(proc_main));

            // ebp
            stack.pushu32(@intFromPtr(buf.ptr));
            // edi
            stack.pushu32(0);
            // esi
            stack.pushu32(0);
            // ebx
            stack.pushu32(0);

            const esp0 = stack.esp();

            break :blk_esp0 esp0;
        };

        break :blk_proc .{
            .esp0 = esp0,
            .esp = esp0,
            // Use the same page dir as the main kernel process.
            .cr3 = kernel_proc.cr3,

            .id = nextPID(),
            .state = .stopped,

            .parent = kernel_proc,
            .next = null,

            // Use the same page dir as the main kernel process.
            .vm = kernel_proc.vm,
        };
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

    asm volatile ("sti");
}

pub fn yield() void {
    yieldRaw(false);
}

pub fn schedule() void {
    kstd.time.tick();

    if (!proc_irq_switching_enabled) {
        return;
    }

    yieldRaw(true);
}

fn yieldRaw(in_irq: bool) void {
    // TODO: write an actual scheduler instead of a round-robin scheduler!
    if (curr_proc.next == null) {
        curr_proc.next = kernel_proc;
    }

    switch_proc(in_irq);
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

    pub fn pushu32(self: *Self, val: anytype) void {
        const bytes = std.mem.toBytes(@as(u32, @intCast(val)));
        const n = bytes.len;

        @memcpy(self.buf[self.head - bytes.len .. self.head], &bytes);

        self.head -= n;
    }

    pub fn esp(self: *const Self) u32 {
        return @intFromPtr(self.buf.ptr) + self.head;
    }

    pub fn patchUpFromHead(self: *Self, at: u32, new_bytes: []const u8) void {
        @memcpy(self.buf[self.head + at .. self.head + at + new_bytes.len], new_bytes);
    }
};

pub const Process = packed struct(u232) {
    esp: u32,
    esp0: u32,
    cr3: u32,

    id: u32,
    state: enum(u8) {
        stopped = 0,
        running = 1,
        killed = 2,
    },

    parent: ?*Process,
    next: ?*Process,

    // TODO: implement.
    vm: *hw.vmem.ProcessVirtualMemory,
};
