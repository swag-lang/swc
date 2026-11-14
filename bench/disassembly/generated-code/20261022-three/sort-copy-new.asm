140001100:     	push	rsi
140001101:     	push	rdi
140001102:     	push	r12
140001104:     	mov	rsi, rcx
140001107:     	mov	rdi, rdx
14000110a:     	mov	r12, r8
14000110d:     	nop	word ptr cs:[rax + rax]
140001117:     	nop	word ptr [rax + rax]
140001120:     	mov	rax, r12
140001123:     	sub	rax, rdi
140001126:     	cmp	rax, 0x10
14000112a:     	jle	0x140001214 <.text+0x214>
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
140001180:     	mov	rcx, qword ptr [rsi + 8*r9]
140001184:     	cmp	rcx, rax
140001187:     	jae	0x14000119d <.text+0x19d>
140001189:     	nop	dword ptr [rax]
140001190:     	add	r9, 0x1
140001194:     	mov	rcx, qword ptr [rsi + 8*r9]
140001198:     	cmp	rcx, rax
14000119b:     	jb	0x140001190 <.text+0x190>
14000119d:     	mov	rdx, qword ptr [rsi + 8*r10]
1400011a1:     	cmp	rdx, rax
1400011a4:     	jbe	0x1400011bd <.text+0x1bd>
1400011a6:     	nop	word ptr cs:[rax + rax]
1400011b0:     	sub	r10, 0x1
1400011b4:     	mov	rdx, qword ptr [rsi + 8*r10]
1400011b8:     	cmp	rdx, rax
1400011bb:     	ja	0x1400011b0 <.text+0x1b0>
1400011bd:     	cmp	r9, r10
1400011c0:     	jg	0x1400011d7 <.text+0x1d7>
1400011c2:     	mov	qword ptr [rsi + 8*r9], rdx
1400011c6:     	mov	qword ptr [rsi + 8*r10], rcx
1400011ca:     	add	r9, 0x1
1400011ce:     	sub	r10, 0x1
1400011d2:     	cmp	r9, r10
1400011d5:     	jle	0x140001180 <.text+0x180>
1400011d7:     	mov	rax, r10
1400011da:     	sub	rax, rdi
1400011dd:     	mov	rcx, r12
1400011e0:     	sub	rcx, r9
1400011e3:     	cmp	rax, rcx
1400011e6:     	jge	0x1400011fe <.text+0x1fe>
1400011e8:     	mov	rcx, rsi
1400011eb:     	mov	rdx, rdi
1400011ee:     	mov	r8, r10
1400011f1:     	mov	rdi, r9
1400011f4:     	call	0x140001100 <.text+0x100>
1400011f9:     	jmp	0x140001120 <.text+0x120>
1400011fe:     	mov	rcx, rsi
140001201:     	mov	rdx, r9
140001204:     	mov	r8, r12
140001207:     	mov	r12, r10
14000120a:     	call	0x140001100 <.text+0x100>
14000120f:     	jmp	0x140001120 <.text+0x120>
140001214:     	lea	rax, [rdi + 0x1]
140001218:     	cmp	rax, r12
14000121b:     	jg	0x140001253 <.text+0x253>
14000121d:     	nop	dword ptr [rax]
140001220:     	mov	rcx, qword ptr [rsi + 8*rax]
140001224:     	lea	rdx, [rax - 0x1]
140001228:     	cmp	rdx, rdi
14000122b:     	jl	0x140001246 <.text+0x246>
14000122d:     	nop	dword ptr [rax]
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
