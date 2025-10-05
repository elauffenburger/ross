BITS 32

extern gdt
extern gdt_len
extern gdt_kernel_code_index
extern gdt_kernel_tss_index
extern gdtr

extern curr_proc
extern curr_proc_time_slice_ms

extern proc_irq_switching_enabled
extern on_irq0

extern kmain

KiB   equ 1024

MULTIBOOT2_MAGIC equ 0x36d76289

STACK_SIZE      equ 16 * KiB
PAGE_ENTRY_SIZE equ 4 * KiB

struc gdt_desc
  .limit: resw 0
  .addr: resd 0
endstruc

struc tss
  .link: resw 0
  ._r1: resw 0

  .esp0: resd 0

  .ss0: resw 0
  ._r2: resw 0

  .esp1: resd 0

  .ss1: resw 0
  ._r3: resw 0

  .esp2: resd 0

  .ss2: resw 0
  ._r4: resw 0

  .cr3: resd 0
  .eip: resd 0
  .eflags: resd 0
  .eax: resd 0
  .ecx: resd 0
  .edx: resd 0
  .ebx: resd 0
  .esp: resd 0
  .ebp: resd 0
  .esi: resd 0
  .edi: resd 0

  .es: resw 0
  ._r5: resw 0

  .cs: resw 0
  ._r6: resw 0

  .ss: resw 0
  ._r7: resw 0

  .ds: resw 0
  ._r8: resw 0

  .fs: resw 0
  ._r9: resw 0

  .gs: resw 0
  ._r10: resw 0

  .ldtr: resw 0
  ._r11: resw 0

  ._r12: resw 0

  .iopb: resw 104

  .ssp: resd 0
endstruc

section .bss
  align 4 * 1024

  page_dir:
    resb PAGE_ENTRY_SIZE
  page_table_1:
    resb PAGE_ENTRY_SIZE

  global stack_bottom
  stack_bottom:
    resb STACK_SIZE
  global stack_top
  stack_top:

section .data
  global multiboot2_info_addr
  multiboot2_info_addr dd 0

  global stack_size
  stack_size dd STACK_SIZE

  gdtr:
    istruc gdt_desc
    iend

  kernel_tss:
    istruc tss
    iend

section .text

; This is pretty weird! The gist of it is we need to enable Protected Mode, load the GDT,
; and set up the segmentation registers through some black magick.
;
; 1. Set the DS register to 0 to tell the CPU we're in segment 0 right now
;    (and that's where it can find the GDT after our lgdt)
; 2. Turn on bit 0 of CR0 to enable Protected Mode.
; 3. Load the GDT.
; 4. Perform a far jump into our kernel-space code segment (segment 1) to tell the processor we're in segment 1,
;    so we just jump to a label but with the Kernel Code segment offset set (which will be 8 * offset_num).
; 5. Set our DS and SS registers
; 6. Done!
%macro load_gdt 0
  align 4

  ; clear interrupts
  cli

  ; set DS to 0 (null segment) to tell the CPU that's where it can find the GDT after lgdt
  xor ax, ax
  mov ds, ax

  ; turn on Protected Mode (...though it should already be on!)
  mov eax, cr0
  or eax, 1
  mov cr0, eax

  ; load the gdt!
  lgdt [gdtr]

  ; set CS to the kernel_code segment offset (8 * index) by far jumping to a local label
  ; and specifying the offset.
  jmp .after_lgdtr:(8 * gdt_kernel_code_index)

.after_lgdtr:
  align 4

  ; set data segment registers to 16d (segment 2)
  mov ax, 16
  mov ds, ax
  mov es, ax
  mov fs, ax
  mov gs, ax
  mov ss, ax
%endmacro

%macro load_tss 1
  mov ax, %1
  ltr ax
%endmacro

global _kentry
_kentry:
  ; make sure eax has the multiboot2 magic number
  cmp eax, MULTIBOOT2_MAGIC
  jne .fail

  ; move ebx to multiboot2_info_addr
  mov [multiboot2_info_addr], ebx

  ; load the GDT
  mov dword [gdtr + gdt_desc.addr], gdt
  mov word [gdtr + gdt_desc.limit], gdt_len
  load_gdt

  ; load the kernel TSS as the active TSS
  mov word [kernel_tss + tss.ss0], 8 * gdt_kernel_tss_index
  mov dword [kernel_tss + tss.esp0], stack_top
  load_tss kernel_tss

  ; jump to_kmain
  jmp kmain

; HACK: how should we surface this?
.fail:
  hlt
  jmp .fail

; TODO: remove -- this is for cooperative multitasking, which we're dropping.
; switch_proc() void
global switch_proc
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
global irq0_handler
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
