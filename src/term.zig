const std = @import("std");

const ps2 = @import("ps2.zig");
const vga = @import("vga.zig");

var kb_reader: *std.io.AnyReader = undefined;

pub fn init() void {
    kb_reader = &ps2.port1.buf_reader;
}

pub fn tick() !void {
    var buffer: @TypeOf(ps2.port1.buffer) = undefined;
    const n = try kb_reader.readAll(&buffer);

    if (n != 0) {
        const str = buffer[0..n];
        vga.printf("got str bytes:", .{});
        for (str) |byte| {
            vga.printf(" 0x{x}", .{byte});
        }

        vga.printf("\n", .{});
    }
}
