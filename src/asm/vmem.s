%include "macros.inc"

global page_dir:data
global paging_init:function

extern __kernel_end
extern __kernel_size
extern _kentry_higher_half

TABLE_ENTRY_SIZE       equ 4 * KiB
NUM_ENTRIES_PER_TABLE  equ 1024

NUM_PAGE_TABLES equ 4 * GiB / TABLE_ENTRY_SIZE

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
    resb TABLE_ENTRY_SIZE * NUM_PAGE_TABLES

  ; Reserve space for all our page tables.
  ;
  ; This will be a contiguous block of entries, meaning:
  ;   - page_tables[0] is (table: 0, entry: 0)
  ;   - page_tables[4095] is (table: 0, entry: 4095)
  ;   - page_tables[4096] is (table: 1, entry: 0)
  page_tables:
    times NUM_PAGE_TABLES resb TABLE_ENTRY_SIZE

section .multiboot.text
  paging_init:
    ; page_table_entry: *u32 = phys_addr(page_tables)
    mov edi, page_tables - HIGHER_HALF

    ; phys_addr = 0
    mov esi, 0
  .map_page_table_entries:
    ; Check if we've finished mapping the kernel.
    cmp esi, (__kernel_end - HIGHER_HALF)
    jge .make_page_dir

    ; entry_val: u32 = phys_addr_to_map | (PRESENT | RW)
    mov edx, esi
    or edx, (PTE_PRESENT | PTE_RW)

    ; page_table_entry.* = entry_val
    mov dword [edi], edx

    ; phys_addr += 4096
    ; page_table_entry += 4
    add esi, 4096
    add edi, 4

    ; map the next entry!
    jmp .map_page_table_entries

  .make_page_dir:
    ; NOTE: we're just mapping in pages for the kernel here; once we start allocating memory outside of the kernel space, we're
    ; have to page new entries in.
    
	  ; map VGA text buf as (PRESENT | RW) to the last page in page_tables[0] (giving it address 0xc03ff000).
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
    mov dword [page_dir - HIGHER_HALF], (page_tables - HIGHER_HALF) + (PDE_PRESENT | PDE_RW)

    ; Now, map the rest of the pages dir entries in.
    ; i = 0
    mov ebx, 0
  .add_page_dir_entry:
    ; dir_entry = (page_tables - HIGHER_HALF + (TABLE_ENTRY_SIZE * i)) + (PDE_PRESENT | PDE_RW)
    mov eax, ebx
    mov ecx, TABLE_ENTRY_SIZE
    mul ecx
    add eax, page_tables - HIGHER_HALF + (PDE_PRESENT | PDE_RW)
    mov esi, eax

    ; mov dword [page_dir - HIGHER_HALF + (HIGHER_HALF_PAGE_DIR_INDEX + i) * 4], dir_entry
    mov eax, ebx
    add eax, HIGHER_HALF_PAGE_DIR_INDEX
    mov ecx, 4
    mul ecx
    add eax, page_dir - HIGHER_HALF
    mov dword [eax], esi

    ; i += 1 
    add ebx, 1

    ; num_page_tables_kernel = __kernel_size / 4MiB
    mov eax, __kernel_size
    mov ecx, 4 * MiB
    div ecx

    ; if (i >= num_page_tables_kernel) break
    cmp ebx, eax
    jl .add_page_dir_entry

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
  paging_init_unset_identity_mapping:
    ; unmap page_dir[0]
    ; HACK: we _should_ be able to do this, but we read multiboot data in the kernel, so we need to maintain the mapping for now; is that a bad thing though?
    ;mov dword [page_dir], 0

    ; reload the page dir
    mov ecx, cr3
    mov cr3, ecx

    ; jump back to _kentry_higher_half
    jmp _kentry_higher_half
