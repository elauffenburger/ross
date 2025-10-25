%include "macros.inc"

STACK_SIZE equ 16 * KiB

section .stack = nobits
  align 4 * 1024

  global stack_bottom:data
  stack_bottom:
    resb STACK_SIZE
  global stack_top:data
  stack_top:

section .data
  global stack_size:data
  stack_size dd STACK_SIZE
