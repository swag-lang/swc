.intel_syntax noprefix
.text
movzx rax, byte ptr [rdi + rsi]
movzx rcx, byte ptr [rdi + rsi + 1]
add rcx, rax
shl rax, 5
add rax, rcx
movzx rcx, byte ptr [rdi + rsi + 2]
add rcx, rax
shl rax, 5
add rax, rcx
movzx rcx, byte ptr [rdi + rsi + 3]
add rcx, rax
shl rax, 5
add rax, rcx
movzx eax, ax
