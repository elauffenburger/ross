const vga = @import("../hw/video.zig").vga;

pub fn Main(str: []const u8) fn () anyerror!void {
    return struct {
        fn main() anyerror!void {
            while (true) {
                vga.writeStr(str);
            }
        }
    }.main;
}
