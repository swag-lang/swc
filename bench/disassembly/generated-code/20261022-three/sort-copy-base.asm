140007c50:     	push	rsi
140007c51:     	push	rdi
140007c52:     	push	r12
140007c54:     	push	r13
140007c56:     	push	r14
140007c58:     	mov	rsi, rcx
140007c5b:     	mov	rdi, rdx
140007c5e:     	mov	r12, r8
140007c61:     	nop	word ptr cs:[rax + rax]
140007c6b:     	nop	dword ptr [rax + rax]
140007c70:     	mov	rax, r12
140007c73:     	sub	rax, rdi
140007c76:     	cmp	rax, 0x10
140007c7a:     	jle	0x140007d64 <.text+0x6d64>
140007c80:     	shr	rax
140007c83:     	lea	rcx, [rdi + rax]
140007c87:     	mov	rax, qword ptr [rsi + 8*rcx]
140007c8b:     	mov	rdx, qword ptr [rsi + 8*rdi]
140007c8f:     	cmp	rax, rdx
140007c92:     	jae	0x140007c9c <.text+0x6c9c>
140007c94:     	mov	qword ptr [rsi + 8*rdi], rax
140007c98:     	mov	qword ptr [rsi + 8*rcx], rdx
140007c9c:     	mov	rax, qword ptr [rsi + 8*r12]
140007ca0:     	mov	rdx, qword ptr [rsi + 8*rdi]
140007ca4:     	cmp	rax, rdx
140007ca7:     	jae	0x140007cb1 <.text+0x6cb1>
140007ca9:     	mov	qword ptr [rsi + 8*rdi], rax
140007cad:     	mov	qword ptr [rsi + 8*r12], rdx
140007cb1:     	mov	rax, qword ptr [rsi + 8*r12]
140007cb5:     	mov	rdx, qword ptr [rsi + 8*rcx]
140007cb9:     	cmp	rax, rdx
140007cbc:     	jae	0x140007cc6 <.text+0x6cc6>
140007cbe:     	mov	qword ptr [rsi + 8*rcx], rax
140007cc2:     	mov	qword ptr [rsi + 8*r12], rdx
140007cc6:     	mov	rax, qword ptr [rsi + 8*rcx]
140007cca:     	mov	r13, rdi
140007ccd:     	mov	r14, r12
140007cd0:     	mov	rcx, qword ptr [rsi + 8*r13]
140007cd4:     	cmp	rcx, rax
140007cd7:     	jae	0x140007ced <.text+0x6ced>
140007cd9:     	nop	dword ptr [rax]
140007ce0:     	add	r13, 0x1
140007ce4:     	mov	rcx, qword ptr [rsi + 8*r13]
140007ce8:     	cmp	rcx, rax
140007ceb:     	jb	0x140007ce0 <.text+0x6ce0>
140007ced:     	mov	rdx, qword ptr [rsi + 8*r14]
140007cf1:     	cmp	rdx, rax
140007cf4:     	jbe	0x140007d0d <.text+0x6d0d>
140007cf6:     	nop	word ptr cs:[rax + rax]
140007d00:     	sub	r14, 0x1
140007d04:     	mov	rdx, qword ptr [rsi + 8*r14]
140007d08:     	cmp	rdx, rax
140007d0b:     	ja	0x140007d00 <.text+0x6d00>
140007d0d:     	cmp	r13, r14
140007d10:     	jg	0x140007d27 <.text+0x6d27>
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
140007d38:     	mov	rcx, rsi
140007d3b:     	mov	rdx, rdi
140007d3e:     	mov	r8, r14
140007d41:     	call	0x140007c50 <.text+0x6c50>
140007d46:     	mov	rdi, r13
140007d49:     	jmp	0x140007c70 <.text+0x6c70>
140007d4e:     	mov	rcx, rsi
140007d51:     	mov	rdx, r13
140007d54:     	mov	r8, r12
140007d57:     	call	0x140007c50 <.text+0x6c50>
140007d5c:     	mov	r12, r14
140007d5f:     	jmp	0x140007c70 <.text+0x6c70>
140007d64:     	lea	rax, [rdi + 0x1]
140007d68:     	cmp	rax, r12
140007d6b:     	jg	0x140007da3 <.text+0x6da3>
140007d6d:     	nop	dword ptr [rax]
140007d70:     	mov	rcx, qword ptr [rsi + 8*rax]
140007d74:     	lea	rdx, [rax - 0x1]
140007d78:     	cmp	rdx, rdi
140007d7b:     	jl	0x140007d96 <.text+0x6d96>
140007d7d:     	nop	dword ptr [rax]
140007d80:     	mov	r8, qword ptr [rsi + 8*rdx]
140007d84:     	cmp	r8, rcx
140007d87:     	jbe	0x140007d96 <.text+0x6d96>
140007d89:     	mov	qword ptr [rsi + 8*rdx + 0x8], r8
140007d8e:     	dec	rdx
140007d91:     	cmp	rdx, rdi
140007d94:     	jge	0x140007d80 <.text+0x6d80>
140007d96:     	mov	qword ptr [rsi + 8*rdx + 0x8], rcx
140007d9b:     	inc	rax
140007d9e:     	cmp	rax, r12
140007da1:     	jle	0x140007d70 <.text+0x6d70>
140007da3:     	pop	r14
140007da5:     	pop	r13
140007da7:     	pop	r12
140007da9:     	pop	rdi
140007daa:     	pop	rsi
140007dab:     	ret
