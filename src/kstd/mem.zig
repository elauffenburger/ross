const std = @import("std");

pub const kernel_heap_allocator = @import("mem/KernelHeapAllocator.zig").kernel_heap_allocator;

// Reserve a 256MiB heap in .bss section.
const heap_size: usize = 256 * 1024 * 1024;
var kheap: [heap_size]u8 linksection(".bss") = [_]u8{0} ** heap_size;
var kheap_end: usize = undefined;

var kheap_head: usize = undefined;

pub fn init() void {
    kheap_head = @intFromPtr(&kheap);
    kheap_end = kheap_head + heap_size;
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
