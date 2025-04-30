pub const MultibootHeader = extern struct {
    const Self = @This();

    pub const Magic = 0x1BADB002;

    pub const Flags = struct {
        pub const Align: u32 = 1 << 0;
        pub const MemInfo: u32 = 1 << 1;
        pub const VideoMode: u32 = 1 << 2;
    };

    pub const VideoMode = packed struct(u128) {
        modeType: u32,
        width: u32,
        height: u32,
        depth: u32,
    };

    magicNumber: i32 = Self.Magic,
    flags: i32,
    checksum: i32,
    rawAddrInfo: [4]u32 = undefined,
    video: VideoMode = undefined,
};
