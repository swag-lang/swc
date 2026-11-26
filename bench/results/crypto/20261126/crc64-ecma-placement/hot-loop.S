.section .rodata
.p2align 4
.Lreverse:
    .byte 15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0

.macro function name, shift
.text
.p2align 6
.globl \name
.type \name,@function
\name:
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    sub $0x590, %rsp
    mov %rdi, %rax
    mov %rdx, %rdi
    mov %rsi, %rbx
    mov %rsi, 0x588(%rsp)
    lea 0x40(%rax), %rdx
    lea 0x80(%rax), %r9
    lea 0xc0(%rax), %r10
    lea 0x100(%rax), %rcx
    lea 0x140(%rax), %r11
    mov $0x100, %r12d
    vmovups .Lreverse(%rip), %xmm6
    jmp \name\()_body
    .p2align 6
    .if \shift
    .space \shift, 0x90
    .endif
\name\()_body:
#include "hot-region.inc"
    add $0x590, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    ret
.size \name, .-\name
.endm
#ifdef REVERSE_PLACEMENT
function ecma_new_placement, 0
function ecma_old_placement, 32
#else
function ecma_old_placement, 32
function ecma_new_placement, 0
#endif
.section .note.GNU-stack,"",@progbits
