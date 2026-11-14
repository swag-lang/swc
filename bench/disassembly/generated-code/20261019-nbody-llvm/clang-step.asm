140001380: f2 0f 11 8c 24 90 00 00 00  	movsd	qword ptr [rsp + 0x90], xmm1
140001389: 66 0f 29 6c 24 30           	movapd	xmmword ptr [rsp + 0x30], xmm5
14000138f: 66 44 0f 29 84 24 a0 00 00 00       	movapd	xmmword ptr [rsp + 0xa0], xmm8
140001399: 66 0f 29 64 24 40           	movapd	xmmword ptr [rsp + 0x40], xmm4
14000139f: 66 44 0f 29 64 24 50        	movapd	xmmword ptr [rsp + 0x50], xmm12
1400013a6: 41 b8 68 00 00 00           	mov	r8d, 0x68
1400013ac: 66 0f 28 f2                 	movapd	xmm6, xmm2
1400013b0: 66 0f 28 94 24 f0 01 00 00  	movapd	xmm2, xmmword ptr [rsp + 0x1f0]
1400013b9: 0f 1f 80 00 00 00 00        	nop	dword ptr [rax]
1400013c0: 66 41 0f 28 cb              	movapd	xmm1, xmm11
1400013c5: f2 42 0f 5c 8c 04 f0 01 00 00       	subsd	xmm1, qword ptr [rsp + r8 + 0x1f0]
1400013cf: f2 46 0f 10 bc 04 10 02 00 00       	movsd	xmm15, qword ptr [rsp + r8 + 0x210]
1400013d9: 66 0f 28 e9                 	movapd	xmm5, xmm1
1400013dd: f2 41 0f 59 ef              	mulsd	xmm5, xmm15
1400013e2: 66 42 0f 10 a4 04 e0 01 00 00       	movupd	xmm4, xmmword ptr [rsp + r8 + 0x1e0]
1400013ec: 66 45 0f 28 e6              	movapd	xmm12, xmm14
1400013f1: 66 44 0f 5c e4              	subpd	xmm12, xmm4
1400013f6: 66 42 0f 10 a4 04 f8 01 00 00       	movupd	xmm4, xmmword ptr [rsp + r8 + 0x1f8]
140001400: 66 45 0f 28 c4              	movapd	xmm8, xmm12
140001405: 66 45 0f 59 c4              	mulpd	xmm8, xmm12
14000140a: 66 45 0f 15 c0              	unpckhpd	xmm8, xmm8              # xmm8 = xmm8[1,1]
14000140f: 66 45 0f 28 d4              	movapd	xmm10, xmm12
140001414: f2 45 0f 59 d4              	mulsd	xmm10, xmm12
140001419: f2 45 0f 58 d0              	addsd	xmm10, xmm8
14000141e: 66 44 0f 28 c1              	movapd	xmm8, xmm1
140001423: f2 44 0f 59 c1              	mulsd	xmm8, xmm1
140001428: f2 45 0f 58 c2              	addsd	xmm8, xmm10
14000142d: 45 0f 57 d2                 	xorps	xmm10, xmm10
140001431: f2 45 0f 51 d0              	sqrtsd	xmm10, xmm8
140001436: f2 45 0f 59 d0              	mulsd	xmm10, xmm8
14000143b: 66 44 0f 28 c3              	movapd	xmm8, xmm3
140001440: f2 45 0f 5e c2              	divsd	xmm8, xmm10
140001445: 66 45 0f 14 ff              	unpcklpd	xmm15, xmm15            # xmm15 = xmm15[0,0]
14000144a: 66 45 0f 59 fc              	mulpd	xmm15, xmm12
14000144f: f2 41 0f 59 e8              	mulsd	xmm5, xmm8
140001454: f2 0f 59 ca                 	mulsd	xmm1, xmm2
140001458: f2 41 0f 59 c8              	mulsd	xmm1, xmm8
14000145d: 66 45 0f 14 c0              	unpcklpd	xmm8, xmm8              # xmm8 = xmm8[0,0]
140001462: 66 45 0f 59 f8              	mulpd	xmm15, xmm8
140001467: 66 41 0f 5c c7              	subpd	xmm0, xmm15
14000146c: 66 44 0f 59 e6              	mulpd	xmm12, xmm6
140001471: 66 45 0f 59 e0              	mulpd	xmm12, xmm8
140001476: 66 44 0f 58 e4              	addpd	xmm12, xmm4
14000147b: 66 46 0f 11 a4 04 f8 01 00 00       	movupd	xmmword ptr [rsp + r8 + 0x1f8], xmm12
140001485: f2 42 0f 58 8c 04 08 02 00 00       	addsd	xmm1, qword ptr [rsp + r8 + 0x208]
14000148f: f2 44 0f 5c ed              	subsd	xmm13, xmm5
140001494: f2 42 0f 11 8c 04 08 02 00 00       	movsd	qword ptr [rsp + r8 + 0x208], xmm1
14000149e: 49 83 c0 38                 	add	r8, 0x38
1400014a2: 49 81 f8 48 01 00 00        	cmp	r8, 0x148
1400014a9: 0f 85 11 ff ff ff           	jne	0x1400013c0 <.text+0x3c0>
1400014af: f2 44 0f 11 ac 24 38 02 00 00       	movsd	qword ptr [rsp + 0x238], xmm13
1400014b9: 66 0f 11 84 24 28 02 00 00  	movupd	xmmword ptr [rsp + 0x228], xmm0
1400014c2: 41 b8 a0 00 00 00           	mov	r8d, 0xa0
1400014c8: 66 44 0f 28 b4 24 b0 00 00 00       	movapd	xmm14, xmmword ptr [rsp + 0xb0]
1400014d2: 66 0f 28 94 24 e0 01 00 00  	movapd	xmm2, xmmword ptr [rsp + 0x1e0]
1400014db: 66 0f 28 bc 24 d0 01 00 00  	movapd	xmm7, xmmword ptr [rsp + 0x1d0]
1400014e4: 66 66 66 2e 0f 1f 84 00 00 00 00 00 	nop	word ptr cs:[rax + rax]
1400014f0: 66 41 0f 28 ce              	movapd	xmm1, xmm14
1400014f5: f2 42 0f 5c 8c 04 f0 01 00 00       	subsd	xmm1, qword ptr [rsp + r8 + 0x1f0]
1400014ff: f2 46 0f 10 9c 04 10 02 00 00       	movsd	xmm11, qword ptr [rsp + r8 + 0x210]
140001509: f2 0f 10 ac 24 70 02 00 00  	movsd	xmm5, qword ptr [rsp + 0x270]
140001512: 66 44 0f 28 f9              	movapd	xmm15, xmm1
140001517: f2 45 0f 59 fb              	mulsd	xmm15, xmm11
14000151c: 66 42 0f 10 a4 04 e0 01 00 00       	movupd	xmm4, xmmword ptr [rsp + r8 + 0x1e0]
140001526: 66 45 0f 28 d1              	movapd	xmm10, xmm9
14000152b: 66 44 0f 5c d4              	subpd	xmm10, xmm4
140001530: 66 41 0f 28 e2              	movapd	xmm4, xmm10
140001535: 66 41 0f 59 e2              	mulpd	xmm4, xmm10
14000153a: 66 0f 15 e4                 	unpckhpd	xmm4, xmm4              # xmm4 = xmm4[1,1]
14000153e: 66 45 0f 28 e2              	movapd	xmm12, xmm10
140001543: f2 45 0f 59 e2              	mulsd	xmm12, xmm10
140001548: f2 44 0f 58 e4              	addsd	xmm12, xmm4
14000154d: 66 0f 28 e1                 	movapd	xmm4, xmm1
140001551: f2 0f 59 e1                 	mulsd	xmm4, xmm1
140001555: f2 41 0f 58 e4              	addsd	xmm4, xmm12
14000155a: 45 0f 57 e4                 	xorps	xmm12, xmm12
14000155e: f2 44 0f 51 e4              	sqrtsd	xmm12, xmm4
140001563: f2 44 0f 59 e4              	mulsd	xmm12, xmm4
140001568: 66 44 0f 28 c3              	movapd	xmm8, xmm3
14000156d: f2 45 0f 5e c4              	divsd	xmm8, xmm12
140001572: 66 0f 28 a4 24 60 02 00 00  	movapd	xmm4, xmmword ptr [rsp + 0x260]
14000157b: 66 45 0f 14 db              	unpcklpd	xmm11, xmm11            # xmm11 = xmm11[0,0]
140001580: 66 45 0f 59 da              	mulpd	xmm11, xmm10
140001585: f2 45 0f 59 f8              	mulsd	xmm15, xmm8
14000158a: f2 0f 59 ca                 	mulsd	xmm1, xmm2
14000158e: f2 41 0f 59 c8              	mulsd	xmm1, xmm8
140001593: 66 45 0f 14 c0              	unpcklpd	xmm8, xmm8              # xmm8 = xmm8[0,0]
140001598: 66 45 0f 59 d8              	mulpd	xmm11, xmm8
14000159d: 66 41 0f 5c e3              	subpd	xmm4, xmm11
1400015a2: 66 0f 29 a4 24 60 02 00 00  	movapd	xmmword ptr [rsp + 0x260], xmm4
1400015ab: f2 41 0f 5c ef              	subsd	xmm5, xmm15
1400015b0: f2 0f 11 ac 24 70 02 00 00  	movsd	qword ptr [rsp + 0x270], xmm5
1400015b9: 66 44 0f 59 d7              	mulpd	xmm10, xmm7
1400015be: 66 42 0f 10 a4 04 f8 01 00 00       	movupd	xmm4, xmmword ptr [rsp + r8 + 0x1f8]
1400015c8: 66 45 0f 59 d0              	mulpd	xmm10, xmm8
1400015cd: 66 44 0f 58 d4              	addpd	xmm10, xmm4
1400015d2: 66 46 0f 11 94 04 f8 01 00 00       	movupd	xmmword ptr [rsp + r8 + 0x1f8], xmm10
1400015dc: f2 42 0f 58 8c 04 08 02 00 00       	addsd	xmm1, qword ptr [rsp + r8 + 0x208]
1400015e6: f2 42 0f 11 8c 04 08 02 00 00       	movsd	qword ptr [rsp + r8 + 0x208], xmm1
1400015f0: 49 83 c0 38                 	add	r8, 0x38
1400015f4: 49 81 f8 48 01 00 00        	cmp	r8, 0x148
1400015fb: 0f 85 ef fe ff ff           	jne	0x1400014f0 <.text+0x4f0>
140001601: 41 b8 d8 00 00 00           	mov	r8d, 0xd8
140001607: 66 0f 28 94 24 c0 01 00 00  	movapd	xmm2, xmmword ptr [rsp + 0x1c0]
140001610: 66 0f 28 bc 24 b0 01 00 00  	movapd	xmm7, xmmword ptr [rsp + 0x1b0]
140001619: f2 0f 10 74 24 28           	movsd	xmm6, qword ptr [rsp + 0x28]
14000161f: 66 44 0f 28 74 24 60        	movapd	xmm14, xmmword ptr [rsp + 0x60]
140001626: 66 2e 0f 1f 84 00 00 00 00 00       	nop	word ptr cs:[rax + rax]
140001630: 66 0f 28 ce                 	movapd	xmm1, xmm6
140001634: f2 42 0f 5c 8c 04 f0 01 00 00       	subsd	xmm1, qword ptr [rsp + r8 + 0x1f0]
14000163e: f2 46 0f 10 94 04 10 02 00 00       	movsd	xmm10, qword ptr [rsp + r8 + 0x210]
140001648: f2 0f 10 ac 24 a8 02 00 00  	movsd	xmm5, qword ptr [rsp + 0x2a8]
140001651: 66 44 0f 28 d9              	movapd	xmm11, xmm1
140001656: f2 45 0f 59 da              	mulsd	xmm11, xmm10
14000165b: 66 42 0f 10 a4 04 e0 01 00 00       	movupd	xmm4, xmmword ptr [rsp + r8 + 0x1e0]
140001665: 66 45 0f 28 ce              	movapd	xmm9, xmm14
14000166a: 66 44 0f 5c cc              	subpd	xmm9, xmm4
14000166f: 66 41 0f 28 e1              	movapd	xmm4, xmm9
140001674: 66 41 0f 59 e1              	mulpd	xmm4, xmm9
140001679: 66 0f 15 e4                 	unpckhpd	xmm4, xmm4              # xmm4 = xmm4[1,1]
14000167d: 66 45 0f 28 c1              	movapd	xmm8, xmm9
140001682: f2 45 0f 59 c1              	mulsd	xmm8, xmm9
140001687: f2 44 0f 58 c4              	addsd	xmm8, xmm4
14000168c: 66 0f 28 e1                 	movapd	xmm4, xmm1
140001690: f2 0f 59 e1                 	mulsd	xmm4, xmm1
140001694: f2 41 0f 58 e0              	addsd	xmm4, xmm8
140001699: 45 0f 57 c0                 	xorps	xmm8, xmm8
14000169d: f2 44 0f 51 c4              	sqrtsd	xmm8, xmm4
1400016a2: f2 44 0f 59 c4              	mulsd	xmm8, xmm4
1400016a7: 66 44 0f 28 e3              	movapd	xmm12, xmm3
1400016ac: f2 45 0f 5e e0              	divsd	xmm12, xmm8
1400016b1: 66 0f 10 a4 24 98 02 00 00  	movupd	xmm4, xmmword ptr [rsp + 0x298]
1400016ba: 66 45 0f 14 d2              	unpcklpd	xmm10, xmm10            # xmm10 = xmm10[0,0]
1400016bf: 66 45 0f 59 d1              	mulpd	xmm10, xmm9
1400016c4: f2 45 0f 59 dc              	mulsd	xmm11, xmm12
1400016c9: f2 0f 59 ca                 	mulsd	xmm1, xmm2
1400016cd: f2 41 0f 59 cc              	mulsd	xmm1, xmm12
1400016d2: 66 45 0f 14 e4              	unpcklpd	xmm12, xmm12            # xmm12 = xmm12[0,0]
1400016d7: 66 45 0f 59 d4              	mulpd	xmm10, xmm12
1400016dc: 66 41 0f 5c e2              	subpd	xmm4, xmm10
1400016e1: 66 0f 11 a4 24 98 02 00 00  	movupd	xmmword ptr [rsp + 0x298], xmm4
1400016ea: f2 41 0f 5c eb              	subsd	xmm5, xmm11
1400016ef: f2 0f 11 ac 24 a8 02 00 00  	movsd	qword ptr [rsp + 0x2a8], xmm5
1400016f8: 66 44 0f 59 cf              	mulpd	xmm9, xmm7
1400016fd: 66 42 0f 10 a4 04 f8 01 00 00       	movupd	xmm4, xmmword ptr [rsp + r8 + 0x1f8]
140001707: 66 45 0f 59 cc              	mulpd	xmm9, xmm12
14000170c: 66 44 0f 58 cc              	addpd	xmm9, xmm4
140001711: 66 46 0f 11 8c 04 f8 01 00 00       	movupd	xmmword ptr [rsp + r8 + 0x1f8], xmm9
14000171b: f2 42 0f 58 8c 04 08 02 00 00       	addsd	xmm1, qword ptr [rsp + r8 + 0x208]
140001725: f2 42 0f 11 8c 04 08 02 00 00       	movsd	qword ptr [rsp + r8 + 0x208], xmm1
14000172f: 49 83 c0 38                 	add	r8, 0x38
140001733: 49 81 f8 48 01 00 00        	cmp	r8, 0x148
14000173a: 0f 85 f0 fe ff ff           	jne	0x140001630 <.text+0x630>
140001740: 41 b8 10 01 00 00           	mov	r8d, 0x110
140001746: 66 0f 10 8c 24 b8 02 00 00  	movupd	xmm1, xmmword ptr [rsp + 0x2b8]
14000174f: 66 44 0f 28 a4 24 a0 01 00 00       	movapd	xmm12, xmmword ptr [rsp + 0x1a0]
140001759: 66 44 0f 28 b4 24 90 01 00 00       	movapd	xmm14, xmmword ptr [rsp + 0x190]
140001763: f2 44 0f 10 bc 24 90 00 00 00       	movsd	xmm15, qword ptr [rsp + 0x90]
14000176d: 0f 1f 00                    	nop	dword ptr [rax]
140001770: 66 41 0f 28 d7              	movapd	xmm2, xmm15
140001775: f2 42 0f 5c 94 04 f0 01 00 00       	subsd	xmm2, qword ptr [rsp + r8 + 0x1f0]
14000177f: f2 46 0f 10 8c 04 10 02 00 00       	movsd	xmm9, qword ptr [rsp + r8 + 0x210]
140001789: f2 0f 10 ac 24 e0 02 00 00  	movsd	xmm5, qword ptr [rsp + 0x2e0]
140001792: 66 44 0f 28 d2              	movapd	xmm10, xmm2
140001797: f2 45 0f 59 d1              	mulsd	xmm10, xmm9
14000179c: 66 42 0f 10 a4 04 e0 01 00 00       	movupd	xmm4, xmmword ptr [rsp + r8 + 0x1e0]
1400017a6: 66 0f 28 f9                 	movapd	xmm7, xmm1
1400017aa: 66 0f 5c fc                 	subpd	xmm7, xmm4
1400017ae: 66 0f 28 e7                 	movapd	xmm4, xmm7
1400017b2: 66 0f 59 e7                 	mulpd	xmm4, xmm7
1400017b6: 66 0f 15 e4                 	unpckhpd	xmm4, xmm4              # xmm4 = xmm4[1,1]
1400017ba: 66 44 0f 28 c7              	movapd	xmm8, xmm7
1400017bf: f2 44 0f 59 c7              	mulsd	xmm8, xmm7
1400017c4: f2 44 0f 58 c4              	addsd	xmm8, xmm4
1400017c9: 66 0f 28 e2                 	movapd	xmm4, xmm2
1400017cd: f2 0f 59 e2                 	mulsd	xmm4, xmm2
1400017d1: f2 41 0f 58 e0              	addsd	xmm4, xmm8
1400017d6: 45 0f 57 c0                 	xorps	xmm8, xmm8
1400017da: f2 44 0f 51 c4              	sqrtsd	xmm8, xmm4
1400017df: f2 44 0f 59 c4              	mulsd	xmm8, xmm4
1400017e4: 66 44 0f 28 db              	movapd	xmm11, xmm3
1400017e9: f2 45 0f 5e d8              	divsd	xmm11, xmm8
1400017ee: 66 0f 28 a4 24 d0 02 00 00  	movapd	xmm4, xmmword ptr [rsp + 0x2d0]
1400017f7: 66 45 0f 14 c9              	unpcklpd	xmm9, xmm9              # xmm9 = xmm9[0,0]
1400017fc: 66 44 0f 59 cf              	mulpd	xmm9, xmm7
140001801: f2 45 0f 59 d3              	mulsd	xmm10, xmm11
140001806: f2 41 0f 59 d4              	mulsd	xmm2, xmm12
14000180b: f2 41 0f 59 d3              	mulsd	xmm2, xmm11
140001810: 66 45 0f 14 db              	unpcklpd	xmm11, xmm11            # xmm11 = xmm11[0,0]
140001815: 66 45 0f 59 cb              	mulpd	xmm9, xmm11
14000181a: 66 41 0f 5c e1              	subpd	xmm4, xmm9
14000181f: 66 0f 29 a4 24 d0 02 00 00  	movapd	xmmword ptr [rsp + 0x2d0], xmm4
140001828: f2 41 0f 5c ea              	subsd	xmm5, xmm10
14000182d: f2 0f 11 ac 24 e0 02 00 00  	movsd	qword ptr [rsp + 0x2e0], xmm5
140001836: 66 41 0f 59 fe              	mulpd	xmm7, xmm14
14000183b: 66 42 0f 10 a4 04 f8 01 00 00       	movupd	xmm4, xmmword ptr [rsp + r8 + 0x1f8]
140001845: 66 41 0f 59 fb              	mulpd	xmm7, xmm11
14000184a: 66 0f 58 fc                 	addpd	xmm7, xmm4
14000184e: 66 42 0f 11 bc 04 f8 01 00 00       	movupd	xmmword ptr [rsp + r8 + 0x1f8], xmm7
140001858: f2 42 0f 58 94 04 08 02 00 00       	addsd	xmm2, qword ptr [rsp + r8 + 0x208]
140001862: f2 42 0f 11 94 04 08 02 00 00       	movsd	qword ptr [rsp + r8 + 0x208], xmm2
14000186c: 49 83 c0 38                 	add	r8, 0x38
140001870: 49 81 f8 48 01 00 00        	cmp	r8, 0x148
140001877: 0f 85 f3 fe ff ff           	jne	0x140001770 <.text+0x770>
14000187d: 66 0f 28 c8                 	movapd	xmm1, xmm0
140001881: 66 0f 28 3d a7 5a 01 00     	movapd	xmm7, xmmword ptr [rip + 0x15aa7] # 0x140017330
140001889: 66 0f 59 cf                 	mulpd	xmm1, xmm7
14000188d: 66 44 0f 28 b4 24 c0 00 00 00       	movapd	xmm14, xmmword ptr [rsp + 0xc0]
140001897: 66 44 0f 58 f1              	addpd	xmm14, xmm1
14000189c: 66 0f 28 8c 24 60 02 00 00  	movapd	xmm1, xmmword ptr [rsp + 0x260]
1400018a5: 66 0f 29 8c 24 90 00 00 00  	movapd	xmmword ptr [rsp + 0x90], xmm1
1400018ae: 66 0f 59 cf                 	mulpd	xmm1, xmm7
1400018b2: 66 0f 28 6c 24 30           	movapd	xmm5, xmmword ptr [rsp + 0x30]
1400018b8: 66 0f 58 e9                 	addpd	xmm5, xmm1
1400018bc: 66 0f 11 ac 24 48 02 00 00  	movupd	xmmword ptr [rsp + 0x248], xmm5
1400018c5: f2 0f 10 94 24 70 02 00 00  	movsd	xmm2, qword ptr [rsp + 0x270]
1400018ce: 66 41 0f 28 cd              	movapd	xmm1, xmm13
1400018d3: 66 0f 29 54 24 30           	movapd	xmmword ptr [rsp + 0x30], xmm2
1400018d9: 66 0f 14 ca                 	unpcklpd	xmm1, xmm2              # xmm1 = xmm1[0],xmm2[0]
1400018dd: 66 0f 59 cf                 	mulpd	xmm1, xmm7
1400018e1: 66 44 0f 28 9c 24 d0 00 00 00       	movapd	xmm11, xmmword ptr [rsp + 0xd0]
1400018eb: 66 44 0f 58 d9              	addpd	xmm11, xmm1
1400018f0: 66 41 0f 28 cb              	movapd	xmm1, xmm11
1400018f5: 66 41 0f 15 cb              	unpckhpd	xmm1, xmm11             # xmm1 = xmm1[1],xmm11[1]
1400018fa: 66 0f 29 8c 24 b0 00 00 00  	movapd	xmmword ptr [rsp + 0xb0], xmm1
140001903: 66 44 0f 17 9c 24 58 02 00 00       	movhpd	qword ptr [rsp + 0x258], xmm11
14000190d: 66 0f 10 8c 24 98 02 00 00  	movupd	xmm1, xmmword ptr [rsp + 0x298]
140001916: 66 0f 29 8c 24 70 01 00 00  	movapd	xmmword ptr [rsp + 0x170], xmm1
14000191f: 66 0f 59 cf                 	mulpd	xmm1, xmm7
140001923: 66 44 0f 28 7c 24 40        	movapd	xmm15, xmmword ptr [rsp + 0x40]
14000192a: 66 44 0f 58 f9              	addpd	xmm15, xmm1
14000192f: 66 44 0f 29 bc 24 80 02 00 00       	movapd	xmmword ptr [rsp + 0x280], xmm15
140001939: f2 0f 10 8c 24 a8 02 00 00  	movsd	xmm1, qword ptr [rsp + 0x2a8]
140001942: f2 0f 11 4c 24 40           	movsd	qword ptr [rsp + 0x40], xmm1
140001948: f2 0f 59 cb                 	mulsd	xmm1, xmm3
14000194c: 66 44 0f 28 64 24 50        	movapd	xmm12, xmmword ptr [rsp + 0x50]
140001953: f2 44 0f 58 e1              	addsd	xmm12, xmm1
140001958: f2 44 0f 11 a4 24 90 02 00 00       	movsd	qword ptr [rsp + 0x290], xmm12
140001962: f2 44 0f 10 84 24 e0 02 00 00       	movsd	xmm8, qword ptr [rsp + 0x2e0]
14000196c: f2 44 0f 10 8c 24 18 03 00 00       	movsd	xmm9, qword ptr [rsp + 0x318]
140001976: f2 0f 10 8c 24 d8 02 00 00  	movsd	xmm1, qword ptr [rsp + 0x2d8]
14000197f: f2 0f 11 8c 24 08 01 00 00  	movsd	qword ptr [rsp + 0x108], xmm1
140001988: 66 0f 28 a4 24 d0 02 00 00  	movapd	xmm4, xmmword ptr [rsp + 0x2d0]
140001991: f2 0f 10 8c 24 10 03 00 00  	movsd	xmm1, qword ptr [rsp + 0x310]
14000199a: f2 0f 11 8c 24 00 01 00 00  	movsd	qword ptr [rsp + 0x100], xmm1
1400019a3: 66 0f 10 b4 24 08 03 00 00  	movupd	xmm6, xmmword ptr [rsp + 0x308]
1400019ac: 66 0f 28 cc                 	movapd	xmm1, xmm4
1400019b0: 66 0f 14 ce                 	unpcklpd	xmm1, xmm6              # xmm1 = xmm1[0],xmm6[0]
1400019b4: 66 0f 59 cf                 	mulpd	xmm1, xmm7
1400019b8: 66 0f 28 94 24 f0 00 00 00  	movapd	xmm2, xmmword ptr [rsp + 0xf0]
1400019c1: 66 0f 58 d1                 	addpd	xmm2, xmm1
1400019c5: 66 0f 29 a4 24 60 01 00 00  	movapd	xmmword ptr [rsp + 0x160], xmm4
1400019ce: 66 0f 28 cc                 	movapd	xmm1, xmm4
1400019d2: 66 44 0f 28 d6              	movapd	xmm10, xmm6
1400019d7: 66 0f 15 ce                 	unpckhpd	xmm1, xmm6              # xmm1 = xmm1[1],xmm6[1]
1400019db: 66 0f 59 cf                 	mulpd	xmm1, xmm7
1400019df: 66 0f 28 a4 24 e0 00 00 00  	movapd	xmm4, xmmword ptr [rsp + 0xe0]
1400019e8: 66 0f 58 e1                 	addpd	xmm4, xmm1
1400019ec: 66 0f 28 ca                 	movapd	xmm1, xmm2
1400019f0: 66 0f 14 cc                 	unpcklpd	xmm1, xmm4              # xmm1 = xmm1[0],xmm4[0]
1400019f4: 66 0f 11 8c 24 b8 02 00 00  	movupd	xmmword ptr [rsp + 0x2b8], xmm1
1400019fd: 66 44 0f 29 44 24 50        	movapd	xmmword ptr [rsp + 0x50], xmm8
140001a04: 66 41 0f 28 c8              	movapd	xmm1, xmm8
140001a09: 66 41 0f 28 f1              	movapd	xmm6, xmm9
140001a0e: 66 41 0f 14 c9              	unpcklpd	xmm1, xmm9              # xmm1 = xmm1[0],xmm9[0]
140001a13: 66 0f 59 cf                 	mulpd	xmm1, xmm7
140001a17: 66 44 0f 28 84 24 a0 00 00 00       	movapd	xmm8, xmmword ptr [rsp + 0xa0]
140001a21: 66 44 0f 58 c1              	addpd	xmm8, xmm1
140001a26: 66 44 0f 13 84 24 c8 02 00 00       	movlpd	qword ptr [rsp + 0x2c8], xmm8
140001a30: 66 0f 29 94 24 f0 00 00 00  	movapd	xmmword ptr [rsp + 0xf0], xmm2
140001a39: 66 0f 28 ca                 	movapd	xmm1, xmm2
140001a3d: 66 0f 29 a4 24 e0 00 00 00  	movapd	xmmword ptr [rsp + 0xe0], xmm4
140001a46: 66 0f 15 cc                 	unpckhpd	xmm1, xmm4              # xmm1 = xmm1[1],xmm4[1]
140001a4a: 66 41 0f 28 e7              	movapd	xmm4, xmm15
140001a4f: 66 0f 29 8c 24 f0 02 00 00  	movapd	xmmword ptr [rsp + 0x2f0], xmm1
140001a58: 66 44 0f 17 84 24 00 03 00 00       	movhpd	qword ptr [rsp + 0x300], xmm8
140001a62: 48 ff c2                    	inc	rdx
140001a65: 66 41 0f 28 c8              	movapd	xmm1, xmm8
140001a6a: f2 44 0f 11 64 24 28        	movsd	qword ptr [rsp + 0x28], xmm12
140001a71: 66 44 0f 29 7c 24 60        	movapd	xmmword ptr [rsp + 0x60], xmm15
140001a78: 66 44 0f 28 cd              	movapd	xmm9, xmm5
140001a7d: 66 44 0f 29 9c 24 d0 00 00 00       	movapd	xmmword ptr [rsp + 0xd0], xmm11
140001a87: 66 44 0f 29 b4 24 c0 00 00 00       	movapd	xmmword ptr [rsp + 0xc0], xmm14
140001a91: 48 81 fa 20 a1 07 00        	cmp	rdx, 0x7a120
140001a98: 66 0f 28 94 24 80 01 00 00  	movapd	xmm2, xmmword ptr [rsp + 0x180]
140001aa1: 0f 85 d9 f8 ff ff           	jne	0x140001380 <.text+0x380>
