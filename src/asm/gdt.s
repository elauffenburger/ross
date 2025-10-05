BITS 32

%include "macros.s"
%include "gdt_macros.s"

section .data
  global gdtr
  gdtr:
    istruc gdt_desc
    iend

  global kernel_tss
  kernel_tss:
    istruc tss
    iend
