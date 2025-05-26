const std = @import("std");

pub const mem = @import("kstd/mem.zig");

pub fn init() void {
    mem.init();
}
