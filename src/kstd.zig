const std = @import("std");

pub const c = struct {
    pub const BUF_SIZ = 256;

    pub fn itoa(num: u32, buf: []u8) void {
        // If num is 0, just bail early!
        if (num == 0) {
            @memcpy(buf, &[_]u8{ '0', 0 });
            return;
        }

        // Figure out the number of characters we'll need to store this number as a string.
        const num_chars: u8 = @intFromFloat(std.math.ceil(std.math.log10(@as(f32, @floatFromInt(num)))));

        // 102 % 10 = 10r2 (buf: "  2")
        // 10  % 10 = 1r0  (buf: " 02")
        // 1   % 10 = 0r1  (buf: "102")
        var curr: u32 = num;
        var i: usize = 0;
        while (curr > 0) {
            buf[num_chars - i - 1] = @as(u8, @intCast(curr % 10)) + 48;

            curr /= 10;
            i += 1;
        }

        buf[num_chars] = 0;
    }

    pub fn memset(T: type, arr: []T, val: T) void {
        for (0..arr.len) |i| {
            arr[i] = val;
        }
    }
};
