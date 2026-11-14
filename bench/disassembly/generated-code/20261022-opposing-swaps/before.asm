14000488f: e8 0c 5f 00 00              	call	0x14000a7a0 <.text+0x97a0>

140004894: 48 83 c4 08                 	add	rsp, 0x8

140004898: c5 f8 10 f0                 	vmovups	xmm6, xmm0

14000489c: 48 c7 07 00 00 00 00        	mov	qword ptr [rdi], 0x0

1400048a3: 48 c7 47 08 01 00 00 00     	mov	qword ptr [rdi + 0x8], 0x1

1400048ab: 48 c7 47 10 02 00 00 00     	mov	qword ptr [rdi + 0x10], 0x2

1400048b3: 48 c7 47 18 03 00 00 00     	mov	qword ptr [rdi + 0x18], 0x3

1400048bb: 48 c7 47 20 04 00 00 00     	mov	qword ptr [rdi + 0x20], 0x4

1400048c3: 48 c7 47 28 05 00 00 00     	mov	qword ptr [rdi + 0x28], 0x5

1400048cb: 48 c7 47 30 06 00 00 00     	mov	qword ptr [rdi + 0x30], 0x6

1400048d3: 48 c7 47 38 07 00 00 00     	mov	qword ptr [rdi + 0x38], 0x7

1400048db: 48 c7 47 40 08 00 00 00     	mov	qword ptr [rdi + 0x40], 0x8

1400048e3: 31 c0                       	xor	eax, eax

1400048e5: 31 c9                       	xor	ecx, ecx

1400048e7: 31 d2                       	xor	edx, edx

1400048e9: 41 b8 09 00 00 00           	mov	r8d, 0x9

1400048ef: 90                          	nop

1400048f0: 49 83 f8 01                 	cmp	r8, 0x1

1400048f4: 74 18                       	je	0x14000490e <.text+0x390e>

1400048f6: 66 2e 0f 1f 84 00 00 00 00 00       	nop	word ptr cs:[rax + rax]

140004900: 4f 89 44 c4 f8              	mov	qword ptr [r12 + 8*r8 - 0x8], r8

140004905: 49 ff c8                    	dec	r8

140004908: 49 83 f8 01                 	cmp	r8, 0x1

14000490c: 75 f2                       	jne	0x140004900 <.text+0x3900>

14000490e: 4c 8b 0f                    	mov	r9, qword ptr [rdi]

140004911: 4c 89 0e                    	mov	qword ptr [rsi], r9

140004914: 4c 8b 57 08                 	mov	r10, qword ptr [rdi + 0x8]

140004918: 4c 89 56 08                 	mov	qword ptr [rsi + 0x8], r10

14000491c: 4c 8b 57 10                 	mov	r10, qword ptr [rdi + 0x10]

140004920: 4c 89 56 10                 	mov	qword ptr [rsi + 0x10], r10

140004924: 4c 8b 57 18                 	mov	r10, qword ptr [rdi + 0x18]

140004928: 4c 89 56 18                 	mov	qword ptr [rsi + 0x18], r10

14000492c: 4c 8b 57 20                 	mov	r10, qword ptr [rdi + 0x20]

140004930: 4c 89 56 20                 	mov	qword ptr [rsi + 0x20], r10

140004934: 4c 8b 57 28                 	mov	r10, qword ptr [rdi + 0x28]

140004938: 4c 89 56 28                 	mov	qword ptr [rsi + 0x28], r10

14000493c: 4c 8b 57 30                 	mov	r10, qword ptr [rdi + 0x30]

140004940: 4c 89 56 30                 	mov	qword ptr [rsi + 0x30], r10

140004944: 4c 8b 57 38                 	mov	r10, qword ptr [rdi + 0x38]

140004948: 4c 89 56 38                 	mov	qword ptr [rsi + 0x38], r10

14000494c: 4c 8b 57 40                 	mov	r10, qword ptr [rdi + 0x40]

140004950: 4c 89 56 40                 	mov	qword ptr [rsi + 0x40], r10

140004954: 45 31 d2                    	xor	r10d, r10d

140004957: 4d 85 c9                    	test	r9, r9

14000495a: 74 3a                       	je	0x140004996 <.text+0x3996>

14000495c: 0f 1f 40 00                 	nop	dword ptr [rax]

140004960: 45 31 db                    	xor	r11d, r11d

140004963: 4d 39 cb                    	cmp	r11, r9

140004966: 7d 23                       	jge	0x14000498b <.text+0x398b>

140004968: 0f 1f 84 00 00 00 00 00     	nop	dword ptr [rax + rax]

140004970: 4e 8b 2c de                 	mov	r13, qword ptr [rsi + 8*r11]

140004974: 4e 8b 34 ce                 	mov	r14, qword ptr [rsi + 8*r9]

140004978: 4e 89 34 de                 	mov	qword ptr [rsi + 8*r11], r14

14000497c: 4e 89 2c ce                 	mov	qword ptr [rsi + 8*r9], r13

140004980: 49 ff c3                    	inc	r11

140004983: 49 ff c9                    	dec	r9

140004986: 4d 39 cb                    	cmp	r11, r9

140004989: 7c e5                       	jl	0x140004970 <.text+0x3970>

14000498b: 49 ff c2                    	inc	r10

14000498e: 4c 8b 0e                    	mov	r9, qword ptr [rsi]

140004991: 4d 85 c9                    	test	r9, r9

140004994: 75 ca                       	jne	0x140004960 <.text+0x3960>

140004996: 49 39 ca                    	cmp	r10, rcx

140004999: 49 0f 4f ca                 	cmovg	rcx, r10

14000499d: f6 c2 01                    	test	dl, 0x1

1400049a0: 75 05                       	jne	0x1400049a7 <.text+0x39a7>

1400049a2: 4c 01 d0                    	add	rax, r10

1400049a5: eb 03                       	jmp	0x1400049aa <.text+0x39aa>

1400049a7: 4c 29 d0                    	sub	rax, r10

1400049aa: 66 0f 1f 44 00 00           	nop	word ptr [rax + rax]

1400049b0: 49 83 f8 09                 	cmp	r8, 0x9

1400049b4: 74 48                       	je	0x1400049fe <.text+0x39fe>

1400049b6: 4c 8b 17                    	mov	r10, qword ptr [rdi]

1400049b9: 45 31 db                    	xor	r11d, r11d

1400049bc: 4d 85 c0                    	test	r8, r8

1400049bf: 7e 21                       	jle	0x1400049e2 <.text+0x39e2>

1400049c1: 66 2e 0f 1f 84 00 00 00 00 00       	nop	word ptr cs:[rax + rax]

1400049cb: 0f 1f 44 00 00              	nop	dword ptr [rax + rax]

1400049d0: 4e 8b 6c df 08              	mov	r13, qword ptr [rdi + 8*r11 + 0x8]

1400049d5: 4e 89 2c df                 	mov	qword ptr [rdi + 8*r11], r13

1400049d9: 49 83 c3 01                 	add	r11, 0x1

1400049dd: 4d 39 c3                    	cmp	r11, r8

1400049e0: 7c ee                       	jl	0x1400049d0 <.text+0x39d0>

1400049e2: 4e 89 14 c7                 	mov	qword ptr [rdi + 8*r8], r10

1400049e6: 4b ff 0c c4                 	dec	qword ptr [r12 + 8*r8]

1400049ea: 4b 83 3c c4 00              	cmp	qword ptr [r12 + 8*r8], 0x0

1400049ef: 7f 05                       	jg	0x1400049f6 <.text+0x39f6>

1400049f1: 49 ff c0                    	inc	r8

1400049f4: eb ba                       	jmp	0x1400049b0 <.text+0x39b0>

1400049f6: 48 ff c2                    	inc	rdx

1400049f9: e9 f2 fe ff ff              	jmp	0x1400048f0 <.text+0x38f0>

1400049fe: 4c 69 e8 e8 03 00 00        	imul	r13, rax, 0x3e8

140004a05: 49 01 cd                    	add	r13, rcx

140004a08: 48 83 ec 08                 	sub	rsp, 0x8

140004a0c: e8 8f 5d 00 00              	call	0x14000a7a0 <.text+0x97a0>

140004a11: 48 83 c4 08                 	add	rsp, 0x8

140004a15: c5 fb 5c c6                 	vsubsd	xmm0, xmm0, xmm6

140004a19: c5 fb 59 05 1f 6e 00 00     	vmulsd	xmm0, xmm0, qword ptr [rip + 0x6e1f] # 0x14000b840

140004a21: 48 8d 05 40 68 00 00        	lea	rax, [rip + 0x6840]     # 0x14000b268

140004a28: 48 81 ec 90 00 00 00        	sub	rsp, 0x90

140004a2f: 48 89 e1                    	mov	rcx, rsp

140004a32: c5 f8 10 0d e6 6d 00 00     	vmovups	xmm1, xmmword ptr [rip + 0x6de6] # 0x14000b820

140004a3a: c5 f8 11 09                 	vmovups	xmmword ptr [rcx], xmm1

140004a3e: 48 89 61 30                 	mov	qword ptr [rcx + 0x30], rsp

140004a42: 48 8d 15 c7 67 00 00        	lea	rdx, [rip + 0x67c7]     # 0x14000b210

140004a49: 48 89 51 38                 	mov	qword ptr [rcx + 0x38], rdx

140004a4d: 4c 89 69 10                 	mov	qword ptr [rcx + 0x10], r13

140004a51: 4c 8d 44 24 10              	lea	r8, [rsp + 0x10]

140004a56: 4c 89 41 40                 	mov	qword ptr [rcx + 0x40], r8

140004a5a: 4c 8d 05 2f 6d 00 00        	lea	r8, [rip + 0x6d2f]      # 0x14000b790

140004a61: 4c 89 41 48                 	mov	qword ptr [rcx + 0x48], r8

140004a65: c5 f8 10 0d c3 6d 00 00     	vmovups	xmm1, xmmword ptr [rip + 0x6dc3] # 0x14000b830

140004a6d: c5 f8 11 49 18              	vmovups	xmmword ptr [rcx + 0x18], xmm1

140004a72: 4c 8d 44 24 18              	lea	r8, [rsp + 0x18]

140004a77: 4c 89 41 50                 	mov	qword ptr [rcx + 0x50], r8

140004a7b: 48 89 51 58                 	mov	qword ptr [rcx + 0x58], rdx

140004a7f: c5 fb 11 41 28              	vmovsd	qword ptr [rcx + 0x28], xmm0

140004a84: 4c 8d 41 28                 	lea	r8, [rcx + 0x28]
