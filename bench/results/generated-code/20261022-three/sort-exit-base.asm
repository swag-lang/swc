140007d0d:     	cmp	r13, r14
140007d10:     	jg	0x140007d22 <.text+0x6d22>
140007d12:     	mov	qword ptr [rsi + 8*r13], rdx
140007d16:     	mov	qword ptr [rsi + 8*r14], rcx
140007d1a:     	add	r13, 0x1
140007d1e:     	sub	r14, 0x1
140007d22:     	cmp	r13, r14
140007d25:     	jle	0x140007cd0 <.text+0x6cd0>
140007d27:     	mov	rax, r14
140007d2a:     	sub	rax, rdi
140007d2d:     	mov	rcx, r12
140007d30:     	sub	rcx, r13
140007d33:     	cmp	rax, rcx
140007d36:     	jge	0x140007d4e <.text+0x6d4e>
