; Emitted x64 scan, SHA-256 675275673d03c855e33463a4de789a567b0153f81134acf0e377d1c32d838c43
140008067:     	lea	r8, [r13 + r10]
14000806c:     	cmp	rdi, r9
14000806f:     	jge	0x140008092 <.text+0x7092>
140008071:     	nop	word ptr cs:[rax + rax]
14000807b:     	nop	dword ptr [rax + rax]
140008080:     	mov	r14b, byte ptr [r12 + rdi]
140008084:     	cmp	byte ptr [r8 + rdi], r14b
140008088:     	jne	0x140008092 <.text+0x7092>
14000808a:     	inc	rdi
14000808d:     	cmp	rdi, r9
140008090:     	jl	0x140008080 <.text+0x7080>
140008092:     	cmp	rdi, rcx
140008095:     	jle	0x1400080a2 <.text+0x70a2>
140008097:     	mov	rcx, rdi
14000809a:     	mov	rdx, rsi
14000809d:     	cmp	rdi, r9
1400080a0:     	je	0x1400080bc <.text+0x70bc>
1400080a2:     	and	r10d, 0x7fff
1400080a9:     	mov	r8, qword ptr [r15 + 8*r10]
1400080ad:     	mov	r10, r8
