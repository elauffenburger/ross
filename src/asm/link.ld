SECTIONS {
  /*  
    * NOTE: we do a couple interesting things in the loader script:
    *  - we start our kernel after 1MiB to prevent messing with the real mode address space
    *    - see https://wiki.osdev.org/Memory_Map_(x86)#Real_mode_address_space_(%3C_1_MiB)
    *  - multiboot sections go first
    *  - we know we're going to memory-map our kernel to the higher half, so we skip ahead and manually set the VMA and LMA of our non-multiboot sections
    *    - VMA is the implicit address after the skip; LMA is provided via AT
    *  - sections are aligned on page boundaries (4KiB) 
    *  - we keep track of the kernel size via __kernel_start, __kernel_end, and __kernel_size symbols
    */

  /* Load code after 1MiB barrier to prevent vm86 from doing weird stuff apparently. */
  . = 1M;

  __kernel_start = .;

  .multiboot : {
    KEEP(*(.multiboot));
  }

  .gdt : {
    KEEP(*(.gdt));
  }

  . += 0xC0000000;

  /* .text ALIGN(4K) : AT (ADDR (.text) - 0xC0000000) { */
  .text ALIGN(4K) : {
    *(.text);
    *(.text.*);
  }

  /* .rodata ALIGN(4K) : AT (ADDR (.rodata) - 0xC0000000) { */
  .rodata ALIGN(4K) : {
    *(.rodata); 
    *(.rodata.*); 
  }

  /* .data ALIGN(4K) : AT (ADDR (.data) - 0xC0000000) {  */
  .data ALIGN(4K) : { 
    *(.data); 
    *(.data.*); 
  }

  /* .bss ALIGN (4K) : AT (ADDR (.bss) - 0xC0000000) { */
  .bss ALIGN (4K) : {
    *(COMMON);
    *(.bss);
    *(.bss.*);
    *(.stack);
  }

  __kernel_end = .;
}

__kernel_size = __kernel_end - __kernel_start;
