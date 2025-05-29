const vmem = @import("vmem.zig");

pub const Process = struct {
    id: u32,
    vm: vmem.ProcessVirtualMemory align(4096),
};
