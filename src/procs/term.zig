const std = @import("std");

const hw = @import("../hw.zig");
const vga = hw.video.vga;
const kstd = @import("../kstd.zig");

const InputBuf = std.fifo.LinearFifo(u8, .{ .Static = 2048 });

pub fn main() !void {
    // HACK: disabled because i _think_ we have some kind of race condition with the serial driver or something; if this is enabled we _sometimes_ just fail to finish logging everything to serial from the "enabling portx scan codes..." messages.
    // kstd.log.dbg("in term!");

    var input_buf: InputBuf = InputBuf.init();
    var events_buf: [10]hw.io.keyboard.KeyEvent = undefined;

    while (true) {
        for (kstd.input.dequeueKeyEvents(&events_buf)) |key_ev| {
            if (key_ev.key_press.state != .pressed) {
                continue;
            }

            switch (key_ev.key_press.key) {
                .backspace => {},
                .escape => {},
                .enter => vga.writeCh('\n'),
                else => {
                    const key = if (key_ev.modifiers.shift and key_ev.key_press.shift_key != null) key_ev.key_press.shift_key.? else key_ev.key_press.key;
                    if (kstd.input.asciiFromKeyName(key)) |ascii_key_code| {
                        try input_buf.writeItem(ascii_key_code);

                        vga.writeCh(ascii_key_code);
                    }
                },
            }
        }
    }
}
