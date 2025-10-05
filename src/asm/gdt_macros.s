bits 32

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
;
; params:
;   %1: gdtr_addr
;   %2: kernel_code_index
%macro load_gdt 2
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
  lgdt %1

  ; set CS to the kernel_code segment offset (8 * index) by far jumping to a local label
  ; and specifying the offset.
  jmp .after_lgdtr:(8 * %2)

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
