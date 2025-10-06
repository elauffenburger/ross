BITS 32

%include "macros.inc"

extern kmain

extern paging_init
extern paging_unset_identity_mapping

MULTIBOOT2_MAGIC equ 0x36d76289

section .multiboot.data
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

    ; set up paging
    call paging_init

    ; jump to higher half by jumping to the absolute address of a 
    ; label in .text (which has a virt addr)
    lea ecx, after_paging_init
    jmp ecx

  ; HACK: how should we surface this?
  .fail:
    hlt
    jmp .fail

section .text
  after_paging_init:
    ; Paging is now go and we're in the higher half!

    ; Now that we're in the higher half, we can undo the 
    ; identity-mapped lower half page dir entries.
    call paging_unset_identity_mapping

    ; jump to kmain
    jmp kmain

    ; if we somehow exit kmain, loop forever
  .loop:
    hlt
    jmp .loop
