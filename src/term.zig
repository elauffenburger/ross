const std = @import("std");

const input = @import("input.zig");
const vga = @import("vga.zig");

// HACK: not sure what the size should actually be here!
var buf = [_]u8{undefined} ** 2048;
var buf_alloc = std.heap.FixedBufferAllocator.init(&buf);
var buf_list = std.ArrayList(u8).init(buf_alloc.allocator());

pub fn init() void {}

pub fn tick() !void {
    if (input.dequeueKeyEvents()) |key_events| {
        for (key_events) |key_ev| {
            if (key_ev.key_press.state != .pressed) {
                continue;
            }

            switch (key_ev.key_press.key) {
                .backspace => {},
                .escape => {},
                else => {
                    const key = if (key_ev.modifiers.shift and key_ev.key_press.shift_key != null) key_ev.key_press.shift_key.? else key_ev.key_press.key;
                    if (input.asciiFromKeyName(key)) |ascii_key_code| {
                        try buf_list.append(ascii_key_code);

                        vga.writeCh(ascii_key_code);
                    }
                },
            }
        }
    }
}
