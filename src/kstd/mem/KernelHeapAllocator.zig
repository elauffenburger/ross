const std = @import("std");

const kmem = @import("../mem.zig");

pub const kernel_heap_allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &kernel_heap_allocator_vtable,
};

const kernel_heap_allocator_vtable: std.mem.Allocator.VTable = .{
    .alloc = KernelHeapAllocator.alloc,
    .resize = KernelHeapAllocator.resize,
    .remap = KernelHeapAllocator.remap,
    .free = KernelHeapAllocator.free,
};

const KernelHeapAllocator = struct {
    fn alloc(ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ptr;
        _ = ret_addr;

        return kmem.kmallocAligned(len, alignment) catch {
            return null;
        };
    }

    fn resize(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ptr; // autofix
        _ = memory; // autofix
        _ = alignment; // autofix
        _ = new_len; // autofix
        _ = ret_addr; // autofix

        @panic("not implemented");
    }

    fn remap(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ptr; // autofix
        _ = memory; // autofix
        _ = alignment; // autofix
        _ = new_len; // autofix
        _ = ret_addr; // autofix

        @panic("not implemented");
    }

    fn free(ptr: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        _ = ptr; // autofix
        _ = memory; // autofix
        _ = alignment; // autofix
        _ = ret_addr; // autofix

        @panic("not implemented");
    }
};
