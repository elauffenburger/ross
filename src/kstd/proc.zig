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

export var proc_irq_switching_enabled = false;
var curr_proc_time_slice_ms: u32 = 0;

extern fn switch_proc() void;

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
    defer asm volatile ("sti");

    proc_irq_switching_enabled = true;

    proc_int_timer.elapsed_ms = 0;
    proc_int_timer.state = .started;
}

pub fn startKProc(proc_main: *const fn () anyerror!void) !void {
    asm volatile ("cli");
    defer asm volatile ("sti");

    // Reuse or create a new proc for this kproc.
    const proc: *Process = try kstd.mem.kernel_heap_allocator.create(Process);
    proc.* = blk_proc: {
        // Allocate a new kernel stack such that registers will be popped in the following order:
        const esp0 = blk_esp0: {
            // HACK: this leaks.
            const stack_buf = try kstd.mem.kernel_heap_allocator.alloc(u8, kstd.mem.stack.stack_bytes.len);

            const esp0 = build_proc_stack_esp(
                stack_buf,
                proc_main,
                hw.cpu.SegmentSelector{
                    .index = @intFromEnum(hw.gdt.GdtSegment.kernelData),
                    .ti = .gdt,
                    .rpl = .kernel,
                },
                hw.cpu.SegmentSelector{
                    .index = @intFromEnum(hw.gdt.GdtSegment.kernelCode),
                    .ti = .gdt,
                    .rpl = .kernel,
                },
            );

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
}

pub fn yield() void {
    schedule();
    switch_proc();
}

pub fn tick() void {
    if (!proc_irq_switching_enabled) {
        return;
    }

    schedule();
}

fn schedule() void {
    // TODO: write an actual scheduler instead of a round-robin scheduler!
    if (curr_proc.next == null) {
        curr_proc.next = kernel_proc.next;
    }
}

var next_pid: u32 = 1;
fn nextPID() u32 {
    const pid = next_pid;
    next_pid += 1;

    return pid;
}

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

fn build_proc_stack_esp(stack_buf: []u8, proc_main: *const fn () anyerror!void, stack_segment: hw.cpu.SegmentSelector, code_segment: hw.cpu.SegmentSelector) u32 {
    var stack = ProcessStackBuilder.init(stack_buf);

    // Stack selector (SS)
    // TODO: is this used?? Or am I just burning stack space?
    stack.pushu32(@as(u16, @bitCast(stack_segment)));

    // ESP
    const stack_top = @intFromPtr(stack_buf.ptr) + stack_buf.len - 1;
    stack.pushu32(stack_top);

    // EFLAGS.
    //
    // HACK: is this right?
    stack.pushu32(asm volatile (
        \\ pushf
        \\ pop %%eax
        : [eflags] "={eax}" (-> u32),
        :
        : "eax", "memory"
    ));

    // Code segment (CS)
    stack.pushu32(@as(u16, @bitCast(code_segment)));

    // EIP
    stack.pushu32(@intFromPtr(proc_main));

    // Push GP registers in the order they'll be popped via POPA.
    const pre_pusha_esp = stack.esp();

    // EAX
    stack.pushu32(0);
    // ECX
    stack.pushu32(0);
    // EDX
    stack.pushu32(0);
    // EBX
    stack.pushu32(0);
    // ESP (pre-push)
    stack.pushu32(pre_pusha_esp);
    // EBP
    stack.pushu32(stack_top);
    // ESI
    stack.pushu32(0);
    // EDI
    stack.pushu32(0);

    return stack.esp();
}
