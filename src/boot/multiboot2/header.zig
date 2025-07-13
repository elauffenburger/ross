const std = @import("std");

const tag = @import("./tag.zig");

const magic: u32 = 0xE85250D6;
const architecture: u32 = 1;

fn headerBytesLen(tags: []const tag.Tag) usize {
    var tags_len: u32 = 0;
    for (tags) |t| {
        const tag_len = t.len();
        tags_len += tag_len;

        // Figure out any padding we have to add to keep everything 8-byte aligned.
        const padding = @mod(tag_len, 8);
        tags_len += padding;
    }

    // The total len is len(req_tags) + len(header_fields)
    return tags_len + (4 * 4);
}

pub fn headerBytes(tags: []const tag.Tag) [headerBytesLen(tags)]u8 {
    const header_length = @as(u32, headerBytesLen(tags));

    const checksum: u32 = 0xffffffff - (magic + architecture + header_length - 1);
    std.debug.assert((magic + architecture + header_length) +% checksum == 0);

    const ResultList = std.fifo.LinearFifo(u8, .{ .Static = 4096 });
    var result_bytes: ResultList = ResultList.init();

    try {
        // Write header fields.
        try result_bytes.write(&std.mem.toBytes(magic));
        try result_bytes.write(&std.mem.toBytes(architecture));
        try result_bytes.write(&std.mem.toBytes(header_length));
        try result_bytes.write(&std.mem.toBytes(checksum));

        // Write tag values.
        for (tags) |t| {
            try t.write(t.context, &result_bytes);

            // Re-align to 8 bytes after write.
            const padding = @mod(result_bytes.readableLength(), 8);
            try result_bytes.write(&std.mem.toBytes(padding));
        }

        var results = [_]u8{undefined} ** header_length;
        @memcpy(&results, result_bytes.readableSlice(0)[0..header_length]);

        return results;
    } catch |err| {
        @compileError(std.fmt.comptimePrint("{?}", .{err}));
    };
}
