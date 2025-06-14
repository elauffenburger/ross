extern curr_proc;

global switch_to_proc

section .text

; NOTE: Adapted from https://wiki.osdev.org/Brendan%27s_Multi-tasking_Tutorial
; switch_to_proc(proc: *Process, from_int: bool) void
switch_to_proc:
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
  ; this is tricky!
  ;   go back 4 u32 to the original esp location before we pushed the registers
  ;     this will be the return addr
  ;   go back one more u32 to get the proc argument
  mov esi, [esp + (4 + 1)*4]
  ;   go back one more u8 to get from_int
  mov edx, [esp + (4 + 2)*4]

  ; mark curr_proc stopped
  mov word [curr_proc + 16], 0
  ; mark proc running
  mov word [esi + 16], 1
  ; make proc the curr_proc
  mov [curr_proc], esi

  ; load proc.esp
  mov esp, [esi]

  ; get proc.cr3
  mov eax, [esi + 8]
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

  ; check if we're coming from an interrupt handler.
  cmp edx, 1
  je .ret_int

.ret_not_int:
  sti
  ret

.ret_int:
  iret
