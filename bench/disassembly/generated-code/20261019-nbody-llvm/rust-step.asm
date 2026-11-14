140001250: 66 44 0f 29 ac 24 a0 01 00 00       	movapd	xmmword ptr [rsp + 0x1a0], xmm13
14000125a: 66 44 0f 29 bc 24 40 01 00 00       	movapd	xmmword ptr [rsp + 0x140], xmm15
140001264: 66 0f 14 e1                 	unpcklpd	xmm4, xmm1              # xmm4 = xmm4[0],xmm1[0]
140001268: 66 0f 29 a4 24 c0 00 00 00  	movapd	xmmword ptr [rsp + 0xc0], xmm4
140001271: 66 0f 28 8c 24 b0 00 00 00  	movapd	xmm1, xmmword ptr [rsp + 0xb0]
14000127a: 66 0f 14 c8                 	unpcklpd	xmm1, xmm0              # xmm1 = xmm1[0],xmm0[0]
14000127e: 66 0f 29 8c 24 b0 00 00 00  	movapd	xmmword ptr [rsp + 0xb0], xmm1
140001287: 66 0f 28 44 24 50           	movapd	xmm0, xmmword ptr [rsp + 0x50]
14000128d: 66 0f 14 c3                 	unpcklpd	xmm0, xmm3              # xmm0 = xmm0[0],xmm3[0]
140001291: 66 0f 29 44 24 50           	movapd	xmmword ptr [rsp + 0x50], xmm0
140001297: 66 0f 28 84 24 90 00 00 00  	movapd	xmm0, xmmword ptr [rsp + 0x90]
1400012a0: 66 41 0f 14 c2              	unpcklpd	xmm0, xmm10             # xmm0 = xmm0[0],xmm10[0]
1400012a5: 66 0f 29 84 24 90 00 00 00  	movapd	xmmword ptr [rsp + 0x90], xmm0
1400012ae: 0f 28 44 24 20              	movaps	xmm0, xmmword ptr [rsp + 0x20]
1400012b3: 41 0f 16 c4                 	movlhps	xmm0, xmm12             # xmm0 = xmm0[0],xmm12[0]
1400012b7: 0f 29 44 24 20              	movaps	xmmword ptr [rsp + 0x20], xmm0
1400012bc: 66 0f 28 a4 24 80 00 00 00  	movapd	xmm4, xmmword ptr [rsp + 0x80]
1400012c5: 66 0f 14 64 24 70           	unpcklpd	xmm4, xmmword ptr [rsp + 0x70] # xmm4 = xmm4[0],mem[0]
1400012cb: 66 0f 28 cc                 	movapd	xmm1, xmm4
1400012cf: 66 0f 29 a4 24 80 00 00 00  	movapd	xmmword ptr [rsp + 0x80], xmm4
1400012d8: 66 0f 28 a4 24 d0 00 00 00  	movapd	xmm4, xmmword ptr [rsp + 0xd0]
1400012e1: 66 45 0f 28 f3              	movapd	xmm14, xmm11
1400012e6: 66 44 0f 14 f5              	unpcklpd	xmm14, xmm5             # xmm14 = xmm14[0],xmm5[0]
1400012eb: 66 44 0f 28 ec              	movapd	xmm13, xmm4
1400012f0: 66 44 0f 14 ed              	unpcklpd	xmm13, xmm5             # xmm13 = xmm13[0],xmm5[0]
1400012f5: 66 0f 28 5c 24 40           	movapd	xmm3, xmmword ptr [rsp + 0x40]
1400012fb: 66 0f 28 c3                 	movapd	xmm0, xmm3
1400012ff: 66 44 0f 29 8c 24 20 02 00 00       	movapd	xmmword ptr [rsp + 0x220], xmm9
140001309: 66 41 0f 14 c1              	unpcklpd	xmm0, xmm9              # xmm0 = xmm0[0],xmm9[0]
14000130e: 66 44 0f 5c e8              	subpd	xmm13, xmm0
140001313: 66 0f 28 54 24 60           	movapd	xmm2, xmmword ptr [rsp + 0x60]
140001319: 66 0f 28 c2                 	movapd	xmm0, xmm2
14000131d: f2 0f 5c c3                 	subsd	xmm0, xmm3
140001321: 66 0f 29 44 24 70           	movapd	xmmword ptr [rsp + 0x70], xmm0
140001327: 66 0f 28 c4                 	movapd	xmm0, xmm4
14000132b: f2 0f 5c c2                 	subsd	xmm0, xmm2
14000132f: 66 0f 14 d3                 	unpcklpd	xmm2, xmm3              # xmm2 = xmm2[0],xmm3[0]
140001333: 66 0f 29 54 24 60           	movapd	xmmword ptr [rsp + 0x60], xmm2
140001339: 66 0f 14 9c 24 20 01 00 00  	unpcklpd	xmm3, xmmword ptr [rsp + 0x120] # xmm3 = xmm3[0],mem[0]
140001342: f2 0f 12 d4                 	movddup	xmm2, xmm4              # xmm2 = xmm4[0,0]
140001346: 66 44 0f 28 cc              	movapd	xmm9, xmm4
14000134b: 66 0f 29 a4 24 d0 00 00 00  	movapd	xmmword ptr [rsp + 0xd0], xmm4
140001354: 66 0f 5c d3                 	subpd	xmm2, xmm3
140001358: 66 0f 28 d8                 	movapd	xmm3, xmm0
14000135c: f2 0f 59 d8                 	mulsd	xmm3, xmm0
140001360: 66 41 0f 28 fe              	movapd	xmm7, xmm14
140001365: 66 0f 5c f9                 	subpd	xmm7, xmm1
140001369: 66 0f 28 e7                 	movapd	xmm4, xmm7
14000136d: 66 0f 59 e7                 	mulpd	xmm4, xmm7
140001371: 66 0f 28 f4                 	movapd	xmm6, xmm4
140001375: 66 0f 15 f4                 	unpckhpd	xmm6, xmm4              # xmm6 = xmm6[1],xmm4[1]
140001379: f2 0f 58 f3                 	addsd	xmm6, xmm3
14000137d: 66 44 0f 29 84 24 c0 01 00 00       	movapd	xmmword ptr [rsp + 0x1c0], xmm8
140001387: 66 0f 28 8c 24 30 01 00 00  	movapd	xmm1, xmmword ptr [rsp + 0x130]
140001390: 66 41 0f 5c c8              	subpd	xmm1, xmm8
140001395: 66 0f 28 d9                 	movapd	xmm3, xmm1
140001399: 66 0f 15 da                 	unpckhpd	xmm3, xmm2              # xmm3 = xmm3[1],xmm2[1]
14000139d: 66 45 0f 28 c5              	movapd	xmm8, xmm13
1400013a2: 66 45 0f 59 c5              	mulpd	xmm8, xmm13
1400013a7: 66 0f 59 db                 	mulpd	xmm3, xmm3
1400013ab: 66 41 0f 58 d8              	addpd	xmm3, xmm8
1400013b0: f2 44 0f 5c 5c 24 30        	subsd	xmm11, qword ptr [rsp + 0x30]
1400013b7: 66 44 0f 28 c1              	movapd	xmm8, xmm1
1400013bc: 66 0f 29 4c 24 40           	movapd	xmmword ptr [rsp + 0x40], xmm1
1400013c2: 66 45 0f 14 c3              	unpcklpd	xmm8, xmm11             # xmm8 = xmm8[0],xmm11[0]
1400013c7: 66 45 0f 59 c0              	mulpd	xmm8, xmm8
1400013cc: 66 44 0f 58 c3              	addpd	xmm8, xmm3
1400013d1: f2 0f 58 f4                 	addsd	xmm6, xmm4
1400013d5: 66 41 0f 51 d8              	sqrtpd	xmm3, xmm8
1400013da: 66 41 0f 59 d8              	mulpd	xmm3, xmm8
1400013df: 45 0f 57 c0                 	xorps	xmm8, xmm8
1400013e3: f2 44 0f 51 c6              	sqrtsd	xmm8, xmm6
1400013e8: f2 44 0f 59 c6              	mulsd	xmm8, xmm6
1400013ed: 66 0f 28 25 ab c0 01 00     	movapd	xmm4, xmmword ptr [rip + 0x1c0ab] # 0x14001d4a0
1400013f5: 66 0f 5e e3                 	divpd	xmm4, xmm3
1400013f9: f2 0f 10 2d 8f c0 01 00     	movsd	xmm5, qword ptr [rip + 0x1c08f] # 0x14001d490
140001401: f2 41 0f 5e e8              	divsd	xmm5, xmm8
140001406: 66 0f 28 d8                 	movapd	xmm3, xmm0
14000140a: f2 0f 59 1d 86 c0 01 00     	mulsd	xmm3, qword ptr [rip + 0x1c086] # 0x14001d498
140001412: f2 0f 59 dd                 	mulsd	xmm3, xmm5
140001416: f2 44 0f 10 bc 24 00 01 00 00       	movsd	xmm15, qword ptr [rsp + 0x100]
140001420: f2 44 0f 5c fb              	subsd	xmm15, xmm3
140001425: 66 0f 14 c2                 	unpcklpd	xmm0, xmm2              # xmm0 = xmm0[0],xmm2[0]
140001429: 66 0f 28 1d 8f c0 01 00     	movapd	xmm3, xmmword ptr [rip + 0x1c08f] # 0x14001d4c0
140001431: 66 0f 59 c3                 	mulpd	xmm0, xmm3
140001435: f2 0f 12 dd                 	movddup	xmm3, xmm5              # xmm3 = xmm5[0,0]
140001439: 66 0f 14 ec                 	unpcklpd	xmm5, xmm4              # xmm5 = xmm5[0],xmm4[0]
14000143d: 66 0f 59 e8                 	mulpd	xmm5, xmm0
140001441: 66 0f 28 f5                 	movapd	xmm6, xmm5
140001445: 66 41 0f 28 c5              	movapd	xmm0, xmm13
14000144a: f2 41 0f 10 c3              	movsd	xmm0, xmm11             # xmm0 = xmm11[0],xmm0[1]
14000144f: 66 0f 28 2d 99 c0 01 00     	movapd	xmm5, xmmword ptr [rip + 0x1c099] # 0x14001d4f0
140001457: 66 0f 59 c5                 	mulpd	xmm0, xmm5
14000145b: 66 44 0f 28 c4              	movapd	xmm8, xmm4
140001460: 66 44 0f 15 c4              	unpckhpd	xmm8, xmm4              # xmm8 = xmm8[1],xmm4[1]
140001465: 66 44 0f 59 c0              	mulpd	xmm8, xmm0
14000146a: 66 0f 58 b4 24 c0 00 00 00  	addpd	xmm6, xmmword ptr [rsp + 0xc0]
140001473: 66 0f 29 b4 24 c0 00 00 00  	movapd	xmmword ptr [rsp + 0xc0], xmm6
14000147c: 66 0f 28 c7                 	movapd	xmm0, xmm7
140001480: 66 0f 28 2d 48 c0 01 00     	movapd	xmm5, xmmword ptr [rip + 0x1c048] # 0x14001d4d0
140001488: 66 0f 59 c5                 	mulpd	xmm0, xmm5
14000148c: 66 0f 59 c3                 	mulpd	xmm0, xmm3
140001490: 66 0f 28 6c 24 20           	movapd	xmm5, xmmword ptr [rsp + 0x20]
140001496: 66 0f 5c e8                 	subpd	xmm5, xmm0
14000149a: 66 0f 29 6c 24 20           	movapd	xmmword ptr [rsp + 0x20], xmm5
1400014a0: 66 0f 28 b4 24 80 01 00 00  	movapd	xmm6, xmmword ptr [rsp + 0x180]
1400014a9: f2 44 0f 5c ce              	subsd	xmm9, xmm6
1400014ae: 66 41 0f 28 c1              	movapd	xmm0, xmm9
1400014b3: f2 41 0f 59 c1              	mulsd	xmm0, xmm9
1400014b8: 66 0f 28 ac 24 a0 00 00 00  	movapd	xmm5, xmmword ptr [rsp + 0xa0]
1400014c1: 66 0f 14 ac 24 10 01 00 00  	unpcklpd	xmm5, xmmword ptr [rsp + 0x110] # xmm5 = xmm5[0],mem[0]
1400014ca: 66 0f 29 ac 24 a0 00 00 00  	movapd	xmmword ptr [rsp + 0xa0], xmm5
1400014d3: 66 44 0f 5c f5              	subpd	xmm14, xmm5
1400014d8: 66 45 0f 28 d6              	movapd	xmm10, xmm14
1400014dd: 66 45 0f 59 d6              	mulpd	xmm10, xmm14
1400014e2: 66 45 0f 28 e2              	movapd	xmm12, xmm10
1400014e7: 66 45 0f 15 e2              	unpckhpd	xmm12, xmm10            # xmm12 = xmm12[1],xmm10[1]
1400014ec: f2 44 0f 58 e0              	addsd	xmm12, xmm0
1400014f1: 66 0f 28 c1                 	movapd	xmm0, xmm1
1400014f5: 66 0f 28 2d e3 bf 01 00     	movapd	xmm5, xmmword ptr [rip + 0x1bfe3] # 0x14001d4e0
1400014fd: 66 0f 59 c5                 	mulpd	xmm0, xmm5
140001501: f2 0f 12 cc                 	movddup	xmm1, xmm4              # xmm1 = xmm4[0,0]
140001505: 66 0f 29 8c 24 00 01 00 00  	movapd	xmmword ptr [rsp + 0x100], xmm1
14000150e: 66 0f 59 c1                 	mulpd	xmm0, xmm1
140001512: 66 0f 28 6c 24 20           	movapd	xmm5, xmmword ptr [rsp + 0x20]
140001518: 66 0f 5c e8                 	subpd	xmm5, xmm0
14000151c: 66 0f 29 6c 24 20           	movapd	xmmword ptr [rsp + 0x20], xmm5
140001522: f2 45 0f 58 e2              	addsd	xmm12, xmm10
140001527: 0f 57 c0                    	xorps	xmm0, xmm0
14000152a: f2 41 0f 51 c4              	sqrtsd	xmm0, xmm12
14000152f: f2 41 0f 59 c4              	mulsd	xmm0, xmm12
140001534: f2 44 0f 10 15 53 bf 01 00  	movsd	xmm10, qword ptr [rip + 0x1bf53] # 0x14001d490
14000153d: f2 44 0f 5e d0              	divsd	xmm10, xmm0
140001542: 66 45 0f 15 ee              	unpckhpd	xmm13, xmm14            # xmm13 = xmm13[1],xmm14[1]
140001547: 66 45 0f 14 de              	unpcklpd	xmm11, xmm14            # xmm11 = xmm11[0],xmm14[0]
14000154c: 66 0f 28 05 bc bf 01 00     	movapd	xmm0, xmmword ptr [rip + 0x1bfbc] # 0x14001d510
140001554: 66 44 0f 59 f0              	mulpd	xmm14, xmm0
140001559: f2 41 0f 12 c2              	movddup	xmm0, xmm10             # xmm0 = xmm10[0,0]
14000155e: 66 41 0f 59 c6              	mulpd	xmm0, xmm14
140001563: 66 44 0f 28 e2              	movapd	xmm12, xmm2
140001568: 66 41 0f c6 d1 01           	shufpd	xmm2, xmm9, 0x1         # xmm2 = xmm2[1],xmm9[0]
14000156e: 66 41 0f 28 c9              	movapd	xmm1, xmm9
140001573: 66 44 0f 59 25 34 bf 01 00  	mulpd	xmm12, xmmword ptr [rip + 0x1bf34] # 0x14001d4b0
14000157c: 66 44 0f 59 e4              	mulpd	xmm12, xmm4
140001581: f2 0f 59 0d 77 bf 01 00     	mulsd	xmm1, qword ptr [rip + 0x1bf77] # 0x14001d500
140001589: f2 41 0f 59 ca              	mulsd	xmm1, xmm10
14000158e: 66 41 0f c6 e2 01           	shufpd	xmm4, xmm10, 0x1        # xmm4 = xmm4[1],xmm10[0]
140001594: 66 0f 28 2d 24 bf 01 00     	movapd	xmm5, xmmword ptr [rip + 0x1bf24] # 0x14001d4c0
14000159c: 66 44 0f 59 ed              	mulpd	xmm13, xmm5
1400015a1: 66 44 0f 59 ec              	mulpd	xmm13, xmm4
1400015a6: 66 44 0f 58 6c 24 50        	addpd	xmm13, xmmword ptr [rsp + 0x50]
1400015ad: 66 44 0f 29 ac 24 10 02 00 00       	movapd	xmmword ptr [rsp + 0x210], xmm13
1400015b7: 66 0f 59 d5                 	mulpd	xmm2, xmm5
1400015bb: 66 0f 59 d4                 	mulpd	xmm2, xmm4
1400015bf: 66 0f 58 94 24 b0 00 00 00  	addpd	xmm2, xmmword ptr [rsp + 0xb0]
1400015c8: 66 0f 29 94 24 00 02 00 00  	movapd	xmmword ptr [rsp + 0x200], xmm2
1400015d1: f2 45 0f 5c fc              	subsd	xmm15, xmm12
1400015d6: 66 45 0f 15 e4              	unpckhpd	xmm12, xmm12            # xmm12 = xmm12[1,1]
1400015db: f2 45 0f 5c fc              	subsd	xmm15, xmm12
1400015e0: 66 0f 59 fd                 	mulpd	xmm7, xmm5
1400015e4: 66 0f 59 fb                 	mulpd	xmm7, xmm3
1400015e8: 66 0f 58 bc 24 90 00 00 00  	addpd	xmm7, xmmword ptr [rsp + 0x90]
1400015f1: 66 0f 28 94 24 e0 00 00 00  	movapd	xmm2, xmmword ptr [rsp + 0xe0]
1400015fa: 66 0f 29 94 24 b0 00 00 00  	movapd	xmmword ptr [rsp + 0xb0], xmm2
140001603: f2 0f 12 de                 	movddup	xmm3, xmm6              # xmm3 = xmm6[0,0]
140001607: 66 0f 5c d3                 	subpd	xmm2, xmm3
14000160b: 66 0f 28 5c 24 20           	movapd	xmm3, xmmword ptr [rsp + 0x20]
140001611: 66 41 0f 5c d8              	subpd	xmm3, xmm8
140001616: 66 0f 29 5c 24 20           	movapd	xmmword ptr [rsp + 0x20], xmm3
14000161c: 66 44 0f 28 ac 24 20 01 00 00       	movapd	xmm13, xmmword ptr [rsp + 0x120]
140001626: f2 41 0f 12 dd              	movddup	xmm3, xmm13             # xmm3 = xmm13[0,0]
14000162b: 66 0f 28 6c 24 60           	movapd	xmm5, xmmword ptr [rsp + 0x60]
140001631: 66 0f 5c eb                 	subpd	xmm5, xmm3
140001635: 66 0f 29 6c 24 60           	movapd	xmmword ptr [rsp + 0x60], xmm5
14000163b: 66 44 0f 28 84 24 20 02 00 00       	movapd	xmm8, xmmword ptr [rsp + 0x220]
140001645: 66 44 0f 28 4c 24 30        	movapd	xmm9, xmmword ptr [rsp + 0x30]
14000164c: 66 45 0f 14 c8              	unpcklpd	xmm9, xmm8              # xmm9 = xmm9[0],xmm8[0]
140001651: 66 44 0f 14 84 24 10 01 00 00       	unpcklpd	xmm8, xmmword ptr [rsp + 0x110] # xmm8 = xmm8[0],mem[0]
14000165b: f2 44 0f 12 a4 24 50 01 00 00       	movddup	xmm12, qword ptr [rsp + 0x150] # xmm12 = mem[0,0]
140001665: 66 45 0f 5c e0              	subpd	xmm12, xmm8
14000166a: f2 44 0f 5c f9              	subsd	xmm15, xmm1
14000166f: 66 44 0f 28 c5              	movapd	xmm8, xmm5
140001674: 66 44 0f 15 c2              	unpckhpd	xmm8, xmm2              # xmm8 = xmm8[1],xmm2[1]
140001679: 66 44 0f 29 44 24 30        	movapd	xmmword ptr [rsp + 0x30], xmm8
140001680: 66 0f 29 94 24 e0 00 00 00  	movapd	xmmword ptr [rsp + 0xe0], xmm2
140001689: 66 41 0f 28 cc              	movapd	xmm1, xmm12
14000168e: 66 41 0f 59 cc              	mulpd	xmm1, xmm12
140001693: 66 45 0f 59 c0              	mulpd	xmm8, xmm8
140001698: 66 44 0f 58 c1              	addpd	xmm8, xmm1
14000169d: 66 0f 28 8c 24 70 01 00 00  	movapd	xmm1, xmmword ptr [rsp + 0x170]
1400016a6: 66 0f 29 8c 24 90 00 00 00  	movapd	xmmword ptr [rsp + 0x90], xmm1
1400016af: 66 0f 28 9c 24 c0 01 00 00  	movapd	xmm3, xmmword ptr [rsp + 0x1c0]
1400016b8: f2 44 0f 12 d3              	movddup	xmm10, xmm3             # xmm10 = xmm3[0,0]
1400016bd: 66 44 0f 5c d1              	subpd	xmm10, xmm1
1400016c2: 66 44 0f 29 94 24 10 01 00 00       	movapd	xmmword ptr [rsp + 0x110], xmm10
1400016cc: 66 45 0f 59 d2              	mulpd	xmm10, xmm10
1400016d1: 66 45 0f 58 d0              	addpd	xmm10, xmm8
1400016d6: 66 45 0f 28 c5              	movapd	xmm8, xmm13
1400016db: f2 44 0f 5c c6              	subsd	xmm8, xmm6
1400016e0: 66 44 0f 29 84 24 20 01 00 00       	movapd	xmmword ptr [rsp + 0x120], xmm8
1400016ea: 66 0f 28 ac 24 80 00 00 00  	movapd	xmm5, xmmword ptr [rsp + 0x80]
1400016f3: 66 0f 28 cd                 	movapd	xmm1, xmm5
1400016f7: 66 44 0f 28 ac 24 a0 00 00 00       	movapd	xmm13, xmmword ptr [rsp + 0xa0]
140001701: 66 41 0f 5c cd              	subpd	xmm1, xmm13
140001706: 66 0f 29 4c 24 50           	movapd	xmmword ptr [rsp + 0x50], xmm1
14000170c: 66 41 0f 5c e9              	subpd	xmm5, xmm9
140001711: 66 45 0f 5c cd              	subpd	xmm9, xmm13
140001716: 66 44 0f 29 8c 24 a0 00 00 00       	movapd	xmmword ptr [rsp + 0xa0], xmm9
140001720: 66 0f 28 4c 24 20           	movapd	xmm1, xmmword ptr [rsp + 0x20]
140001726: 66 0f 5c c8                 	subpd	xmm1, xmm0
14000172a: 66 0f 29 4c 24 20           	movapd	xmmword ptr [rsp + 0x20], xmm1
140001730: 66 41 0f 28 c8              	movapd	xmm1, xmm8
140001735: f2 41 0f 59 c8              	mulsd	xmm1, xmm8
14000173a: 66 41 0f 28 c1              	movapd	xmm0, xmm9
14000173f: 66 41 0f 59 c1              	mulpd	xmm0, xmm9
140001744: 66 44 0f 28 f0              	movapd	xmm14, xmm0
140001749: 66 44 0f 15 f0              	unpckhpd	xmm14, xmm0             # xmm14 = xmm14[1],xmm0[1]
14000174e: f2 44 0f 58 f1              	addsd	xmm14, xmm1
140001753: 66 0f 28 4c 24 40           	movapd	xmm1, xmmword ptr [rsp + 0x40]
140001759: 66 0f 28 35 5f bd 01 00     	movapd	xmm6, xmmword ptr [rip + 0x1bd5f] # 0x14001d4c0
140001761: 66 0f 59 ce                 	mulpd	xmm1, xmm6
140001765: 66 0f 59 8c 24 00 01 00 00  	mulpd	xmm1, xmmword ptr [rsp + 0x100]
14000176e: 66 0f 58 8c 24 f0 00 00 00  	addpd	xmm1, xmmword ptr [rsp + 0xf0]
140001777: 66 0f 29 4c 24 40           	movapd	xmmword ptr [rsp + 0x40], xmm1
14000177d: 66 44 0f 28 84 24 90 01 00 00       	movapd	xmm8, xmmword ptr [rsp + 0x190]
140001787: 66 44 0f 29 84 24 80 00 00 00       	movapd	xmmword ptr [rsp + 0x80], xmm8
140001791: 66 44 0f 5c c3              	subpd	xmm8, xmm3
140001796: 66 44 0f 28 4c 24 70        	movapd	xmm9, xmmword ptr [rsp + 0x70]
14000179d: f2 45 0f 59 c9              	mulsd	xmm9, xmm9
1400017a2: 66 45 0f 28 e8              	movapd	xmm13, xmm8
1400017a7: 66 45 0f 59 e8              	mulpd	xmm13, xmm8
1400017ac: 66 41 0f 28 cd              	movapd	xmm1, xmm13
1400017b1: 66 41 0f 15 cd              	unpckhpd	xmm1, xmm13             # xmm1 = xmm1[1],xmm13[1]
1400017b6: f2 41 0f 58 c9              	addsd	xmm1, xmm9
1400017bb: f2 44 0f 58 f0              	addsd	xmm14, xmm0
1400017c0: 45 0f 57 c9                 	xorps	xmm9, xmm9
1400017c4: f2 45 0f 51 ce              	sqrtsd	xmm9, xmm14
1400017c9: f2 45 0f 59 ce              	mulsd	xmm9, xmm14
1400017ce: f2 0f 10 05 ba bc 01 00     	movsd	xmm0, qword ptr [rip + 0x1bcba] # 0x14001d490
1400017d6: 66 0f 28 d8                 	movapd	xmm3, xmm0
1400017da: f2 41 0f 5e d9              	divsd	xmm3, xmm9
1400017df: 66 44 0f 59 de              	mulpd	xmm11, xmm6
1400017e4: 66 44 0f 59 dc              	mulpd	xmm11, xmm4
1400017e9: f2 41 0f 58 cd              	addsd	xmm1, xmm13
1400017ee: 66 44 0f 58 9c 24 60 01 00 00       	addpd	xmm11, xmmword ptr [rsp + 0x160]
1400017f8: f2 44 0f 11 bc 24 00 01 00 00       	movsd	qword ptr [rsp + 0x100], xmm15
140001802: f2 44 0f 59 f8              	mulsd	xmm15, xmm0
140001807: 66 0f 28 f0                 	movapd	xmm6, xmm0
14000180b: f2 44 0f 58 bc 24 d0 00 00 00       	addsd	xmm15, qword ptr [rsp + 0xd0]
140001815: 66 44 0f 29 bc 24 d0 00 00 00       	movapd	xmmword ptr [rsp + 0xd0], xmm15
14000181f: 66 0f 28 64 24 60           	movapd	xmm4, xmmword ptr [rsp + 0x60]
140001825: 66 0f 14 e2                 	unpcklpd	xmm4, xmm2              # xmm4 = xmm4[0],xmm2[0]
140001829: 66 44 0f 28 ec              	movapd	xmm13, xmm4
14000182e: 66 0f 59 e4                 	mulpd	xmm4, xmm4
140001832: 66 44 0f 28 fd              	movapd	xmm15, xmm5
140001837: 66 0f 28 54 24 50           	movapd	xmm2, xmmword ptr [rsp + 0x50]
14000183d: 66 44 0f 15 fa              	unpckhpd	xmm15, xmm2             # xmm15 = xmm15[1],xmm2[1]
140001842: 66 45 0f 28 f7              	movapd	xmm14, xmm15
140001847: 66 45 0f 59 f7              	mulpd	xmm14, xmm15
14000184c: 66 44 0f 58 f4              	addpd	xmm14, xmm4
140001851: 66 44 0f 28 cd              	movapd	xmm9, xmm5
140001856: 66 44 0f 14 ca              	unpcklpd	xmm9, xmm2              # xmm9 = xmm9[0],xmm2[0]
14000185b: 66 41 0f 28 e1              	movapd	xmm4, xmm9
140001860: 66 41 0f 59 e1              	mulpd	xmm4, xmm9
140001865: 66 41 0f 58 e6              	addpd	xmm4, xmm14
14000186a: 66 41 0f 51 c2              	sqrtpd	xmm0, xmm10
14000186f: 66 41 0f 59 c2              	mulpd	xmm0, xmm10
140001874: 66 44 0f 51 f4              	sqrtpd	xmm14, xmm4
140001879: 66 44 0f 59 f4              	mulpd	xmm14, xmm4
14000187e: 0f 57 e4                    	xorps	xmm4, xmm4
140001881: f2 0f 51 e1                 	sqrtsd	xmm4, xmm1
140001885: f2 0f 59 e1                 	mulsd	xmm4, xmm1
140001889: 66 0f 28 15 0f bc 01 00     	movapd	xmm2, xmmword ptr [rip + 0x1bc0f] # 0x14001d4a0
140001891: 66 44 0f 28 d2              	movapd	xmm10, xmm2
140001896: 66 45 0f 5e d6              	divpd	xmm10, xmm14
14000189b: f2 0f 5e f4                 	divsd	xmm6, xmm4
14000189f: 66 0f 59 2d 49 bc 01 00     	mulpd	xmm5, xmmword ptr [rip + 0x1bc49] # 0x14001d4f0
1400018a7: f2 41 0f 12 e2              	movddup	xmm4, xmm10             # xmm4 = xmm10[0,0]
1400018ac: 66 0f 59 e5                 	mulpd	xmm4, xmm5
1400018b0: 66 0f 29 a4 24 f0 00 00 00  	movapd	xmmword ptr [rsp + 0xf0], xmm4
1400018b9: 66 41 0f 28 e0              	movapd	xmm4, xmm8
1400018be: 66 0f 28 2d 1a bc 01 00     	movapd	xmm5, xmmword ptr [rip + 0x1bc1a] # 0x14001d4e0
1400018c6: 66 0f 59 e5                 	mulpd	xmm4, xmm5
1400018ca: f2 0f 12 ce                 	movddup	xmm1, xmm6              # xmm1 = xmm6[0,0]
1400018ce: 66 0f 59 e1                 	mulpd	xmm4, xmm1
1400018d2: 66 0f 5c fc                 	subpd	xmm7, xmm4
1400018d6: 66 0f 28 25 f2 bb 01 00     	movapd	xmm4, xmmword ptr [rip + 0x1bbf2] # 0x14001d4d0
1400018de: 66 44 0f 59 fc              	mulpd	xmm15, xmm4
1400018e3: 66 45 0f 59 fa              	mulpd	xmm15, xmm10
1400018e8: 66 44 0f 58 bc 24 10 02 00 00       	addpd	xmm15, xmmword ptr [rsp + 0x210]
1400018f2: 66 44 0f 59 ec              	mulpd	xmm13, xmm4
1400018f7: 66 45 0f 59 ea              	mulpd	xmm13, xmm10
1400018fc: 66 44 0f 58 ac 24 00 02 00 00       	addpd	xmm13, xmmword ptr [rsp + 0x200]
140001906: 66 44 0f 59 cc              	mulpd	xmm9, xmm4
14000190b: 66 45 0f 59 ca              	mulpd	xmm9, xmm10
140001910: 66 45 0f 58 cb              	addpd	xmm9, xmm11
140001915: 66 0f 28 e2                 	movapd	xmm4, xmm2
140001919: 66 0f 5e e0                 	divpd	xmm4, xmm0
14000191d: 66 41 0f 28 c4              	movapd	xmm0, xmm12
140001922: 66 0f 59 c5                 	mulpd	xmm0, xmm5
140001926: 66 0f 59 c4                 	mulpd	xmm0, xmm4
14000192a: 66 41 0f 58 c7              	addpd	xmm0, xmm15
14000192f: 66 0f 28 54 24 30           	movapd	xmm2, xmmword ptr [rsp + 0x30]
140001935: 66 0f 59 d5                 	mulpd	xmm2, xmm5
140001939: 66 0f 59 d4                 	mulpd	xmm2, xmm4
14000193d: 66 41 0f 58 d5              	addpd	xmm2, xmm13
140001942: 66 44 0f 28 bc 24 10 01 00 00       	movapd	xmm15, xmmword ptr [rsp + 0x110]
14000194c: 66 45 0f 28 df              	movapd	xmm11, xmm15
140001951: 66 45 0f 14 dc              	unpcklpd	xmm11, xmm12            # xmm11 = xmm11[0],xmm12[0]
140001956: 45 0f 12 e7                 	movhlps	xmm12, xmm15            # xmm12 = xmm15[1],xmm12[1]
14000195a: 44 0f 29 64 24 30           	movaps	xmmword ptr [rsp + 0x30], xmm12
140001960: 66 44 0f 59 fd              	mulpd	xmm15, xmm5
140001965: 66 44 0f 59 fc              	mulpd	xmm15, xmm4
14000196a: 66 45 0f 58 f9              	addpd	xmm15, xmm9
14000196f: 66 0f 28 b4 24 a0 00 00 00  	movapd	xmm6, xmmword ptr [rsp + 0xa0]
140001978: 66 44 0f 28 f6              	movapd	xmm14, xmm6
14000197d: 66 44 0f 15 f6              	unpckhpd	xmm14, xmm6             # xmm14 = xmm14[1],xmm6[1]
140001982: 66 44 0f 28 2d a5 bb 01 00  	movapd	xmm13, xmmword ptr [rip + 0x1bba5] # 0x14001d530
14000198b: 66 45 0f 59 f5              	mulpd	xmm14, xmm13
140001990: f2 0f 12 db                 	movddup	xmm3, xmm3              # xmm3 = xmm3[0,0]
140001994: 66 44 0f 59 f3              	mulpd	xmm14, xmm3
140001999: 66 0f 28 e8                 	movapd	xmm5, xmm0
14000199d: 66 41 0f 5c ee              	subpd	xmm5, xmm14
1400019a2: 66 44 0f 58 f0              	addpd	xmm14, xmm0
1400019a7: f2 0f 12 84 24 20 01 00 00  	movddup	xmm0, qword ptr [rsp + 0x120] # xmm0 = mem[0,0]
1400019b0: 66 41 0f 59 c5              	mulpd	xmm0, xmm13
1400019b5: 66 0f 59 c3                 	mulpd	xmm0, xmm3
1400019b9: 66 44 0f 28 e2              	movapd	xmm12, xmm2
1400019be: 66 44 0f 5c e0              	subpd	xmm12, xmm0
1400019c3: 66 0f 58 c2                 	addpd	xmm0, xmm2
1400019c7: f2 44 0f 12 ce              	movddup	xmm9, xmm6              # xmm9 = xmm6[0,0]
1400019cc: 66 45 0f 59 cd              	mulpd	xmm9, xmm13
1400019d1: 66 44 0f 59 cb              	mulpd	xmm9, xmm3
1400019d6: 66 45 0f d0 f9              	addsubpd	xmm15, xmm9
1400019db: f2 0f 12 5c 24 70           	movddup	xmm3, qword ptr [rsp + 0x70] # xmm3 = mem[0,0]
1400019e1: 66 0f 59 1d 37 bb 01 00     	mulpd	xmm3, xmmword ptr [rip + 0x1bb37] # 0x14001d520
1400019e9: 66 0f 59 d9                 	mulpd	xmm3, xmm1
1400019ed: 66 0f 28 94 24 c0 00 00 00  	movapd	xmm2, xmmword ptr [rsp + 0xc0]
1400019f6: 66 0f d0 d3                 	addsubpd	xmm2, xmm3
1400019fa: 66 44 0f 28 4c 24 60        	movapd	xmm9, xmmword ptr [rsp + 0x60]
140001a01: 66 0f 28 1d e7 ba 01 00     	movapd	xmm3, xmmword ptr [rip + 0x1bae7] # 0x14001d4f0
140001a09: 66 44 0f 59 cb              	mulpd	xmm9, xmm3
140001a0e: 66 41 0f 28 da              	movapd	xmm3, xmm10
140001a13: 66 0f 14 dc                 	unpcklpd	xmm3, xmm4              # xmm3 = xmm3[0],xmm4[0]
140001a17: 66 41 0f 59 d9              	mulpd	xmm3, xmm9
140001a1c: 66 44 0f 28 2d eb ba 01 00  	movapd	xmm13, xmmword ptr [rip + 0x1baeb] # 0x14001d510
140001a25: 66 0f 28 b4 24 e0 00 00 00  	movapd	xmm6, xmmword ptr [rsp + 0xe0]
140001a2e: 66 41 0f 59 f5              	mulpd	xmm6, xmm13
140001a33: 66 45 0f 28 ca              	movapd	xmm9, xmm10
140001a38: 66 44 0f 15 cc              	unpckhpd	xmm9, xmm4              # xmm9 = xmm9[1],xmm4[1]
140001a3d: 66 44 0f 59 ce              	mulpd	xmm9, xmm6
140001a42: 66 0f 28 f2                 	movapd	xmm6, xmm2
140001a46: 66 0f 5c bc 24 f0 00 00 00  	subpd	xmm7, xmmword ptr [rsp + 0xf0]
140001a4f: 66 44 0f 59 05 78 ba 01 00  	mulpd	xmm8, xmmword ptr [rip + 0x1ba78] # 0x14001d4d0
140001a58: 66 44 0f 59 c1              	mulpd	xmm8, xmm1
140001a5d: 66 44 0f 58 44 24 40        	addpd	xmm8, xmmword ptr [rsp + 0x40]
140001a64: 66 0f 5c f3                 	subpd	xmm6, xmm3
140001a68: 66 0f 28 54 24 20           	movapd	xmm2, xmmword ptr [rsp + 0x20]
140001a6e: 66 0f 28 1d 2a ba 01 00     	movapd	xmm3, xmmword ptr [rip + 0x1ba2a] # 0x14001d4a0
140001a76: 66 0f 59 d3                 	mulpd	xmm2, xmm3
140001a7a: 66 0f 58 94 24 30 01 00 00  	addpd	xmm2, xmmword ptr [rsp + 0x130]
140001a83: 66 0f 28 4c 24 50           	movapd	xmm1, xmmword ptr [rsp + 0x50]
140001a89: 66 41 0f 59 cd              	mulpd	xmm1, xmm13
140001a8e: 66 45 0f 15 d2              	unpckhpd	xmm10, xmm10            # xmm10 = xmm10[1,1]
140001a93: 66 44 0f 59 d1              	mulpd	xmm10, xmm1
140001a98: 66 41 0f 5c f1              	subpd	xmm6, xmm9
140001a9d: 66 44 0f 28 8c 24 40 01 00 00       	movapd	xmm9, xmmword ptr [rsp + 0x140]
140001aa7: 66 44 0f 59 1d 40 ba 01 00  	mulpd	xmm11, xmmword ptr [rip + 0x1ba40] # 0x14001d4f0
140001ab0: f2 0f 12 cc                 	movddup	xmm1, xmm4              # xmm1 = xmm4[0,0]
140001ab4: 66 41 0f 59 cb              	mulpd	xmm1, xmm11
140001ab9: 66 41 0f 5c fa              	subpd	xmm7, xmm10
140001abe: 66 44 0f 5c c1              	subpd	xmm8, xmm1
140001ac3: 66 44 0f 28 de              	movapd	xmm11, xmm6
140001ac8: 66 44 0f 59 db              	mulpd	xmm11, xmm3
140001acd: 66 44 0f 58 9c 24 b0 00 00 00       	addpd	xmm11, xmmword ptr [rsp + 0xb0]
140001ad7: 66 0f 28 4c 24 30           	movapd	xmm1, xmmword ptr [rsp + 0x30]
140001add: 66 41 0f 59 cd              	mulpd	xmm1, xmm13
140001ae2: 66 0f 15 e4                 	unpckhpd	xmm4, xmm4              # xmm4 = xmm4[1,1]
140001ae6: 66 0f 59 e1                 	mulpd	xmm4, xmm1
140001aea: 66 41 0f 28 ce              	movapd	xmm1, xmm14
140001aef: 66 0f 29 6c 24 50           	movapd	xmmword ptr [rsp + 0x50], xmm5
140001af5: f2 0f 10 cd                 	movsd	xmm1, xmm5              # xmm1 = xmm5[0],xmm1[1]
140001af9: 66 44 0f 5c c4              	subpd	xmm8, xmm4
140001afe: 66 44 0f 28 ef              	movapd	xmm13, xmm7
140001b03: 66 44 0f 59 eb              	mulpd	xmm13, xmm3
140001b08: 66 44 0f 58 ac 24 80 00 00 00       	addpd	xmm13, xmmword ptr [rsp + 0x80]
140001b12: 66 0f 29 8c 24 c0 00 00 00  	movapd	xmmword ptr [rsp + 0xc0], xmm1
140001b1b: 66 0f 59 cb                 	mulpd	xmm1, xmm3
140001b1f: 66 44 0f 58 c9              	addpd	xmm9, xmm1
140001b24: 66 0f 28 c8                 	movapd	xmm1, xmm0
140001b28: 66 44 0f 29 a4 24 b0 00 00 00       	movapd	xmmword ptr [rsp + 0xb0], xmm12
140001b32: f2 41 0f 10 cc              	movsd	xmm1, xmm12             # xmm1 = xmm12[0],xmm1[1]
140001b37: 66 0f 29 8c 24 40 01 00 00  	movapd	xmmword ptr [rsp + 0x140], xmm1
140001b40: 66 0f 59 cb                 	mulpd	xmm1, xmm3
140001b44: 66 0f 28 a4 24 a0 01 00 00  	movapd	xmm4, xmmword ptr [rsp + 0x1a0]
140001b4d: 66 0f 58 e1                 	addpd	xmm4, xmm1
140001b51: 66 0f 29 a4 24 a0 01 00 00  	movapd	xmmword ptr [rsp + 0x1a0], xmm4
140001b5a: 66 44 0f 29 bc 24 60 01 00 00       	movapd	xmmword ptr [rsp + 0x160], xmm15
140001b64: 66 44 0f 59 fb              	mulpd	xmm15, xmm3
140001b69: 66 44 0f 58 bc 24 90 00 00 00       	addpd	xmm15, xmmword ptr [rsp + 0x90]
140001b73: 66 44 0f 29 84 24 f0 00 00 00       	movapd	xmmword ptr [rsp + 0xf0], xmm8
140001b7d: 66 44 0f 59 c3              	mulpd	xmm8, xmm3
140001b82: 66 44 0f 58 84 24 c0 01 00 00       	addpd	xmm8, xmmword ptr [rsp + 0x1c0]
140001b8c: 66 41 0f 28 cf              	movapd	xmm1, xmm15
140001b91: 66 41 0f 15 cf              	unpckhpd	xmm1, xmm15             # xmm1 = xmm1[1],xmm15[1]
140001b96: 66 0f 29 8c 24 a0 00 00 00  	movapd	xmmword ptr [rsp + 0xa0], xmm1
140001b9f: 66 41 0f 28 c9              	movapd	xmm1, xmm9
140001ba4: 66 41 0f 15 c9              	unpckhpd	xmm1, xmm9              # xmm1 = xmm1[1],xmm9[1]
140001ba9: 66 0f 29 8c 24 10 01 00 00  	movapd	xmmword ptr [rsp + 0x110], xmm1
140001bb2: 66 44 0f 28 d7              	movapd	xmm10, xmm7
140001bb7: 66 44 0f 15 d7              	unpckhpd	xmm10, xmm7             # xmm10 = xmm10[1],xmm7[1]
140001bbc: 66 0f 28 cc                 	movapd	xmm1, xmm4
140001bc0: 66 0f 15 cc                 	unpckhpd	xmm1, xmm4              # xmm1 = xmm1[1],xmm4[1]
140001bc4: 66 0f 29 8c 24 80 01 00 00  	movapd	xmmword ptr [rsp + 0x180], xmm1
140001bcd: 66 0f 28 ce                 	movapd	xmm1, xmm6
140001bd1: 66 0f 15 ce                 	unpckhpd	xmm1, xmm6              # xmm1 = xmm1[1],xmm6[1]
140001bd5: 66 41 0f 28 dd              	movapd	xmm3, xmm13
140001bda: 66 41 0f 15 dd              	unpckhpd	xmm3, xmm13             # xmm3 = xmm3[1],xmm13[1]
140001bdf: 66 0f 29 5c 24 70           	movapd	xmmword ptr [rsp + 0x70], xmm3
140001be5: 66 0f 15 c0                 	unpckhpd	xmm0, xmm0              # xmm0 = xmm0[1,1]
140001be9: 66 41 0f 28 de              	movapd	xmm3, xmm14
140001bee: 66 41 0f 15 de              	unpckhpd	xmm3, xmm14             # xmm3 = xmm3[1],xmm14[1]
140001bf3: 66 41 0f 28 e3              	movapd	xmm4, xmm11
140001bf8: 66 41 0f 15 e3              	unpckhpd	xmm4, xmm11             # xmm4 = xmm4[1],xmm11[1]
140001bfd: 66 0f 29 64 24 40           	movapd	xmmword ptr [rsp + 0x40], xmm4
140001c03: 44 0f 28 64 24 20           	movaps	xmm12, xmmword ptr [rsp + 0x20]
140001c09: 45 0f 12 e4                 	movhlps	xmm12, xmm12            # xmm12 = xmm12[1,1]
140001c0d: 66 0f 28 ea                 	movapd	xmm5, xmm2
140001c11: 66 0f 15 ea                 	unpckhpd	xmm5, xmm2              # xmm5 = xmm5[1],xmm2[1]
140001c15: 66 41 0f 28 e0              	movapd	xmm4, xmm8
140001c1a: 66 41 0f 15 e0              	unpckhpd	xmm4, xmm8              # xmm4 = xmm4[1],xmm8[1]
140001c1f: 66 0f 29 a4 24 50 01 00 00  	movapd	xmmword ptr [rsp + 0x150], xmm4
140001c28: 66 0f 28 e6                 	movapd	xmm4, xmm6
140001c2c: 66 0f 29 bc 24 90 00 00 00  	movapd	xmmword ptr [rsp + 0x90], xmm7
140001c35: 66 44 0f 29 9c 24 e0 00 00 00       	movapd	xmmword ptr [rsp + 0xe0], xmm11
140001c3f: 66 44 0f 29 5c 24 60        	movapd	xmmword ptr [rsp + 0x60], xmm11
140001c46: 66 0f 29 94 24 30 01 00 00  	movapd	xmmword ptr [rsp + 0x130], xmm2
140001c4f: 66 44 0f 28 da              	movapd	xmm11, xmm2
140001c54: 66 44 0f 29 ac 24 90 01 00 00       	movapd	xmmword ptr [rsp + 0x190], xmm13
140001c5e: 66 44 0f 29 ac 24 80 00 00 00       	movapd	xmmword ptr [rsp + 0x80], xmm13
140001c68: 66 44 0f 29 bc 24 70 01 00 00       	movapd	xmmword ptr [rsp + 0x170], xmm15
140001c72: 66 44 0f 29 7c 24 30        	movapd	xmmword ptr [rsp + 0x30], xmm15
140001c79: 66 45 0f 28 f9              	movapd	xmm15, xmm9
140001c7e: 66 0f 28 94 24 a0 01 00 00  	movapd	xmm2, xmmword ptr [rsp + 0x1a0]
140001c87: 66 44 0f 28 ea              	movapd	xmm13, xmm2
140001c8c: 66 0f 29 94 24 20 01 00 00  	movapd	xmmword ptr [rsp + 0x120], xmm2
140001c95: 48 ff c8                    	dec	rax
140001c98: 0f 85 b2 f5 ff ff           	jne	0x140001250 <.text+0x250>
