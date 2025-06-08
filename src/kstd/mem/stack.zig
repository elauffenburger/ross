// Reserve 16K for the kernel stack in the .bss section.
const stack_size = 16 * 1024;
pub var stack_bytes: [stack_size]u8 align(4) linksection(".bss") = undefined;

pub inline fn reset() void {
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        :
        : [stack_top] "r" (top()),
        : "esp", "ebp"
    );
}

pub inline fn top() u32 {
    return @as(u32, @intFromPtr(&stack_bytes)) + stack_bytes.len;
}
