extern curr_proc;

global proc_irq_switching_enabled

global yield_to_proc
global irq_switch_to_proc

pic_1_cmd_port equ 0x20
pic_cmd_eoi equ 0x20

%macro outb 3
  mov %1, %3
  out %2, %1
%endmacro

section .data
  proc_irq_switching_enabled: db 0

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

  ; save eax
  push eax

  ; Check if curr_proc.next is null; if so, bail!
  mov eax, [curr_proc]
  mov eax, [eax + 21]
  cmp eax, 0
  je .abort

  ; ...otherwise, if irq proc switch is actually enabled; if not, bail!
  mov al, [proc_irq_switching_enabled]
  cmp al, 1
  je .switch

  ; ...otherwise send eoi, restore eax, and bail.
.abort:
  xor eax, eax
  outb al, pic_1_cmd_port, pic_1_cmd_port
  pop eax
  iret

.switch:
  ; restore eax before pusha
  pop eax

  ; save registers
  pusha

  ; move *curr_proc to edi
  mov edi, [curr_proc]

  ; save esp in SavedRegisters
  mov [edi], esp

  ; mark curr_proc stopped
  mov word [edi + 16], 0

  ; move curr_proc.next to edi
  mov edi, [edi + 28]
  ; mark new proc running
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
  ; send eoi
  outb al, pic_1_cmd_port, pic_1_cmd_port

  ; restore registers
  popa

  iret

