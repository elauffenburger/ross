const std = @import("std");

const kb = @import("keyboard.zig");
const kstd = @import("kstd.zig");

const InputBuffer = kstd.collections.BufferQueue(kb.KeyEvent, 1024);

var buf = InputBuffer{};

pub fn onKeyEvent(key_ev: kb.KeyEvent) !void {
    try buf.append(key_ev);
}

pub fn dequeueKeyEvents(events: []kb.KeyEvent) ?[]kb.KeyEvent {
    if (buf.items.len == 0) {
        return null;
    }

    const n = buf.dequeueSlice(events);
    return events[0..n];
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

        else => null,
    };
}
