const std = @import("std");

pub const Fonts = struct {
    pub const @"Uni1-Fixed16" = ParsedFont(@embedFile("./fonts/Uni1-Fixed16.psf")[0..]).font();

    fn ParsedFont(buf: []const u8) type {
        const Parser = struct {
            fn Psf1() type {
                @setEvalBranchQuota(2048);

                // Parse the header.
                const header = std.mem.bytesToValue(psf1.Header, buf[0..32]);

                // Calculate character dimensions.
                const ch_width = 8;
                const ch_height = header.char_size - ch_width;

                // Calculate char info.
                const chars_bytes = buf[33..];
                const num_chars = if (header.font_mode.has_512_glyphs) 512 else 256;

                comptime var font_chars = [_]Font.Char{undefined} ** num_chars;

                // HACK: we might need to do some calculations to get the worst-case for this based on the number of bytes after the bitmap table.
                const FontCharsLookupFifo = std.fifo.LinearFifo(struct { []u16, usize }, .{ .Static = num_chars });
                comptime var font_chars_lookup_entries_raw: FontCharsLookupFifo = FontCharsLookupFifo.init();

                // Parse each character.
                var head: usize = 0;
                for (0..num_chars) |char_i| {
                    // Get the bitmap.
                    font_chars[char_i] = .{
                        .bitmap = chars_bytes[head .. head + header.char_size],
                    };

                    head += header.char_size;
                }

                // If the font has a unicode table, we can now add the unicode lookup info.
                for (0..num_chars) |char_i| {
                    // Add single-point entries.
                    while (head < font_chars.len) {
                        const code_point_buf = font_chars[head .. head + 2];
                        const code_point = std.mem.bytesToValue(u16, code_point_buf);

                        head += 2;

                        switch (code_point) {
                            0xfffe => break,
                            else => {
                                font_chars_lookup_entries_raw.writeItem(.{ code_point_buf, char_i });
                            },
                        }
                    }

                    // Add multi-point sequences.
                    var uni_char_head = head;
                    while (head < font_chars.len) {
                        const code_point_buf = font_chars[head .. head + 2];
                        const code_point = std.mem.bytesToValue(u16, code_point_buf);

                        head += 2;

                        switch (code_point) {
                            0xfffe => {
                                const as_u16s: [*:0]const u16 = @ptrCast(font_chars[uni_char_head .. head - 2].ptr);
                                font_chars_lookup_entries_raw.writeItem(.{ as_u16s[0..], char_i });

                                uni_char_head = head;
                            },
                            0xffff => break,
                        }
                    }
                }

                comptime var font_chars_lookup_entries: @TypeOf(font_chars_lookup_entries_raw.buf) = undefined;
                @memcpy(&font_chars_lookup_entries, &font_chars_lookup_entries_raw.buf);

                // Return the Font type with the parsed chars.
                return struct {
                    const chars = font_chars;
                    const chars_lookup_entries = font_chars_lookup_entries;

                    pub fn font() Font {
                        return .{
                            .char_info = .{
                                .width = ch_width,
                                .height = ch_height,
                            },

                            .chars = &chars,

                            .charIndexFromCodePoints = charIndexFromCodePoints,
                        };
                    }

                    fn charIndexFromCodePoints(char_points: []u16) ?usize {
                        inline for (chars_lookup_entries) |item| {
                            if (std.mem.eql(u16, item.@"0", char_points)) {
                                return item.@"1";
                            }
                        }

                        return null;
                    }
                };
            }

            fn Psf2() type {
                std.debug.panic("not implemented", .{});
            }
        };

        // Figure out if this is a psf1 or psf2 file...
        if (std.mem.bytesToValue(u16, buf[0..2]) == psf1.Header.Magic) {
            return Parser.Psf1();
        }
        if (std.mem.bytesToValue(u16, buf[0..4]) == psf2.Header.Magic) {
            return Parser.Psf2();
        }

        // ...otherwise, give up!
        @compileError(std.fmt.comptimePrint("bad psf magic: 0x{x}", .{buf[0..4]}));
    }
};

// NOTE: Each row of each glyph is padded to a whole number of bytes
// NOTE: All field values are little-endian.

const psf1 = struct {
    const Header = packed struct {
        const Magic = 0x0436;

        magic: u16 = Magic,

        font_mode: packed struct(u8) {
            // If this bit is set, the font face will have 512 glyphs.
            // If it is unset, then the font face will have just 256 glyphs.
            has_512_glyphs: bool,

            // If this bit is set, the font face will have a unicode table.
            has_table: bool,

            // Equivalent to has_table.
            seq: bool,

            _unused: u5,
        },

        // NOTE: The width is a constant 8, so height is char_size - 8.
        char_size: u8,
    };
};

const psf2 = struct {
    const Header = packed struct {
        const Magic = 0x864ab572;

        magic: u32 = Magic,

        version: u32,

        // Offset of bitmaps in file.
        // NOTE: likely 32.
        header_size: u32,

        flags: packed struct(u32) {
            // If this bit is set, the font face will have a unicode table.
            has_table: bool,
        },

        num_glyphs: u32,
        bytes_per_glyph: u32,

        height: u32,
        width: u32,
    };
};

pub const Font = struct {
    pub const Char = struct {
        bitmap: []const u8,
    };

    char_info: struct {
        width: u8,
        height: u8,
    },
    chars: []const Char,
    charIndexFromCodePoints: *const fn (char_points: []u16) ?usize,
};
