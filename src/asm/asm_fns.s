extern curr_proc;

global yield_to_proc
global irq_switch_to_proc

section .text

; NOTE: Adapted from https://wiki.osdev.org/Brendan%27s_Multi-tasking_Tutorial
; yield_to_proc() void
yield_to_proc:
  ; Notes:
  ;   For cdecl; EAX, ECX, and EDX are already saved by the caller and don't need to be saved again
  ;   EIP is already saved on the stack by the caller's "CALL" instruction
  ;   The task isn't able to change CR3 so it doesn't need to be saved

  cli

  ; save registers
  push ebx
  push esi
  push edi
  push ebp

  ; move curr_proc to edi
  mov edi, [curr_proc]

  ; save esp in SavedRegisters
  mov [edi], esp

  ; get next proc
  mov edi, [curr_proc + 28]

  ; mark curr_proc stopped
  mov word [curr_proc + 16], 0
  ; mark proc running
  mov word [edi + 16], 1
  ; make proc the curr_proc
  mov [curr_proc], edi

  ; load proc.esp
  mov esp, [edi]

  ; get proc.cr3
  mov eax, [edi + 8]
  ; get current c3
  mov ecx, cr3
  ; compare cr3 values; if they're the same, skip updating the register value
  cmp eax, ecx
  je .done
  ; ...otherwise, update cr3
  mov cr3, eax

  ; TODO: change TSS

.done:
  ; restore registers
  pop ebp
  pop edi
  pop esi
  pop ebx

  sti
  ret

; irq_switch_to_proc() void
irq_switch_to_proc:
  ; Notes:
  ;   The task isn't able to change CR3 so it doesn't need to be saved

  ; save registers
  pusha

  ; move curr_proc to edi
  mov edi, [curr_proc]

  ; save esp in SavedRegisters
  mov [edi], esp

  ; get next proc
  mov edi, [curr_proc + 28]

  ; mark curr_proc stopped
  mov word [curr_proc + 16], 0
  ; mark proc running
  mov word [edi + 16], 1
  ; make proc the curr_proc
  mov [curr_proc], esi

  ; load proc.esp
  mov esp, [edi]

  ; get proc.cr3
  mov eax, [edi + 8]
  ; get current c3
  mov ecx, cr3
  ; compare cr3 values; if they're the same, skip updating the register value
  cmp eax, ecx
  je .done
  ; ...otherwise, update cr3
  mov cr3, eax

  ; TODO: change TSS

.done:
  ; restore registers
  popa

  iret
