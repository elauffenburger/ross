BITS 32

%include "macros.s"
%include "gdt_macros.s"

extern gdt
extern gdt_len
extern gdt_kernel_code_index
extern gdt_kernel_tss_index
extern kernel_tss
extern gdtr

extern stack_top

extern kmain

MULTIBOOT2_MAGIC equ 0x36d76289

section .data
  global multiboot2_info_addr
  multiboot2_info_addr dd 0

section .text
  global _kentry
  _kentry:
    ; make sure eax has the multiboot2 magic number
    cmp eax, MULTIBOOT2_MAGIC
    jne .fail

    ; move ebx to multiboot2_info_addr
    mov [multiboot2_info_addr], ebx

    ; load the GDT
    mov dword [gdtr + gdt_desc.addr], gdt
    mov word [gdtr + gdt_desc.limit], gdt_len
    load_gdt [gdtr], gdt_kernel_tss_index

    ; load the kernel TSS as the active TSS
    mov word [kernel_tss + tss.ss0], 8 * gdt_kernel_tss_index
    mov dword [kernel_tss + tss.esp0], stack_top
    load_tss kernel_tss

    ; jump to_kmain
    jmp kmain

  ; HACK: how should we surface this?
  .fail:
    hlt
    jmp .fail
