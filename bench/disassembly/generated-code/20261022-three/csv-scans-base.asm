140003440:     	mov	r15, rcx
140003443:     	cmp	r15, rdi
140003446:     	jae	0x14000345f <.text+0x245f>
140003448:     	nop	dword ptr [rax + rax]
140003450:     	cmp	byte ptr [rsi + r15], 0xa
140003455:     	je	0x14000345f <.text+0x245f>
140003457:     	inc	r15
14000345a:     	cmp	r15, rdi
14000345d:     	jb	0x140003450 <.text+0x2450>
14000345f:     	cmp	rcx, r15
140003462:     	jae	0x14000347f <.text+0x247f>
140003464:     	nop	word ptr cs:[rax + rax]
14000346e:     	nop
140003470:     	cmp	byte ptr [rsi + rcx], 0x2c
140003474:     	je	0x14000347f <.text+0x247f>
140003476:     	add	rcx, 0x1
14000347a:     	cmp	rcx, r15
14000347d:     	jb	0x140003470 <.text+0x2470>
14000347f:     	lea	rdi, [rcx + 0x1]
140003483:     	mov	rcx, rdi
140003486:     	cmp	rcx, r15
140003489:     	jae	0x14000349f <.text+0x249f>
14000348b:     	nop	dword ptr [rax + rax]
140003490:     	cmp	byte ptr [rsi + rcx], 0x2c
140003494:     	je	0x14000349f <.text+0x249f>
140003496:     	add	rcx, 0x1
14000349a:     	cmp	rcx, r15
14000349d:     	jb	0x140003490 <.text+0x2490>
14000349f:     	mov	r11, rcx
1400034a2:     	sub	r11, rdi
1400034a5:     	add	rcx, 0x1
1400034a9:     	cmp	rcx, r15
1400034ac:     	jae	0x1400034bf <.text+0x24bf>
1400034ae:     	nop
1400034b0:     	cmp	byte ptr [rsi + rcx], 0x2c
1400034b4:     	je	0x1400034bf <.text+0x24bf>
1400034b6:     	add	rcx, 0x1
1400034ba:     	cmp	rcx, r15
1400034bd:     	jb	0x1400034b0 <.text+0x24b0>
1400034bf:     	add	rcx, 0x1
1400034c3:     	xor	r14d, r14d
1400034c6:     	cmp	rcx, r15
1400034c9:     	jae	0x1400034ed <.text+0x24ed>
1400034cb:     	nop	dword ptr [rax + rax]
