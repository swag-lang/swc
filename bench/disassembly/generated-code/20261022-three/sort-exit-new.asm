1400011ad:     	cmp	r13, r14
1400011b0:     	jg	0x1400011c7 <.text+0x1c7>
1400011b2:     	mov	qword ptr [rsi + 8*r13], rdx
1400011b6:     	mov	qword ptr [rsi + 8*r14], rcx
1400011ba:     	add	r13, 0x1
1400011be:     	sub	r14, 0x1
1400011c2:     	cmp	r13, r14
1400011c5:     	jle	0x140001170 <.text+0x170>
1400011c7:     	mov	rax, r14
1400011ca:     	sub	rax, rdi
1400011cd:     	mov	rcx, r12
1400011d0:     	sub	rcx, r13
1400011d3:     	cmp	rax, rcx
1400011d6:     	jge	0x1400011ee <.text+0x1ee>
