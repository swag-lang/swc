.intel_syntax noprefix
.text
movzx rax, byte ptr [rdi + rsi]
imul rax, rax, 35937
movzx rcx, byte ptr [rdi + rsi + 1]
imul rcx, rcx, 1089
add rax, rcx
movzx rcx, byte ptr [rdi + rsi + 2]
movzx rdx, byte ptr [rdi + rsi + 3]
add rdx, rcx
shl rcx, 5
add rcx, rdx
add rax, rcx
movzx eax, ax
