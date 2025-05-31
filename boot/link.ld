ENTRY(_kmain)

SECTIONS {
    . = 1M; /* Load code after 1MiB barrier to prevent vm86 from doing weird stuff apparently. */

    __kernel_start = .;

    .text : ALIGN(4K) {
        KEEP(*(.multiboot))
        *(.text)
        *(.text.*)
    }

    .rodata : ALIGN(4K) { *(.rodata); *(.rodata.*) }
    .data : ALIGN(4K) { *(.data); *(.data.*); }

    __bss_start = .;

    .bss : ALIGN (4K) { *(.bss); *(.bss.*) }

    __kernel_end = .;

    . = ALIGN(4M);

    __userspace_start = .;
}

__kernel_size = __kernel_end - __kernel_start;
__kernel_to_bss_size = __bss_start - __kernel_start;