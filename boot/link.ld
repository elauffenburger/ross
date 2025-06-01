ENTRY(_kmain)

SECTIONS {
    __kernel_start = .;

    /* Load code after 1MiB barrier to prevent vm86 from doing weird stuff apparently. */
    . = 1M;

    .text : ALIGN(4K) {
        KEEP(*(.multiboot));

        *(.text);
        *(.text.*);
    }

    .rodata : ALIGN(4K) { *(.rodata); *(.rodata.*); }
    .data : ALIGN(4K) { *(.data); *(.data.*); }

    .bss : ALIGN (4K) {
        *(.bss);
        *(.bss.*);
    }

    __kernel_end = .;
}

__kernel_size = __kernel_end - __kernel_start;
