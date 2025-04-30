ENTRY(_kmain)

SECTIONS {
    . = 1M; /* Load code after 1MB barrier to prevent vm86 from doing weird stuff apparently. */

    .text : ALIGN(4K) {
        KEEP(*(.multiboot))
        KEEP(*(.asm_fns))
        *(.text)
    }

    .rodata : ALIGN(4K) {
        *(.rodata)
    }

    .data : ALIGN(4K) {
        *(.data)
    }

    .bss : ALIGN (4K) {
        *(.bss)
    }
}