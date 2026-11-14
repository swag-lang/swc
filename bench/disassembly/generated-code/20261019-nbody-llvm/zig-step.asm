140001190: 66 44 0f 29 bd b0 00 00 00  	movapd	xmmword ptr [rbp + 0xb0], xmm15
140001199: 66 0f 29 8d f0 00 00 00     	movapd	xmmword ptr [rbp + 0xf0], xmm1
1400011a1: 66 44 0f 28 c4              	movapd	xmm8, xmm4
1400011a6: 66 44 0f 28 f8              	movapd	xmm15, xmm0
1400011ab: 66 0f 28 cb                 	movapd	xmm1, xmm3
1400011af: 66 45 0f 28 d3              	movapd	xmm10, xmm11
1400011b4: 66 0f 29 7d b0              	movapd	xmmword ptr [rbp - 0x50], xmm7
1400011b9: 66 0f 28 c4                 	movapd	xmm0, xmm4
1400011bd: 66 0f 5c c3                 	subpd	xmm0, xmm3
1400011c1: 66 0f 29 85 d0 00 00 00     	movapd	xmmword ptr [rbp + 0xd0], xmm0
1400011c9: 66 0f 29 5d 70              	movapd	xmmword ptr [rbp + 0x70], xmm3
1400011ce: 66 0f 14 ff                 	unpcklpd	xmm7, xmm7              # xmm7 = xmm7[0,0]
1400011d2: 66 44 0f 28 ef              	movapd	xmm13, xmm7
1400011d7: 66 45 0f 5c eb              	subpd	xmm13, xmm11
1400011dc: 66 44 0f 29 5d 50           	movapd	xmmword ptr [rbp + 0x50], xmm11
1400011e2: 66 0f 59 c0                 	mulpd	xmm0, xmm0
1400011e6: 66 0f 28 dc                 	movapd	xmm3, xmm4
1400011ea: 66 41 0f 5c df              	subpd	xmm3, xmm15
1400011ef: 66 0f 29 5d 20              	movapd	xmmword ptr [rbp + 0x20], xmm3
1400011f4: 66 44 0f 29 7d 60           	movapd	xmmword ptr [rbp + 0x60], xmm15
1400011fa: 66 0f 59 db                 	mulpd	xmm3, xmm3
1400011fe: 66 41 0f 28 ed              	movapd	xmm5, xmm13
140001203: 66 41 0f 59 ed              	mulpd	xmm5, xmm13
140001208: 66 0f 28 f0                 	movapd	xmm6, xmm0
14000120c: 66 0f 15 f3                 	unpckhpd	xmm6, xmm3              # xmm6 = xmm6[1],xmm3[1]
140001210: 66 0f 58 f5                 	addpd	xmm6, xmm5
140001214: 66 0f 14 c3                 	unpcklpd	xmm0, xmm3              # xmm0 = xmm0[0],xmm3[0]
140001218: 66 0f 58 c6                 	addpd	xmm0, xmm6
14000121c: 66 0f 51 d8                 	sqrtpd	xmm3, xmm0
140001220: 66 0f 59 d8                 	mulpd	xmm3, xmm0
140001224: 66 0f 29 5d e0              	movapd	xmmword ptr [rbp - 0x20], xmm3
140001229: 66 0f 29 95 e0 00 00 00     	movapd	xmmword ptr [rbp + 0xe0], xmm2
140001231: 66 0f 28 ad 00 01 00 00     	movapd	xmm5, xmmword ptr [rbp + 0x100]
140001239: 66 44 0f 29 8d 00 01 00 00  	movapd	xmmword ptr [rbp + 0x100], xmm9
140001242: 66 0f 29 65 a0              	movapd	xmmword ptr [rbp - 0x60], xmm4
140001247: 66 0f 5c e2                 	subpd	xmm4, xmm2
14000124b: 66 0f 5c fd                 	subpd	xmm7, xmm5
14000124f: 66 0f 29 6d 40              	movapd	xmmword ptr [rbp + 0x40], xmm5
140001254: 66 41 0f 28 f0              	movapd	xmm6, xmm8
140001259: 66 41 0f 5c f1              	subpd	xmm6, xmm9
14000125e: 66 0f 28 c4                 	movapd	xmm0, xmm4
140001262: 66 0f 15 c6                 	unpckhpd	xmm0, xmm6              # xmm0 = xmm0[1],xmm6[1]
140001266: 66 0f 59 c0                 	mulpd	xmm0, xmm0
14000126a: 66 0f 28 df                 	movapd	xmm3, xmm7
14000126e: 66 0f 59 df                 	mulpd	xmm3, xmm7
140001272: 66 0f 58 d8                 	addpd	xmm3, xmm0
140001276: 66 0f 28 c4                 	movapd	xmm0, xmm4
14000127a: 66 0f 14 c6                 	unpcklpd	xmm0, xmm6              # xmm0 = xmm0[0],xmm6[0]
14000127e: 66 0f 59 c0                 	mulpd	xmm0, xmm0
140001282: 66 0f 58 c3                 	addpd	xmm0, xmm3
140001286: 66 0f 51 d8                 	sqrtpd	xmm3, xmm0
14000128a: 66 0f 59 d8                 	mulpd	xmm3, xmm0
14000128e: 66 44 0f 28 0d 79 1e 06 00  	movapd	xmm9, xmmword ptr [rip + 0x61e79] # 0x140063110
140001297: 66 44 0f 5e cb              	divpd	xmm9, xmm3
14000129c: 66 0f 28 c4                 	movapd	xmm0, xmm4
1400012a0: 66 44 0f 28 1d 87 1e 06 00  	movapd	xmm11, xmmword ptr [rip + 0x61e87] # 0x140063130
1400012a9: 66 41 0f 59 c3              	mulpd	xmm0, xmm11
1400012ae: 66 41 0f 28 d9              	movapd	xmm3, xmm9
1400012b3: 66 41 0f 14 d9              	unpcklpd	xmm3, xmm9              # xmm3 = xmm3[0],xmm9[0]
1400012b8: 66 0f 29 5d f0              	movapd	xmmword ptr [rbp - 0x10], xmm3
1400012bd: 66 0f 59 c3                 	mulpd	xmm0, xmm3
1400012c1: 66 41 0f 58 c4              	addpd	xmm0, xmm12
1400012c6: 66 0f 29 45 c0              	movapd	xmmword ptr [rbp - 0x40], xmm0
1400012cb: 66 44 0f 28 e7              	movapd	xmm12, xmm7
1400012d0: 66 41 0f 59 fb              	mulpd	xmm7, xmm11
1400012d5: 66 41 0f 59 f9              	mulpd	xmm7, xmm9
1400012da: 66 0f 58 bd 30 01 00 00     	addpd	xmm7, xmmword ptr [rbp + 0x130]
1400012e2: 66 0f 29 7d d0              	movapd	xmmword ptr [rbp - 0x30], xmm7
1400012e7: f2 44 0f 5c b5 b0 00 00 00  	subsd	xmm14, qword ptr [rbp + 0xb0]
1400012f0: 66 44 0f 28 c1              	movapd	xmm8, xmm1
1400012f5: 66 45 0f 5c c7              	subpd	xmm8, xmm15
1400012fa: 66 41 0f 28 c6              	movapd	xmm0, xmm14
1400012ff: f2 41 0f 59 c6              	mulsd	xmm0, xmm14
140001304: 66 41 0f 28 d0              	movapd	xmm2, xmm8
140001309: 66 41 0f 59 d0              	mulpd	xmm2, xmm8
14000130e: 66 0f 28 da                 	movapd	xmm3, xmm2
140001312: 66 0f 15 da                 	unpckhpd	xmm3, xmm2              # xmm3 = xmm3[1],xmm2[1]
140001316: f2 0f 58 d8                 	addsd	xmm3, xmm0
14000131a: f2 0f 58 da                 	addsd	xmm3, xmm2
14000131e: 0f 57 c0                    	xorps	xmm0, xmm0
140001321: f2 0f 51 c3                 	sqrtsd	xmm0, xmm3
140001325: f2 0f 59 c3                 	mulsd	xmm0, xmm3
140001329: f2 0f 10 15 1f 1e 06 00     	movsd	xmm2, qword ptr [rip + 0x61e1f] # 0x140063150
140001331: 66 44 0f 28 da              	movapd	xmm11, xmm2
140001336: 66 44 0f 28 fa              	movapd	xmm15, xmm2
14000133b: f2 44 0f 5e d8              	divsd	xmm11, xmm0
140001340: 66 0f 28 95 f0 00 00 00     	movapd	xmm2, xmmword ptr [rbp + 0xf0]
140001348: 66 0f 28 c2                 	movapd	xmm0, xmm2
14000134c: 66 0f 14 c2                 	unpcklpd	xmm0, xmm2              # xmm0 = xmm0[0],xmm2[0]
140001350: 66 44 0f 5c d0              	subpd	xmm10, xmm0
140001355: 66 44 0f 29 95 30 01 00 00  	movapd	xmmword ptr [rbp + 0x130], xmm10
14000135e: 66 44 0f 59 25 b9 1d 06 00  	mulpd	xmm12, xmmword ptr [rip + 0x61db9] # 0x140063120
140001367: 66 45 0f 59 e1              	mulpd	xmm12, xmm9
14000136c: 66 44 0f 29 a5 b0 00 00 00  	movapd	xmmword ptr [rbp + 0xb0], xmm12
140001375: 66 0f 28 de                 	movapd	xmm3, xmm6
140001379: 66 0f 28 05 bf 1d 06 00     	movapd	xmm0, xmmword ptr [rip + 0x61dbf] # 0x140063140
140001381: 66 0f 59 d8                 	mulpd	xmm3, xmm0
140001385: 66 45 0f 15 c9              	unpckhpd	xmm9, xmm9              # xmm9 = xmm9[1,1]
14000138a: 66 41 0f 59 d9              	mulpd	xmm3, xmm9
14000138f: 66 0f 29 5d 00              	movapd	xmmword ptr [rbp], xmm3
140001394: 66 44 0f 28 15 93 1d 06 00  	movapd	xmm10, xmmword ptr [rip + 0x61d93] # 0x140063130
14000139d: 66 41 0f 59 f2              	mulpd	xmm6, xmm10
1400013a2: 66 41 0f 59 f1              	mulpd	xmm6, xmm9
1400013a7: 66 0f 58 b5 40 01 00 00     	addpd	xmm6, xmmword ptr [rbp + 0x140]
1400013af: 66 0f 29 75 10              	movapd	xmmword ptr [rbp + 0x10], xmm6
1400013b4: 66 0f 28 dd                 	movapd	xmm3, xmm5
1400013b8: 66 0f 15 dd                 	unpckhpd	xmm3, xmm5              # xmm3 = xmm3[1],xmm5[1]
1400013bc: 66 44 0f 28 a5 e0 00 00 00  	movapd	xmm12, xmmword ptr [rbp + 0xe0]
1400013c5: 66 41 0f 28 cc              	movapd	xmm1, xmm12
1400013ca: 66 0f 28 bd 00 01 00 00     	movapd	xmm7, xmmword ptr [rbp + 0x100]
1400013d2: 66 0f 5c cf                 	subpd	xmm1, xmm7
1400013d6: 66 0f 29 4d 30              	movapd	xmmword ptr [rbp + 0x30], xmm1
1400013db: 66 0f 28 c2                 	movapd	xmm0, xmm2
1400013df: f2 0f 5c c3                 	subsd	xmm0, xmm3
1400013e3: 66 0f 29 85 f0 00 00 00     	movapd	xmmword ptr [rbp + 0xf0], xmm0
1400013eb: f2 0f 59 c0                 	mulsd	xmm0, xmm0
1400013ef: 66 0f 28 d1                 	movapd	xmm2, xmm1
1400013f3: 66 0f 59 d1                 	mulpd	xmm2, xmm1
1400013f7: 66 0f 28 ea                 	movapd	xmm5, xmm2
1400013fb: 66 0f 15 ea                 	unpckhpd	xmm5, xmm2              # xmm5 = xmm5[1],xmm2[1]
1400013ff: f2 0f 58 e8                 	addsd	xmm5, xmm0
140001403: f2 0f 58 ea                 	addsd	xmm5, xmm2
140001407: 0f 57 c0                    	xorps	xmm0, xmm0
14000140a: f2 0f 51 c5                 	sqrtsd	xmm0, xmm5
14000140e: f2 0f 59 c5                 	mulsd	xmm0, xmm5
140001412: 66 41 0f 28 cf              	movapd	xmm1, xmm15
140001417: f2 0f 5e c8                 	divsd	xmm1, xmm0
14000141b: 66 0f 29 8d 40 01 00 00     	movapd	xmmword ptr [rbp + 0x140], xmm1
140001423: 66 0f 28 05 e5 1c 06 00     	movapd	xmm0, xmmword ptr [rip + 0x61ce5] # 0x140063110
14000142b: 66 0f 5e 45 e0              	divpd	xmm0, xmmword ptr [rbp - 0x20]
140001430: 66 41 0f 28 d5              	movapd	xmm2, xmm13
140001435: 66 0f 59 15 53 1d 06 00     	mulpd	xmm2, xmmword ptr [rip + 0x61d53] # 0x140063190
14000143d: 66 0f 59 d0                 	mulpd	xmm2, xmm0
140001441: f2 44 0f 10 bd 28 01 00 00  	movsd	xmm15, qword ptr [rbp + 0x128]
14000144a: f2 44 0f 5c fa              	subsd	xmm15, xmm2
14000144f: 66 0f 15 d2                 	unpckhpd	xmm2, xmm2              # xmm2 = xmm2[1,1]
140001453: f2 44 0f 5c fa              	subsd	xmm15, xmm2
140001458: 66 45 0f 59 ea              	mulpd	xmm13, xmm10
14000145d: 66 44 0f 59 e8              	mulpd	xmm13, xmm0
140001462: 66 44 0f 58 ad a0 00 00 00  	addpd	xmm13, xmmword ptr [rbp + 0xa0]
14000146b: 66 0f 28 55 20              	movapd	xmm2, xmmword ptr [rbp + 0x20]
140001470: 66 44 0f 28 ca              	movapd	xmm9, xmm2
140001475: 66 45 0f 59 ca              	mulpd	xmm9, xmm10
14000147a: 66 0f 28 e8                 	movapd	xmm5, xmm0
14000147e: 66 0f 15 e8                 	unpckhpd	xmm5, xmm0              # xmm5 = xmm5[1],xmm0[1]
140001482: 66 44 0f 59 cd              	mulpd	xmm9, xmm5
140001487: 66 44 0f 58 8d 80 00 00 00  	addpd	xmm9, xmmword ptr [rbp + 0x80]
140001490: 66 41 0f 28 f0              	movapd	xmm6, xmm8
140001495: 66 0f 28 0d c3 1c 06 00     	movapd	xmm1, xmmword ptr [rip + 0x61cc3] # 0x140063160
14000149d: 66 0f 59 f1                 	mulpd	xmm6, xmm1
1400014a1: 66 45 0f 14 db              	unpcklpd	xmm11, xmm11            # xmm11 = xmm11[0,0]
1400014a6: 66 41 0f 59 f3              	mulpd	xmm6, xmm11
1400014ab: 66 44 0f 58 ce              	addpd	xmm9, xmm6
1400014b0: 66 0f 28 35 b8 1c 06 00     	movapd	xmm6, xmmword ptr [rip + 0x61cb8] # 0x140063170
1400014b8: 66 0f 59 e6                 	mulpd	xmm4, xmm6
1400014bc: 66 0f 59 65 f0              	mulpd	xmm4, xmmword ptr [rbp - 0x10]
1400014c1: 66 44 0f 28 95 d0 00 00 00  	movapd	xmm10, xmmword ptr [rbp + 0xd0]
1400014ca: 66 41 0f 28 f2              	movapd	xmm6, xmm10
1400014cf: 66 0f 59 f1                 	mulpd	xmm6, xmm1
1400014d3: 66 0f 14 c0                 	unpcklpd	xmm0, xmm0              # xmm0 = xmm0[0,0]
1400014d7: 66 0f 59 f0                 	mulpd	xmm6, xmm0
1400014db: 66 0f 28 8d c0 00 00 00     	movapd	xmm1, xmmword ptr [rbp + 0xc0]
1400014e3: 66 0f 5c ce                 	subpd	xmm1, xmm6
1400014e7: 66 0f 28 35 b1 1c 06 00     	movapd	xmm6, xmmword ptr [rip + 0x61cb1] # 0x1400631a0
1400014ef: 66 0f 59 d6                 	mulpd	xmm2, xmm6
1400014f3: 66 0f 59 d5                 	mulpd	xmm2, xmm5
1400014f7: 66 0f 5c ca                 	subpd	xmm1, xmm2
1400014fb: 66 0f 5c cc                 	subpd	xmm1, xmm4
1400014ff: 66 0f 5c 4d 00              	subpd	xmm1, xmmword ptr [rbp]
140001504: 66 0f 29 8d c0 00 00 00     	movapd	xmmword ptr [rbp + 0xc0], xmm1
14000150c: 66 0f 28 a5 b0 00 00 00     	movapd	xmm4, xmmword ptr [rbp + 0xb0]
140001514: f2 44 0f 5c fc              	subsd	xmm15, xmm4
140001519: 66 0f 15 e4                 	unpckhpd	xmm4, xmm4              # xmm4 = xmm4[1,1]
14000151d: f2 44 0f 5c fc              	subsd	xmm15, xmm4
140001522: 66 41 0f 28 ca              	movapd	xmm1, xmm10
140001527: 66 0f 59 0d 01 1c 06 00     	mulpd	xmm1, xmmword ptr [rip + 0x61c01] # 0x140063130
14000152f: 66 0f 59 c8                 	mulpd	xmm1, xmm0
140001533: 66 0f 58 8d 90 00 00 00     	addpd	xmm1, xmmword ptr [rbp + 0x90]
14000153b: 66 44 0f 59 c6              	mulpd	xmm8, xmm6
140001540: 66 45 0f 59 c3              	mulpd	xmm8, xmm11
140001545: 66 41 0f 5c c8              	subpd	xmm1, xmm8
14000154a: 66 45 0f 14 f6              	unpcklpd	xmm14, xmm14            # xmm14 = xmm14[0,0]
14000154f: 66 44 0f 59 35 58 1c 06 00  	mulpd	xmm14, xmmword ptr [rip + 0x61c58] # 0x1400631b0
140001558: 66 45 0f 59 f3              	mulpd	xmm14, xmm11
14000155d: 66 41 0f 28 c5              	movapd	xmm0, xmm13
140001562: 66 41 0f 5c c6              	subpd	xmm0, xmm14
140001567: 66 45 0f 58 f5              	addpd	xmm14, xmm13
14000156c: f2 44 0f 10 f0              	movsd	xmm14, xmm0             # xmm14 = xmm0[0],xmm14[1]
140001571: 66 44 0f 28 6d 50           	movapd	xmm13, xmmword ptr [rbp + 0x50]
140001577: 66 44 0f 5c eb              	subpd	xmm13, xmm3
14000157c: 66 0f 28 65 70              	movapd	xmm4, xmmword ptr [rbp + 0x70]
140001581: 66 0f 28 ec                 	movapd	xmm5, xmm4
140001585: 66 41 0f 5c ec              	subpd	xmm5, xmm12
14000158a: 66 44 0f 28 d7              	movapd	xmm10, xmm7
14000158f: 66 0f 5c e7                 	subpd	xmm4, xmm7
140001593: 66 0f 28 dd                 	movapd	xmm3, xmm5
140001597: 66 0f 15 dc                 	unpckhpd	xmm3, xmm4              # xmm3 = xmm3[1],xmm4[1]
14000159b: 66 0f 59 db                 	mulpd	xmm3, xmm3
14000159f: 66 44 0f 28 9d 30 01 00 00  	movapd	xmm11, xmmword ptr [rbp + 0x130]
1400015a8: 66 41 0f 28 c3              	movapd	xmm0, xmm11
1400015ad: 66 41 0f 14 c5              	unpcklpd	xmm0, xmm13             # xmm0 = xmm0[0],xmm13[0]
1400015b2: 66 0f 28 f0                 	movapd	xmm6, xmm0
1400015b6: 66 0f 59 f0                 	mulpd	xmm6, xmm0
1400015ba: 66 0f 58 f3                 	addpd	xmm6, xmm3
1400015be: 66 0f 28 fd                 	movapd	xmm7, xmm5
1400015c2: 66 0f 28 dd                 	movapd	xmm3, xmm5
1400015c6: 66 0f 14 ec                 	unpcklpd	xmm5, xmm4              # xmm5 = xmm5[0],xmm4[0]
1400015ca: 66 0f 59 ed                 	mulpd	xmm5, xmm5
1400015ce: 66 0f 58 f5                 	addpd	xmm6, xmm5
1400015d2: 66 44 0f 51 c6              	sqrtpd	xmm8, xmm6
1400015d7: 66 44 0f 59 c6              	mulpd	xmm8, xmm6
1400015dc: 66 0f 28 2d 2c 1b 06 00     	movapd	xmm5, xmmword ptr [rip + 0x61b2c] # 0x140063110
1400015e4: 66 41 0f 5e e8              	divpd	xmm5, xmm8
1400015e9: 66 0f 28 15 7f 1b 06 00     	movapd	xmm2, xmmword ptr [rip + 0x61b7f] # 0x140063170
1400015f1: 66 0f 59 fa                 	mulpd	xmm7, xmm2
1400015f5: 66 0f 28 d5                 	movapd	xmm2, xmm5
1400015f9: 66 0f 14 d5                 	unpcklpd	xmm2, xmm5              # xmm2 = xmm2[0],xmm5[0]
1400015fd: 66 0f 59 fa                 	mulpd	xmm7, xmm2
140001601: 66 0f 5c cf                 	subpd	xmm1, xmm7
140001605: 66 0f 29 8d d0 00 00 00     	movapd	xmmword ptr [rbp + 0xd0], xmm1
14000160d: 66 44 0f 28 45 60           	movapd	xmm8, xmmword ptr [rbp + 0x60]
140001613: 66 45 0f 28 e0              	movapd	xmm12, xmm8
140001618: 66 44 0f 5c a5 e0 00 00 00  	subpd	xmm12, xmmword ptr [rbp + 0xe0]
140001621: 66 45 0f 5c c2              	subpd	xmm8, xmm10
140001626: 66 41 0f 28 f4              	movapd	xmm6, xmm12
14000162b: 66 41 0f 15 f0              	unpckhpd	xmm6, xmm8              # xmm6 = xmm6[1],xmm8[1]
140001630: 66 0f 59 f6                 	mulpd	xmm6, xmm6
140001634: 66 41 0f 28 fb              	movapd	xmm7, xmm11
140001639: 66 41 0f 15 fd              	unpckhpd	xmm7, xmm13             # xmm7 = xmm7[1],xmm13[1]
14000163e: 66 0f 29 bd 30 01 00 00     	movapd	xmmword ptr [rbp + 0x130], xmm7
140001646: 66 0f 59 ff                 	mulpd	xmm7, xmm7
14000164a: 66 0f 58 fe                 	addpd	xmm7, xmm6
14000164e: 66 41 0f 28 f4              	movapd	xmm6, xmm12
140001653: 66 41 0f 14 f0              	unpcklpd	xmm6, xmm8              # xmm6 = xmm6[0],xmm8[0]
140001658: 66 0f 59 f6                 	mulpd	xmm6, xmm6
14000165c: 66 0f 58 fe                 	addpd	xmm7, xmm6
140001660: 66 44 0f 51 d7              	sqrtpd	xmm10, xmm7
140001665: 66 44 0f 59 d7              	mulpd	xmm10, xmm7
14000166a: f2 44 0f 11 bd 28 01 00 00  	movsd	qword ptr [rbp + 0x128], xmm15
140001673: 66 41 0f 28 ff              	movapd	xmm7, xmm15
140001678: f2 0f 59 3d d0 1a 06 00     	mulsd	xmm7, qword ptr [rip + 0x61ad0] # 0x140063150
140001680: f2 0f 58 7d b0              	addsd	xmm7, qword ptr [rbp - 0x50]
140001685: 66 44 0f 28 3d 82 1a 06 00  	movapd	xmm15, xmmword ptr [rip + 0x61a82] # 0x140063110
14000168e: 66 41 0f 28 f7              	movapd	xmm6, xmm15
140001693: 66 41 0f 5e f2              	divpd	xmm6, xmm10
140001698: 66 44 0f 59 1d cf 1a 06 00  	mulpd	xmm11, xmmword ptr [rip + 0x61acf] # 0x140063170
1400016a1: 66 44 0f 28 d5              	movapd	xmm10, xmm5
1400016a6: 66 44 0f 14 d6              	unpcklpd	xmm10, xmm6             # xmm10 = xmm10[0],xmm6[0]
1400016ab: 66 45 0f 59 d3              	mulpd	xmm10, xmm11
1400016b0: 66 45 0f 5c f2              	subpd	xmm14, xmm10
1400016b5: 66 44 0f 59 2d 82 1a 06 00  	mulpd	xmm13, xmmword ptr [rip + 0x61a82] # 0x140063140
1400016be: 66 44 0f 28 d5              	movapd	xmm10, xmm5
1400016c3: 66 44 0f 15 d6              	unpckhpd	xmm10, xmm6             # xmm10 = xmm10[1],xmm6[1]
1400016c8: 66 45 0f 59 d5              	mulpd	xmm10, xmm13
1400016cd: 66 45 0f 5c f2              	subpd	xmm14, xmm10
1400016d2: 66 45 0f 28 de              	movapd	xmm11, xmm14
1400016d7: 66 44 0f 28 35 80 1a 06 00  	movapd	xmm14, xmmword ptr [rip + 0x61a80] # 0x140063160
1400016e0: 66 41 0f 59 c6              	mulpd	xmm0, xmm14
1400016e5: 66 0f 59 c5                 	mulpd	xmm0, xmm5
1400016e9: 66 0f 58 45 d0              	addpd	xmm0, xmmword ptr [rbp - 0x30]
1400016ee: 66 44 0f 28 95 30 01 00 00  	movapd	xmm10, xmmword ptr [rbp + 0x130]
1400016f7: 66 44 0f 59 15 a0 1a 06 00  	mulpd	xmm10, xmmword ptr [rip + 0x61aa0] # 0x1400631a0
140001700: 66 44 0f 59 d6              	mulpd	xmm10, xmm6
140001705: 66 44 0f 58 d0              	addpd	xmm10, xmm0
14000170a: 66 0f 28 8d f0 00 00 00     	movapd	xmm1, xmmword ptr [rbp + 0xf0]
140001712: 66 0f 14 c9                 	unpcklpd	xmm1, xmm1              # xmm1 = xmm1[0,0]
140001716: 66 0f 59 0d 62 1a 06 00     	mulpd	xmm1, xmmword ptr [rip + 0x61a62] # 0x140063180
14000171e: 66 0f 28 85 40 01 00 00     	movapd	xmm0, xmmword ptr [rbp + 0x140]
140001726: 66 0f 14 c0                 	unpcklpd	xmm0, xmm0              # xmm0 = xmm0[0,0]
14000172a: 66 0f 29 85 40 01 00 00     	movapd	xmmword ptr [rbp + 0x140], xmm0
140001732: 66 0f 59 c8                 	mulpd	xmm1, xmm0
140001736: 66 41 0f 28 c2              	movapd	xmm0, xmm10
14000173b: 66 0f 5c c1                 	subpd	xmm0, xmm1
14000173f: 66 44 0f 58 d1              	addpd	xmm10, xmm1
140001744: f2 44 0f 10 d0              	movsd	xmm10, xmm0             # xmm10 = xmm0[0],xmm10[1]
140001749: 66 44 0f 29 95 30 01 00 00  	movapd	xmmword ptr [rbp + 0x130], xmm10
140001752: 66 44 0f 29 9d a0 00 00 00  	movapd	xmmword ptr [rbp + 0xa0], xmm11
14000175b: 66 45 0f 59 df              	mulpd	xmm11, xmm15
140001760: 66 44 0f 58 5d 50           	addpd	xmm11, xmmword ptr [rbp + 0x50]
140001766: 66 45 0f 59 d7              	mulpd	xmm10, xmm15
14000176b: 66 44 0f 58 55 40           	addpd	xmm10, xmmword ptr [rbp + 0x40]
140001771: 66 41 0f 59 de              	mulpd	xmm3, xmm14
140001776: 66 0f 59 d3                 	mulpd	xmm2, xmm3
14000177a: 66 0f 58 55 c0              	addpd	xmm2, xmmword ptr [rbp - 0x40]
14000177f: 66 0f 28 c4                 	movapd	xmm0, xmm4
140001783: 66 44 0f 28 3d b4 19 06 00  	movapd	xmm15, xmmword ptr [rip + 0x619b4] # 0x140063140
14000178c: 66 41 0f 59 c7              	mulpd	xmm0, xmm15
140001791: 66 0f 15 ed                 	unpckhpd	xmm5, xmm5              # xmm5 = xmm5[1,1]
140001795: 66 0f 59 c5                 	mulpd	xmm0, xmm5
140001799: 66 0f 28 9d d0 00 00 00     	movapd	xmm3, xmmword ptr [rbp + 0xd0]
1400017a1: 66 0f 5c d8                 	subpd	xmm3, xmm0
1400017a5: 66 41 0f 59 e6              	mulpd	xmm4, xmm14
1400017aa: 66 0f 59 e5                 	mulpd	xmm4, xmm5
1400017ae: 66 0f 58 65 10              	addpd	xmm4, xmmword ptr [rbp + 0x10]
1400017b3: 66 41 0f 28 c4              	movapd	xmm0, xmm12
1400017b8: 66 44 0f 28 2d af 19 06 00  	movapd	xmm13, xmmword ptr [rip + 0x619af] # 0x140063170
1400017c1: 66 41 0f 59 c5              	mulpd	xmm0, xmm13
1400017c6: 66 0f 28 ce                 	movapd	xmm1, xmm6
1400017ca: 66 0f 14 ce                 	unpcklpd	xmm1, xmm6              # xmm1 = xmm1[0],xmm6[0]
1400017ce: 66 0f 59 c1                 	mulpd	xmm0, xmm1
1400017d2: 66 44 0f 5c c8              	subpd	xmm9, xmm0
1400017d7: 66 44 0f 28 35 c0 19 06 00  	movapd	xmm14, xmmword ptr [rip + 0x619c0] # 0x1400631a0
1400017e0: 66 45 0f 59 e6              	mulpd	xmm12, xmm14
1400017e5: 66 44 0f 59 e1              	mulpd	xmm12, xmm1
1400017ea: 66 44 0f 58 e2              	addpd	xmm12, xmm2
1400017ef: 66 41 0f 28 c0              	movapd	xmm0, xmm8
1400017f4: 66 41 0f 59 c7              	mulpd	xmm0, xmm15
1400017f9: 66 0f 15 f6                 	unpckhpd	xmm6, xmm6              # xmm6 = xmm6[1,1]
1400017fd: 66 0f 59 c6                 	mulpd	xmm0, xmm6
140001801: 66 41 0f 28 c9              	movapd	xmm1, xmm9
140001806: 66 0f 5c c8                 	subpd	xmm1, xmm0
14000180a: 66 45 0f 59 c6              	mulpd	xmm8, xmm14
14000180f: 66 44 0f 59 c6              	mulpd	xmm8, xmm6
140001814: 66 44 0f 58 c4              	addpd	xmm8, xmm4
140001819: 66 0f 28 55 30              	movapd	xmm2, xmmword ptr [rbp + 0x30]
14000181e: 66 0f 28 c2                 	movapd	xmm0, xmm2
140001822: 66 41 0f 59 c7              	mulpd	xmm0, xmm15
140001827: 66 0f 28 a5 40 01 00 00     	movapd	xmm4, xmmword ptr [rbp + 0x140]
14000182f: 66 0f 59 c4                 	mulpd	xmm0, xmm4
140001833: 66 44 0f 5c e0              	subpd	xmm12, xmm0
140001838: 66 41 0f 59 d5              	mulpd	xmm2, xmm13
14000183d: 66 0f 59 d4                 	mulpd	xmm2, xmm4
140001841: 66 44 0f 28 ca              	movapd	xmm9, xmm2
140001846: 66 45 0f 28 fb              	movapd	xmm15, xmm11
14000184b: 66 45 0f 15 fb              	unpckhpd	xmm15, xmm11            # xmm15 = xmm15[1],xmm11[1]
140001850: 66 45 0f 58 c8              	addpd	xmm9, xmm8
140001855: 66 0f 28 a5 c0 00 00 00     	movapd	xmm4, xmmword ptr [rbp + 0xc0]
14000185d: 66 0f 28 2d ab 18 06 00     	movapd	xmm5, xmmword ptr [rip + 0x618ab] # 0x140063110
140001865: 66 0f 59 e5                 	mulpd	xmm4, xmm5
140001869: 66 0f 58 65 a0              	addpd	xmm4, xmmword ptr [rbp - 0x60]
14000186e: 66 0f 29 9d 90 00 00 00     	movapd	xmmword ptr [rbp + 0x90], xmm3
140001876: 66 0f 59 dd                 	mulpd	xmm3, xmm5
14000187a: 66 0f 58 5d 70              	addpd	xmm3, xmmword ptr [rbp + 0x70]
14000187f: 66 0f 29 8d 80 00 00 00     	movapd	xmmword ptr [rbp + 0x80], xmm1
140001887: 66 0f 28 c1                 	movapd	xmm0, xmm1
14000188b: 66 0f 59 c5                 	mulpd	xmm0, xmm5
14000188f: 66 0f 58 45 60              	addpd	xmm0, xmmword ptr [rbp + 0x60]
140001894: 66 41 0f 28 d4              	movapd	xmm2, xmm12
140001899: 66 0f 59 d5                 	mulpd	xmm2, xmm5
14000189d: 66 0f 58 95 e0 00 00 00     	addpd	xmm2, xmmword ptr [rbp + 0xe0]
1400018a5: 66 44 0f 29 8d 40 01 00 00  	movapd	xmmword ptr [rbp + 0x140], xmm9
1400018ae: 66 44 0f 59 cd              	mulpd	xmm9, xmm5
1400018b3: 66 44 0f 58 8d 00 01 00 00  	addpd	xmm9, xmmword ptr [rbp + 0x100]
1400018bc: 66 45 0f 28 f3              	movapd	xmm14, xmm11
1400018c1: 66 44 0f 29 95 00 01 00 00  	movapd	xmmword ptr [rbp + 0x100], xmm10
1400018ca: 66 41 0f 28 ca              	movapd	xmm1, xmm10
1400018cf: 48 83 c2 ff                 	add	rdx, -0x1
1400018d3: 0f 85 b7 f8 ff ff           	jne	0x140001190 <.text+0x190>
