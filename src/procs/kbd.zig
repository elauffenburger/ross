const std = @import("std");

const io = @import("../hw/io.zig");
const ps2 = io.ps2;
const kb = io.keyboard;
const kstd = @import("../kstd.zig");
const klog = kstd.log;

var kb_reader: *std.io.AnyReader = undefined;
var kb_buf: [128]u8 = undefined;

var left_shift_held = false;
var right_shift_held = false;

pub fn main() !void {
    kstd.proc.yield();

    init();

    while (true) {
        const n = try kb_reader.readAll(&kb_buf);
        if (n != 0) {
            const key_code = kb_buf[0..n];
            if (kb.Keys.keyFromKeyCodes(key_code)) |key_press| {
                switch (key_press.key) {
                    .@"left shift" => left_shift_held = key_press.state == .pressed,
                    .@"right shift" => right_shift_held = key_press.state == .pressed,
                    else => {},
                }

                try kstd.input.onKeyEvent(.{
                    .key_press = key_press,
                    .modifiers = .{
                        .shift = left_shift_held or right_shift_held,
                    },
                });
            } else {
                // TODO: what do?
            }
        }

        kstd.proc.yield();
    }
}

fn init() void {
    // Enable scan codes for port1.
    klog.dbgf("enabling port1 scan codes...", .{});
    ps2.port1.writeData(ps2.Device.EnableScanning.C);
    klog.dbg("ok!");

    // Enable typematic for port1.
    klog.dbgf("enabling port1 typematic settings...", .{});
    ps2.port1.writeData(ps2.Device.SetTypematic.C);
    ps2.port1.writeData(@bitCast(
        ps2.Device.SetTypematic.D{
            .repeat_rate = 31,
            .delay = .@"750ms",
        },
    ));
    klog.dbg("ok!");

    kb_reader = &ps2.port1.buf_reader;
}

fn debugPrintKey(key: kb.Keys.KeyPress) void {
    klog.dbgf(
        "key: {s}, key_ascii: {c} shift_key: {s}, shift_key_ascii: {c} state: {s}",
        .{
            key.key_def.key_name,
            if (key.key_def.key_ascii) |key_ascii| key_ascii else ' ',
            if (key.key_def.shift_key_name) |shift_key_name| shift_key_name else "none",
            if (key.key_def.shift_key_ascii) |shift_key_ascii| shift_key_ascii else ' ',
            @tagName(key.state),
        },
    );
}
