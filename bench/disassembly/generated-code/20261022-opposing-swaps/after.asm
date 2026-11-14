140007454: 48 83 c4 08                 	add	rsp, 0x8

140007458: 49 89 c4                    	mov	r12, rax

14000745b: 48 83 ec 08                 	sub	rsp, 0x8

14000745f: e8 dc cf ff ff              	call	0x140004440 <.text+0x3440>

140007464: 48 83 c4 08                 	add	rsp, 0x8

140007468: c5 f8 10 f0                 	vmovups	xmm6, xmm0

14000746c: 48 c7 07 00 00 00 00        	mov	qword ptr [rdi], 0x0

140007473: 48 c7 47 08 01 00 00 00     	mov	qword ptr [rdi + 0x8], 0x1

14000747b: 48 c7 47 10 02 00 00 00     	mov	qword ptr [rdi + 0x10], 0x2

140007483: 48 c7 47 18 03 00 00 00     	mov	qword ptr [rdi + 0x18], 0x3

14000748b: 48 c7 47 20 04 00 00 00     	mov	qword ptr [rdi + 0x20], 0x4

140007493: 48 c7 47 28 05 00 00 00     	mov	qword ptr [rdi + 0x28], 0x5

14000749b: 48 c7 47 30 06 00 00 00     	mov	qword ptr [rdi + 0x30], 0x6

1400074a3: 48 c7 47 38 07 00 00 00     	mov	qword ptr [rdi + 0x38], 0x7

1400074ab: 48 c7 47 40 08 00 00 00     	mov	qword ptr [rdi + 0x40], 0x8

1400074b3: 31 c0                       	xor	eax, eax

1400074b5: 31 c9                       	xor	ecx, ecx

1400074b7: 31 d2                       	xor	edx, edx

1400074b9: 41 b8 09 00 00 00           	mov	r8d, 0x9

1400074bf: 90                          	nop

1400074c0: 49 83 f8 01                 	cmp	r8, 0x1

1400074c4: 74 18                       	je	0x1400074de <.text+0x64de>

1400074c6: 66 2e 0f 1f 84 00 00 00 00 00       	nop	word ptr cs:[rax + rax]

1400074d0: 4f 89 44 c4 f8              	mov	qword ptr [r12 + 8*r8 - 0x8], r8

1400074d5: 49 ff c8                    	dec	r8

1400074d8: 49 83 f8 01                 	cmp	r8, 0x1

1400074dc: 75 f2                       	jne	0x1400074d0 <.text+0x64d0>

1400074de: 4c 8b 0f                    	mov	r9, qword ptr [rdi]

1400074e1: 4c 89 0e                    	mov	qword ptr [rsi], r9

1400074e4: 4c 8b 57 08                 	mov	r10, qword ptr [rdi + 0x8]

1400074e8: 4c 89 56 08                 	mov	qword ptr [rsi + 0x8], r10

1400074ec: 4c 8b 57 10                 	mov	r10, qword ptr [rdi + 0x10]

1400074f0: 4c 89 56 10                 	mov	qword ptr [rsi + 0x10], r10

1400074f4: 4c 8b 57 18                 	mov	r10, qword ptr [rdi + 0x18]

1400074f8: 4c 89 56 18                 	mov	qword ptr [rsi + 0x18], r10

1400074fc: 4c 8b 57 20                 	mov	r10, qword ptr [rdi + 0x20]

140007500: 4c 89 56 20                 	mov	qword ptr [rsi + 0x20], r10

140007504: 4c 8b 57 28                 	mov	r10, qword ptr [rdi + 0x28]

140007508: 4c 89 56 28                 	mov	qword ptr [rsi + 0x28], r10

14000750c: 4c 8b 57 30                 	mov	r10, qword ptr [rdi + 0x30]

140007510: 4c 89 56 30                 	mov	qword ptr [rsi + 0x30], r10

140007514: 4c 8b 57 38                 	mov	r10, qword ptr [rdi + 0x38]

140007518: 4c 89 56 38                 	mov	qword ptr [rsi + 0x38], r10

14000751c: 4c 8b 57 40                 	mov	r10, qword ptr [rdi + 0x40]

140007520: 4c 89 56 40                 	mov	qword ptr [rsi + 0x40], r10

140007524: 45 31 d2                    	xor	r10d, r10d

140007527: 4d 85 c9                    	test	r9, r9

14000752a: 0f 84 aa 00 00 00           	je	0x1400075da <.text+0x65da>

140007530: 4d 85 c9                    	test	r9, r9

140007533: 0f 8e 92 00 00 00           	jle	0x1400075cb <.text+0x65cb>

140007539: 4c 8b 2e                    	mov	r13, qword ptr [rsi]

14000753c: 4e 8b 34 ce                 	mov	r14, qword ptr [rsi + 8*r9]

140007540: 4c 89 36                    	mov	qword ptr [rsi], r14

140007543: 4e 89 2c ce                 	mov	qword ptr [rsi + 8*r9], r13

140007547: 49 ff c9                    	dec	r9

14000754a: 49 83 f9 01                 	cmp	r9, 0x1

14000754e: 0f 8e 77 00 00 00           	jle	0x1400075cb <.text+0x65cb>

140007554: 4c 8b 6e 08                 	mov	r13, qword ptr [rsi + 0x8]

140007558: 4e 8b 34 ce                 	mov	r14, qword ptr [rsi + 8*r9]

14000755c: 4c 89 76 08                 	mov	qword ptr [rsi + 0x8], r14

140007560: 4e 89 2c ce                 	mov	qword ptr [rsi + 8*r9], r13

140007564: 49 ff c9                    	dec	r9

140007567: 49 83 f9 02                 	cmp	r9, 0x2

14000756b: 7e 5e                       	jle	0x1400075cb <.text+0x65cb>

14000756d: 4c 8b 6e 10                 	mov	r13, qword ptr [rsi + 0x10]

140007571: 4e 8b 34 ce                 	mov	r14, qword ptr [rsi + 8*r9]

140007575: 4c 89 76 10                 	mov	qword ptr [rsi + 0x10], r14

140007579: 4e 89 2c ce                 	mov	qword ptr [rsi + 8*r9], r13

14000757d: 49 ff c9                    	dec	r9

140007580: 49 83 f9 03                 	cmp	r9, 0x3

140007584: 7e 45                       	jle	0x1400075cb <.text+0x65cb>

140007586: 4c 8b 6e 18                 	mov	r13, qword ptr [rsi + 0x18]

14000758a: 4e 8b 34 ce                 	mov	r14, qword ptr [rsi + 8*r9]

14000758e: 4c 89 76 18                 	mov	qword ptr [rsi + 0x18], r14

140007592: 4e 89 2c ce                 	mov	qword ptr [rsi + 8*r9], r13

140007596: 49 ff c9                    	dec	r9

140007599: 49 83 f9 04                 	cmp	r9, 0x4

14000759d: 7e 2c                       	jle	0x1400075cb <.text+0x65cb>

14000759f: 41 bb 04 00 00 00           	mov	r11d, 0x4

1400075a5: eb 09                       	jmp	0x1400075b0 <.text+0x65b0>

1400075a7: 4d 39 cb                    	cmp	r11, r9

1400075aa: 7d 1f                       	jge	0x1400075cb <.text+0x65cb>

1400075ac: 0f 1f 40 00                 	nop	dword ptr [rax]

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
