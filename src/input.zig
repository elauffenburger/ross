const std = @import("std");

const kb = @import("keyboard.zig");

var buffered_events_allocator = std.heap.FixedBufferAllocator.init(@constCast(&[_]u8{undefined} ** 1024));
var buffered_events = std.ArrayList(kb.KeyEvent)
    .init(buffered_events_allocator.allocator());

pub fn onKeyEvent(key_ev: kb.KeyEvent) !void {
    try buffered_events.append(key_ev);
}

pub fn dequeueKeyEvents() ?[]kb.KeyEvent {
    if (buffered_events.items.len == 0) {
        return null;
    }

    const events = buffered_events.items[0..];
    buffered_events.clearRetainingCapacity();

    return events;
}

pub fn asciiFromKeyName(key_name: kb.Keys.Key) ?u8 {
    return switch (key_name) {
        .@"`" => '`',
        .@"1" => '1',
        .@"2" => '2',
        .@"3" => '3',
        .@"4" => '4',
        .@"5" => '5',
        .@"6" => '6',
        .@"7" => '7',
        .@"8" => '8',
        .@"9" => '9',
        .@"0" => '0',
        .@"-" => '-',
        .@"=" => '=',
        .@"[" => '[',
        .@"]" => ']',
        .@"\\" => '\\',
        .@";" => ';',
        .@"'" => '\'',
        .@"," => ',',
        .@"." => '.',
        .@"/" => '/',

        .a => 'a',
        .b => 'b',
        .c => 'c',
        .d => 'd',
        .e => 'e',
        .f => 'f',
        .g => 'g',
        .h => 'h',
        .i => 'i',
        .j => 'j',
        .k => 'k',
        .l => 'l',
        .m => 'm',
        .n => 'n',
        .o => 'o',
        .p => 'p',
        .q => 'q',
        .r => 'r',
        .s => 's',
        .t => 't',
        .u => 'u',
        .v => 'v',
        .w => 'w',
        .x => 'x',
        .y => 'y',
        .z => 'z',

        .@"@" => '@',
        .@"#" => '#',
        .@"$" => '$',
        .@"%" => '%',
        .@"^" => '^',
        .@"&" => '&',
        .@"*" => '*',
        .@"(" => '(',
        .@")" => ')',
        ._ => '_',
        .@"+" => '+',
        .@"{" => '{',
        .@"}" => '}',
        .@"|" => '|',
        .@":" => ':',
        .@"\"" => '"',
        .@"<" => '<',
        .@">" => '>',
        .@"?" => '?',

        .A => 'A',
        .B => 'B',
        .C => 'C',
        .D => 'D',
        .E => 'E',
        .F => 'F',
        .G => 'G',
        .H => 'H',
        .I => 'I',
        .J => 'J',
        .K => 'K',
        .L => 'L',
        .M => 'M',
        .N => 'N',
        .O => 'O',
        .P => 'P',
        .Q => 'Q',
        .R => 'R',
        .S => 'S',
        .T => 'T',
        .U => 'U',
        .V => 'V',
        .W => 'W',
        .X => 'X',
        .Y => 'Y',
        .Z => 'Z',

        _ => null,
    };
}
