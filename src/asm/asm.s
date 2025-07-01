extern curr_proc
extern curr_proc_time_slice_ms
extern proc_irq_switching_enabled
extern on_irq0

global switch_proc
global irq0_handler

section .data
  switch_proc_in_irq db 0

section .text

; switch_proc() void
switch_proc:
  ; save registers
  push ebx
  push esi
  push edi
  push ebp

  ; esi = curr_proc
  mov esi, [curr_proc]

  ; curr_proc.*.esp = esp
  mov [esi], esp

  ; esi.*.state = .stopped
  mov byte [esi + 16], 0

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

  ret

; irq0_handler() void
irq0_handler:
  ; save registers
  pusha

  ; call on_irq0
  ; NOTE: the direction flag must be clear on entry for SYS V calling conv.
  cld
  call on_irq0

  ; check if proc switching is enabled; if so, perform the switch; otherwise, we're done!
  cmp byte [proc_irq_switching_enabled], 0x1
  je .switch

.exit_early:
  ; restore registers and return
  popa
  iret

.switch:
  ; esi = curr_proc
  mov esi, [curr_proc]

  ; curr_proc.*.esp = esp
  mov [esi], esp

  ; esi.*.state = .stopped
  mov byte [esi + 16], 0

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
  popa

  ; re-enable interrupts if they were disabled
  push eax
  mov eax, [esp + 12]
  or eax, 0x0200
  mov [esp + 12], eax
  pop eax

  ; return to new eip
  iret
