const std = @import("std");

const serial = @import("../hw/io.zig").serial;

var port: *serial.COMPort = undefined;

pub var debugVerbosity: enum(u8) { none, debug, v } = .v;

const writer = std.io.AnyWriter{
    .context = undefined,
    .writeFn = blk: {
        const helper = struct {
            fn write(_: *const anyopaque, buffer: []const u8) anyerror!usize {
                try port.buf_writer.writeAll(buffer);
                return buffer.len;
            }
        };

        break :blk helper.write;
    },
};

pub fn init(serial_proof: serial.InitProof) !void {
    try serial_proof.prove();

    port = &serial.com1;
}

fn addNewline(comptime msg: []const u8) [msg.len + 1]u8 {
    const n = msg.len;
    comptime var msg_lf: [n + 1]u8 = undefined;

    @memcpy(msg_lf[0..n], msg);
    msg_lf[n] = '\n';

    return msg_lf;
}

pub fn dbg(comptime msg: []const u8) void {
    dbgf(&addNewline(msg), .{});
}

pub fn dbgv(comptime msg: []const u8) void {
    dbgvf(&addNewline(msg), .{});
}

pub fn dbgf(comptime format: []const u8, args: anytype) void {
    debugLog(format, args, .debug);
}

pub fn dbgvf(comptime format: []const u8, args: anytype) void {
    debugLog(format, args, .v);
}

pub fn debugLog(comptime format: []const u8, args: anytype, verbosity: @TypeOf(debugVerbosity)) void {
    if (@intFromEnum(debugVerbosity) >= @intFromEnum(verbosity)) {
        var buf: [1024]u8 = undefined;
        const res = std.fmt.bufPrint(&buf, format, args) catch {
            return;
        };

        writer.writeAll(res) catch {
            // TODO: what do?
            return;
        };
    }
}
