extern curr_proc
extern curr_proc_time_slice_ms

global switch_proc

section .data
  switch_proc_in_irq db 0

section .text

; switch_proc(in_irq: bool) void
switch_proc:
  ; save in_irq
  mov eax, [esp + 4]
  mov [switch_proc_in_irq], eax

  ; save registers
  push ebx
  push esi
  push edi
  push ebp

  ; move *curr_proc to edi
  mov edi, [curr_proc]

  ; save esp in SavedRegisters
  mov [edi], esp

  ; mark curr_proc stopped
  mov word [edi + 16], 0

  ; move curr_proc.next to edi
  mov edi, [edi + 21]
  ; mark new proc running
  mov word [edi + 16], 1

  ; make proc the curr_proc
  mov [curr_proc], esi

  ; load proc.esp
  mov esp, [edi]

  ; get proc.cr3
  mov ebx, [edi + 8]
  ; get current c3
  mov ecx, cr3
  ; compare cr3 values; if they're the same, skip updating the register value
  cmp ebx, ecx
  je .done
  ; ...otherwise, update cr3
  mov cr3, ebx

  ; TODO: change TSS if switching to userspace

.done:
  ; restore registers
  pop ebp
  pop edi
  pop esi
  pop ebx

  mov eax, [switch_proc_in_irq]
  cmp eax, 1
  je .in_irq

.not_irq:
  ret

.in_irq:
  iret
