global hello_world

section .asm_fns
  align 4

hello_world:
  push ax

  mov ah, 0x0e

  mov al, 'h'
  int 0x10

  hlt

  mov al, 'h'
  int 0x10

  mov al, 'e'
  int 0x10

  mov al, 'l'
  int 0x10
  int 0x10

  mov al, 'o'
  int 0x10

  mov al, ' '
  int 0x10

  mov al, 'a'
  int 0x10

  mov al, 's'
  int 0x10

  mov al, 'm'
  int 0x10

  mov al, 10
  int 0x10

  pop ax
  ret
