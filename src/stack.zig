// Reserve 16K for the kernel stack in the .bss section.
const KERNEL_STACK_SIZE = 16 * 1024;
pub var kernel_stack_bytes: [KERNEL_STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

// Reserve 16K for the userspace stack in the .bss section.
const STACK_SIZE = 16 * 1024;
pub var user_stack_bytes: [STACK_SIZE]u8 align(4) linksection(".bss") = undefined;

pub inline fn resetTo(stack: []align(4) u8) void {
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        :
        : [stack_top] "r" (top(stack)),
        : "esp", "ebp"
    );
}

pub inline fn top(stack: []align(4) u8) u32 {
    return @as(u32, @intFromPtr(stack.ptr)) + stack.len;
}
