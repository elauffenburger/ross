%include "macros.inc"

global page_dir:data
global paging_init:function

extern __kernel_start
extern __kernel_end
extern __kernel_size

PAGE_ENTRY_SIZE equ 4 * KiB

NUM_PAGE_TABLES        equ 4 * GiB / PAGE_ENTRY_SIZE

; HACK: this should be computed from __kernel_size and used at runtime
NUM_PAGE_TABLES_KERNEL equ 4000

HIGHER_HALF_PAGE_DIR_INDEX equ 768

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

section .bss
  align 4 * KiB

  ; Reserve space for the page directory.
  page_dir:
    resb PAGE_ENTRY_SIZE * NUM_PAGE_TABLES

  ; Reserve space for all our page tables.
  page_tables:
    times NUM_PAGE_TABLES resb PAGE_ENTRY_SIZE

section .multiboot.text
  ; paging_init(return_addr: u32)
  ;
  ; NOTE: we're passing return_addr in ebx, so make sure not to clobber that register!
  paging_init:
    ; HINT: search logs for: movl $0x3ff, %ecx

    ; page_table_entry_phys_ptr = virt_addr(page_tables[0]) - HIGHER_HALF
    mov edi, (page_tables - HIGHER_HALF)
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

    ; If we've finished mapping the first dir entry, jump to done.
    cmp esi, (__kernel_end - HIGHER_HALF)
    jge .dir_entry_one_done

    ; Otherwise, map the page into the page table!

    ; page_table_entry = phys_addr_to_map | (PRESENT | RW)
    mov edx, esi
    or edx, (PTE_PRESENT | PTE_RW)

    ; *page_table_entry_phys_ptr = page_entry
    mov dword [edi], edx

  .next_page:
    ; phys_addr_to_map += 4096
    ; page_table_entry_phys_ptr += 4
    add esi, 4096
    add edi, 4

    loop .loop

  .dir_entry_one_done:
	  ; map VGA text buf as (PRESENT | RW) to the last page in page table 1 (giving it address 0xc03ff000).
    mov dword [page_tables - HIGHER_HALF + 4 * 1023], (VGA_TEXT_BUF_ADDR | (PTE_PRESENT | PTE_RW))

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

    ; NOTE: we're just mapping in pages for the kernel here; once we start allocating memory outside of the kernel space, we're
    ; have to page new entries in.
  %assign i 0
  %rep NUM_PAGE_TABLES_KERNEL
    %define page_dir_entry (page_tables - HIGHER_HALF + (i * 4)) + (PDE_PRESENT | PDE_RW)

    mov dword [page_dir - HIGHER_HALF + (0   + i) * 4], page_dir_entry
    mov dword [page_dir - HIGHER_HALF + (768 + i) * 4], page_dir_entry

    %assign i i+1
  %endrep

  .set_page_dir:
    ; set page_dir as the active page directory via cr3
    mov ecx, page_dir - HIGHER_HALF
    mov cr3, ecx

    ; enable protected mode w/ paging
    mov ecx, cr0
    or ecx, (CR0_PE | CR0_PG)
    mov cr0, ecx

    ; We're done init-ing the page dir, so we're now free to jump to the higher half of memory;
    ; we can do that by just targeting a function in the .text section (which has been linked above xc0000000).
    ;
    ; Since we have to jump to _some_ function in the higher half and we'll eventually need to remove the
    ; identity mapping of the first page, we might as well make that our first stop in .text!
    jmp paging_init_unset_identity_mapping

section .text:
  ; NOTE: this is expected to be called from paging_init!
  ; You _cannot_ it from any other function.
  paging_init_unset_identity_mapping:
    ; unmap page_dir[0]
    mov dword [page_dir], 0

    ; reload the page dir
    mov ecx, cr3
    mov cr3, ecx

    ; jump to the return address passed to paging_init in ebx.
    jmp ebx
