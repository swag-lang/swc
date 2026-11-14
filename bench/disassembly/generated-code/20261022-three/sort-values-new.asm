140001100:     	push	rsi
140001101:     	push	rdi
140001102:     	push	r12
140001104:     	mov	rsi, rcx
140001107:     	mov	rdi, rdx
14000110a:     	mov	r12, r8
140001120:     	mov	rax, r12
140001123:     	sub	rax, rdi
140001126:     	cmp	rax, 0x10
14000112a:     	jle	0x140001209 <.text+0x209>
140001130:     	shr	rax
140001133:     	lea	rcx, [rdi + rax]
140001137:     	mov	rax, qword ptr [rsi + 8*rcx]
14000113b:     	mov	rdx, qword ptr [rsi + 8*rdi]
14000113f:     	cmp	rax, rdx
140001142:     	jae	0x14000114c <.text+0x14c>
140001144:     	mov	qword ptr [rsi + 8*rdi], rax
140001148:     	mov	qword ptr [rsi + 8*rcx], rdx
14000114c:     	mov	rax, qword ptr [rsi + 8*r12]
140001150:     	mov	rdx, qword ptr [rsi + 8*rdi]
140001154:     	cmp	rax, rdx
140001157:     	jae	0x140001161 <.text+0x161>
140001159:     	mov	qword ptr [rsi + 8*rdi], rax
14000115d:     	mov	qword ptr [rsi + 8*r12], rdx
140001161:     	mov	rax, qword ptr [rsi + 8*r12]
140001165:     	mov	rdx, qword ptr [rsi + 8*rcx]
140001169:     	cmp	rax, rdx
14000116c:     	jae	0x140001176 <.text+0x176>
14000116e:     	mov	qword ptr [rsi + 8*rcx], rax
140001172:     	mov	qword ptr [rsi + 8*r12], rdx
140001176:     	mov	rax, qword ptr [rsi + 8*rcx]
14000117a:     	mov	r9, rdi
14000117d:     	mov	r10, r12
140001180:     	cmp	qword ptr [rsi + 8*r9], rax
140001184:     	jae	0x14000119a <.text+0x19a>
140001190:     	add	r9, 0x1
140001194:     	cmp	qword ptr [rsi + 8*r9], rax
140001198:     	jb	0x140001190 <.text+0x190>
14000119a:     	cmp	qword ptr [rsi + 8*r10], rax
14000119e:     	jbe	0x1400011aa <.text+0x1aa>
1400011a0:     	sub	r10, 0x1
1400011a4:     	cmp	qword ptr [rsi + 8*r10], rax
1400011a8:     	ja	0x1400011a0 <.text+0x1a0>
1400011aa:     	cmp	r9, r10
1400011ad:     	jg	0x1400011cc <.text+0x1cc>
1400011af:     	mov	rcx, qword ptr [rsi + 8*r9]
1400011b3:     	mov	rdx, qword ptr [rsi + 8*r10]
1400011b7:     	mov	qword ptr [rsi + 8*r9], rdx
1400011bb:     	mov	qword ptr [rsi + 8*r10], rcx
1400011bf:     	add	r9, 0x1
1400011c3:     	sub	r10, 0x1
1400011c7:     	cmp	r9, r10
1400011ca:     	jle	0x140001180 <.text+0x180>
1400011cc:     	mov	rax, r10
1400011cf:     	sub	rax, rdi
1400011d2:     	mov	rcx, r12
1400011d5:     	sub	rcx, r9
1400011d8:     	cmp	rax, rcx
1400011db:     	jge	0x1400011f3 <.text+0x1f3>
1400011dd:     	mov	rcx, rsi
1400011e0:     	mov	rdx, rdi
1400011e3:     	mov	r8, r10
1400011e6:     	mov	rdi, r9
1400011e9:     	call	0x140001100 <.text+0x100>
1400011ee:     	jmp	0x140001120 <.text+0x120>
1400011f3:     	mov	rcx, rsi
1400011f6:     	mov	rdx, r9
1400011f9:     	mov	r8, r12
1400011fc:     	mov	r12, r10
1400011ff:     	call	0x140001100 <.text+0x100>
140001204:     	jmp	0x140001120 <.text+0x120>
140001209:     	lea	rax, [rdi + 0x1]
14000120d:     	cmp	rax, r12
140001210:     	jg	0x140001253 <.text+0x253>
140001220:     	mov	rcx, qword ptr [rsi + 8*rax]
140001224:     	lea	rdx, [rax - 0x1]
140001228:     	cmp	rdx, rdi
14000122b:     	jl	0x140001246 <.text+0x246>
140001230:     	mov	r8, qword ptr [rsi + 8*rdx]
140001234:     	cmp	r8, rcx
140001237:     	jbe	0x140001246 <.text+0x246>
140001239:     	mov	qword ptr [rsi + 8*rdx + 0x8], r8
14000123e:     	dec	rdx
140001241:     	cmp	rdx, rdi
140001244:     	jge	0x140001230 <.text+0x230>
140001246:     	mov	qword ptr [rsi + 8*rdx + 0x8], rcx
14000124b:     	inc	rax
14000124e:     	cmp	rax, r12
140001251:     	jle	0x140001220 <.text+0x220>
140001253:     	pop	r12
140001255:     	pop	rdi
140001256:     	pop	rsi
140001257:     	ret
