const std = @import("std");

pub const log = @import("kstd/log.zig");
pub const mem = @import("kstd/mem.zig");

pub fn yield() void {
    asm volatile (
        \\ pusha
        \\
    );
}
