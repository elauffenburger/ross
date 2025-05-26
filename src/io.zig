pub fn inb(port: u16) u8 {
    return asm volatile (
        \\ movw %[port], %%dx
        \\ inb %%dx, %%al
        : [res] "={al}" (-> u8),
        : [port] "r" (port),
        : "eax", "dx"
    );
}

pub fn outb(port: u16, val: u8) void {
    asm volatile (
        \\ movb %[val], %%al
        \\ movw %[port], %%dx
        \\ outb %%al, %%dx
        :
        : [port] "r" (port),
          [val] "r" (val),
        : "eax", "dx"
    );
}

pub fn wait() void {
    // This is a bit weird, but we're basically just sending a byte on a (hopefully)
    // unused IO port to force waiting a little before sending more data.
    //
    // Apparently PICs can take a sec to process commands, so we want to give them some
    // breathing room.
    asm volatile (
        \\ movb $0x00, %%al
        \\ outb %%al, $0x80
        ::: "eax");
}
