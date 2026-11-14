.intel_syntax noprefix
.text
movzx rax, byte ptr [rdi + rsi]
imul rax, rax, 35937
movzx rcx, byte ptr [rdi + rsi + 1]
imul rcx, rcx, 1089
movzx rdx, byte ptr [rdi + rsi + 2]
imul rdx, rdx, 33
add rcx, rdx
movzx rdx, byte ptr [rdi + rsi + 3]
add rax, rdx
add rax, rcx
movzx eax, ax
