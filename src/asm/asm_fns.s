extern curr_proc;

global switch_to_proc

section .text

; NOTE: Adapted from https://wiki.osdev.org/Brendan%27s_Multi-tasking_Tutorial
; switch_to_proc(proc: *Process) void
switch_to_proc:
  ; Notes:
  ;   For cdecl; EAX, ECX, and EDX are already saved by the caller and don't need to be saved again
  ;   EIP is already saved on the stack by the caller's "CALL" instruction
  ;   The task isn't able to change CR3 so it doesn't need to be saved

  push ebx                    ; save registers
  push esi
  push edi
  push ebp

  mov edi, [curr_proc]        ; move curr_proc to edi
                              ; we need to offset by (4) u32s we pushed and (2) pointers to get to the current registers arg
  mov [edi], esp              ; save esp in SavedRegisters

  mov esi, [esp -(4 + 1)*4]   ; move proc to esi
  mov [curr_proc], esi        ; make proc the curr_proc

  mov esp, [esi + 9]          ; load proc.esp

  ; TODO: load new page dir.
  ; mov eax, [esi + 17]         ; load proc.cr3
  ; mov cr3, eax

  ; TODO: change TSS

  pop ebp                     ; restore registers
  pop edi
  pop esi
  pop ebx

  ret
