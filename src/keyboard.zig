const std = @import("std");

const ps2 = @import("ps2.zig");
const vga = @import("vga.zig");

var kb_reader: *std.io.AnyReader = undefined;
var shift_pressed = false;

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
    var buffer: @TypeOf(ps2.port1.buffer) = undefined;
    const n = try kb_reader.readAll(&buffer);

    if (n != 0) {
        vga.printf("{s}\n", .{std.fmt.fmtSliceHexLower(buffer[0..n])});
    }
}

const Key = struct {
    key_name: []const u8,
    shift_key_name: ?[]const u8,
    key_code: []const u8,
    released_key_code: []const u8,

    pub fn new(key_name: []const u8, shift_key_name: ?[]const u8, key_code: []const u8) @This() {
        const released_key_code = blk: {
            switch (key_code.len) {
                1 => break :blk &[_]u8{ 0xf0, key_code[0] },
                2 => break :blk &[_]u8{ key_code[0], 0xf0, key_code[1] },
                else => @compileError(std.fmt.comptimePrint("not implemented: key code with len {d} ({s})", .{ key_code.len, key_name })),
            }
        };

        return .{
            .key_name = key_name,
            .shift_key_name = shift_key_name,
            .key_code = key_code,
            .released_key_code = released_key_code,
        };
    }
};

const Keys = KeyMap(&[_]Key{
    Key.new("F1", null, &[_]u8{0x05}),
    Key.new("F2", null, &[_]u8{0x06}),
    Key.new("F3", null, &[_]u8{0x04}),
    Key.new("F4", null, &[_]u8{0x0C}),
    Key.new("F5", null, &[_]u8{0x03}),
    Key.new("F6", null, &[_]u8{0x0B}),
    Key.new("F7", null, &[_]u8{0x83}),
    Key.new("F8", null, &[_]u8{0x0A}),
    Key.new("F9", null, &[_]u8{0x01}),
    Key.new("F10", null, &[_]u8{0x09}),
    Key.new("F11", null, &[_]u8{0x78}),
    Key.new("F12", null, &[_]u8{0x07}),

    Key.new("`", "~", &[_]u8{0x0E}),
    Key.new("1", "!", &[_]u8{0x16}),
    Key.new("2", "@", &[_]u8{0x1E}),
    Key.new("3", "#", &[_]u8{0x26}),
    Key.new("4", "$", &[_]u8{0x25}),
    Key.new("5", "%", &[_]u8{0x2E}),
    Key.new("6", "^", &[_]u8{0x36}),
    Key.new("7", "&", &[_]u8{0x3D}),
    Key.new("8", "*", &[_]u8{0x3E}),
    Key.new("9", "(", &[_]u8{0x46}),
    Key.new("0", ")", &[_]u8{0x45}),
    Key.new("-", "_", &[_]u8{0x4E}),
    Key.new("=", "+", &[_]u8{0x55}),

    Key.new("space", null, &[_]u8{0x29}),
    Key.new("tab", null, &[_]u8{0x0D}),
    Key.new("enter", null, &[_]u8{0x5A}),
    Key.new("escape", null, &[_]u8{0x76}),
    Key.new("backspace", null, &[_]u8{0x66}),

    Key.new("[", "{", &[_]u8{0x54}),
    Key.new("]", "}", &[_]u8{0x5B}),
    Key.new("\\", "|", &[_]u8{0x5D}),
    Key.new(";", ":", &[_]u8{0x4C}),
    Key.new("'", "\"", &[_]u8{0x52}),
    Key.new(",", "<", &[_]u8{0x41}),
    Key.new(".", ">", &[_]u8{0x49}),
    Key.new("/", "?", &[_]u8{0x4A}),

    Key.new("a", "A", &[_]u8{0x1C}),
    Key.new("b", "B", &[_]u8{0x32}),
    Key.new("c", "C", &[_]u8{0x21}),
    Key.new("d", "D", &[_]u8{0x23}),
    Key.new("e", "E", &[_]u8{0x24}),
    Key.new("f", "F", &[_]u8{0x2B}),
    Key.new("g", "G", &[_]u8{0x34}),
    Key.new("h", "H", &[_]u8{0x33}),
    Key.new("i", "I", &[_]u8{0x43}),
    Key.new("j", "J", &[_]u8{0x3B}),
    Key.new("k", "K", &[_]u8{0x42}),
    Key.new("l", "L", &[_]u8{0x4B}),
    Key.new("m", "M", &[_]u8{0x3A}),
    Key.new("n", "N", &[_]u8{0x31}),
    Key.new("o", "O", &[_]u8{0x44}),
    Key.new("p", "P", &[_]u8{0x4D}),
    Key.new("q", "Q", &[_]u8{0x15}),
    Key.new("r", "R", &[_]u8{0x2D}),
    Key.new("s", "S", &[_]u8{0x1B}),
    Key.new("t", "T", &[_]u8{0x2C}),
    Key.new("u", "U", &[_]u8{0x3C}),
    Key.new("v", "V", &[_]u8{0x2A}),
    Key.new("w", "W", &[_]u8{0x1D}),
    Key.new("x", "X", &[_]u8{0x22}),
    Key.new("y", "Y", &[_]u8{0x35}),
    Key.new("z", "Z", &[_]u8{0x1A}),

    Key.new("right alt", null, &[_]u8{ 0xE0, 0x11 }),
    Key.new("right shift", null, &[_]u8{0x59}),
    Key.new("right control", null, &[_]u8{ 0xE0, 0x14 }),
    Key.new("right GUI", null, &[_]u8{ 0xE0, 0x27 }),

    Key.new("left alt", null, &[_]u8{0x11}),
    Key.new("left shift", null, &[_]u8{0x12}),
    Key.new("left control", null, &[_]u8{0x14}),
    Key.new("left GUI", null, &[_]u8{ 0xE0, 0x1F }),

    Key.new("cursor up", null, &[_]u8{ 0xE0, 0x75 }),
    Key.new("cursor right", null, &[_]u8{ 0xE0, 0x74 }),
    Key.new("cursor down", null, &[_]u8{ 0xE0, 0x72 }),
    Key.new("cursor left", null, &[_]u8{ 0xE0, 0x6B }),
});

fn KeyMap(keys: []const Key) type {
    // Get the total number of key codes (including shift codes).
    var num_key_codes = 0;
    for (keys) |k| {
        num_key_codes += 1;

        if (k.shift_key_name != null) {
            num_key_codes += 1;
        }
    }

    var key_code_t_fields = [_]std.builtin.Type.EnumField{undefined} ** num_key_codes;
    {
        var i = 0;
        for (keys) |k| {
            key_code_t_fields[i] = .{
                .name = std.fmt.comptimePrint("{s}", .{k.key_name}),
                .value = i,
            };
            i += 1;

            if (k.shift_key_name) |shift_key_name| {
                key_code_t_fields[i] = .{
                    .name = std.fmt.comptimePrint("{s}", .{shift_key_name}),
                    .value = i,
                };
                i += 1;
            }
        }
    }

    const key_code_t = @Type(.{
        .@"enum" = std.builtin.Type.Enum{
            .fields = &key_code_t_fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .tag_type = u8,
            .is_exhaustive = true,
        },
    });

    const key_press_t = struct {
        key: key_code_t,
        state: enum {
            pressed,
            released,
        },
    };

    return struct {
        pub const KeyCode = @FieldType(key_press_t, "key");
        pub const KeyState = @FieldType(key_press_t, "state");

        pub const KeyPress = key_press_t;

        pub fn keyFromKeyCodes(key_code: []const u8) ?KeyPress {
            inline for (keys) |k| {
                if (std.mem.eql(u8, key_code, k.key_code)) {
                    return .{
                        .key = std.meta.stringToEnum(KeyCode, k.key_name).?,
                        .state = .pressed,
                    };
                }

                if (std.mem.eql(u8, key_code, k.released_key_code)) {
                    return .{
                        .key = std.meta.stringToEnum(KeyCode, k.key_name).?,
                        .state = .pressed,
                    };
                }
            }

            return null;
        }
    };
}

test "keymap: k" {
    const key = Keys.keyFromKeyCodes(&[_]u8{0x42}).?;

    std.debug.assert(key.key == .k);
    std.debug.assert(key.state == .pressed);
}
