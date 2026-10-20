.intel_syntax noprefix
.text
scan:
add r13, 1
mov rcx, qword ptr [rsi + r13 * 8]
cmp rcx, rax
jb scan
