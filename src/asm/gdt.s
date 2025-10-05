bits 32

struc gdt_desc
  .limit: resw 0
  .addr: resd 0
endstruc

struc tss
  .link: resw 0
  ._r1: resw 0

  .esp0: resd 0

  .ss0: resw 0
  ._r2: resw 0

  .esp1: resd 0

  .ss1: resw 0
  ._r3: resw 0

  .esp2: resd 0

  .ss2: resw 0
  ._r4: resw 0

  .cr3: resd 0
  .eip: resd 0
  .eflags: resd 0
  .eax: resd 0
  .ecx: resd 0
  .edx: resd 0
  .ebx: resd 0
  .esp: resd 0
  .ebp: resd 0
  .esi: resd 0
  .edi: resd 0

  .es: resw 0
  ._r5: resw 0

  .cs: resw 0
  ._r6: resw 0

  .ss: resw 0
  ._r7: resw 0

  .ds: resw 0
  ._r8: resw 0

  .fs: resw 0
  ._r9: resw 0

  .gs: resw 0
  ._r10: resw 0

  .ldtr: resw 0
  ._r11: resw 0

  ._r12: resw 0

  .iopb: resw 104

  .ssp: resd 0
endstruc

section .data
  gdtr:
    istruc gdt_desc
    iend

  kernel_tss:
    istruc tss
    iend
