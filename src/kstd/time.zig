const std = @import("std");

const hw = @import("../hw.zig");
const kstd = @import("../kstd.zig");

pub const Timer = struct {
    const Self = @This();

    var timers = std.AutoHashMap(u32, Timer)
        .init(kstd.mem.kernel_heap_allocator);

    var next_id: u32 = 0;

    id: u32,
    state: enum { started, stopped },
    elapsed_ms: u32 = 0,

    pub fn init() !*Self {
        const id = next_id;
        next_id += 1;

        const timer = .{
            .id = id,
            .state = .stopped,
        };

        try timers.put(id, timer);
        return timers.getPtr(id).?;
    }

    pub fn reset(self: *Self) void {
        self.state = .stopped;
        self.elapsed_ms = 0;
    }

    pub fn deinit(self: *Self) void {
        timers.remove(self.id);
        timers.allocator.destroy(self);
    }
};

pub fn tickTimers() void {
    const rate_hz = hw.timers.pit.rateHz();
    const elapsed_ms = (1.0 / @as(f32, @floatFromInt(rate_hz))) * 1000;

    var iter = Timer.timers.valueIterator();
    while (iter.next()) |timer| {
        if (timer.state == .started) {
            timer.elapsed_ms += @intFromFloat(elapsed_ms);
        }
    }
}
