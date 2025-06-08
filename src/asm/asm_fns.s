extern curr_proc;

global switch_to_proc

section .text

; NOTE: Adapted from https://wiki.osdev.org/Brendan%27s_Multi-tasking_Tutorial
; switch_to_proc(proc: *Process) void
switch_to_proc:
  cli

  ; Notes:
  ;   For cdecl; EAX, ECX, and EDX are already saved by the caller and don't need to be saved again
  ;   EIP is already saved on the stack by the caller's "CALL" instruction
  ;   The task isn't able to change CR3 so it doesn't need to be saved

  ; save registers
  push ebx
  push esi
  push edi
  push ebp

  ; move curr_proc to edi
  mov edi, [curr_proc]

  ; save esp in SavedRegisters
  mov [edi], esp

  ; move proc to esi
  ; we need to offset by (3) u32s we pushed and (2) pointers to get to the current registers arg
  mov esi, [esp + (3 + 2)*4]

  ; make proc the curr_proc
  mov [curr_proc], esi

  ; load proc.esp
  mov esp, [esi]

  ; TODO: load new page dir.
  ;; load proc.cr3
  ; mov eax, [esi + 17]
  ; mov cr3, eax

  ; TODO: change TSS

  ; restore registers
  pop ebp
  pop edi
  pop esi
  pop ebx

  ; restore interrupts
  sti

  ret
