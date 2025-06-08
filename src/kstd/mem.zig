const std = @import("std");

pub const kernel_heap_allocator = @import("mem/KernelHeapAllocator.zig").kernel_heap_allocator;
pub const stack = @import("mem/stack.zig");

// Reserve a 512MiB heap in .bss section.
const heap_size: usize = 512 * 1024 * 1024;
var kheap: [heap_size]u8 linksection(".bss.kernel_heap") = undefined;

var kheap_head: usize = undefined;
var kheap_end: usize = undefined;

extern var __kernel_size: u32;
fn kernelSize() usize {
    return @as(usize, @intFromPtr(&__kernel_size));
}

pub fn init() void {
    kheap_head = @intFromPtr(&kheap);
    kheap_end = kheap_head + kheap.len;
}

pub fn kmallocAligned(n: usize, alignment: std.mem.Alignment) error{OutOfHeapSpace}![*]u8 {
    kheap_head = alignment.forward(kheap_head);

    const new_address = kheap_head + n;
    if (new_address >= kheap_end) {
        return error.OutOfHeapSpace;
    }

    const ptr = kheap_head;
    kheap_head = new_address;

    return @ptrFromInt(ptr);
}
