%include "macros.inc"

global multiboot2_info_addr:data
global _kentry:function

extern kmain
extern paging_init
extern stack_top

MULTIBOOT2_MAGIC equ 0x36d76289

section .multiboot.data
  multiboot2_info_addr dd 0

section .multiboot.text
  _kentry:
    ; make sure eax has the multiboot2 magic number
    cmp eax, MULTIBOOT2_MAGIC
    jne .fail

    ; move ebx to multiboot2_info_addr
    mov [multiboot2_info_addr], ebx

    ; set up paging
    ; 
    ; NOTE: since we don't have a stack yet, we'll pass the return address in ebx.
    mov ebx, kentry_higher_half
    jmp paging_init

  ; TODO: how should we surface this?
  .fail:
    hlt
    jmp .fail

section .text
  kentry_higher_half:
    ; Paging is go and we're in the higher half!

    ; set up stack
    mov esp, stack_top

    ; jump to kmain
    jmp kmain

    ; if we somehow exit kmain, loop forever
  .loop:
    hlt
    jmp .loop
