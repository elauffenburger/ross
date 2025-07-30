const std = @import("std");

pub const Fonts = struct {
    pub const @"Uni1-Fixed16" = ParsedFont(@embedFile("./fonts/Uni1-Fixed16.psf")[0..]).font();

    fn ParsedFont(buf: []const u8) type {
        const Parser = struct {
            fn Psf1() type {
                @setEvalBranchQuota(20000);

                // TODO: handle padding for fonts that aren't whole byte numbers in size.

                // Parse the header.
                const header = std.mem.bytesToValue(psf1.Header, buf[0..4]);

                // Calculate character dimensions.
                const ch_width = 8;
                const ch_height = header.char_size;

                // Calculate char info.
                const chars_bytes = buf[4..];
                const num_chars = if (header.font_mode.has_512_glyphs) 512 else 256;

                comptime var font_chars = [_]Font.Char{undefined} ** num_chars;

                // Parse each character.
                var head: usize = 0;
                for (0..num_chars) |char_i| {
                    // Get the bitmap.
                    font_chars[char_i] = .{
                        .bitmap = chars_bytes[head .. head + header.char_size],
                    };

                    head += header.char_size;
                }

                // // If the font has a unicode table, we can now add the unicode lookup info.
                // if (header.font_mode.has_table or header.font_mode.seq) {
                //     // HACK: we might need to do some calculations to get the worst-case for this based on the number of bytes after the bitmap table.
                //     const FontCharsLookupFifo = std.fifo.LinearFifo(struct { []const u16, usize }, .{ .Static = num_chars * 3 });
                //     comptime var font_chars_lookup_entries_raw: FontCharsLookupFifo = FontCharsLookupFifo.init();

                //     for (0..num_chars) |char_i| {
                //         // Add single-point entries.
                //         while (head < chars_bytes.len) {
                //             const code_point_buf = chars_bytes[head .. head + 2];
                //             const code_point = std.mem.bytesToValue(u16, code_point_buf);

                //             head += 2;

                //             switch (code_point) {
                //                 0xfffe => break,
                //                 else => {
                //                     font_chars_lookup_entries_raw.writeItem(.{ &[_]u16{code_point}, char_i }) catch |err| {
                //                         @compileError(std.fmt.comptimePrint("woah what happened: {}", .{err}));
                //                     };
                //                 },
                //             }
                //         }

                //         // Add multi-point sequences.
                //         var uni_char_head = head;
                //         while (head < chars_bytes.len) {
                //             const code_point_buf = chars_bytes[head .. head + 2];
                //             const code_point = std.mem.bytesToValue(u16, code_point_buf);

                //             head += 2;

                //             switch (code_point) {
                //                 0xfffe => {
                //                     const as_u16s: [*:0]const u16 = @ptrCast(chars_bytes[uni_char_head .. head - 2].ptr);
                //                     font_chars_lookup_entries_raw.writeItem(.{ as_u16s[0..], char_i }) catch |err| {
                //                         @compileError(std.fmt.comptimePrint("woah what happened: {}", .{err}));
                //                     };

                //                     uni_char_head = head;
                //                 },
                //                 0xffff => break,
                //             }
                //         }
                //     }
                // }

                // // HACK: testing
                // for (font_chars[65].bitmap) |byte| {
                //     var line = [_]u8{0} ** 8;
                //     for (0..8) |bit| {
                //         line[bit] = if (byte & (1 << (7 - bit)) != 0) '1' else ' ';
                //     }

                //     @compileLog(line);
                // }

                // Return the Font type with the parsed chars.
                return struct {
                    const chars = font_chars;

                    pub fn font() Font {
                        return .{
                            .char_info = .{
                                .width = ch_width,
                                .height = ch_height,
                            },

                            .chars = &chars,
                        };
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
    const Header = packed struct(u32) {
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
};
