.intel_syntax noprefix
.text
movzx rax, byte ptr [rdi + rsi]
imul rax, rax, 33
movzx rcx, byte ptr [rdi + rsi + 1]
add rax, rcx
imul rax, rax, 33
movzx rcx, byte ptr [rdi + rsi + 2]
add rax, rcx
imul rax, rax, 33
movzx rcx, byte ptr [rdi + rsi + 3]
add rax, rcx
movzx eax, ax
