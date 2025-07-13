const std = @import("std");

const kmem = @import("../mem.zig");

pub const allocator: std.mem.Allocator = .{
    // SAFETY: unused.
    .ptr = undefined,
    .vtable = &.{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    },
};

fn alloc(ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    _ = ptr;
    _ = ret_addr;

    return kmem.kmallocAligned(len, alignment) catch {
        return null;
    };
}

// TODO: implement!
fn resize(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
    _ = ptr; // autofix
    _ = memory; // autofix
    _ = alignment; // autofix
    _ = new_len; // autofix
    _ = ret_addr; // autofix

    return false;
}

// TODO: implement!
fn remap(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
    _ = ptr; // autofix
    _ = memory; // autofix
    _ = alignment; // autofix
    _ = new_len; // autofix
    _ = ret_addr; // autofix

    return null;
}

// TODO: implement!
fn free(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
    _ = ptr; // autofix
    _ = memory; // autofix
    _ = alignment; // autofix
    _ = ret_addr; // autofix
}
