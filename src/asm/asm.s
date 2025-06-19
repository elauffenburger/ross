extern curr_proc;

global proc_irq_switching_enabled
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

; irq_switch_to_proc() void
irq_switch_to_proc:
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
  outb al, pic_1_cmd_port, pic_cmd_eoi
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
  mov edi, [edi + 21]
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

  ; TODO: change TSS if switching to userspace

.done:
  ; send eoi
  xor eax, eax
  outb al, pic_1_cmd_port, pic_cmd_eoi

  ; restore registers
  popa

  ; turn interrupts back on in the eflags pushed to the stack.
  .eflags_offset: equ 4 + (4 * 2)

  push eax
  mov eax, [esp + .eflags_offset]
  or eax, 0x0200
  mov [esp + .eflags_offset], eax
  pop eax

  iret
