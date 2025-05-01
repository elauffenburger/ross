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
  ; clear interrupts
  cli

  ; write base addr
  pop eax
  mov [gdtr], eax

  ; write limit
  mov eax, [esp + 8]
  mov [gdtr], ax

  ; load gdtr
  lgdt [gdtr]

  ; re-enable interrupts
  sti

  hlt

  ret