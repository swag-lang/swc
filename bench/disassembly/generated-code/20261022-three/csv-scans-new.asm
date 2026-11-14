1400061dd:     	nop	dword ptr [rax]
1400061e0:     	mov	r15, rcx
1400061e3:     	cmp	rcx, rdi
1400061e6:     	jae	0x140006260 <.text+0x5260>
1400061ec:     	mov	rax, rdi
1400061ef:     	sub	rax, r15
1400061f2:     	cmp	rax, 0x4
1400061f6:     	jb	0x140006240 <.text+0x5240>
1400061f8:     	mov	rax, rdi
1400061fb:     	sub	rax, 0x3
1400061ff:     	cmp	r15, rax
140006202:     	jae	0x140006240 <.text+0x5240>
140006204:     	nop	word ptr cs:[rax + rax]
14000620e:     	nop
140006210:     	cmp	byte ptr [rsi + r15], 0xa
140006215:     	je	0x140006260 <.text+0x5260>
140006217:     	cmp	byte ptr [rsi + r15 + 0x1], 0xa
14000621d:     	je	0x140006251 <.text+0x5251>
14000621f:     	cmp	byte ptr [rsi + r15 + 0x2], 0xa
140006225:     	je	0x140006256 <.text+0x5256>
140006227:     	cmp	byte ptr [rsi + r15 + 0x3], 0xa
14000622d:     	je	0x14000625c <.text+0x525c>
14000622f:     	lea	r15, [r15 + 0x4]
140006233:     	cmp	r15, rax
140006236:     	jb	0x140006210 <.text+0x5210>
140006238:     	nop	dword ptr [rax + rax]
140006240:     	cmp	r15, rdi
140006243:     	jae	0x140006260 <.text+0x5260>
140006245:     	cmp	byte ptr [rsi + r15], 0xa
14000624a:     	je	0x140006260 <.text+0x5260>
14000624c:     	inc	r15
14000624f:     	jmp	0x140006240 <.text+0x5240>
140006251:     	inc	r15
140006254:     	jmp	0x140006260 <.text+0x5260>
140006256:     	lea	r15, [r15 + 0x2]
14000625a:     	jmp	0x140006260 <.text+0x5260>
14000625c:     	lea	r15, [r15 + 0x3]
140006260:     	cmp	rcx, r15
140006263:     	jae	0x1400062e0 <.text+0x52e0>
140006269:     	mov	rax, r15
14000626c:     	sub	rax, rcx
14000626f:     	cmp	rax, 0x4
140006273:     	jb	0x1400062c0 <.text+0x52c0>
140006279:     	mov	rax, r15
14000627c:     	sub	rax, 0x3
140006280:     	cmp	rcx, rax
140006283:     	jae	0x1400062c0 <.text+0x52c0>
140006285:     	nop	word ptr cs:[rax + rax]
14000628f:     	nop
140006290:     	cmp	byte ptr [rsi + rcx], 0x2c
140006294:     	je	0x1400062e0 <.text+0x52e0>
140006296:     	cmp	byte ptr [rsi + rcx + 0x1], 0x2c
14000629b:     	je	0x1400062d1 <.text+0x52d1>
14000629d:     	cmp	byte ptr [rsi + rcx + 0x2], 0x2c
1400062a2:     	je	0x1400062d6 <.text+0x52d6>
1400062a4:     	cmp	byte ptr [rsi + rcx + 0x3], 0x2c
1400062a9:     	je	0x1400062dc <.text+0x52dc>
1400062ab:     	lea	rcx, [rcx + 0x4]
1400062af:     	cmp	rcx, rax
1400062b2:     	jb	0x140006290 <.text+0x5290>
1400062b4:     	nop	word ptr cs:[rax + rax]
1400062be:     	nop
1400062c0:     	cmp	rcx, r15
1400062c3:     	jae	0x1400062e0 <.text+0x52e0>
1400062c5:     	cmp	byte ptr [rsi + rcx], 0x2c
1400062c9:     	je	0x1400062e0 <.text+0x52e0>
1400062cb:     	add	rcx, 0x1
1400062cf:     	jmp	0x1400062c0 <.text+0x52c0>
1400062d1:     	inc	rcx
1400062d4:     	jmp	0x1400062e0 <.text+0x52e0>
1400062d6:     	lea	rcx, [rcx + 0x2]
1400062da:     	jmp	0x1400062e0 <.text+0x52e0>
1400062dc:     	lea	rcx, [rcx + 0x3]
1400062e0:     	lea	rdi, [rcx + 0x1]
1400062e4:     	mov	rcx, rdi
1400062e7:     	cmp	rdi, r15
1400062ea:     	jae	0x140006360 <.text+0x5360>
1400062f0:     	mov	rax, r15
1400062f3:     	sub	rax, rcx
1400062f6:     	cmp	rax, 0x4
1400062fa:     	jb	0x140006340 <.text+0x5340>
1400062fc:     	mov	rax, r15
1400062ff:     	sub	rax, 0x3
140006303:     	cmp	rcx, rax
140006306:     	jae	0x140006340 <.text+0x5340>
140006308:     	nop	dword ptr [rax + rax]
140006310:     	cmp	byte ptr [rsi + rcx], 0x2c
140006314:     	je	0x140006360 <.text+0x5360>
140006316:     	cmp	byte ptr [rsi + rcx + 0x1], 0x2c
14000631b:     	je	0x140006351 <.text+0x5351>
14000631d:     	cmp	byte ptr [rsi + rcx + 0x2], 0x2c
140006322:     	je	0x140006356 <.text+0x5356>
140006324:     	cmp	byte ptr [rsi + rcx + 0x3], 0x2c
140006329:     	je	0x14000635c <.text+0x535c>
14000632b:     	lea	rcx, [rcx + 0x4]
14000632f:     	cmp	rcx, rax
140006332:     	jb	0x140006310 <.text+0x5310>
140006334:     	nop	word ptr cs:[rax + rax]
14000633e:     	nop
140006340:     	cmp	rcx, r15
140006343:     	jae	0x140006360 <.text+0x5360>
140006345:     	cmp	byte ptr [rsi + rcx], 0x2c
140006349:     	je	0x140006360 <.text+0x5360>
14000634b:     	add	rcx, 0x1
14000634f:     	jmp	0x140006340 <.text+0x5340>
140006351:     	inc	rcx
140006354:     	jmp	0x140006360 <.text+0x5360>
140006356:     	lea	rcx, [rcx + 0x2]
14000635a:     	jmp	0x140006360 <.text+0x5360>
14000635c:     	lea	rcx, [rcx + 0x3]
140006360:     	mov	r11, rcx
140006363:     	sub	r11, rdi
140006366:     	add	rcx, 0x1
14000636a:     	cmp	rcx, r15
14000636d:     	jae	0x140006400 <.text+0x5400>
140006373:     	mov	rax, r15
140006376:     	sub	rax, rcx
140006379:     	cmp	rax, 0x4
14000637d:     	jb	0x1400063e0 <.text+0x53e0>
140006383:     	mov	rax, r15
140006386:     	sub	rax, 0x3
14000638a:     	cmp	rcx, rax
14000638d:     	jae	0x1400063e0 <.text+0x53e0>
140006393:     	nop	word ptr cs:[rax + rax]
14000639d:     	nop	word ptr cs:[rax + rax]
1400063a7:     	nop	word ptr [rax + rax]
1400063b0:     	cmp	byte ptr [rsi + rcx], 0x2c
1400063b4:     	je	0x140006400 <.text+0x5400>
1400063b6:     	cmp	byte ptr [rsi + rcx + 0x1], 0x2c
1400063bb:     	je	0x1400063f1 <.text+0x53f1>
1400063bd:     	cmp	byte ptr [rsi + rcx + 0x2], 0x2c
1400063c2:     	je	0x1400063f6 <.text+0x53f6>
1400063c4:     	cmp	byte ptr [rsi + rcx + 0x3], 0x2c
1400063c9:     	je	0x1400063fc <.text+0x53fc>
1400063cb:     	lea	rcx, [rcx + 0x4]
1400063cf:     	cmp	rcx, rax
1400063d2:     	jb	0x1400063b0 <.text+0x53b0>
1400063d4:     	nop	word ptr cs:[rax + rax]
1400063de:     	nop
1400063e0:     	cmp	rcx, r15
1400063e3:     	jae	0x140006400 <.text+0x5400>
1400063e5:     	cmp	byte ptr [rsi + rcx], 0x2c
1400063e9:     	je	0x140006400 <.text+0x5400>
1400063eb:     	add	rcx, 0x1
1400063ef:     	jmp	0x1400063e0 <.text+0x53e0>
1400063f1:     	inc	rcx
1400063f4:     	jmp	0x140006400 <.text+0x5400>
1400063f6:     	lea	rcx, [rcx + 0x2]
1400063fa:     	jmp	0x140006400 <.text+0x5400>
1400063fc:     	lea	rcx, [rcx + 0x3]
140006400:     	add	rcx, 0x1
140006404:     	xor	r14d, r14d
140006407:     	cmp	rcx, r15
14000640a:     	jae	0x14000642d <.text+0x542d>
14000640c:     	nop	dword ptr [rax]
