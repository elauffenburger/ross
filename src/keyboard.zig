const std = @import("std");

const ps2 = @import("ps2.zig");
const types = @import("types.zig");
const vga = @import("vga.zig");

var kb_reader: *std.io.AnyReader = undefined;
var left_shift_held = false;
var right_shift_held = false;

var kb_buf: @TypeOf(ps2.port1.buffer) = undefined;

pub fn init() void {
    // Enable scan codes for port1.
    vga.dbg("enabling port1 scan codes...", .{});
    ps2.port1.writeData(ps2.Device.EnableScanning.C);

    // Enable typematic for port1.
    vga.dbg("enabling port1 typematic settings...", .{});
    ps2.port1.writeData(ps2.Device.SetTypematic.C);
    ps2.port1.writeData(@bitCast(
        ps2.Device.SetTypematic.D{
            .repeat_rate = 31,
            .delay = .@"750ms",
        },
    ));

    kb_reader = &ps2.port1.buf_reader;
}

pub fn tick() !void {
    const n = try kb_reader.readAll(&kb_buf);
    if (n != 0) {
        const key_code = kb_buf[0..n];
        if (Keys.keyFromKeyCodes(key_code)) |key| {
            handleKeyPress(key);
        }
    }
}

inline fn shiftHeld() bool {
    return left_shift_held or right_shift_held;
}

fn handleKeyPress(key_press: Keys.KeyPress) void {
    if (key_press.key.is_char) {
        // If the key is being released, do nothing.
        if (key_press.state == .released) {
            return;
        }

        // If shift isn't held, send the key_ascii.
        if (!shiftHeld()) {
            recv(key_press.key.key_ascii.?);
            return;
        }

        // If shift _is_ held and a shift key ascii is available, send it!
        if (key_press.key.shift_key_ascii) |shift_key_ascii| {
            recv(shift_key_ascii);
            return;
        }

        // ...otherwise send the unshifted key ascii.
        recv(key_press.key.key_ascii.?);
        return;
    }

    switch (key_press.key_name) {
        .@"left shift" => left_shift_held = key_press.state == .pressed,
        .@"right shift" => right_shift_held = key_press.state == .pressed,
        else => {
            // TODO: handle unknown special key.
        },
    }
}

fn recv(ch: u8) void {
    // TODO: actually send to terminal.
    vga.writeCh(ch);
}

fn debugPrintKey(key: Keys.KeyPress) void {
    vga.dbg(
        "key: {s}, key_ascii: {c} shift_key: {s}, shift_key_ascii: {c} state: {s}\n",
        .{
            key.key.key_name,
            if (key.key.key_ascii) |key_ascii| key_ascii else ' ',
            if (key.key.shift_key_name) |shift_key_name| shift_key_name else "none",
            if (key.key.shift_key_ascii) |shift_key_ascii| shift_key_ascii else ' ',
            @tagName(key.state),
        },
    );
}

const Key = struct {
    is_char: bool,

    key_name: []const u8,
    key_ascii: ?u8,

    shift_key_name: ?[]const u8,
    shift_key_ascii: ?u8,

    key_code: []const u8,
    released_key_code: []const u8,

    pub fn new(
        args: types.Exclude(Key, .{"released_key_code"}),
    ) @This() {
        const released_key_code = blk: {
            switch (args.key_code.len) {
                1 => break :blk &[_]u8{ 0xf0, args.key_code[0] },
                2 => break :blk &[_]u8{ args.key_code[0], 0xf0, args.key_code[1] },
                else => @compileError(std.fmt.comptimePrint("not implemented: key code with len {d} ({s})", .{ args.key_code.len, args.key_name })),
            }
        };

        return .{
            .is_char = args.is_char,

            .key_name = args.key_name,
            .key_ascii = args.key_ascii,

            .shift_key_name = args.shift_key_name,
            .shift_key_ascii = args.shift_key_ascii,

            .key_code = args.key_code,
            .released_key_code = released_key_code,
        };
    }
};

pub fn k(key_name: []const u8, shift_key_name: ?[]const u8, key_code: []const u8) Key {
    return Key.new(.{
        .is_char = false,

        .key_name = key_name,
        .key_ascii = null,

        .shift_key_name = shift_key_name,
        .shift_key_ascii = null,

        .key_code = key_code,
    });
}

fn kc(key_ascii: u8, shift_key_ascii: u8, key_code: []const u8) Key {
    return Key.new(.{
        .is_char = true,

        .key_name = std.fmt.comptimePrint("{c}", .{key_ascii}),
        .key_ascii = key_ascii,

        .shift_key_name = std.fmt.comptimePrint("{c}", .{shift_key_ascii}),
        .shift_key_ascii = shift_key_ascii,

        .key_code = key_code,
    });
}

const Keys = KeyMap(&[_]Key{
    k("F1", null, &[_]u8{0x05}),
    k("F2", null, &[_]u8{0x06}),
    k("F3", null, &[_]u8{0x04}),
    k("F4", null, &[_]u8{0x0C}),
    k("F5", null, &[_]u8{0x03}),
    k("F6", null, &[_]u8{0x0B}),
    k("F7", null, &[_]u8{0x83}),
    k("F8", null, &[_]u8{0x0A}),
    k("F9", null, &[_]u8{0x01}),
    k("F10", null, &[_]u8{0x09}),
    k("F11", null, &[_]u8{0x78}),
    k("F12", null, &[_]u8{0x07}),

    kc('`', '~', &[_]u8{0x0E}),
    kc('1', '!', &[_]u8{0x16}),
    kc('2', '@', &[_]u8{0x1E}),
    kc('3', '#', &[_]u8{0x26}),
    kc('4', '$', &[_]u8{0x25}),
    kc('5', '%', &[_]u8{0x2E}),
    kc('6', '^', &[_]u8{0x36}),
    kc('7', '&', &[_]u8{0x3D}),
    kc('8', '*', &[_]u8{0x3E}),
    kc('9', '(', &[_]u8{0x46}),
    kc('0', ')', &[_]u8{0x45}),
    kc('-', '_', &[_]u8{0x4E}),
    kc('=', '+', &[_]u8{0x55}),

    kc('[', '{', &[_]u8{0x54}),
    kc(']', '}', &[_]u8{0x5B}),
    kc('\\', '|', &[_]u8{0x5D}),
    kc(';', ':', &[_]u8{0x4C}),
    kc('\'', '"', &[_]u8{0x52}),
    kc(',', '<', &[_]u8{0x41}),
    kc('.', '>', &[_]u8{0x49}),
    kc('/', '?', &[_]u8{0x4A}),

    kc('a', 'A', &[_]u8{0x1C}),
    kc('b', 'B', &[_]u8{0x32}),
    kc('c', 'C', &[_]u8{0x21}),
    kc('d', 'D', &[_]u8{0x23}),
    kc('e', 'E', &[_]u8{0x24}),
    kc('f', 'F', &[_]u8{0x2B}),
    kc('g', 'G', &[_]u8{0x34}),
    kc('h', 'H', &[_]u8{0x33}),
    kc('i', 'I', &[_]u8{0x43}),
    kc('j', 'J', &[_]u8{0x3B}),
    kc('k', 'K', &[_]u8{0x42}),
    kc('l', 'L', &[_]u8{0x4B}),
    kc('m', 'M', &[_]u8{0x3A}),
    kc('n', 'N', &[_]u8{0x31}),
    kc('o', 'O', &[_]u8{0x44}),
    kc('p', 'P', &[_]u8{0x4D}),
    kc('q', 'Q', &[_]u8{0x15}),
    kc('r', 'R', &[_]u8{0x2D}),
    kc('s', 'S', &[_]u8{0x1B}),
    kc('t', 'T', &[_]u8{0x2C}),
    kc('u', 'U', &[_]u8{0x3C}),
    kc('v', 'V', &[_]u8{0x2A}),
    kc('w', 'W', &[_]u8{0x1D}),
    kc('x', 'X', &[_]u8{0x22}),
    kc('y', 'Y', &[_]u8{0x35}),
    kc('z', 'Z', &[_]u8{0x1A}),

    Key.new(.{
        .is_char = true,
        .key_name = "backspace",
        .key_ascii = 0x08,
        .shift_key_name = null,
        .shift_key_ascii = null,
        .key_code = &[_]u8{0x66},
    }),
    Key.new(.{
        .is_char = true,
        .key_name = "space",
        .key_ascii = ' ',
        .shift_key_name = null,
        .shift_key_ascii = null,
        .key_code = &[_]u8{0x29},
    }),
    Key.new(.{
        .is_char = true,
        .key_name = "tab",
        .key_ascii = '\t',
        .shift_key_name = null,
        .shift_key_ascii = null,
        .key_code = &[_]u8{0x0D},
    }),
    Key.new(.{
        .is_char = true,
        .key_name = "enter",
        .key_ascii = '\n',
        .shift_key_name = null,
        .shift_key_ascii = null,
        .key_code = &[_]u8{0x5A},
    }),
    Key.new(.{
        .is_char = true,
        .key_name = "escape",
        .key_ascii = 0x1B,
        .shift_key_name = null,
        .shift_key_ascii = null,
        .key_code = &[_]u8{0x76},
    }),

    k("right alt", null, &[_]u8{ 0xE0, 0x11 }),
    k("right shift", null, &[_]u8{0x59}),
    k("right control", null, &[_]u8{ 0xE0, 0x14 }),
    k("right GUI", null, &[_]u8{ 0xE0, 0x27 }),

    k("left alt", null, &[_]u8{0x11}),
    k("left shift", null, &[_]u8{0x12}),
    k("left control", null, &[_]u8{0x14}),
    k("left GUI", null, &[_]u8{ 0xE0, 0x1F }),

    k("cursor up", null, &[_]u8{ 0xE0, 0x75 }),
    k("cursor right", null, &[_]u8{ 0xE0, 0x74 }),
    k("cursor down", null, &[_]u8{ 0xE0, 0x72 }),
    k("cursor left", null, &[_]u8{ 0xE0, 0x6B }),
});

fn KeyMap(keys: []const Key) type {
    // Get the total number of key codes (including shift codes).
    var num_keys = 0;
    for (keys) |key| {
        num_keys += 1;

        if (key.shift_key_name != null) {
            num_keys += 1;
        }
    }

    var key_name_t_fields = [_]std.builtin.Type.EnumField{undefined} ** num_keys;
    {
        var i = 0;
        for (keys) |key| {
            key_name_t_fields[i] = .{
                .name = std.fmt.comptimePrint("{s}", .{key.key_name}),
                .value = i,
            };
            i += 1;

            if (key.shift_key_name) |shift_key_name| {
                key_name_t_fields[i] = .{
                    .name = std.fmt.comptimePrint("{s}", .{shift_key_name}),
                    .value = i,
                };
                i += 1;
            }
        }
    }

    const key_name_t = @Type(.{
        .@"enum" = std.builtin.Type.Enum{
            .fields = &key_name_t_fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .tag_type = u8,
            .is_exhaustive = true,
        },
    });

    const key_press_t = struct {
        key_name: key_name_t,
        key: Key,
        state: enum {
            pressed,
            released,
        },
    };

    return struct {
        pub const KeyName = key_name_t;
        pub const KeyState = @FieldType(key_press_t, "state");

        pub const KeyPress = key_press_t;

        pub fn keyFromKeyCodes(key_code: []const u8) ?KeyPress {
            inline for (keys) |key| {
                if (std.mem.eql(u8, key_code, key.key_code)) {
                    return .{
                        .key_name = std.meta.stringToEnum(KeyName, key.key_name).?,
                        .key = key,
                        .state = .pressed,
                    };
                }

                if (std.mem.eql(u8, key_code, key.released_key_code)) {
                    return .{
                        .key_name = std.meta.stringToEnum(KeyName, key.key_name).?,
                        .key = key,
                        .state = .released,
                    };
                }
            }

            return null;
        }
    };
}

test "keymap: k" {
    const key = Keys.keyFromKeyCodes(&[_]u8{0x42}).?;

    std.debug.assert(key.key_name == .k);
    std.debug.assert(key.state == .pressed);
}
