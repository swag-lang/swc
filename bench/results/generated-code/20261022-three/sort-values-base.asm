140007c60:     	push	rsi
140007c61:     	push	rdi
140007c62:     	push	r12
140007c64:     	mov	rsi, rcx
140007c67:     	mov	rdi, rdx
140007c6a:     	mov	r12, r8
140007c80:     	mov	rax, r12
140007c83:     	sub	rax, rdi
140007c86:     	cmp	rax, 0x10
140007c8a:     	jle	0x140007d74 <.text+0x6d74>
140007c90:     	shr	rax
140007c93:     	lea	rcx, [rdi + rax]
140007c97:     	mov	rax, qword ptr [rsi + 8*rcx]
140007c9b:     	mov	rdx, qword ptr [rsi + 8*rdi]
140007c9f:     	cmp	rax, rdx
140007ca2:     	jae	0x140007cac <.text+0x6cac>
140007ca4:     	mov	qword ptr [rsi + 8*rdi], rax
140007ca8:     	mov	qword ptr [rsi + 8*rcx], rdx
140007cac:     	mov	rax, qword ptr [rsi + 8*r12]
140007cb0:     	mov	rdx, qword ptr [rsi + 8*rdi]
140007cb4:     	cmp	rax, rdx
140007cb7:     	jae	0x140007cc1 <.text+0x6cc1>
140007cb9:     	mov	qword ptr [rsi + 8*rdi], rax
140007cbd:     	mov	qword ptr [rsi + 8*r12], rdx
140007cc1:     	mov	rax, qword ptr [rsi + 8*r12]
140007cc5:     	mov	rdx, qword ptr [rsi + 8*rcx]
140007cc9:     	cmp	rax, rdx
140007ccc:     	jae	0x140007cd6 <.text+0x6cd6>
140007cce:     	mov	qword ptr [rsi + 8*rcx], rax
140007cd2:     	mov	qword ptr [rsi + 8*r12], rdx
140007cd6:     	mov	rax, qword ptr [rsi + 8*rcx]
140007cda:     	mov	r9, rdi
140007cdd:     	mov	r10, r12
140007ce0:     	mov	rcx, qword ptr [rsi + 8*r9]
140007ce4:     	cmp	rcx, rax
140007ce7:     	jae	0x140007cfd <.text+0x6cfd>
140007cf0:     	add	r9, 0x1
140007cf4:     	mov	rcx, qword ptr [rsi + 8*r9]
140007cf8:     	cmp	rcx, rax
140007cfb:     	jb	0x140007cf0 <.text+0x6cf0>
140007cfd:     	mov	rdx, qword ptr [rsi + 8*r10]
140007d01:     	cmp	rdx, rax
140007d04:     	jbe	0x140007d1d <.text+0x6d1d>
140007d10:     	sub	r10, 0x1
140007d14:     	mov	rdx, qword ptr [rsi + 8*r10]
140007d18:     	cmp	rdx, rax
140007d1b:     	ja	0x140007d10 <.text+0x6d10>
140007d1d:     	cmp	r9, r10
140007d20:     	jg	0x140007d37 <.text+0x6d37>
140007d22:     	mov	qword ptr [rsi + 8*r9], rdx
140007d26:     	mov	qword ptr [rsi + 8*r10], rcx
140007d2a:     	add	r9, 0x1
140007d2e:     	sub	r10, 0x1
140007d32:     	cmp	r9, r10
140007d35:     	jle	0x140007ce0 <.text+0x6ce0>
140007d37:     	mov	rax, r10
140007d3a:     	sub	rax, rdi
140007d3d:     	mov	rcx, r12
140007d40:     	sub	rcx, r9
140007d43:     	cmp	rax, rcx
140007d46:     	jge	0x140007d5e <.text+0x6d5e>
140007d48:     	mov	rcx, rsi
140007d4b:     	mov	rdx, rdi
140007d4e:     	mov	r8, r10
140007d51:     	mov	rdi, r9
140007d54:     	call	0x140007c60 <.text+0x6c60>
140007d59:     	jmp	0x140007c80 <.text+0x6c80>
140007d5e:     	mov	rcx, rsi
140007d61:     	mov	rdx, r9
140007d64:     	mov	r8, r12
140007d67:     	mov	r12, r10
140007d6a:     	call	0x140007c60 <.text+0x6c60>
140007d6f:     	jmp	0x140007c80 <.text+0x6c80>
140007d74:     	lea	rax, [rdi + 0x1]
140007d78:     	cmp	rax, r12
140007d7b:     	jg	0x140007db3 <.text+0x6db3>
140007d80:     	mov	rcx, qword ptr [rsi + 8*rax]
140007d84:     	lea	rdx, [rax - 0x1]
140007d88:     	cmp	rdx, rdi
140007d8b:     	jl	0x140007da6 <.text+0x6da6>
140007d90:     	mov	r8, qword ptr [rsi + 8*rdx]
140007d94:     	cmp	r8, rcx
140007d97:     	jbe	0x140007da6 <.text+0x6da6>
140007d99:     	mov	qword ptr [rsi + 8*rdx + 0x8], r8
140007d9e:     	dec	rdx
140007da1:     	cmp	rdx, rdi
140007da4:     	jge	0x140007d90 <.text+0x6d90>
140007da6:     	mov	qword ptr [rsi + 8*rdx + 0x8], rcx
140007dab:     	inc	rax
140007dae:     	cmp	rax, r12
140007db1:     	jle	0x140007d80 <.text+0x6d80>
140007db3:     	pop	r12
140007db5:     	pop	rdi
140007db6:     	pop	rsi
140007db7:     	ret
