extern const __stack_bottom: u8;
extern const __stack_top: u8;

pub inline fn top() u32 {
    return @intCast(@intFromPtr(&__stack_top));
}
