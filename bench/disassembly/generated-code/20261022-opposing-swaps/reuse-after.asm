140007520: 4c 89 56 40                 	mov	qword ptr [rsi + 0x40], r10
140007524: 45 31 d2                    	xor	r10d, r10d
140007527: 4d 85 c9                    	test	r9, r9
14000752a: 0f 84 aa 00 00 00           	je	0x1400075da <.text+0x65da>
140007530: 4d 85 c9                    	test	r9, r9
140007533: 0f 8e 92 00 00 00           	jle	0x1400075cb <.text+0x65cb>
140007539: 4e 8b 34 ce                 	mov	r14, qword ptr [rsi + 8*r9]
14000753d: 4c 89 36                    	mov	qword ptr [rsi], r14
140007540: 4e 89 0c ce                 	mov	qword ptr [rsi + 8*r9], r9
140007544: 49 ff c9                    	dec	r9
140007547: 49 83 f9 01                 	cmp	r9, 0x1
14000754b: 0f 8e 7a 00 00 00           	jle	0x1400075cb <.text+0x65cb>
140007551: 4c 8b 6e 08                 	mov	r13, qword ptr [rsi + 0x8]
140007555: 4e 8b 34 ce                 	mov	r14, qword ptr [rsi + 8*r9]
140007559: 4c 89 76 08                 	mov	qword ptr [rsi + 0x8], r14
14000755d: 4e 89 2c ce                 	mov	qword ptr [rsi + 8*r9], r13
140007561: 49 ff c9                    	dec	r9
140007564: 49 83 f9 02                 	cmp	r9, 0x2
140007568: 7e 61                       	jle	0x1400075cb <.text+0x65cb>
14000756a: 4c 8b 6e 10                 	mov	r13, qword ptr [rsi + 0x10]
14000756e: 4e 8b 34 ce                 	mov	r14, qword ptr [rsi + 8*r9]
140007572: 4c 89 76 10                 	mov	qword ptr [rsi + 0x10], r14
140007576: 4e 89 2c ce                 	mov	qword ptr [rsi + 8*r9], r13
14000757a: 49 ff c9                    	dec	r9
14000757d: 49 83 f9 03                 	cmp	r9, 0x3
140007581: 7e 48                       	jle	0x1400075cb <.text+0x65cb>
140007583: 4c 8b 6e 18                 	mov	r13, qword ptr [rsi + 0x18]
140007587: 4e 8b 34 ce                 	mov	r14, qword ptr [rsi + 8*r9]
14000758b: 4c 89 76 18                 	mov	qword ptr [rsi + 0x18], r14
14000758f: 4e 89 2c ce                 	mov	qword ptr [rsi + 8*r9], r13
140007593: 49 ff c9                    	dec	r9
140007596: 49 83 f9 04                 	cmp	r9, 0x4
14000759a: 7e 2f                       	jle	0x1400075cb <.text+0x65cb>
14000759c: 41 bb 04 00 00 00           	mov	r11d, 0x4
1400075a2: eb 0c                       	jmp	0x1400075b0 <.text+0x65b0>
1400075a4: 4d 39 cb                    	cmp	r11, r9
1400075a7: 7d 22                       	jge	0x1400075cb <.text+0x65cb>
1400075a9: 0f 1f 80 00 00 00 00        	nop	dword ptr [rax]
1400075b0: 4e 8b 2c de                 	mov	r13, qword ptr [rsi + 8*r11]
1400075b4: 4e 8b 34 ce                 	mov	r14, qword ptr [rsi + 8*r9]
1400075b8: 4e 89 34 de                 	mov	qword ptr [rsi + 8*r11], r14
1400075bc: 4e 89 2c ce                 	mov	qword ptr [rsi + 8*r9], r13
1400075c0: 49 ff c3                    	inc	r11
1400075c3: 49 ff c9                    	dec	r9
1400075c6: 4d 39 cb                    	cmp	r11, r9
1400075c9: 7c e5                       	jl	0x1400075b0 <.text+0x65b0>
1400075cb: 49 ff c2                    	inc	r10
1400075ce: 4c 8b 0e                    	mov	r9, qword ptr [rsi]
1400075d1: 4d 85 c9                    	test	r9, r9
1400075d4: 0f 85 56 ff ff ff           	jne	0x140007530 <.text+0x6530>
1400075da: 49 39 ca                    	cmp	r10, rcx
1400075dd: 49 0f 4f ca                 	cmovg	rcx, r10
1400075e1: f6 c2 01                    	test	dl, 0x1
1400075e4: 75 05                       	jne	0x1400075eb <.text+0x65eb>
1400075e6: 4c 01 d0                    	add	rax, r10
1400075e9: eb 03                       	jmp	0x1400075ee <.text+0x65ee>
1400075eb: 4c 29 d0                    	sub	rax, r10
1400075ee: 66 90                       	nop
1400075f0: 49 83 f8 09                 	cmp	r8, 0x9
1400075f4: 74 58                       	je	0x14000764e <.text+0x664e>
1400075f6: 4c 8b 17                    	mov	r10, qword ptr [rdi]
1400075f9: 45 31 db                    	xor	r11d, r11d
1400075fc: 4d 85 c0                    	test	r8, r8
1400075ff: 7e 31                       	jle	0x140007632 <.text+0x6632>
140007601: 66 2e 0f 1f 84 00 00 00 00 00       	nop	word ptr cs:[rax + rax]
14000760b: 66 2e 0f 1f 84 00 00 00 00 00       	nop	word ptr cs:[rax + rax]
140007615: 66 2e 0f 1f 84 00 00 00 00 00       	nop	word ptr cs:[rax + rax]
14000761f: 90                          	nop
140007620: 4e 8b 6c df 08              	mov	r13, qword ptr [rdi + 8*r11 + 0x8]
140007625: 4e 89 2c df                 	mov	qword ptr [rdi + 8*r11], r13
140007629: 49 83 c3 01                 	add	r11, 0x1
14000762d: 4d 39 c3                    	cmp	r11, r8
140007630: 7c ee                       	jl	0x140007620 <.text+0x6620>
140007632: 4e 89 14 c7                 	mov	qword ptr [rdi + 8*r8], r10
140007636: 4b ff 0c c4                 	dec	qword ptr [r12 + 8*r8]
14000763a: 4b 83 3c c4 00              	cmp	qword ptr [r12 + 8*r8], 0x0
14000763f: 7f 05                       	jg	0x140007646 <.text+0x6646>
140007641: 49 ff c0                    	inc	r8
140007644: eb aa                       	jmp	0x1400075f0 <.text+0x65f0>
140007646: 48 ff c2                    	inc	rdx
140007649: e9 72 fe ff ff              	jmp	0x1400074c0 <.text+0x64c0>
14000764e: 4c 69 e8 e8 03 00 00        	imul	r13, rax, 0x3e8
140007655: 49 01 cd                    	add	r13, rcx
