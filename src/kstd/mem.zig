const std = @import("std");

pub const kernel_heap_allocator = @import("mem/KernelHeapAllocator.zig").kernel_heap_allocator;

// Reserve a 256KiB heap in .bss section.
const heap_size: usize = 256 * 1024;
var kheap: [heap_size]u8 linksection(".bss") = [_]u8{0} ** heap_size;

var kheap_next: usize = undefined;
var kheap_end: usize = undefined;

pub fn init() void {
    kheap_next = @intFromPtr(&kheap);
    kheap_end = kheap_next + heap_size;
}

pub fn kmallocAligned(n: usize, alignment: std.mem.Alignment) error{OutOfHeapSpace}![*]u8 {
    // TODO: respect alignment.
    _ = alignment; // autofix

    if (kheap_next + n >= kheap_end) {
        return error.OutOfHeapSpace;
    }

    const ptr = kheap_next;
    kheap_next += n;

    return @ptrFromInt(ptr);
}
