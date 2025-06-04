const std = @import("std");

const input = @import("input.zig");
const vga = @import("vga.zig");

// HACK: not sure what the size should actually be here!
var input_buffer = std.ArrayList(u8)
    .init(std.heap.FixedBufferAllocator.init([_]u8{undefined} ** 2048));

pub fn init() void {}

pub fn tick() !void {
    if (input.dequeueKeyEvents()) |key_events| {
        for (key_events) |key_ev| {
            switch (key_ev.key_press.key) {
                .backspace => {},
                .escape => {},
                else => {
                    const key_name = if (key_ev.modifiers.shift) key_ev.key_press.key_def.shift_key_name else key_ev.key_press.key_def.key_name;
                    if (input.asciiFromKeyName(key_name)) |ascii_key_code| {
                        input_buffer.append(ascii_key_code);

                        vga.writeCh(ascii_key_code);
                    }
                },
            }
        }
    }
}
