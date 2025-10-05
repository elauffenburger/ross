# From zero to boot

## Build

`mise-tasks/build.sh` builds and runs the OS.

At a high level we:

- build the kernel
- package an iso
- run the iso with qemu

### Building the kernel

We actually use `build.zig` for the entire kernel build process without any magicks.

Some important notes:

- os: `freestanding`
- arch: `x86`
- abi: `none`
- cpu features:
  - we have to add/remove some features because our CPU doesn't support certain features
    - this is really just because [OS Dev](https://wiki.osdev.org/Zig_Bare_Bones#Code) claims it's necessary, but I should confirm...
    - add:
      - `soft_float`
    - remove:
      - `mmx`
      - `sse`
      - `sse2`
      - `avx`
      - `avx2`
- we disable `libc`/`libcpp` support because we, well, don't support them
- we explicitly set DWARF format to be 32bit
- we turn off the red zone to make sure we don't clobber variables in IRQ handlers (see [here](https://os.phil-opp.com/red-zone/))
- we have some assembly code at `src/asm/asm.s`
  - assembled with `nasm`
  - and used for precise operations like booting (our kernel entrypoint, `_kentry`, is here) or multitasking
  - we turn of section GC to make sure the compiler doesn't strip symbols it thinks we aren't using
- we use a linker script at `src/asm/link.ld` to control linkage
  - we start after `1M`
  - we put code in the `.multiboot` section first (since `multiboot2` requires it)
  - we provide a `__kernel_size` variable to tell the kernel how much space we have

### ISO packaging

# TODO: fill this out

- We use `limine` as a bootloader in `multiboot2` mode
  - see:
    - `vendor/limine`
    - `boot/limine.conf`

## Booting

### Phase 0 (bootloading) / Phase 1 (bootstrapping)

Before even running any code, we layout a `multiboot2` header in `src/main.zig` which is added to the `.multiboot` section and loaded first in the binary via `src/asm/link.ld`.

We enter at `_kentry` in `asm.s` which: handles bootloader bookkeeping:

- validates the `multiboot2` magic number
- moves the `multiboot2_info_addr` info to a global we can access from our `zig` code later
- trampolines us into the `zig` `_kmain` function

Once we're in `_kmain`, we:

- reset the kernel stack
- set up the GDT
- trampoline into `kmain` proper

### Phase 2 (`kmain`)

Now that we're in `kmain`, we can actually start doing stuff!

- We parse the `multiboot2` info that we saved in `multiboot2_info_addr` to get a list of capabilities and set systems up later (most notably `vga`).
- We set up our kernel memory (stack/heap) management
- We enable serial comms
- We turn on debugging features like logging
- We enable vga output

Now, we have to set up our interrupt handlers, so we:

- disable interrupts
- configure the IDT
  - sets up interrupt handlers
- enable the PIC
  - manages hardware driven by interrupts
  - we offset the table addresses by `20` (decimal) so we don't have conflicts with CPU interrupts
- enable the PIT
  - periodically triggers an interrupt
- enable interrupts
- enable ps/2 interfaces
  - for keyboard input
- set up process control
  - for multitasking
- set up virtual memory
  - this has to happen after setting up the IDT because a GPF will fire immediately
  - we identity-map the OS, so we don't have to immediately jump to an offset address, but I'm not sure how long we can do that for...
- we start up some kernel processes:
  - keyboard driver
  - terminal
