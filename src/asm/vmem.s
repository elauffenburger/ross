%include "macros.inc"

extern __kernel_start
extern __kernel_end

extern after_paging_init

PAGE_ENTRY_SIZE equ 4 * KiB

section .bss
  align 4 * KiB

  global page_dir
  page_dir:
    resb PAGE_ENTRY_SIZE

  global page_table_0
  page_table_0:
    resb PAGE_ENTRY_SIZE

section .multiboot.text
  global paging_init
  paging_init:
    ; page_table_entry_phys_ptr = page_table_0_addr_virt - HIGHER_HALF
    mov edi, (page_table_0 - HIGHER_HALF)
    ; phys_addr_to_map
    mov esi, 0

    ; num_pages_to_map
    ;
    ; NOTE: we're only mapping at most 1023 pages; 
    ; we'll manually map memory-mapped IO (like VGA) into the last page.
    mov ecx, 1023

  .loop:
    ; If we're not at least at __kernel_start yet, go to the next page.
    cmp esi, __kernel_start
    jl .next_page

    ; If we've finished mapping the kernel; jump to done.
    cmp esi, (__kernel_end - HIGHER_HALF)
    jge .page_one_done

    ; Otherwise, map the page into the page table!
    
    ; page_entry = phys_addr_to_map | (PRESENT | RW)
    mov edx, esi  
    or edx, (PTE_PRESENT | PTE_RW)

    ; *page_table_entry_phys_ptr = page_entry
    mov [edi], edx

  .next_page:
    ; phys_addr_to_map += 4096
    ; page_table_entry_phys_ptr += 4
    add esi, 4096
    add edi, 4

    loop .loop

  .page_one_done:
	  ; map VGA text buf as (PRESENT | RW) to the last page in page table 1 (giving it address 0xc03ff000).
    mov dword [page_table_0 - HIGHER_HALF + 4 * 1023], (VGA_TEXT_BUF_ADDR | (PTE_PRESENT | PTE_RW))

    ; Here be dragons! 
    ;
    ; Once we turn on protected mode, we need to be in a valid address or else things are going 
    ; to get _weird_ (we'd immediately page fault because we're no longer in a mapped address).
    ;
    ; To avoid this, we need to identity map the kernel such that the following dir entries are the same:
    ;   - page_dir[0]:
    ;     - 0x00000000 to 0x003fffff
    ;     - what we just mapped
    ;     - where we currently are physically
    ;
    ;   - page_dir[768]:
    ;     - 0xc0000000 to 0xc03fffff
    ;     - where we virtually mapped the kernel via the linker
    ;
    ; This mapping would be the same for page_dir[1] -> page_dir[769], etc.
    ;
    ; Once we turn on protected mode, we'll still be in a valid (paged-in) address in page table 0,
    ; after which we can jump to the higher half and drop page table 0 (so it can be used for userspace).

    ; page_dir[0]   = phys_addr(addr_of_index(page_table, 0)) | flags_to_int(PRESENT | RW)
    ; page_dir[768] = ...
    mov dword [page_dir - HIGHER_HALF + 0],   (page_table_0 - HIGHER_HALF + (PDE_PRESENT | PDE_RW))
    mov dword [page_dir - HIGHER_HALF + 768], (page_table_0 - HIGHER_HALF + (PDE_PRESENT | PDE_RW))

    ; set page_dir as the active page directory via cr3
    mov ecx, page_dir - HIGHER_HALF
    mov cr3, ecx

    ; enable protected mode w/ paging
    mov ecx, cr0
    or ecx, (CR0_PE | CR0_PG)
    mov cr0, ecx

    ; we're done!
    ret

section .text:
  global paging_unset_identity_mapping
  paging_unset_identity_mapping:
    ; unmap page_dir[0] 
    mov dword [page_dir + 0], 0

    ; reload the page dir
    mov ecx, cr3
    mov cr3, ecx

    ret

VGA_TEXT_BUF_ADDR  equ 0x000b8000
VGA_FRAME_BUF_ADDR equ 0x000a0000

PTE_PRESENT equ 1 << 0
PTE_RW      equ 1 << 1

PDE_PRESENT equ 1 << 0
PDE_RW      equ 1 << 1

; Protected Mode Enable
CR0_PE equ 1 << 0
; Write protect
CR0_WP equ 1 << 16
; Paging
CR0_PG equ 1 << 31
