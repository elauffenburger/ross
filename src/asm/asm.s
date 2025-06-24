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

  ; esi = curr_proc
  mov esi, [curr_proc]

  ; esi.*.esp
  mov [esi], esp

  ; esi.*.state = .stopped
  mov word [esi + 16], 0

  ; esi = curr_proc.next
  mov esi, [esi + 21]
  ; esi.*.state = .running
  mov word [esi + 16], 1

  ; curr_proc = esi
  mov [curr_proc], esi

  ; esp = esi.esp
  mov esp, [esi]

  ; TODO: update TSS if switching to userspace

  ; compare cr3 values; if they're the same, skip updating the register value
  mov ebx, [esi + 8]
  mov ecx, cr3
  cmp ebx, ecx
  je .done

.update_cr3:
  ; ...otherwise, update cr3
  mov cr3, ebx

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
