pub const input = @import("kstd/input.zig");
pub const log = @import("kstd/log.zig");
pub const mem = @import("kstd/mem.zig");
pub const proc = @import("kstd/proc.zig");
pub const time = @import("kstd/time.zig");
pub const types = @import("kstd/types.zig");

pub fn yield() void {
    asm volatile (
        \\ pusha
        \\
    );
}
