BITS 32

%include "macros.s"

PAGE_ENTRY_SIZE equ 4 * KiB

section .bss
  align 4 * 1024

  page_dir:
    resb PAGE_ENTRY_SIZE
  page_table_1:
    resb PAGE_ENTRY_SIZE
