global gdtr
global load_gdtr

section .data
  align 4

gdtr:
  dw 0x00 ; gdt limit
  dd 0x00 ; gdt address

section .text
  align 4

; ---------
; load_gdtr(addr: u32, limit: u16) u32
; ---------
;
; This is pretty weird, so an explanation is warranted!
;
; 1. Set the DS register to 0 to indicate that the GDT is in the NULL segment.
; 2. Turn on bit 0 of CR0 to enable Protected Mode.
; 3. Load the GDT!
; 4. Perform a long jump into our kernel-space code segment (segment 1) to tell the processor we're in segment 1,
;    so we just jump into a fn-local label but with the code segment offset (which will be 8 * offset_num).
; 5. Set our DS and SS registers
; 6. Done! Let the caller know where the GDTR data is stored.
load_gdtr:
  cli

  push ebp
  mov ebp, esp

  ; write base addr
  mov eax, [ebp + 8]
  mov [gdtr + 2], eax

  ; write limit
  xor eax, eax
  mov ax, [ebp + 12]
  mov [gdtr], ax

  ; set DS to 0
  xor ax, ax
  mov ds, ax

  ; turn on Protected Mode (...though it should already be on!)
  mov eax, cr0
  or eax, 1
  mov cr0, eax

  ; load the gdt!
  lgdt [gdtr]

  ; tell the processor we're in segment 1
  jmp 8:.after_lgdtr

.after_lgdtr:
  mov ax, 16
  mov ds, ax

  mov eax, gdtr

  mov esp, ebp
  pop ebp

  ret