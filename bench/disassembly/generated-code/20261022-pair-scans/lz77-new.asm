; Emitted x64 scan, SHA-256 463fdeea58c965016ed6e55bde56adbbb0082a44aa274e4dee8380d714e7c559
1400014ef:     	lea	r8, [r13 + r10]
1400014f4:     	cmp	rdi, r9
1400014f7:     	jge	0x140001583 <.text+0x583>
1400014fd:     	nop	word ptr cs:[rax + rax]
140001507:     	nop	word ptr [rax + rax]
140001510:     	mov	r14, r9
140001513:     	sub	r14, rdi
140001516:     	cmp	r14, 0x4
14000151a:     	jb	0x140001550 <.text+0x550>
14000151c:     	mov	r14b, byte ptr [r12 + rdi]
140001520:     	cmp	byte ptr [r8 + rdi], r14b
140001524:     	jne	0x140001583 <.text+0x583>
140001526:     	mov	r14b, byte ptr [r12 + rdi + 0x1]
14000152b:     	cmp	byte ptr [r8 + rdi + 0x1], r14b
140001530:     	jne	0x140001574 <.text+0x574>
140001532:     	mov	r14b, byte ptr [r12 + rdi + 0x2]
140001537:     	cmp	byte ptr [r8 + rdi + 0x2], r14b
14000153c:     	jne	0x140001579 <.text+0x579>
14000153e:     	mov	r14b, byte ptr [r12 + rdi + 0x3]
140001543:     	cmp	byte ptr [r8 + rdi + 0x3], r14b
140001548:     	jne	0x14000157f <.text+0x57f>
14000154a:     	lea	rdi, [rdi + 0x4]
14000154e:     	jmp	0x140001510 <.text+0x510>
140001550:     	cmp	rdi, r9
140001553:     	jge	0x140001583 <.text+0x583>
140001555:     	nop	word ptr cs:[rax + rax]
14000155f:     	nop
140001560:     	mov	r14b, byte ptr [r12 + rdi]
140001564:     	cmp	byte ptr [r8 + rdi], r14b
140001568:     	jne	0x140001583 <.text+0x583>
14000156a:     	inc	rdi
14000156d:     	cmp	rdi, r9
140001570:     	jl	0x140001560 <.text+0x560>
140001572:     	jmp	0x140001583 <.text+0x583>
140001574:     	inc	rdi
140001577:     	jmp	0x140001583 <.text+0x583>
140001579:     	lea	rdi, [rdi + 0x2]
14000157d:     	jmp	0x140001583 <.text+0x583>
14000157f:     	lea	rdi, [rdi + 0x3]
140001583:     	cmp	rdi, rcx
140001586:     	jle	0x140001593 <.text+0x593>
140001588:     	mov	rcx, rdi
14000158b:     	mov	rdx, rsi
14000158e:     	cmp	rdi, r9
140001591:     	je	0x1400015ad <.text+0x5ad>
140001593:     	and	r10d, 0x7fff
14000159a:     	mov	r8, qword ptr [r15 + 8*r10]
14000159e:     	mov	r10, r8
1400015a1:     	inc	r11
1400015a4:     	test	r8, r8
