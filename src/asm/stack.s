BITS 32

%include "macros.s"

STACK_SIZE equ 16 * KiB

section .stack = nobits
  align 4 * 1024

  global stack_bottom
  stack_bottom:
    resb STACK_SIZE
  global stack_top
  stack_top:

section .data
  global stack_size
  stack_size dd STACK_SIZE
