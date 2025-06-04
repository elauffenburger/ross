const std = @import("std");

const input = @import("input.zig");
const vga = @import("vga.zig");

// HACK: not sure what the size should actually be here!
var input_buffer_allocator = std.heap.FixedBufferAllocator.init(@constCast(&([_]u8{undefined} ** 2048)));
var input_buffer = std.ArrayList(u8)
    .init(input_buffer_allocator.allocator());

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
                        try input_buffer.append(ascii_key_code);

                        vga.writeCh(ascii_key_code);
                    }
                },
            }
        }
    }
}
