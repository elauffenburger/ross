global gdtr
global load_gdtr

section .data
  align 4

gdtr:
  dw 0 ; gdt limit
  dd 0 ; gdt address

section .text
  align 4

; load_gdtr(addr, limit)
load_gdtr:
  cli

  push ebp
  mov ebp, esp

  ; write base addr
  mov eax, [ebp + 16]
  mov [gdtr + 2], eax

  ; write limit
  mov ax, [ebp + 16 + 4]
  mov [gdtr], ax

  ; load gdtr
  lgdt [gdtr]

  mov eax, gdtr

  mov esp, ebp
  pop ebp

  ; sti
  ; nop

  ret