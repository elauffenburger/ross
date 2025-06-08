const std = @import("std");

const types = @import("types.zig");

pub const KeyEvent = struct {
    key_press: Keys.KeyPress,
    modifiers: struct {
        shift: bool = false,
    },
};

pub const KeyDef = struct {
    key_name: []const u8,
    shift_key_name: ?[]const u8,

    key_code: []const u8,
    released_key_code: []const u8,

    pub fn new(args: types.Exclude(KeyDef, .{"released_key_code"})) @This() {
        const released_key_code = blk: {
            switch (args.key_code.len) {
                1 => break :blk &[_]u8{ 0xf0, args.key_code[0] },
                2 => break :blk &[_]u8{ args.key_code[0], 0xf0, args.key_code[1] },
                else => @compileError(std.fmt.comptimePrint("not implemented: key code with len {d} ({s})", .{ args.key_code.len, args.key_name })),
            }
        };

        return .{
            .key_name = args.key_name,
            .shift_key_name = args.shift_key_name,

            .key_code = args.key_code,
            .released_key_code = released_key_code,
        };
    }
};

pub const Keys = KeyMap(&[_]KeyDef{
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

    k("`", "~", &[_]u8{0x0E}),
    k("1", "!", &[_]u8{0x16}),
    k("2", "@", &[_]u8{0x1E}),
    k("3", "#", &[_]u8{0x26}),
    k("4", "$", &[_]u8{0x25}),
    k("5", "%", &[_]u8{0x2E}),
    k("6", "^", &[_]u8{0x36}),
    k("7", "&", &[_]u8{0x3D}),
    k("8", "*", &[_]u8{0x3E}),
    k("9", "(", &[_]u8{0x46}),
    k("0", ")", &[_]u8{0x45}),
    k("-", "_", &[_]u8{0x4E}),
    k("=", "+", &[_]u8{0x55}),

    k("[", "{", &[_]u8{0x54}),
    k("]", "}", &[_]u8{0x5B}),
    k("\\", "|", &[_]u8{0x5D}),
    k(";", ":", &[_]u8{0x4C}),
    k("'", "\"", &[_]u8{0x52}),
    k(",", "<", &[_]u8{0x41}),
    k(".", ">", &[_]u8{0x49}),
    k("/", "?", &[_]u8{0x4A}),

    k("a", "A", &[_]u8{0x1C}),
    k("b", "B", &[_]u8{0x32}),
    k("c", "C", &[_]u8{0x21}),
    k("d", "D", &[_]u8{0x23}),
    k("e", "E", &[_]u8{0x24}),
    k("f", "F", &[_]u8{0x2B}),
    k("g", "G", &[_]u8{0x34}),
    k("h", "H", &[_]u8{0x33}),
    k("i", "I", &[_]u8{0x43}),
    k("j", "J", &[_]u8{0x3B}),
    k("k", "K", &[_]u8{0x42}),
    k("l", "L", &[_]u8{0x4B}),
    k("m", "M", &[_]u8{0x3A}),
    k("n", "N", &[_]u8{0x31}),
    k("o", "O", &[_]u8{0x44}),
    k("p", "P", &[_]u8{0x4D}),
    k("q", "Q", &[_]u8{0x15}),
    k("r", "R", &[_]u8{0x2D}),
    k("s", "S", &[_]u8{0x1B}),
    k("t", "T", &[_]u8{0x2C}),
    k("u", "U", &[_]u8{0x3C}),
    k("v", "V", &[_]u8{0x2A}),
    k("w", "W", &[_]u8{0x1D}),
    k("x", "X", &[_]u8{0x22}),
    k("y", "Y", &[_]u8{0x35}),
    k("z", "Z", &[_]u8{0x1A}),

    k("backspace", null, &[_]u8{0x66}),
    k("space", null, &[_]u8{0x29}),
    k("tab", null, &[_]u8{0x0D}),
    k("enter", null, &[_]u8{0x5A}),
    k("escape", null, &[_]u8{0x76}),

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

fn KeyMap(keys: []const KeyDef) type {
    // Get the total number of key codes (including shift codes).
    var num_keys = 0;
    for (keys) |key| {
        num_keys += 1;

        if (key.shift_key_name != null) {
            num_keys += 1;
        }
    }

    var key_t_fields = [_]std.builtin.Type.EnumField{undefined} ** num_keys;
    {
        var i = 0;
        for (keys) |key| {
            key_t_fields[i] = .{
                .name = std.fmt.comptimePrint("{s}", .{key.key_name}),
                .value = i,
            };
            i += 1;

            if (key.shift_key_name) |shift_key_name| {
                key_t_fields[i] = .{
                    .name = std.fmt.comptimePrint("{s}", .{shift_key_name}),
                    .value = i,
                };
                i += 1;
            }
        }
    }

    const key_t: type = @Type(.{
        .@"enum" = std.builtin.Type.Enum{
            .fields = &key_t_fields,
            .decls = &.{},
            .tag_type = u8,
            .is_exhaustive = true,
        },
    });

    const key_press_t = struct {
        key_def: KeyDef,

        key: key_t,
        shift_key: ?key_t,

        state: enum {
            pressed,
            released,
        },
    };

    return struct {
        pub const Key = key_t;
        pub const KeyState = @FieldType(key_press_t, "state");

        pub const KeyPress = key_press_t;

        pub fn keyFromKeyCodes(key_code: []const u8) ?KeyPress {
            inline for (keys) |key_def| {
                const matched_state: ?KeyState = blk: {
                    if (std.mem.eql(u8, key_code, key_def.key_code)) {
                        break :blk .pressed;
                    }

                    if (std.mem.eql(u8, key_code, key_def.released_key_code)) {
                        break :blk .released;
                    }

                    break :blk null;
                };

                if (matched_state) |match| {
                    return .{
                        .key = std.meta.stringToEnum(Key, key_def.key_name).?,
                        .shift_key = if (key_def.shift_key_name) |shift_key_name| std.meta.stringToEnum(Key, shift_key_name) else null,
                        .key_def = key_def,
                        .state = match,
                    };
                }
            }

            return null;
        }
    };
}

fn k(key_name: []const u8, shift_key_name: ?[]const u8, key_code: []const u8) KeyDef {
    return KeyDef.new(.{
        .key_name = key_name,
        .shift_key_name = shift_key_name,

        .key_code = key_code,
    });
}

test "keymap: k" {
    const key = Keys.keyFromKeyCodes(&[_]u8{0x42}).?;

    std.debug.assert(key.key == .k);
    std.debug.assert(key.state == .pressed);
}
