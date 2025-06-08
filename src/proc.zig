const std = @import("std");

const cpu = @import("cpu.zig");
const kstd = @import("kstd.zig");
const vmem = @import("vmem.zig");

pub const Process = struct {
    id: u32,
    vm: vmem.ProcessVirtualMemory,
};

pub const ProcessState = enum {
    started,
    running,
    stopped,
    killed,
};

const max_procs = 256;

const procs = kstd.collections.BufferQueue(Process, max_procs);
const killed_procs = kstd.collections.BufferQueue(Process, max_procs);

var next_pid = 2;

pub fn addKProc(kproc_main: *const fn () void) void {
    _ = kproc_main; // autofix

    const proc = newProc();
    _ = proc; // autofix
}

fn newProc() Process {
    // Find a killed_proc we can recycle...
    if (killed_procs.dequeue()) |proc| {
        return proc;
    }

    // ...or give up and create a new one!
    const proc = .{
        .id = next_pid,
        .vm = .{},
    };

    next_pid += 1;

    return proc;
}
