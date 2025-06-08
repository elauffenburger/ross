// TODO: for reasons I don't know, it looks like something I'm doing in here was causing virtual memory to fail; I switched over to BufferQueue from some allocators and then all was well. We were getting page faults and i'm guessing they're legit?

const std = @import("std");

const kb = @import("../hw/io.zig").keyboard;

var buf: std.fifo.LinearFifo(kb.KeyEvent, .{ .Static = 1024 }) = undefined;

pub fn init() void {
    buf = @TypeOf(buf).init();
}

pub fn onKeyEvent(key_ev: kb.KeyEvent) !void {
    try buf.writeItem(key_ev);
}

pub fn dequeueKeyEvents(events: []kb.KeyEvent) []kb.KeyEvent {
    if (buf.count == 0) {
        return events[0..0];
    }

    const n = buf.read(events);
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
