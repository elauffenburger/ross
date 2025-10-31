%include "macros.inc"

global stack_bottom:data
global stack_top:data
global stack_size:data

STACK_SIZE equ 2 * MiB

; HACK: try just throwing this in bss?
; section .stack = nobits
section .bss
  ; sysv expects 16-byte aligned addresses before a call; 4-byte everywhere else. Let's just set it to 16 to be safe?
  ; TODO: aren't we wasting a ton of space here? Won't zig actually take care of this for us, so we're safe to use 4-byte aligned addresses here?
  align 16

  stack_bottom:
    resb STACK_SIZE
  stack_top:

section .data
  stack_size dd STACK_SIZE
