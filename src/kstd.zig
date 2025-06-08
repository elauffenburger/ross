const std = @import("std");

pub const collections = @import("kstd/collections.zig");
pub const mem = @import("kstd/mem.zig");

pub fn init() void {
    mem.init();
}

pub fn yield() void {
    asm volatile (
        \\ pusha
        \\
    );
}
