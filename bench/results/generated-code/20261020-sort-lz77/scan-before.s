.intel_syntax noprefix
.text
scan:
add r13, 1
cmp qword ptr [rsi + r13 * 8], rax
jb scan
