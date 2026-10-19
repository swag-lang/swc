140001000: 48 81 ec a8 00 00 00        	sub	rsp, 0xa8
140001007: 44 0f 29 bc 24 90 00 00 00  	movaps	xmmword ptr [rsp + 0x90], xmm15
140001010: 44 0f 29 b4 24 80 00 00 00  	movaps	xmmword ptr [rsp + 0x80], xmm14
140001019: 44 0f 29 6c 24 70           	movaps	xmmword ptr [rsp + 0x70], xmm13
14000101f: 44 0f 29 64 24 60           	movaps	xmmword ptr [rsp + 0x60], xmm12
140001025: 44 0f 29 5c 24 50           	movaps	xmmword ptr [rsp + 0x50], xmm11
14000102b: 44 0f 29 54 24 40           	movaps	xmmword ptr [rsp + 0x40], xmm10
140001031: 44 0f 29 4c 24 30           	movaps	xmmword ptr [rsp + 0x30], xmm9
140001037: 44 0f 29 44 24 20           	movaps	xmmword ptr [rsp + 0x20], xmm8
14000103d: 0f 29 7c 24 10              	movaps	xmmword ptr [rsp + 0x10], xmm7
140001042: 0f 29 34 24                 	movaps	xmmword ptr [rsp], xmm6
140001046: f2 0f 10 59 10              	movsd	xmm3, qword ptr [rcx + 0x10]
14000104b: 66 0f 28 f3                 	movapd	xmm6, xmm3
14000104f: f2 0f 5c 71 48              	subsd	xmm6, qword ptr [rcx + 0x48]
140001054: 66 44 0f 28 c6              	movapd	xmm8, xmm6
140001059: f2 44 0f 59 c6              	mulsd	xmm8, xmm6
14000105e: f2 0f 10 51 68              	movsd	xmm2, qword ptr [rcx + 0x68]
140001063: 66 0f 28 fe                 	movapd	xmm7, xmm6
140001067: f2 0f 59 fa                 	mulsd	xmm7, xmm2
14000106b: f2 0f 10 41 28              	movsd	xmm0, qword ptr [rcx + 0x28]
140001070: f2 0f 10 61 30              	movsd	xmm4, qword ptr [rcx + 0x30]
140001075: 66 0f 10 29                 	movupd	xmm5, xmmword ptr [rcx]
140001079: 66 44 0f 10 51 38           	movupd	xmm10, xmmword ptr [rcx + 0x38]
14000107f: 66 44 0f 28 cd              	movapd	xmm9, xmm5
140001084: 66 45 0f 5c ca              	subpd	xmm9, xmm10
140001089: 66 45 0f 28 d1              	movapd	xmm10, xmm9
14000108e: 66 0f 14 d2                 	unpcklpd	xmm2, xmm2              # xmm2 = xmm2[0,0]
140001092: 66 41 0f 59 d1              	mulpd	xmm2, xmm9
140001097: 66 45 0f 59 c9              	mulpd	xmm9, xmm9
14000109c: 66 45 0f 28 d9              	movapd	xmm11, xmm9
1400010a1: 66 45 0f 15 d9              	unpckhpd	xmm11, xmm9             # xmm11 = xmm11[1],xmm9[1]
1400010a6: f2 45 0f 58 d9              	addsd	xmm11, xmm9
1400010ab: f2 45 0f 58 d8              	addsd	xmm11, xmm8
1400010b0: 45 0f 57 c0                 	xorps	xmm8, xmm8
1400010b4: f2 45 0f 51 c3              	sqrtsd	xmm8, xmm11
1400010b9: f2 45 0f 59 c3              	mulsd	xmm8, xmm11
1400010be: 66 44 0f 28 d9              	movapd	xmm11, xmm1
1400010c3: f2 45 0f 5e d8              	divsd	xmm11, xmm8
1400010c8: f2 41 0f 59 fb              	mulsd	xmm7, xmm11
1400010cd: f2 0f 5c c7                 	subsd	xmm0, xmm7
1400010d1: 66 44 0f 28 cc              	movapd	xmm9, xmm4
1400010d6: 66 44 0f 14 cc              	unpcklpd	xmm9, xmm4              # xmm9 = xmm9[0],xmm4[0]
1400010db: 66 45 0f 59 d1              	mulpd	xmm10, xmm9
1400010e0: f2 0f 59 f4                 	mulsd	xmm6, xmm4
1400010e4: f2 41 0f 59 f3              	mulsd	xmm6, xmm11
1400010e9: 66 41 0f 28 fb              	movapd	xmm7, xmm11
1400010ee: 66 41 0f 14 fb              	unpcklpd	xmm7, xmm11             # xmm7 = xmm7[0],xmm11[0]
1400010f3: 66 44 0f 59 d7              	mulpd	xmm10, xmm7
1400010f8: 66 44 0f 10 41 50           	movupd	xmm8, xmmword ptr [rcx + 0x50]
1400010fe: 66 45 0f 58 c2              	addpd	xmm8, xmm10
140001103: 66 44 0f 11 41 50           	movupd	xmmword ptr [rcx + 0x50], xmm8
140001109: f2 0f 58 71 60              	addsd	xmm6, qword ptr [rcx + 0x60]
14000110e: f2 0f 11 71 60              	movsd	qword ptr [rcx + 0x60], xmm6
140001113: f2 0f 5c 99 80 00 00 00     	subsd	xmm3, qword ptr [rcx + 0x80]
14000111b: 66 44 0f 28 c3              	movapd	xmm8, xmm3
140001120: f2 44 0f 59 c3              	mulsd	xmm8, xmm3
140001125: f2 0f 10 b1 a0 00 00 00     	movsd	xmm6, qword ptr [rcx + 0xa0]
14000112d: 66 44 0f 28 d3              	movapd	xmm10, xmm3
140001132: f2 44 0f 59 d6              	mulsd	xmm10, xmm6
140001137: 66 44 0f 10 59 70           	movupd	xmm11, xmmword ptr [rcx + 0x70]
14000113d: 66 41 0f 5c eb              	subpd	xmm5, xmm11
140001142: 66 44 0f 59 cd              	mulpd	xmm9, xmm5
140001147: 66 0f 14 f6                 	unpcklpd	xmm6, xmm6              # xmm6 = xmm6[0,0]
14000114b: 66 0f 59 f5                 	mulpd	xmm6, xmm5
14000114f: 66 0f 59 ed                 	mulpd	xmm5, xmm5
140001153: 66 44 0f 28 dd              	movapd	xmm11, xmm5
140001158: 66 44 0f 15 dd              	unpckhpd	xmm11, xmm5             # xmm11 = xmm11[1],xmm5[1]
14000115d: f2 44 0f 58 dd              	addsd	xmm11, xmm5
140001162: f2 45 0f 58 d8              	addsd	xmm11, xmm8
140001167: 0f 57 ed                    	xorps	xmm5, xmm5
14000116a: f2 41 0f 51 eb              	sqrtsd	xmm5, xmm11
14000116f: f2 41 0f 59 eb              	mulsd	xmm5, xmm11
140001174: 66 44 0f 28 c1              	movapd	xmm8, xmm1
140001179: f2 44 0f 5e c5              	divsd	xmm8, xmm5
14000117e: f2 45 0f 59 d0              	mulsd	xmm10, xmm8
140001183: f2 41 0f 5c c2              	subsd	xmm0, xmm10
140001188: f2 0f 59 dc                 	mulsd	xmm3, xmm4
14000118c: f2 41 0f 59 d8              	mulsd	xmm3, xmm8
140001191: 66 45 0f 14 c0              	unpcklpd	xmm8, xmm8              # xmm8 = xmm8[0,0]
140001196: 66 45 0f 59 c8              	mulpd	xmm9, xmm8
14000119b: 66 0f 10 a1 88 00 00 00     	movupd	xmm4, xmmword ptr [rcx + 0x88]
1400011a3: 66 41 0f 58 e1              	addpd	xmm4, xmm9
1400011a8: 66 0f 11 a1 88 00 00 00     	movupd	xmmword ptr [rcx + 0x88], xmm4
1400011b0: f2 0f 58 99 98 00 00 00     	addsd	xmm3, qword ptr [rcx + 0x98]
1400011b8: f2 0f 11 99 98 00 00 00     	movsd	qword ptr [rcx + 0x98], xmm3
1400011c0: f2 0f 10 59 10              	movsd	xmm3, qword ptr [rcx + 0x10]
1400011c5: 66 44 0f 28 db              	movapd	xmm11, xmm3
1400011ca: f2 44 0f 5c 99 b8 00 00 00  	subsd	xmm11, qword ptr [rcx + 0xb8]
1400011d3: 66 45 0f 28 cb              	movapd	xmm9, xmm11
1400011d8: f2 45 0f 59 cb              	mulsd	xmm9, xmm11
1400011dd: f2 44 0f 10 91 d8 00 00 00  	movsd	xmm10, qword ptr [rcx + 0xd8]
1400011e6: 66 45 0f 28 e3              	movapd	xmm12, xmm11
1400011eb: f2 45 0f 59 e2              	mulsd	xmm12, xmm10
1400011f0: f2 0f 10 69 30              	movsd	xmm5, qword ptr [rcx + 0x30]
1400011f5: 66 0f 10 21                 	movupd	xmm4, xmmword ptr [rcx]
1400011f9: 66 44 0f 10 a9 a8 00 00 00  	movupd	xmm13, xmmword ptr [rcx + 0xa8]
140001202: 66 44 0f 28 f4              	movapd	xmm14, xmm4
140001207: 66 45 0f 5c f5              	subpd	xmm14, xmm13
14000120c: 66 45 0f 28 fe              	movapd	xmm15, xmm14
140001211: 66 45 0f 14 d2              	unpcklpd	xmm10, xmm10            # xmm10 = xmm10[0,0]
140001216: 66 45 0f 59 d6              	mulpd	xmm10, xmm14
14000121b: 66 45 0f 59 f6              	mulpd	xmm14, xmm14
140001220: 66 45 0f 28 ee              	movapd	xmm13, xmm14
140001225: 66 45 0f 15 ee              	unpckhpd	xmm13, xmm14            # xmm13 = xmm13[1],xmm14[1]
14000122a: f2 45 0f 58 ee              	addsd	xmm13, xmm14
14000122f: f2 45 0f 58 e9              	addsd	xmm13, xmm9
140001234: 45 0f 57 c9                 	xorps	xmm9, xmm9
140001238: f2 45 0f 51 cd              	sqrtsd	xmm9, xmm13
14000123d: f2 45 0f 59 cd              	mulsd	xmm9, xmm13
140001242: 66 44 0f 28 e9              	movapd	xmm13, xmm1
140001247: f2 45 0f 5e e9              	divsd	xmm13, xmm9
14000124c: f2 45 0f 59 e5              	mulsd	xmm12, xmm13
140001251: 66 44 0f 28 cd              	movapd	xmm9, xmm5
140001256: 66 44 0f 14 cd              	unpcklpd	xmm9, xmm5              # xmm9 = xmm9[0],xmm5[0]
14000125b: 66 45 0f 59 f9              	mulpd	xmm15, xmm9
140001260: f2 44 0f 59 dd              	mulsd	xmm11, xmm5
140001265: f2 45 0f 59 dd              	mulsd	xmm11, xmm13
14000126a: 66 45 0f 14 ed              	unpcklpd	xmm13, xmm13            # xmm13 = xmm13[0,0]
14000126f: 66 45 0f 59 fd              	mulpd	xmm15, xmm13
140001274: 66 44 0f 10 b1 c0 00 00 00  	movupd	xmm14, xmmword ptr [rcx + 0xc0]
14000127d: 66 45 0f 58 f7              	addpd	xmm14, xmm15
140001282: 66 44 0f 11 b1 c0 00 00 00  	movupd	xmmword ptr [rcx + 0xc0], xmm14
14000128b: f2 44 0f 58 99 d0 00 00 00  	addsd	xmm11, qword ptr [rcx + 0xd0]
140001294: f2 41 0f 5c c4              	subsd	xmm0, xmm12
140001299: f2 44 0f 11 99 d0 00 00 00  	movsd	qword ptr [rcx + 0xd0], xmm11
1400012a2: f2 0f 5c 99 f0 00 00 00     	subsd	xmm3, qword ptr [rcx + 0xf0]
1400012aa: 66 44 0f 10 99 e0 00 00 00  	movupd	xmm11, xmmword ptr [rcx + 0xe0]
1400012b3: 66 41 0f 5c e3              	subpd	xmm4, xmm11
1400012b8: 66 44 0f 28 dc              	movapd	xmm11, xmm4
1400012bd: 66 44 0f 59 dc              	mulpd	xmm11, xmm4
1400012c2: 66 45 0f 28 e3              	movapd	xmm12, xmm11
1400012c7: 66 45 0f 15 e3              	unpckhpd	xmm12, xmm11            # xmm12 = xmm12[1],xmm11[1]
1400012cc: f2 45 0f 58 e3              	addsd	xmm12, xmm11
1400012d1: 66 44 0f 28 db              	movapd	xmm11, xmm3
1400012d6: f2 44 0f 59 db              	mulsd	xmm11, xmm3
1400012db: f2 45 0f 58 e3              	addsd	xmm12, xmm11
1400012e0: 45 0f 57 db                 	xorps	xmm11, xmm11
1400012e4: f2 45 0f 51 dc              	sqrtsd	xmm11, xmm12
1400012e9: f2 45 0f 59 dc              	mulsd	xmm11, xmm12
1400012ee: 66 44 0f 28 e1              	movapd	xmm12, xmm1
1400012f3: f2 45 0f 5e e3              	divsd	xmm12, xmm11
1400012f8: f2 44 0f 10 99 10 01 00 00  	movsd	xmm11, qword ptr [rcx + 0x110]
140001301: 66 0f 59 d7                 	mulpd	xmm2, xmm7
140001305: 66 0f 10 79 18              	movupd	xmm7, xmmword ptr [rcx + 0x18]
14000130a: 66 0f 5c fa                 	subpd	xmm7, xmm2
14000130e: 66 0f 28 d3                 	movapd	xmm2, xmm3
140001312: f2 41 0f 59 d3              	mulsd	xmm2, xmm11
140001317: 66 41 0f 59 f0              	mulpd	xmm6, xmm8
14000131c: 66 0f 5c fe                 	subpd	xmm7, xmm6
140001320: 66 45 0f 59 d5              	mulpd	xmm10, xmm13
140001325: 66 41 0f 5c fa              	subpd	xmm7, xmm10
14000132a: 66 45 0f 14 db              	unpcklpd	xmm11, xmm11            # xmm11 = xmm11[0,0]
14000132f: 66 44 0f 59 dc              	mulpd	xmm11, xmm4
140001334: f2 41 0f 59 d4              	mulsd	xmm2, xmm12
140001339: f2 0f 59 dd                 	mulsd	xmm3, xmm5
14000133d: f2 41 0f 59 dc              	mulsd	xmm3, xmm12
140001342: 66 45 0f 14 e4              	unpcklpd	xmm12, xmm12            # xmm12 = xmm12[0,0]
140001347: 66 45 0f 59 dc              	mulpd	xmm11, xmm12
14000134c: 66 41 0f 5c fb              	subpd	xmm7, xmm11
140001351: 66 0f 11 79 18              	movupd	xmmword ptr [rcx + 0x18], xmm7
140001356: f2 0f 5c c2                 	subsd	xmm0, xmm2
14000135a: f2 0f 11 41 28              	movsd	qword ptr [rcx + 0x28], xmm0
14000135f: 66 41 0f 59 e1              	mulpd	xmm4, xmm9
140001364: 66 41 0f 59 e4              	mulpd	xmm4, xmm12
140001369: 66 0f 10 81 f8 00 00 00     	movupd	xmm0, xmmword ptr [rcx + 0xf8]
140001371: 66 0f 58 c4                 	addpd	xmm0, xmm4
140001375: 66 0f 11 81 f8 00 00 00     	movupd	xmmword ptr [rcx + 0xf8], xmm0
14000137d: f2 0f 58 99 08 01 00 00     	addsd	xmm3, qword ptr [rcx + 0x108]
140001385: f2 0f 11 99 08 01 00 00     	movsd	qword ptr [rcx + 0x108], xmm3
14000138d: f2 0f 10 61 48              	movsd	xmm4, qword ptr [rcx + 0x48]
140001392: 66 0f 28 fc                 	movapd	xmm7, xmm4
140001396: f2 0f 5c b9 80 00 00 00     	subsd	xmm7, qword ptr [rcx + 0x80]
14000139e: 66 44 0f 28 c7              	movapd	xmm8, xmm7
1400013a3: f2 44 0f 59 c7              	mulsd	xmm8, xmm7
1400013a8: f2 0f 10 91 a0 00 00 00     	movsd	xmm2, qword ptr [rcx + 0xa0]
1400013b0: 66 0f 28 df                 	movapd	xmm3, xmm7
1400013b4: f2 0f 59 da                 	mulsd	xmm3, xmm2
1400013b8: f2 0f 10 41 60              	movsd	xmm0, qword ptr [rcx + 0x60]
1400013bd: f2 0f 10 69 68              	movsd	xmm5, qword ptr [rcx + 0x68]
1400013c2: 66 0f 10 71 38              	movupd	xmm6, xmmword ptr [rcx + 0x38]
1400013c7: 66 44 0f 10 51 70           	movupd	xmm10, xmmword ptr [rcx + 0x70]
1400013cd: 66 44 0f 28 ce              	movapd	xmm9, xmm6
1400013d2: 66 45 0f 5c ca              	subpd	xmm9, xmm10
1400013d7: 66 45 0f 28 d1              	movapd	xmm10, xmm9
1400013dc: 66 0f 14 d2                 	unpcklpd	xmm2, xmm2              # xmm2 = xmm2[0,0]
1400013e0: 66 41 0f 59 d1              	mulpd	xmm2, xmm9
1400013e5: 66 45 0f 59 c9              	mulpd	xmm9, xmm9
1400013ea: 66 45 0f 28 d9              	movapd	xmm11, xmm9
1400013ef: 66 45 0f 15 d9              	unpckhpd	xmm11, xmm9             # xmm11 = xmm11[1],xmm9[1]
1400013f4: f2 45 0f 58 d9              	addsd	xmm11, xmm9
1400013f9: f2 45 0f 58 d8              	addsd	xmm11, xmm8
1400013fe: 45 0f 57 c0                 	xorps	xmm8, xmm8
140001402: f2 45 0f 51 c3              	sqrtsd	xmm8, xmm11
140001407: f2 45 0f 59 c3              	mulsd	xmm8, xmm11
14000140c: 66 44 0f 28 c9              	movapd	xmm9, xmm1
140001411: f2 45 0f 5e c8              	divsd	xmm9, xmm8
140001416: f2 41 0f 59 d9              	mulsd	xmm3, xmm9
14000141b: f2 0f 5c c3                 	subsd	xmm0, xmm3
14000141f: 66 0f 28 dd                 	movapd	xmm3, xmm5
140001423: 66 0f 14 dd                 	unpcklpd	xmm3, xmm5              # xmm3 = xmm3[0],xmm5[0]
140001427: 66 44 0f 59 d3              	mulpd	xmm10, xmm3
14000142c: f2 0f 59 fd                 	mulsd	xmm7, xmm5
140001430: f2 41 0f 59 f9              	mulsd	xmm7, xmm9
140001435: 66 45 0f 28 c1              	movapd	xmm8, xmm9
14000143a: 66 45 0f 14 c1              	unpcklpd	xmm8, xmm9              # xmm8 = xmm8[0],xmm9[0]
14000143f: 66 45 0f 59 d0              	mulpd	xmm10, xmm8
140001444: 66 44 0f 10 89 88 00 00 00  	movupd	xmm9, xmmword ptr [rcx + 0x88]
14000144d: 66 45 0f 58 ca              	addpd	xmm9, xmm10
140001452: 66 44 0f 11 89 88 00 00 00  	movupd	xmmword ptr [rcx + 0x88], xmm9
14000145b: f2 0f 58 b9 98 00 00 00     	addsd	xmm7, qword ptr [rcx + 0x98]
140001463: f2 0f 11 b9 98 00 00 00     	movsd	qword ptr [rcx + 0x98], xmm7
14000146b: f2 0f 5c a1 b8 00 00 00     	subsd	xmm4, qword ptr [rcx + 0xb8]
140001473: 66 44 0f 28 cc              	movapd	xmm9, xmm4
140001478: f2 44 0f 59 cc              	mulsd	xmm9, xmm4
14000147d: f2 0f 10 b9 d8 00 00 00     	movsd	xmm7, qword ptr [rcx + 0xd8]
140001485: 66 44 0f 28 d4              	movapd	xmm10, xmm4
14000148a: f2 44 0f 59 d7              	mulsd	xmm10, xmm7
14000148f: 66 44 0f 10 99 a8 00 00 00  	movupd	xmm11, xmmword ptr [rcx + 0xa8]
140001498: 66 44 0f 10 a1 c0 00 00 00  	movupd	xmm12, xmmword ptr [rcx + 0xc0]
1400014a1: 66 41 0f 5c f3              	subpd	xmm6, xmm11
1400014a6: 66 0f 59 de                 	mulpd	xmm3, xmm6
1400014aa: 66 0f 14 ff                 	unpcklpd	xmm7, xmm7              # xmm7 = xmm7[0,0]
1400014ae: 66 0f 59 fe                 	mulpd	xmm7, xmm6
1400014b2: 66 0f 59 f6                 	mulpd	xmm6, xmm6
1400014b6: 66 44 0f 28 de              	movapd	xmm11, xmm6
1400014bb: 66 44 0f 15 de              	unpckhpd	xmm11, xmm6             # xmm11 = xmm11[1],xmm6[1]
1400014c0: f2 44 0f 58 de              	addsd	xmm11, xmm6
1400014c5: f2 45 0f 58 d9              	addsd	xmm11, xmm9
1400014ca: 0f 57 f6                    	xorps	xmm6, xmm6
1400014cd: f2 41 0f 51 f3              	sqrtsd	xmm6, xmm11
1400014d2: f2 41 0f 59 f3              	mulsd	xmm6, xmm11
1400014d7: 66 44 0f 28 c9              	movapd	xmm9, xmm1
1400014dc: f2 44 0f 5e ce              	divsd	xmm9, xmm6
1400014e1: f2 45 0f 59 d1              	mulsd	xmm10, xmm9
1400014e6: f2 41 0f 5c c2              	subsd	xmm0, xmm10
1400014eb: f2 0f 59 e5                 	mulsd	xmm4, xmm5
1400014ef: f2 41 0f 59 e1              	mulsd	xmm4, xmm9
1400014f4: 66 45 0f 28 d1              	movapd	xmm10, xmm9
1400014f9: 66 45 0f 14 d1              	unpcklpd	xmm10, xmm9             # xmm10 = xmm10[0],xmm9[0]
1400014fe: 66 41 0f 59 da              	mulpd	xmm3, xmm10
140001503: 66 41 0f 58 dc              	addpd	xmm3, xmm12
140001508: 66 0f 11 99 c0 00 00 00     	movupd	xmmword ptr [rcx + 0xc0], xmm3
140001510: f2 0f 58 a1 d0 00 00 00     	addsd	xmm4, qword ptr [rcx + 0xd0]
140001518: f2 0f 11 a1 d0 00 00 00     	movsd	qword ptr [rcx + 0xd0], xmm4
140001520: f2 0f 10 61 48              	movsd	xmm4, qword ptr [rcx + 0x48]
140001525: f2 0f 5c a1 f0 00 00 00     	subsd	xmm4, qword ptr [rcx + 0xf0]
14000152d: 66 44 0f 28 dc              	movapd	xmm11, xmm4
140001532: f2 44 0f 10 89 10 01 00 00  	movsd	xmm9, qword ptr [rcx + 0x110]
14000153b: 66 0f 28 f4                 	movapd	xmm6, xmm4
14000153f: f2 41 0f 59 f1              	mulsd	xmm6, xmm9
140001544: f2 0f 10 69 68              	movsd	xmm5, qword ptr [rcx + 0x68]
140001549: 66 44 0f 10 61 38           	movupd	xmm12, xmmword ptr [rcx + 0x38]
14000154f: 66 44 0f 10 a9 e0 00 00 00  	movupd	xmm13, xmmword ptr [rcx + 0xe0]
140001558: 66 45 0f 5c e5              	subpd	xmm12, xmm13
14000155d: 66 45 0f 14 c9              	unpcklpd	xmm9, xmm9              # xmm9 = xmm9[0,0]
140001562: 66 45 0f 59 cc              	mulpd	xmm9, xmm12
140001567: f2 0f 59 e5                 	mulsd	xmm4, xmm5
14000156b: 66 0f 14 ed                 	unpcklpd	xmm5, xmm5              # xmm5 = xmm5[0,0]
14000156f: 66 41 0f 59 ec              	mulpd	xmm5, xmm12
140001574: 66 45 0f 59 e4              	mulpd	xmm12, xmm12
140001579: 66 45 0f 28 ec              	movapd	xmm13, xmm12
14000157e: 66 45 0f 15 ec              	unpckhpd	xmm13, xmm12            # xmm13 = xmm13[1],xmm12[1]
140001583: f2 45 0f 58 ec              	addsd	xmm13, xmm12
140001588: f2 45 0f 59 db              	mulsd	xmm11, xmm11
14000158d: f2 45 0f 58 eb              	addsd	xmm13, xmm11
140001592: 45 0f 57 db                 	xorps	xmm11, xmm11
140001596: f2 45 0f 51 dd              	sqrtsd	xmm11, xmm13
14000159b: f2 45 0f 59 dd              	mulsd	xmm11, xmm13
1400015a0: 66 44 0f 28 e1              	movapd	xmm12, xmm1
1400015a5: f2 45 0f 5e e3              	divsd	xmm12, xmm11
1400015aa: 66 41 0f 59 d0              	mulpd	xmm2, xmm8
1400015af: 66 44 0f 10 41 50           	movupd	xmm8, xmmword ptr [rcx + 0x50]
1400015b5: 66 44 0f 5c c2              	subpd	xmm8, xmm2
1400015ba: 66 41 0f 59 fa              	mulpd	xmm7, xmm10
1400015bf: 66 44 0f 5c c7              	subpd	xmm8, xmm7
1400015c4: f2 41 0f 59 f4              	mulsd	xmm6, xmm12
1400015c9: f2 41 0f 59 e4              	mulsd	xmm4, xmm12
1400015ce: 66 45 0f 14 e4              	unpcklpd	xmm12, xmm12            # xmm12 = xmm12[0,0]
1400015d3: 66 45 0f 59 cc              	mulpd	xmm9, xmm12
1400015d8: 66 45 0f 5c c1              	subpd	xmm8, xmm9
1400015dd: 66 44 0f 11 41 50           	movupd	xmmword ptr [rcx + 0x50], xmm8
1400015e3: f2 0f 5c c6                 	subsd	xmm0, xmm6
1400015e7: f2 0f 11 41 60              	movsd	qword ptr [rcx + 0x60], xmm0
1400015ec: 66 41 0f 59 ec              	mulpd	xmm5, xmm12
1400015f1: 66 0f 10 81 f8 00 00 00     	movupd	xmm0, xmmword ptr [rcx + 0xf8]
1400015f9: 66 0f 58 c5                 	addpd	xmm0, xmm5
1400015fd: 66 0f 11 81 f8 00 00 00     	movupd	xmmword ptr [rcx + 0xf8], xmm0
140001605: f2 0f 58 a1 08 01 00 00     	addsd	xmm4, qword ptr [rcx + 0x108]
14000160d: f2 0f 11 a1 08 01 00 00     	movsd	qword ptr [rcx + 0x108], xmm4
140001615: f2 0f 10 a1 80 00 00 00     	movsd	xmm4, qword ptr [rcx + 0x80]
14000161d: 66 0f 28 c4                 	movapd	xmm0, xmm4
140001621: f2 0f 5c 81 b8 00 00 00     	subsd	xmm0, qword ptr [rcx + 0xb8]
140001629: 66 44 0f 28 c8              	movapd	xmm9, xmm0
14000162e: f2 44 0f 59 c8              	mulsd	xmm9, xmm0
140001633: f2 0f 10 b9 d8 00 00 00     	movsd	xmm7, qword ptr [rcx + 0xd8]
14000163b: 66 44 0f 28 c0              	movapd	xmm8, xmm0
140001640: f2 44 0f 59 c7              	mulsd	xmm8, xmm7
140001645: f2 0f 10 b1 98 00 00 00     	movsd	xmm6, qword ptr [rcx + 0x98]
14000164d: 66 0f 10 69 70              	movupd	xmm5, xmmword ptr [rcx + 0x70]
140001652: 66 0f 10 91 a8 00 00 00     	movupd	xmm2, xmmword ptr [rcx + 0xa8]
14000165a: 66 44 0f 28 d5              	movapd	xmm10, xmm5
14000165f: 66 44 0f 5c d2              	subpd	xmm10, xmm2
140001664: 66 41 0f 28 d2              	movapd	xmm2, xmm10
140001669: 66 0f 14 ff                 	unpcklpd	xmm7, xmm7              # xmm7 = xmm7[0,0]
14000166d: 66 41 0f 59 fa              	mulpd	xmm7, xmm10
140001672: 66 45 0f 59 d2              	mulpd	xmm10, xmm10
140001677: 66 45 0f 28 da              	movapd	xmm11, xmm10
14000167c: 66 45 0f 15 da              	unpckhpd	xmm11, xmm10            # xmm11 = xmm11[1],xmm10[1]
140001681: f2 45 0f 58 da              	addsd	xmm11, xmm10
140001686: f2 44 0f 10 91 a0 00 00 00  	movsd	xmm10, qword ptr [rcx + 0xa0]
14000168f: f2 45 0f 58 d9              	addsd	xmm11, xmm9
140001694: 45 0f 57 c9                 	xorps	xmm9, xmm9
140001698: f2 45 0f 51 cb              	sqrtsd	xmm9, xmm11
14000169d: f2 45 0f 59 cb              	mulsd	xmm9, xmm11
1400016a2: 66 44 0f 28 d9              	movapd	xmm11, xmm1
1400016a7: f2 45 0f 5e d9              	divsd	xmm11, xmm9
1400016ac: f2 45 0f 59 c3              	mulsd	xmm8, xmm11
1400016b1: 66 45 0f 28 ca              	movapd	xmm9, xmm10
1400016b6: 66 45 0f 14 ca              	unpcklpd	xmm9, xmm10             # xmm9 = xmm9[0],xmm10[0]
1400016bb: 66 41 0f 59 d1              	mulpd	xmm2, xmm9
1400016c0: f2 41 0f 59 c2              	mulsd	xmm0, xmm10
1400016c5: f2 41 0f 59 c3              	mulsd	xmm0, xmm11
1400016ca: 66 45 0f 14 db              	unpcklpd	xmm11, xmm11            # xmm11 = xmm11[0,0]
1400016cf: 66 41 0f 59 d3              	mulpd	xmm2, xmm11
1400016d4: 66 0f 58 d3                 	addpd	xmm2, xmm3
1400016d8: 66 0f 11 91 c0 00 00 00     	movupd	xmmword ptr [rcx + 0xc0], xmm2
1400016e0: f2 0f 58 81 d0 00 00 00     	addsd	xmm0, qword ptr [rcx + 0xd0]
1400016e8: f2 41 0f 5c f0              	subsd	xmm6, xmm8
1400016ed: f2 0f 11 81 d0 00 00 00     	movsd	qword ptr [rcx + 0xd0], xmm0
1400016f5: f2 0f 5c a1 f0 00 00 00     	subsd	xmm4, qword ptr [rcx + 0xf0]
1400016fd: 66 0f 10 99 e0 00 00 00     	movupd	xmm3, xmmword ptr [rcx + 0xe0]
140001705: 66 0f 5c eb                 	subpd	xmm5, xmm3
140001709: 66 0f 28 dd                 	movapd	xmm3, xmm5
14000170d: 66 0f 59 dd                 	mulpd	xmm3, xmm5
140001711: 66 44 0f 28 c3              	movapd	xmm8, xmm3
140001716: 66 44 0f 15 c3              	unpckhpd	xmm8, xmm3              # xmm8 = xmm8[1],xmm3[1]
14000171b: f2 44 0f 58 c3              	addsd	xmm8, xmm3
140001720: 66 0f 28 dc                 	movapd	xmm3, xmm4
140001724: f2 0f 59 dc                 	mulsd	xmm3, xmm4
140001728: f2 44 0f 58 c3              	addsd	xmm8, xmm3
14000172d: 45 0f 57 e4                 	xorps	xmm12, xmm12
140001731: f2 45 0f 51 e0              	sqrtsd	xmm12, xmm8
140001736: f2 45 0f 59 e0              	mulsd	xmm12, xmm8
14000173b: 66 0f 28 d9                 	movapd	xmm3, xmm1
14000173f: f2 41 0f 5e dc              	divsd	xmm3, xmm12
140001744: 66 41 0f 59 fb              	mulpd	xmm7, xmm11
140001749: 66 44 0f 10 81 88 00 00 00  	movupd	xmm8, xmmword ptr [rcx + 0x88]
140001752: 66 44 0f 5c c7              	subpd	xmm8, xmm7
140001757: 66 0f 28 fc                 	movapd	xmm7, xmm4
14000175b: f2 41 0f 59 e2              	mulsd	xmm4, xmm10
140001760: f2 44 0f 10 91 10 01 00 00  	movsd	xmm10, qword ptr [rcx + 0x110]
140001769: f2 41 0f 59 fa              	mulsd	xmm7, xmm10
14000176e: 66 45 0f 14 d2              	unpcklpd	xmm10, xmm10            # xmm10 = xmm10[0,0]
140001773: 66 44 0f 59 d5              	mulpd	xmm10, xmm5
140001778: f2 0f 59 fb                 	mulsd	xmm7, xmm3
14000177c: f2 0f 59 e3                 	mulsd	xmm4, xmm3
140001780: 66 0f 14 db                 	unpcklpd	xmm3, xmm3              # xmm3 = xmm3[0,0]
140001784: 66 44 0f 59 d3              	mulpd	xmm10, xmm3
140001789: 66 45 0f 5c c2              	subpd	xmm8, xmm10
14000178e: 66 44 0f 11 81 88 00 00 00  	movupd	xmmword ptr [rcx + 0x88], xmm8
140001797: f2 0f 5c f7                 	subsd	xmm6, xmm7
14000179b: f2 0f 11 b1 98 00 00 00     	movsd	qword ptr [rcx + 0x98], xmm6
1400017a3: 66 41 0f 59 e9              	mulpd	xmm5, xmm9
1400017a8: 66 0f 59 eb                 	mulpd	xmm5, xmm3
1400017ac: 66 0f 10 99 f8 00 00 00     	movupd	xmm3, xmmword ptr [rcx + 0xf8]
1400017b4: 66 0f 58 dd                 	addpd	xmm3, xmm5
1400017b8: 66 0f 11 99 f8 00 00 00     	movupd	xmmword ptr [rcx + 0xf8], xmm3
1400017c0: f2 0f 58 a1 08 01 00 00     	addsd	xmm4, qword ptr [rcx + 0x108]
1400017c8: f2 0f 11 a1 08 01 00 00     	movsd	qword ptr [rcx + 0x108], xmm4
1400017d0: f2 0f 10 b1 a8 00 00 00     	movsd	xmm6, qword ptr [rcx + 0xa8]
1400017d8: f2 0f 5c b1 e0 00 00 00     	subsd	xmm6, qword ptr [rcx + 0xe0]
1400017e0: 66 0f 28 de                 	movapd	xmm3, xmm6
1400017e4: f2 0f 59 de                 	mulsd	xmm3, xmm6
1400017e8: f2 0f 10 b9 10 01 00 00     	movsd	xmm7, qword ptr [rcx + 0x110]
1400017f0: f2 0f 10 a9 d8 00 00 00     	movsd	xmm5, qword ptr [rcx + 0xd8]
1400017f8: 66 44 0f 10 81 b0 00 00 00  	movupd	xmm8, xmmword ptr [rcx + 0xb0]
140001801: 66 0f 10 a1 e8 00 00 00     	movupd	xmm4, xmmword ptr [rcx + 0xe8]
140001809: 66 44 0f 5c c4              	subpd	xmm8, xmm4
14000180e: 66 41 0f 28 e0              	movapd	xmm4, xmm8
140001813: 66 41 0f 59 e0              	mulpd	xmm4, xmm8
140001818: f2 0f 58 dc                 	addsd	xmm3, xmm4
14000181c: 66 0f 15 e4                 	unpckhpd	xmm4, xmm4              # xmm4 = xmm4[1,1]
140001820: f2 0f 58 e3                 	addsd	xmm4, xmm3
140001824: 0f 57 db                    	xorps	xmm3, xmm3
140001827: f2 0f 51 dc                 	sqrtsd	xmm3, xmm4
14000182b: f2 0f 59 dc                 	mulsd	xmm3, xmm4
14000182f: 66 0f 28 e1                 	movapd	xmm4, xmm1
140001833: f2 0f 5e e3                 	divsd	xmm4, xmm3
140001837: 66 0f 28 de                 	movapd	xmm3, xmm6
14000183b: f2 0f 59 dd                 	mulsd	xmm3, xmm5
14000183f: 66 41 0f 14 f0              	unpcklpd	xmm6, xmm8              # xmm6 = xmm6[0],xmm8[0]
140001844: 66 0f 14 ed                 	unpcklpd	xmm5, xmm5              # xmm5 = xmm5[0,0]
140001848: 66 41 0f 59 e8              	mulpd	xmm5, xmm8
14000184d: 66 45 0f 15 c0              	unpckhpd	xmm8, xmm8              # xmm8 = xmm8[1,1]
140001852: f2 44 0f 59 c7              	mulsd	xmm8, xmm7
140001857: 66 0f 14 ff                 	unpcklpd	xmm7, xmm7              # xmm7 = xmm7[0,0]
14000185b: 66 0f 59 fe                 	mulpd	xmm7, xmm6
14000185f: 66 0f 28 f4                 	movapd	xmm6, xmm4
140001863: 66 0f 14 f4                 	unpcklpd	xmm6, xmm4              # xmm6 = xmm6[0],xmm4[0]
140001867: 66 0f 59 fe                 	mulpd	xmm7, xmm6
14000186b: 66 0f 5c d7                 	subpd	xmm2, xmm7
14000186f: 66 0f 11 91 c0 00 00 00     	movupd	xmmword ptr [rcx + 0xc0], xmm2
140001877: f2 44 0f 59 c4              	mulsd	xmm8, xmm4
14000187c: f2 41 0f 5c c0              	subsd	xmm0, xmm8
140001881: f2 0f 11 81 d0 00 00 00     	movsd	qword ptr [rcx + 0xd0], xmm0
140001889: 66 0f 59 ee                 	mulpd	xmm5, xmm6
14000188d: 66 0f 10 81 00 01 00 00     	movupd	xmm0, xmmword ptr [rcx + 0x100]
140001895: 66 0f 58 c5                 	addpd	xmm0, xmm5
140001899: 66 0f 11 81 00 01 00 00     	movupd	xmmword ptr [rcx + 0x100], xmm0
1400018a1: 66 0f 10 11                 	movupd	xmm2, xmmword ptr [rcx]
1400018a5: 66 0f 10 69 18              	movupd	xmm5, xmmword ptr [rcx + 0x18]
1400018aa: 66 0f 28 c1                 	movapd	xmm0, xmm1
1400018ae: 66 0f 14 c1                 	unpcklpd	xmm0, xmm1              # xmm0 = xmm0[0],xmm1[0]
1400018b2: 66 0f 59 e8                 	mulpd	xmm5, xmm0
1400018b6: 66 0f 58 ea                 	addpd	xmm5, xmm2
1400018ba: 66 0f 11 29                 	movupd	xmmword ptr [rcx], xmm5
1400018be: f2 0f 10 51 28              	movsd	xmm2, qword ptr [rcx + 0x28]
1400018c3: f2 0f 59 d1                 	mulsd	xmm2, xmm1
1400018c7: f2 0f 58 51 10              	addsd	xmm2, qword ptr [rcx + 0x10]
1400018cc: f2 0f 11 51 10              	movsd	qword ptr [rcx + 0x10], xmm2
1400018d1: 66 0f 10 51 38              	movupd	xmm2, xmmword ptr [rcx + 0x38]
1400018d6: 66 0f 10 69 50              	movupd	xmm5, xmmword ptr [rcx + 0x50]
1400018db: 66 0f 59 e8                 	mulpd	xmm5, xmm0
1400018df: 66 0f 58 ea                 	addpd	xmm5, xmm2
1400018e3: 66 0f 11 69 38              	movupd	xmmword ptr [rcx + 0x38], xmm5
1400018e8: f2 0f 10 51 60              	movsd	xmm2, qword ptr [rcx + 0x60]
1400018ed: f2 0f 59 d1                 	mulsd	xmm2, xmm1
1400018f1: f2 0f 58 51 48              	addsd	xmm2, qword ptr [rcx + 0x48]
1400018f6: f2 0f 11 51 48              	movsd	qword ptr [rcx + 0x48], xmm2
1400018fb: 66 0f 10 51 70              	movupd	xmm2, xmmword ptr [rcx + 0x70]
140001900: 66 0f 10 a9 88 00 00 00     	movupd	xmm5, xmmword ptr [rcx + 0x88]
140001908: 66 0f 59 e8                 	mulpd	xmm5, xmm0
14000190c: 66 0f 58 ea                 	addpd	xmm5, xmm2
140001910: 66 0f 11 69 70              	movupd	xmmword ptr [rcx + 0x70], xmm5
140001915: f2 0f 10 91 98 00 00 00     	movsd	xmm2, qword ptr [rcx + 0x98]
14000191d: f2 0f 59 d1                 	mulsd	xmm2, xmm1
140001921: f2 0f 58 91 80 00 00 00     	addsd	xmm2, qword ptr [rcx + 0x80]
140001929: f2 0f 11 91 80 00 00 00     	movsd	qword ptr [rcx + 0x80], xmm2
140001931: 66 0f 10 91 a8 00 00 00     	movupd	xmm2, xmmword ptr [rcx + 0xa8]
140001939: 66 0f 10 a9 c0 00 00 00     	movupd	xmm5, xmmword ptr [rcx + 0xc0]
140001941: 66 0f 59 e8                 	mulpd	xmm5, xmm0
140001945: 66 0f 58 ea                 	addpd	xmm5, xmm2
140001949: 66 0f 11 a9 a8 00 00 00     	movupd	xmmword ptr [rcx + 0xa8], xmm5
140001951: f2 0f 10 91 d0 00 00 00     	movsd	xmm2, qword ptr [rcx + 0xd0]
140001959: f2 0f 59 d1                 	mulsd	xmm2, xmm1
14000195d: f2 0f 58 91 b8 00 00 00     	addsd	xmm2, qword ptr [rcx + 0xb8]
140001965: f2 0f 11 91 b8 00 00 00     	movsd	qword ptr [rcx + 0xb8], xmm2
14000196d: 66 0f 14 cc                 	unpcklpd	xmm1, xmm4              # xmm1 = xmm1[0],xmm4[0]
140001971: f2 0f 10 91 08 01 00 00     	movsd	xmm2, qword ptr [rcx + 0x108]
140001979: 66 0f 14 d3                 	unpcklpd	xmm2, xmm3              # xmm2 = xmm2[0],xmm3[0]
14000197d: 66 0f 59 d1                 	mulpd	xmm2, xmm1
140001981: 66 0f 10 89 f0 00 00 00     	movupd	xmm1, xmmword ptr [rcx + 0xf0]
140001989: 66 0f 58 ca                 	addpd	xmm1, xmm2
14000198d: 66 0f 10 91 e0 00 00 00     	movupd	xmm2, xmmword ptr [rcx + 0xe0]
140001995: 66 0f 11 89 f0 00 00 00     	movupd	xmmword ptr [rcx + 0xf0], xmm1
14000199d: 66 0f 10 89 f8 00 00 00     	movupd	xmm1, xmmword ptr [rcx + 0xf8]
1400019a5: 66 0f 59 c8                 	mulpd	xmm1, xmm0
1400019a9: 66 0f 58 ca                 	addpd	xmm1, xmm2
1400019ad: 66 0f 11 89 e0 00 00 00     	movupd	xmmword ptr [rcx + 0xe0], xmm1
1400019b5: 0f 28 34 24                 	movaps	xmm6, xmmword ptr [rsp]
1400019b9: 0f 28 7c 24 10              	movaps	xmm7, xmmword ptr [rsp + 0x10]
1400019be: 44 0f 28 44 24 20           	movaps	xmm8, xmmword ptr [rsp + 0x20]
1400019c4: 44 0f 28 4c 24 30           	movaps	xmm9, xmmword ptr [rsp + 0x30]
1400019ca: 44 0f 28 54 24 40           	movaps	xmm10, xmmword ptr [rsp + 0x40]
1400019d0: 44 0f 28 5c 24 50           	movaps	xmm11, xmmword ptr [rsp + 0x50]
1400019d6: 44 0f 28 64 24 60           	movaps	xmm12, xmmword ptr [rsp + 0x60]
1400019dc: 44 0f 28 6c 24 70           	movaps	xmm13, xmmword ptr [rsp + 0x70]
1400019e2: 44 0f 28 b4 24 80 00 00 00  	movaps	xmm14, xmmword ptr [rsp + 0x80]
1400019eb: 44 0f 28 bc 24 90 00 00 00  	movaps	xmm15, xmmword ptr [rsp + 0x90]
1400019f4: 48 81 c4 a8 00 00 00        	add	rsp, 0xa8
1400019fb: c3                          	ret
