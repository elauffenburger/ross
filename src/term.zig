const std = @import("std");

const input = @import("input.zig");
const kb = @import("keyboard.zig");
const kstd = @import("kstd.zig");
const vga = @import("vga.zig");

// HACK: not sure what the size should actually be here!
var input_buf = kstd.collections.BufferQueue(u8, 2048){};

pub fn init() void {}

pub fn tick() !void {
    var events_buf: [10]kb.KeyEvent = undefined;
    if (input.dequeueKeyEvents(&events_buf)) |kb_events| {
        for (kb_events) |key_ev| {
            if (key_ev.key_press.state != .pressed) {
                continue;
            }

            switch (key_ev.key_press.key) {
                .backspace => {},
                .escape => {},
                .enter => {
                    vga.writeCh('\n');
                },
                else => {
                    const key = if (key_ev.modifiers.shift and key_ev.key_press.shift_key != null) key_ev.key_press.shift_key.? else key_ev.key_press.key;
                    if (input.asciiFromKeyName(key)) |ascii_key_code| {
                        try input_buf.append(ascii_key_code);

                        vga.writeCh(ascii_key_code);
                    }
                },
            }
        }
    }
}
