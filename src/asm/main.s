BITS 32

%include "macros.s"

extern kmain

MULTIBOOT2_MAGIC equ 0x36d76289

HIGHER_HALF equ 0xc0000000

section .data
  global multiboot2_info_addr
  multiboot2_info_addr dd 0

section .multiboot.text
  global _kentry
  _kentry:
    ; make sure eax has the multiboot2 magic number
    cmp eax, MULTIBOOT2_MAGIC
    jne .fail

    ; move ebx to multiboot2_info_addr
    mov [multiboot2_info_addr], ebx

  jmp paging_init

section .text
  to_kmain:
    ; jump to_kmain
    jmp kmain

  ; HACK: how should we surface this?
  .fail:
    hlt
    jmp .fail
