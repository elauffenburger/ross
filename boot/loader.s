; entrypoint for the bootloader
global _kstart

; kernel entrypoint
extern _kmain

; size of stack in bytes
KERNEL_STACK_SIZE equ 4096

; GRUB flags
MAGIC_NUMBER equ 0x1BADB002
FLAGS        equ 0x0
CHECKSUM     equ -MAGIC_NUMBER

section .bss
  align 4

; kernel stack
kernel_stack:
  resb KERNEL_STACK_SIZE

section .text:
  align 4

  ; write GRUB data
  dd MAGIC_NUMBER
  dd FLAGS
  dd CHECKSUM

_kstart:
  ; transfer control to the kernel
  call _kmain
