const std = @import("std");

pub fn BufferQueue(T: type, size: usize) type {
    return struct {
        const Self = @This();

        const Error = error{OutOfMemory};

        buf: [size]T = undefined,

        items: []T = undefined,

        pub fn append(self: *Self, item: T) !void {
            try self.appendSlice(&[_]T{item});
        }

        pub fn appendSlice(self: *Self, buffer: []const T) !void {
            const new_len = self.items.len + buffer.len;
            if (new_len > self.buf.len) {
                return error.OutOfMemory;
            }

            @memcpy(self.buf[self.items.len..new_len], buffer);
            self.items = self.buf[0..new_len];
        }

        pub fn dequeueSlice(self: *Self, buffer: []T) usize {
            if (self.items.len == 0) {
                return 0;
            }

            const n = if (self.items.len < buffer.len) self.items.len else buffer.len;
            @memcpy(buffer[0..n], self.buf[0..n]);

            const old_len = self.items.len;
            const new_len = old_len - n;
            if (new_len == 0) {
                self.items = self.buf[0..new_len];
                return n;
            }

            var new_buffer: [size]T = undefined;
            @memcpy(new_buffer[0..new_len], self.buf[n..old_len]);

            @memcpy(self.buf[0..new_len], new_buffer[0..new_len]);
            self.items = self.buf[0..new_len];

            return n;
        }
    };
}

test "BufferQueue" {
    const Queue = BufferQueue(u8, 10);
    var queue = Queue{};

    try queue.appendSlice(&[_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 });

    {
        var buf: [3]u8 = undefined;
        std.debug.assert(queue.dequeueSlice(&buf) == 3);
        std.debug.assert(std.mem.eql(u8, &[_]u8{ 0, 1, 2 }, &buf));
        std.debug.assert(std.mem.eql(u8, &[_]u8{ 3, 4, 5, 6, 7, 8, 9 }, queue.items));
    }

    try queue.appendSlice(&[_]u8{ 10, 11 });
    std.debug.assert(std.mem.eql(u8, &[_]u8{ 3, 4, 5, 6, 7, 8, 9, 10, 11 }, queue.items));

    {
        var buf: [9]u8 = undefined;
        std.debug.assert(queue.dequeueSlice(&buf) == 9);
        std.debug.assert(std.mem.eql(u8, &[_]u8{ 3, 4, 5, 6, 7, 8, 9, 10, 11 }, &buf));
        std.debug.assert(std.mem.eql(u8, &[_]u8{}, queue.items));
    }
}
