const std = @import("std");

pub fn BufferQueue(T: type, size: usize) type {
    return struct {
        const Self = @This();

        buffer: [size]T = undefined,
        head: usize = 0,

        pub fn appendSlice(self: *Self, buffer: []const T) error{OutOfMemory}!void {
            const new_head = self.head + buffer.len;
            if (new_head > buffer.len) {
                return error.OutOfMemory;
            }

            @memcpy(self.buffer[self.head..new_head], buffer);
            self.head += buffer.len;
        }

        pub fn dequeueSlice(self: *Self, buffer: []T) usize {
            const n = if (self.buffer.len < buffer.len) self.buffer.len else buffer.len;
            @memcpy(buffer[0..n], self.buffer[0..n]);

            const old_head = self.head;
            self.head -= n;
            if (self.head == 0) {
                return n;
            }

            var new_buffer: [size]T = undefined;
            @memcpy(new_buffer[0..n], self.buffer[self.head..old_head]);

            self.head = n;
            @memcpy(self.buffer[0..self.head], new_buffer[0..n]);

            return n;
        }
    };
}

test "BufferQueue" {
    const Queue = BufferQueue(u8, 10);
    var queue = Queue{};

    try queue.appendSlice(&[_]u8{ 0, 1, 2, 3, 4, 5 });

    var buf: [3]u8 = undefined;
    std.debug.assert(queue.dequeueSlice(&buf) == 3);
    std.debug.assert(std.mem.eql(u8, &[_]u8{ 0, 1, 2 }, &buf));
    std.debug.assert(std.mem.eql(u8, &[_]u8{ 3, 4, 5 }, queue.buffer[0..queue.head]));
}
