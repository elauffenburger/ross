pub const Header = extern struct {
    const Self = @This();

    pub const Magic = 0x1BADB002;

    pub const Flags = struct {
        pub const Align: u32 = 1;
        pub const MemInfo: u32 = 2;
        pub const VideoMode: u32 = 4;
    };

    pub const Addresses = extern struct {
        header: u32,
        load: u32,
        load_end: u32,
        bss_end: u32,
        entry: u32,
    };

    pub const VideoMode = extern struct {
        mode_type: u32,
        width: u32,
        height: u32,
        depth: u32,
    };

    magic_number: u32 = Self.Magic,
    flags: u32,
    checksum: u32,
    addresses: Addresses = @bitCast(@as(u160, 0)),
    video: VideoMode = @bitCast(@as(u128, 0)),
};
