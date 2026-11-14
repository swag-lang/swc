140002240:     	mov	dword ptr [rsp + 0x3c], r12d
140002245:     	add	r11d, eax
140002248:     	xor	r10d, r11d
14000224b:     	shld	r10d, r10d, 0x10
140002250:     	add	r15d, r10d
140002253:     	xor	eax, r15d
140002256:     	shld	eax, eax, 0xc
14000225a:     	add	r11d, eax
14000225d:     	xor	r10d, r11d
140002260:     	shld	r10d, r10d, 0x8
140002265:     	add	r15d, r10d
140002268:     	xor	eax, r15d
14000226b:     	shld	eax, eax, 0x7
14000226f:     	add	ecx, ebp
140002271:     	xor	edx, ecx
140002273:     	shld	edx, edx, 0x10
140002277:     	mov	r12d, dword ptr [rsp + 0x34]
14000227c:     	add	r12d, edx
14000227f:     	xor	ebp, r12d
140002282:     	shld	ebp, ebp, 0xc
140002286:     	add	ecx, ebp
140002288:     	xor	edx, ecx
14000228a:     	shld	edx, edx, 0x8
14000228e:     	add	r12d, edx
140002291:     	mov	dword ptr [rsp + 0x34], r12d
140002296:     	xor	ebp, r12d
140002299:     	mov	r12d, dword ptr [rsp + 0x3c]
14000229e:     	shld	ebp, ebp, 0x7
1400022a2:     	add	r14d, ebx
1400022a5:     	xor	r8d, r14d
1400022a8:     	shld	r8d, r8d, 0x10
1400022ad:     	add	r12d, r8d
1400022b0:     	xor	ebx, r12d
1400022b3:     	shld	ebx, ebx, 0xc
1400022b7:     	add	r14d, ebx
1400022ba:     	xor	r8d, r14d
1400022bd:     	shld	r8d, r8d, 0x8
1400022c2:     	add	r12d, r8d
1400022c5:     	xor	ebx, r12d
1400022c8:     	shld	ebx, ebx, 0x7
1400022cc:     	add	edi, esi
1400022ce:     	xor	r9d, edi
1400022d1:     	shld	r9d, r9d, 0x10
1400022d6:     	add	r13d, r9d
1400022d9:     	xor	esi, r13d
1400022dc:     	shld	esi, esi, 0xc
1400022e0:     	add	edi, esi
1400022e2:     	xor	r9d, edi
1400022e5:     	shld	r9d, r9d, 0x8
1400022ea:     	add	r13d, r9d
1400022ed:     	xor	esi, r13d
1400022f0:     	shld	esi, esi, 0x7
1400022f4:     	add	r11d, ebp
1400022f7:     	xor	r9d, r11d
1400022fa:     	shld	r9d, r9d, 0x10
1400022ff:     	add	r12d, r9d
140002302:     	xor	ebp, r12d
140002305:     	shld	ebp, ebp, 0xc
140002309:     	add	r11d, ebp
14000230c:     	xor	r9d, r11d
14000230f:     	shld	r9d, r9d, 0x8
140002314:     	add	r12d, r9d
140002317:     	xor	ebp, r12d
14000231a:     	shld	ebp, ebp, 0x7
14000231e:     	add	ecx, ebx
140002320:     	xor	r10d, ecx
140002323:     	shld	r10d, r10d, 0x10
140002328:     	add	r13d, r10d
14000232b:     	xor	ebx, r13d
14000232e:     	shld	ebx, ebx, 0xc
140002332:     	add	ecx, ebx
140002334:     	xor	r10d, ecx
140002337:     	shld	r10d, r10d, 0x8
14000233c:     	add	r13d, r10d
14000233f:     	xor	ebx, r13d
140002342:     	shld	ebx, ebx, 0x7
140002346:     	add	r14d, esi
140002349:     	xor	edx, r14d
14000234c:     	shld	edx, edx, 0x10
140002350:     	add	r15d, edx
140002353:     	xor	esi, r15d
140002356:     	shld	esi, esi, 0xc
14000235a:     	add	r14d, esi
14000235d:     	xor	edx, r14d
140002360:     	shld	edx, edx, 0x8
140002364:     	add	r15d, edx
140002367:     	mov	dword ptr [rsp + 0x3c], r15d
14000236c:     	xor	esi, r15d
14000236f:     	shld	esi, esi, 0x7
140002373:     	add	edi, eax
140002375:     	xor	r8d, edi
140002378:     	shld	r8d, r8d, 0x10
14000237d:     	mov	r15d, dword ptr [rsp + 0x34]
140002382:     	add	r15d, r8d
140002385:     	xor	eax, r15d
140002388:     	shld	eax, eax, 0xc
14000238c:     	add	edi, eax
14000238e:     	xor	r8d, edi
140002391:     	shld	r8d, r8d, 0x8
140002396:     	add	r15d, r8d
140002399:     	mov	dword ptr [rsp + 0x34], r15d
14000239e:     	xor	eax, r15d
1400023a1:     	mov	r15d, dword ptr [rsp + 0x3c]
1400023a6:     	shld	eax, eax, 0x7
1400023aa:     	dec	dword ptr [rsp + 0x38]
1400023ae:     	jne	0x140002240 <.text+0x1240>
