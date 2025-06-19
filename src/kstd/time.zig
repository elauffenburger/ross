const std = @import("std");

const hw = @import("../hw.zig");
const kstd = @import("../kstd.zig");

const TimerTreap = std.Treap(
    *Timer,
    struct {
        fn compare(left: *Timer, right: *Timer) std.math.Order {
            if (left.id > right.id) {
                return .gt;
            } else if (left.id < right.id) {
                return .lt;
            }

            return .eq;
        }
    }.compare,
);

var timers = TimerTreap{};

pub const Timer = struct {
    const Self = @This();

    var next_id: u32 = 1;

    id: u32 = 0,
    state: enum { started, stopped } = .stopped,
    elapsed_ms: u32 = 0,

    on_tick: ?*const fn (Self) void,
};

pub fn registerTimer(timer: *Timer) !void {
    const id = Timer.next_id;
    Timer.next_id += 1;

    timer.id = id;
    var entry = timers.getEntryFor(timer);

    // TODO: make sure this entry isn't already taken somehow.
    entry.set(try kstd.mem.kernel_heap_allocator.create(TimerTreap.Node));
}

pub fn tickTimers() void {
    const rate_hz = hw.timers.pit.rateHz();
    const elapsed_ms = (1.0 / @as(f32, @floatFromInt(rate_hz))) * 1000;

    var iter = timers.inorderIterator();
    while (iter.next()) |node| {
        const timer = node.key;
        if (timer.state == .started) {
            timer.elapsed_ms += @intFromFloat(elapsed_ms);

            if (timer.on_tick) |on_tick| {
                on_tick(*timer);
            }
        }
    }
}
