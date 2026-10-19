140001220: f2 44 0f 11 9c 24 c0 00 00 00       	movsd	qword ptr [rsp + 0xc0], xmm11
14000122a: f2 44 0f 11 a4 24 e0 00 00 00       	movsd	qword ptr [rsp + 0xe0], xmm12
140001234: f2 0f 11 94 24 d0 00 00 00  	movsd	qword ptr [rsp + 0xd0], xmm2
14000123d: 66 45 0f 28 d0              	movapd	xmm10, xmm8
140001242: f2 44 0f 11 84 24 b8 00 00 00       	movsd	qword ptr [rsp + 0xb8], xmm8
14000124c: f2 44 0f 5c d2              	subsd	xmm10, xmm2
140001251: 66 44 0f 28 eb              	movapd	xmm13, xmm3
140001256: f2 45 0f 5c ec              	subsd	xmm13, xmm12
14000125b: 66 41 0f 28 c5              	movapd	xmm0, xmm13
140001260: f2 41 0f 59 c5              	mulsd	xmm0, xmm13
140001265: 66 41 0f 28 ca              	movapd	xmm1, xmm10
14000126a: f2 41 0f 59 ca              	mulsd	xmm1, xmm10
14000126f: f2 0f 58 c8                 	addsd	xmm1, xmm0
140001273: f2 44 0f 11 bc 24 d8 00 00 00       	movsd	qword ptr [rsp + 0xd8], xmm15
14000127d: f2 0f 10 84 24 98 00 00 00  	movsd	xmm0, qword ptr [rsp + 0x98]
140001286: f2 44 0f 5c f8              	subsd	xmm15, xmm0
14000128b: 66 41 0f 28 c7              	movapd	xmm0, xmm15
140001290: f2 41 0f 59 c7              	mulsd	xmm0, xmm15
140001295: f2 0f 58 c1                 	addsd	xmm0, xmm1
140001299: 0f 57 d2                    	xorps	xmm2, xmm2
14000129c: f2 0f 51 d0                 	sqrtsd	xmm2, xmm0
1400012a0: f2 0f 59 d0                 	mulsd	xmm2, xmm0
1400012a4: f2 0f 10 0d 3c 61 01 00     	movsd	xmm1, qword ptr [rip + 0x1613c] # 0x1400173e8
1400012ac: f2 0f 5e ca                 	divsd	xmm1, xmm2
1400012b0: 66 41 0f 28 c2              	movapd	xmm0, xmm10
1400012b5: f2 0f 10 15 33 61 01 00     	movsd	xmm2, qword ptr [rip + 0x16133] # 0x1400173f0
1400012bd: f2 0f 59 c2                 	mulsd	xmm0, xmm2
1400012c1: f2 0f 59 c1                 	mulsd	xmm0, xmm1
1400012c5: f2 0f 58 84 24 a8 00 00 00  	addsd	xmm0, qword ptr [rsp + 0xa8]
1400012ce: 66 45 0f 28 e5              	movapd	xmm12, xmm13
1400012d3: f2 44 0f 59 e2              	mulsd	xmm12, xmm2
1400012d8: f2 44 0f 59 e1              	mulsd	xmm12, xmm1
1400012dd: f2 44 0f 58 a4 24 b0 00 00 00       	addsd	xmm12, qword ptr [rsp + 0xb0]
1400012e7: 66 41 0f 28 f7              	movapd	xmm6, xmm15
1400012ec: f2 0f 59 f2                 	mulsd	xmm6, xmm2
1400012f0: f2 0f 59 f1                 	mulsd	xmm6, xmm1
1400012f4: f2 0f 58 b4 24 a0 00 00 00  	addsd	xmm6, qword ptr [rsp + 0xa0]
1400012fd: f2 0f 10 15 f3 60 01 00     	movsd	xmm2, qword ptr [rip + 0x160f3] # 0x1400173f8
140001305: f2 44 0f 59 d2              	mulsd	xmm10, xmm2
14000130a: f2 44 0f 59 d1              	mulsd	xmm10, xmm1
14000130f: f2 44 0f 58 94 24 90 00 00 00       	addsd	xmm10, qword ptr [rsp + 0x90]
140001319: f2 44 0f 11 94 24 c8 00 00 00       	movsd	qword ptr [rsp + 0xc8], xmm10
140001323: f2 44 0f 59 ea              	mulsd	xmm13, xmm2
140001328: f2 44 0f 59 e9              	mulsd	xmm13, xmm1
14000132d: f2 44 0f 58 ac 24 88 00 00 00       	addsd	xmm13, qword ptr [rsp + 0x88]
140001337: f2 44 0f 11 ac 24 90 00 00 00       	movsd	qword ptr [rsp + 0x90], xmm13
140001341: f2 44 0f 59 fa              	mulsd	xmm15, xmm2
140001346: f2 44 0f 59 f9              	mulsd	xmm15, xmm1
14000134b: f2 44 0f 58 7c 24 30        	addsd	xmm15, qword ptr [rsp + 0x30]
140001352: f2 44 0f 11 7c 24 30        	movsd	qword ptr [rsp + 0x30], xmm15
140001359: f2 0f 10 8c 24 80 00 00 00  	movsd	xmm1, qword ptr [rsp + 0x80]
140001362: f2 0f 10 54 24 78           	movsd	xmm2, qword ptr [rsp + 0x78]
140001368: f2 44 0f 10 9c 24 b8 00 00 00       	movsd	xmm11, qword ptr [rsp + 0xb8]
140001372: f2 44 0f 5c da              	subsd	xmm11, xmm2
140001377: 66 44 0f 28 fb              	movapd	xmm15, xmm3
14000137c: f2 0f 11 9c 24 e8 00 00 00  	movsd	qword ptr [rsp + 0xe8], xmm3
140001385: 66 44 0f 28 c3              	movapd	xmm8, xmm3
14000138a: f2 44 0f 5c c1              	subsd	xmm8, xmm1
14000138f: 66 41 0f 28 c8              	movapd	xmm1, xmm8
140001394: f2 41 0f 59 c8              	mulsd	xmm1, xmm8
140001399: 66 41 0f 28 db              	movapd	xmm3, xmm11
14000139e: f2 41 0f 59 db              	mulsd	xmm3, xmm11
1400013a3: f2 0f 58 d9                 	addsd	xmm3, xmm1
1400013a7: f2 0f 10 4c 24 70           	movsd	xmm1, qword ptr [rsp + 0x70]
1400013ad: f2 0f 10 94 24 d8 00 00 00  	movsd	xmm2, qword ptr [rsp + 0xd8]
1400013b6: f2 0f 5c d1                 	subsd	xmm2, xmm1
1400013ba: 66 0f 28 ca                 	movapd	xmm1, xmm2
1400013be: f2 0f 59 ca                 	mulsd	xmm1, xmm2
1400013c2: f2 0f 58 cb                 	addsd	xmm1, xmm3
1400013c6: 0f 57 db                    	xorps	xmm3, xmm3
1400013c9: f2 0f 51 d9                 	sqrtsd	xmm3, xmm1
1400013cd: f2 0f 59 d9                 	mulsd	xmm3, xmm1
1400013d1: f2 44 0f 10 2d 0e 60 01 00  	movsd	xmm13, qword ptr [rip + 0x1600e] # 0x1400173e8
1400013da: f2 44 0f 5e eb              	divsd	xmm13, xmm3
1400013df: 66 41 0f 28 db              	movapd	xmm3, xmm11
1400013e4: f2 44 0f 10 15 13 60 01 00  	movsd	xmm10, qword ptr [rip + 0x16013] # 0x140017400
1400013ed: f2 41 0f 59 da              	mulsd	xmm3, xmm10
1400013f2: f2 41 0f 59 dd              	mulsd	xmm3, xmm13
1400013f7: f2 0f 58 d8                 	addsd	xmm3, xmm0
1400013fb: 66 41 0f 28 c8              	movapd	xmm1, xmm8
140001400: f2 41 0f 59 ca              	mulsd	xmm1, xmm10
140001405: f2 41 0f 59 cd              	mulsd	xmm1, xmm13
14000140a: f2 41 0f 58 cc              	addsd	xmm1, xmm12
14000140f: f2 0f 10 05 e1 5f 01 00     	movsd	xmm0, qword ptr [rip + 0x15fe1] # 0x1400173f8
140001417: f2 44 0f 59 d8              	mulsd	xmm11, xmm0
14000141c: f2 45 0f 59 dd              	mulsd	xmm11, xmm13
140001421: f2 45 0f 58 de              	addsd	xmm11, xmm14
140001426: f2 44 0f 11 9c 24 f0 00 00 00       	movsd	qword ptr [rsp + 0xf0], xmm11
140001430: f2 44 0f 59 c0              	mulsd	xmm8, xmm0
140001435: f2 45 0f 59 c5              	mulsd	xmm8, xmm13
14000143a: f2 45 0f 58 c1              	addsd	xmm8, xmm9
14000143f: f2 44 0f 11 84 24 00 01 00 00       	movsd	qword ptr [rsp + 0x100], xmm8
140001449: 66 44 0f 28 ca              	movapd	xmm9, xmm2
14000144e: f2 45 0f 59 ca              	mulsd	xmm9, xmm10
140001453: f2 45 0f 59 cd              	mulsd	xmm9, xmm13
140001458: f2 0f 59 d0                 	mulsd	xmm2, xmm0
14000145c: 66 44 0f 28 d0              	movapd	xmm10, xmm0
140001461: f2 41 0f 59 d5              	mulsd	xmm2, xmm13
140001466: f2 0f 58 54 24 38           	addsd	xmm2, qword ptr [rsp + 0x38]
14000146c: f2 44 0f 58 ce              	addsd	xmm9, xmm6
140001471: f2 44 0f 10 44 24 68        	movsd	xmm8, qword ptr [rsp + 0x68]
140001478: f2 44 0f 10 64 24 60        	movsd	xmm12, qword ptr [rsp + 0x60]
14000147f: f2 0f 10 84 24 b8 00 00 00  	movsd	xmm0, qword ptr [rsp + 0xb8]
140001488: 66 44 0f 28 e8              	movapd	xmm13, xmm0
14000148d: f2 45 0f 5c ec              	subsd	xmm13, xmm12
140001492: 66 41 0f 28 f7              	movapd	xmm6, xmm15
140001497: f2 41 0f 5c f0              	subsd	xmm6, xmm8
14000149c: 66 44 0f 28 c6              	movapd	xmm8, xmm6
1400014a1: f2 44 0f 59 c6              	mulsd	xmm8, xmm6
1400014a6: 66 45 0f 28 e5              	movapd	xmm12, xmm13
1400014ab: f2 45 0f 59 e5              	mulsd	xmm12, xmm13
1400014b0: f2 45 0f 58 e0              	addsd	xmm12, xmm8
1400014b5: f2 44 0f 10 44 24 58        	movsd	xmm8, qword ptr [rsp + 0x58]
1400014bc: f2 44 0f 10 b4 24 d8 00 00 00       	movsd	xmm14, qword ptr [rsp + 0xd8]
1400014c6: 66 45 0f 28 fe              	movapd	xmm15, xmm14
1400014cb: f2 45 0f 5c f8              	subsd	xmm15, xmm8
1400014d0: 66 45 0f 28 c7              	movapd	xmm8, xmm15
1400014d5: f2 45 0f 59 c7              	mulsd	xmm8, xmm15
1400014da: f2 45 0f 58 c4              	addsd	xmm8, xmm12
1400014df: 45 0f 57 e4                 	xorps	xmm12, xmm12
1400014e3: f2 45 0f 51 e0              	sqrtsd	xmm12, xmm8
1400014e8: f2 45 0f 59 e0              	mulsd	xmm12, xmm8
1400014ed: f2 44 0f 10 1d f2 5e 01 00  	movsd	xmm11, qword ptr [rip + 0x15ef2] # 0x1400173e8
1400014f6: 66 45 0f 28 c3              	movapd	xmm8, xmm11
1400014fb: f2 45 0f 5e c4              	divsd	xmm8, xmm12
140001500: 66 45 0f 28 e5              	movapd	xmm12, xmm13
140001505: f2 45 0f 59 ea              	mulsd	xmm13, xmm10
14000150a: f2 45 0f 59 e8              	mulsd	xmm13, xmm8
14000150f: f2 44 0f 58 ed              	addsd	xmm13, xmm5
140001514: f2 0f 10 2d ec 5e 01 00     	movsd	xmm5, qword ptr [rip + 0x15eec] # 0x140017408
14000151c: f2 44 0f 59 e5              	mulsd	xmm12, xmm5
140001521: f2 45 0f 59 e0              	mulsd	xmm12, xmm8
140001526: f2 44 0f 58 e3              	addsd	xmm12, xmm3
14000152b: 66 0f 28 de                 	movapd	xmm3, xmm6
14000152f: f2 0f 59 dd                 	mulsd	xmm3, xmm5
140001533: f2 41 0f 59 d8              	mulsd	xmm3, xmm8
140001538: f2 0f 58 d9                 	addsd	xmm3, xmm1
14000153c: f2 0f 11 9c 24 f8 00 00 00  	movsd	qword ptr [rsp + 0xf8], xmm3
140001545: 66 41 0f 28 cf              	movapd	xmm1, xmm15
14000154a: f2 0f 59 cd                 	mulsd	xmm1, xmm5
14000154e: f2 41 0f 59 c8              	mulsd	xmm1, xmm8
140001553: f2 41 0f 58 c9              	addsd	xmm1, xmm9
140001558: f2 0f 11 8c 24 88 00 00 00  	movsd	qword ptr [rsp + 0x88], xmm1
140001561: f2 41 0f 59 f2              	mulsd	xmm6, xmm10
140001566: f2 41 0f 59 f0              	mulsd	xmm6, xmm8
14000156b: f2 0f 58 b4 24 c0 00 00 00  	addsd	xmm6, qword ptr [rsp + 0xc0]
140001574: f2 0f 11 b4 24 c0 00 00 00  	movsd	qword ptr [rsp + 0xc0], xmm6
14000157d: f2 45 0f 59 fa              	mulsd	xmm15, xmm10
140001582: f2 45 0f 59 f8              	mulsd	xmm15, xmm8
140001587: f2 44 0f 58 7c 24 40        	addsd	xmm15, qword ptr [rsp + 0x40]
14000158e: f2 0f 10 4c 24 28           	movsd	xmm1, qword ptr [rsp + 0x28]
140001594: f2 0f 10 5c 24 20           	movsd	xmm3, qword ptr [rsp + 0x20]
14000159a: f2 0f 5c c3                 	subsd	xmm0, xmm3
14000159e: f2 0f 10 ac 24 e8 00 00 00  	movsd	xmm5, qword ptr [rsp + 0xe8]
1400015a7: f2 0f 5c e9                 	subsd	xmm5, xmm1
1400015ab: 66 0f 28 cd                 	movapd	xmm1, xmm5
1400015af: f2 0f 59 cd                 	mulsd	xmm1, xmm5
1400015b3: 66 0f 28 d8                 	movapd	xmm3, xmm0
1400015b7: f2 0f 59 d8                 	mulsd	xmm3, xmm0
1400015bb: f2 0f 58 d9                 	addsd	xmm3, xmm1
1400015bf: f2 0f 10 74 24 50           	movsd	xmm6, qword ptr [rsp + 0x50]
1400015c5: f2 44 0f 5c f6              	subsd	xmm14, xmm6
1400015ca: 66 41 0f 28 ce              	movapd	xmm1, xmm14
1400015cf: f2 41 0f 59 ce              	mulsd	xmm1, xmm14
1400015d4: f2 0f 58 cb                 	addsd	xmm1, xmm3
1400015d8: 0f 57 db                    	xorps	xmm3, xmm3
1400015db: f2 0f 51 d9                 	sqrtsd	xmm3, xmm1
1400015df: f2 0f 59 d9                 	mulsd	xmm3, xmm1
1400015e3: 66 45 0f 28 cb              	movapd	xmm9, xmm11
1400015e8: 66 41 0f 28 cb              	movapd	xmm1, xmm11
1400015ed: f2 0f 5e cb                 	divsd	xmm1, xmm3
1400015f1: 66 0f 28 d8                 	movapd	xmm3, xmm0
1400015f5: f2 41 0f 59 da              	mulsd	xmm3, xmm10
1400015fa: f2 0f 59 d9                 	mulsd	xmm3, xmm1
1400015fe: f2 0f 58 df                 	addsd	xmm3, xmm7
140001602: f2 0f 11 5c 24 38           	movsd	qword ptr [rsp + 0x38], xmm3
140001608: f2 0f 10 1d 00 5e 01 00     	movsd	xmm3, qword ptr [rip + 0x15e00] # 0x140017410
140001610: f2 0f 59 c3                 	mulsd	xmm0, xmm3
140001614: f2 0f 59 c1                 	mulsd	xmm0, xmm1
140001618: f2 0f 11 84 24 a8 00 00 00  	movsd	qword ptr [rsp + 0xa8], xmm0
140001621: 66 0f 28 c5                 	movapd	xmm0, xmm5
140001625: f2 0f 59 c3                 	mulsd	xmm0, xmm3
140001629: f2 0f 59 c1                 	mulsd	xmm0, xmm1
14000162d: f2 0f 11 84 24 b0 00 00 00  	movsd	qword ptr [rsp + 0xb0], xmm0
140001636: 66 41 0f 28 c6              	movapd	xmm0, xmm14
14000163b: f2 0f 59 c3                 	mulsd	xmm0, xmm3
14000163f: f2 41 0f 59 ea              	mulsd	xmm5, xmm10
140001644: f2 0f 59 c1                 	mulsd	xmm0, xmm1
140001648: f2 0f 11 84 24 a0 00 00 00  	movsd	qword ptr [rsp + 0xa0], xmm0
140001651: f2 0f 59 e9                 	mulsd	xmm5, xmm1
140001655: f2 45 0f 59 f2              	mulsd	xmm14, xmm10
14000165a: f2 44 0f 59 f1              	mulsd	xmm14, xmm1
14000165f: f2 0f 58 ec                 	addsd	xmm5, xmm4
140001663: f2 0f 11 6c 24 40           	movsd	qword ptr [rsp + 0x40], xmm5
140001669: f2 44 0f 58 74 24 48        	addsd	xmm14, qword ptr [rsp + 0x48]
140001670: f2 44 0f 11 74 24 48        	movsd	qword ptr [rsp + 0x48], xmm14
140001677: f2 44 0f 10 9c 24 d0 00 00 00       	movsd	xmm11, qword ptr [rsp + 0xd0]
140001681: 66 41 0f 28 f3              	movapd	xmm6, xmm11
140001686: f2 0f 5c 74 24 78           	subsd	xmm6, qword ptr [rsp + 0x78]
14000168c: f2 44 0f 10 84 24 e0 00 00 00       	movsd	xmm8, qword ptr [rsp + 0xe0]
140001696: 66 41 0f 28 e8              	movapd	xmm5, xmm8
14000169b: f2 0f 5c ac 24 80 00 00 00  	subsd	xmm5, qword ptr [rsp + 0x80]
1400016a4: 66 0f 28 cd                 	movapd	xmm1, xmm5
1400016a8: f2 0f 59 cd                 	mulsd	xmm1, xmm5
1400016ac: 66 0f 28 de                 	movapd	xmm3, xmm6
1400016b0: f2 0f 59 de                 	mulsd	xmm3, xmm6
1400016b4: f2 0f 58 d9                 	addsd	xmm3, xmm1
1400016b8: f2 0f 10 84 24 98 00 00 00  	movsd	xmm0, qword ptr [rsp + 0x98]
1400016c1: 66 44 0f 28 f0              	movapd	xmm14, xmm0
1400016c6: f2 44 0f 5c 74 24 70        	subsd	xmm14, qword ptr [rsp + 0x70]
1400016cd: 66 41 0f 28 ce              	movapd	xmm1, xmm14
1400016d2: f2 41 0f 59 ce              	mulsd	xmm1, xmm14
1400016d7: f2 0f 58 cb                 	addsd	xmm1, xmm3
1400016db: 0f 57 db                    	xorps	xmm3, xmm3
1400016de: f2 0f 51 d9                 	sqrtsd	xmm3, xmm1
1400016e2: f2 0f 59 d9                 	mulsd	xmm3, xmm1
1400016e6: 66 41 0f 28 c9              	movapd	xmm1, xmm9
1400016eb: 66 45 0f 28 d1              	movapd	xmm10, xmm9
1400016f0: f2 0f 5e cb                 	divsd	xmm1, xmm3
1400016f4: 66 0f 28 e6                 	movapd	xmm4, xmm6
1400016f8: f2 0f 10 1d 00 5d 01 00     	movsd	xmm3, qword ptr [rip + 0x15d00] # 0x140017400
140001700: f2 0f 59 e3                 	mulsd	xmm4, xmm3
140001704: f2 0f 59 e1                 	mulsd	xmm4, xmm1
140001708: f2 0f 58 a4 24 c8 00 00 00  	addsd	xmm4, qword ptr [rsp + 0xc8]
140001711: 66 0f 28 fd                 	movapd	xmm7, xmm5
140001715: f2 0f 59 fb                 	mulsd	xmm7, xmm3
140001719: f2 0f 59 f9                 	mulsd	xmm7, xmm1
14000171d: f2 0f 58 bc 24 90 00 00 00  	addsd	xmm7, qword ptr [rsp + 0x90]
140001726: 66 45 0f 28 ce              	movapd	xmm9, xmm14
14000172b: f2 44 0f 59 cb              	mulsd	xmm9, xmm3
140001730: f2 44 0f 59 c9              	mulsd	xmm9, xmm1
140001735: f2 44 0f 58 4c 24 30        	addsd	xmm9, qword ptr [rsp + 0x30]
14000173c: f2 0f 10 1d d4 5c 01 00     	movsd	xmm3, qword ptr [rip + 0x15cd4] # 0x140017418
140001744: f2 0f 59 f3                 	mulsd	xmm6, xmm3
140001748: f2 0f 59 f1                 	mulsd	xmm6, xmm1
14000174c: f2 0f 58 b4 24 f0 00 00 00  	addsd	xmm6, qword ptr [rsp + 0xf0]
140001755: f2 0f 59 eb                 	mulsd	xmm5, xmm3
140001759: f2 0f 59 e9                 	mulsd	xmm5, xmm1
14000175d: f2 0f 58 ac 24 00 01 00 00  	addsd	xmm5, qword ptr [rsp + 0x100]
140001766: f2 44 0f 59 f3              	mulsd	xmm14, xmm3
14000176b: f2 44 0f 59 f1              	mulsd	xmm14, xmm1
140001770: f2 0f 10 8c 24 a8 00 00 00  	movsd	xmm1, qword ptr [rsp + 0xa8]
140001779: f2 41 0f 58 cc              	addsd	xmm1, xmm12
14000177e: f2 0f 11 8c 24 a8 00 00 00  	movsd	qword ptr [rsp + 0xa8], xmm1
140001787: f2 44 0f 58 f2              	addsd	xmm14, xmm2
14000178c: 66 41 0f 28 db              	movapd	xmm3, xmm11
140001791: f2 0f 5c 5c 24 60           	subsd	xmm3, qword ptr [rsp + 0x60]
140001797: 66 41 0f 28 c8              	movapd	xmm1, xmm8
14000179c: 66 45 0f 28 d8              	movapd	xmm11, xmm8
1400017a1: f2 0f 5c 4c 24 68           	subsd	xmm1, qword ptr [rsp + 0x68]
1400017a7: 66 0f 28 d1                 	movapd	xmm2, xmm1
1400017ab: f2 0f 59 d1                 	mulsd	xmm2, xmm1
1400017af: 66 44 0f 28 c3              	movapd	xmm8, xmm3
1400017b4: f2 44 0f 59 c3              	mulsd	xmm8, xmm3
1400017b9: f2 44 0f 58 c2              	addsd	xmm8, xmm2
1400017be: 66 44 0f 28 e0              	movapd	xmm12, xmm0
1400017c3: f2 44 0f 5c 64 24 58        	subsd	xmm12, qword ptr [rsp + 0x58]
1400017ca: 66 41 0f 28 d4              	movapd	xmm2, xmm12
1400017cf: f2 41 0f 59 d4              	mulsd	xmm2, xmm12
1400017d4: f2 41 0f 58 d0              	addsd	xmm2, xmm8
1400017d9: 45 0f 57 c0                 	xorps	xmm8, xmm8
1400017dd: f2 44 0f 51 c2              	sqrtsd	xmm8, xmm2
1400017e2: f2 44 0f 59 c2              	mulsd	xmm8, xmm2
1400017e7: f2 45 0f 5e d0              	divsd	xmm10, xmm8
1400017ec: 66 0f 28 d3                 	movapd	xmm2, xmm3
1400017f0: f2 0f 10 05 10 5c 01 00     	movsd	xmm0, qword ptr [rip + 0x15c10] # 0x140017408
1400017f8: f2 0f 59 d0                 	mulsd	xmm2, xmm0
1400017fc: f2 41 0f 59 d2              	mulsd	xmm2, xmm10
140001801: f2 0f 58 d4                 	addsd	xmm2, xmm4
140001805: 66 44 0f 28 c1              	movapd	xmm8, xmm1
14000180a: f2 44 0f 59 c0              	mulsd	xmm8, xmm0
14000180f: f2 45 0f 59 c2              	mulsd	xmm8, xmm10
140001814: f2 44 0f 58 c7              	addsd	xmm8, xmm7
140001819: 66 41 0f 28 fc              	movapd	xmm7, xmm12
14000181e: f2 0f 59 f8                 	mulsd	xmm7, xmm0
140001822: f2 41 0f 59 fa              	mulsd	xmm7, xmm10
140001827: f2 41 0f 58 f9              	addsd	xmm7, xmm9
14000182c: f2 0f 10 05 e4 5b 01 00     	movsd	xmm0, qword ptr [rip + 0x15be4] # 0x140017418
140001834: f2 0f 59 d8                 	mulsd	xmm3, xmm0
140001838: f2 41 0f 59 da              	mulsd	xmm3, xmm10
14000183d: f2 41 0f 58 dd              	addsd	xmm3, xmm13
140001842: f2 0f 59 c8                 	mulsd	xmm1, xmm0
140001846: f2 41 0f 59 ca              	mulsd	xmm1, xmm10
14000184b: f2 0f 58 8c 24 c0 00 00 00  	addsd	xmm1, qword ptr [rsp + 0xc0]
140001854: f2 0f 11 8c 24 c8 00 00 00  	movsd	qword ptr [rsp + 0xc8], xmm1
14000185d: f2 44 0f 59 e0              	mulsd	xmm12, xmm0
140001862: f2 45 0f 59 e2              	mulsd	xmm12, xmm10
140001867: f2 0f 10 84 24 b0 00 00 00  	movsd	xmm0, qword ptr [rsp + 0xb0]
140001870: f2 0f 58 84 24 f8 00 00 00  	addsd	xmm0, qword ptr [rsp + 0xf8]
140001879: f2 0f 11 84 24 b0 00 00 00  	movsd	qword ptr [rsp + 0xb0], xmm0
140001882: f2 45 0f 58 e7              	addsd	xmm12, xmm15
140001887: f2 44 0f 10 94 24 d0 00 00 00       	movsd	xmm10, qword ptr [rsp + 0xd0]
140001891: f2 44 0f 5c 54 24 20        	subsd	xmm10, qword ptr [rsp + 0x20]
140001898: 66 41 0f 28 e3              	movapd	xmm4, xmm11
14000189d: f2 0f 5c 64 24 28           	subsd	xmm4, qword ptr [rsp + 0x28]
1400018a3: 66 0f 28 c4                 	movapd	xmm0, xmm4
1400018a7: f2 0f 59 c4                 	mulsd	xmm0, xmm4
1400018ab: 66 45 0f 28 ca              	movapd	xmm9, xmm10
1400018b0: f2 45 0f 59 ca              	mulsd	xmm9, xmm10
1400018b5: f2 44 0f 58 c8              	addsd	xmm9, xmm0
1400018ba: f2 44 0f 10 9c 24 98 00 00 00       	movsd	xmm11, qword ptr [rsp + 0x98]
1400018c4: f2 44 0f 5c 5c 24 50        	subsd	xmm11, qword ptr [rsp + 0x50]
1400018cb: 66 41 0f 28 c3              	movapd	xmm0, xmm11
1400018d0: f2 41 0f 59 c3              	mulsd	xmm0, xmm11
1400018d5: f2 41 0f 58 c1              	addsd	xmm0, xmm9
1400018da: 45 0f 57 c9                 	xorps	xmm9, xmm9
1400018de: f2 44 0f 51 c8              	sqrtsd	xmm9, xmm0
1400018e3: f2 44 0f 59 c8              	mulsd	xmm9, xmm0
1400018e8: f2 0f 10 05 f8 5a 01 00     	movsd	xmm0, qword ptr [rip + 0x15af8] # 0x1400173e8
1400018f0: f2 41 0f 5e c1              	divsd	xmm0, xmm9
1400018f5: f2 44 0f 10 8c 24 a0 00 00 00       	movsd	xmm9, qword ptr [rsp + 0xa0]
1400018ff: f2 44 0f 58 8c 24 88 00 00 00       	addsd	xmm9, qword ptr [rsp + 0x88]
140001909: f2 44 0f 11 8c 24 a0 00 00 00       	movsd	qword ptr [rsp + 0xa0], xmm9
140001913: 66 45 0f 28 ea              	movapd	xmm13, xmm10
140001918: f2 0f 10 0d f0 5a 01 00     	movsd	xmm1, qword ptr [rip + 0x15af0] # 0x140017410
140001920: f2 44 0f 59 e9              	mulsd	xmm13, xmm1
140001925: f2 44 0f 59 e8              	mulsd	xmm13, xmm0
14000192a: f2 44 0f 58 ea              	addsd	xmm13, xmm2
14000192f: f2 44 0f 11 ac 24 90 00 00 00       	movsd	qword ptr [rsp + 0x90], xmm13
140001939: 66 0f 28 d4                 	movapd	xmm2, xmm4
14000193d: f2 0f 59 d1                 	mulsd	xmm2, xmm1
140001941: f2 0f 59 d0                 	mulsd	xmm2, xmm0
140001945: f2 41 0f 58 d0              	addsd	xmm2, xmm8
14000194a: f2 0f 11 94 24 88 00 00 00  	movsd	qword ptr [rsp + 0x88], xmm2
140001953: 66 41 0f 28 d3              	movapd	xmm2, xmm11
140001958: f2 0f 59 d1                 	mulsd	xmm2, xmm1
14000195c: f2 0f 10 0d b4 5a 01 00     	movsd	xmm1, qword ptr [rip + 0x15ab4] # 0x140017418
140001964: f2 44 0f 59 d1              	mulsd	xmm10, xmm1
140001969: f2 44 0f 59 d0              	mulsd	xmm10, xmm0
14000196e: f2 0f 59 e1                 	mulsd	xmm4, xmm1
140001972: f2 0f 59 e0                 	mulsd	xmm4, xmm0
140001976: f2 44 0f 59 d9              	mulsd	xmm11, xmm1
14000197b: f2 0f 59 d0                 	mulsd	xmm2, xmm0
14000197f: f2 0f 11 54 24 30           	movsd	qword ptr [rsp + 0x30], xmm2
140001985: f2 44 0f 59 d8              	mulsd	xmm11, xmm0
14000198a: f2 0f 10 44 24 78           	movsd	xmm0, qword ptr [rsp + 0x78]
140001990: f2 0f 5c 44 24 60           	subsd	xmm0, qword ptr [rsp + 0x60]
140001996: f2 44 0f 10 ac 24 80 00 00 00       	movsd	xmm13, qword ptr [rsp + 0x80]
1400019a0: f2 44 0f 5c 6c 24 68        	subsd	xmm13, qword ptr [rsp + 0x68]
1400019a7: 66 41 0f 28 d5              	movapd	xmm2, xmm13
1400019ac: f2 41 0f 59 d5              	mulsd	xmm2, xmm13
1400019b1: 66 44 0f 28 c0              	movapd	xmm8, xmm0
1400019b6: f2 44 0f 59 c0              	mulsd	xmm8, xmm0
1400019bb: f2 44 0f 58 c2              	addsd	xmm8, xmm2
1400019c0: f2 0f 10 54 24 70           	movsd	xmm2, qword ptr [rsp + 0x70]
1400019c6: f2 0f 5c 54 24 58           	subsd	xmm2, qword ptr [rsp + 0x58]
1400019cc: 66 44 0f 28 ca              	movapd	xmm9, xmm2
1400019d1: f2 44 0f 59 ca              	mulsd	xmm9, xmm2
1400019d6: f2 45 0f 58 c8              	addsd	xmm9, xmm8
1400019db: f2 45 0f 51 f9              	sqrtsd	xmm15, xmm9
1400019e0: f2 45 0f 59 f9              	mulsd	xmm15, xmm9
1400019e5: f2 44 0f 10 0d fa 59 01 00  	movsd	xmm9, qword ptr [rip + 0x159fa] # 0x1400173e8
1400019ee: 66 45 0f 28 c1              	movapd	xmm8, xmm9
1400019f3: f2 45 0f 5e c7              	divsd	xmm8, xmm15
1400019f8: 66 44 0f 28 f8              	movapd	xmm15, xmm0
1400019fd: f2 0f 10 0d 03 5a 01 00     	movsd	xmm1, qword ptr [rip + 0x15a03] # 0x140017408
140001a05: f2 44 0f 59 f9              	mulsd	xmm15, xmm1
140001a0a: f2 45 0f 59 f8              	mulsd	xmm15, xmm8
140001a0f: f2 44 0f 58 fe              	addsd	xmm15, xmm6
140001a14: 66 41 0f 28 f5              	movapd	xmm6, xmm13
140001a19: f2 0f 59 f1                 	mulsd	xmm6, xmm1
140001a1d: f2 41 0f 59 f0              	mulsd	xmm6, xmm8
140001a22: f2 0f 58 f5                 	addsd	xmm6, xmm5
140001a26: 66 0f 28 ea                 	movapd	xmm5, xmm2
140001a2a: f2 0f 59 e9                 	mulsd	xmm5, xmm1
140001a2e: f2 41 0f 59 e8              	mulsd	xmm5, xmm8
140001a33: f2 41 0f 58 ee              	addsd	xmm5, xmm14
140001a38: f2 44 0f 10 74 24 30        	movsd	xmm14, qword ptr [rsp + 0x30]
140001a3f: f2 44 0f 58 f7              	addsd	xmm14, xmm7
140001a44: f2 44 0f 11 74 24 30        	movsd	qword ptr [rsp + 0x30], xmm14
140001a4b: f2 0f 10 3d cd 59 01 00     	movsd	xmm7, qword ptr [rip + 0x159cd] # 0x140017420
140001a53: f2 0f 59 c7                 	mulsd	xmm0, xmm7
140001a57: f2 41 0f 59 c0              	mulsd	xmm0, xmm8
140001a5c: f2 0f 58 c3                 	addsd	xmm0, xmm3
140001a60: f2 44 0f 58 54 24 38        	addsd	xmm10, qword ptr [rsp + 0x38]
140001a67: f2 44 0f 59 ef              	mulsd	xmm13, xmm7
140001a6c: f2 45 0f 59 e8              	mulsd	xmm13, xmm8
140001a71: f2 44 0f 58 ac 24 c8 00 00 00       	addsd	xmm13, qword ptr [rsp + 0xc8]
140001a7b: f2 0f 59 d7                 	mulsd	xmm2, xmm7
140001a7f: f2 41 0f 59 d0              	mulsd	xmm2, xmm8
140001a84: f2 41 0f 58 d4              	addsd	xmm2, xmm12
140001a89: f2 44 0f 10 64 24 78        	movsd	xmm12, qword ptr [rsp + 0x78]
140001a90: f2 44 0f 5c 64 24 20        	subsd	xmm12, qword ptr [rsp + 0x20]
140001a97: f2 0f 10 8c 24 80 00 00 00  	movsd	xmm1, qword ptr [rsp + 0x80]
140001aa0: f2 0f 5c 4c 24 28           	subsd	xmm1, qword ptr [rsp + 0x28]
140001aa6: 66 0f 28 d9                 	movapd	xmm3, xmm1
140001aaa: f2 0f 59 d9                 	mulsd	xmm3, xmm1
140001aae: 66 41 0f 28 fc              	movapd	xmm7, xmm12
140001ab3: f2 41 0f 59 fc              	mulsd	xmm7, xmm12
140001ab8: f2 0f 58 fb                 	addsd	xmm7, xmm3
140001abc: f2 0f 58 64 24 40           	addsd	xmm4, qword ptr [rsp + 0x40]
140001ac2: f2 44 0f 10 44 24 70        	movsd	xmm8, qword ptr [rsp + 0x70]
140001ac9: f2 44 0f 5c 44 24 50        	subsd	xmm8, qword ptr [rsp + 0x50]
140001ad0: 66 41 0f 28 d8              	movapd	xmm3, xmm8
140001ad5: f2 41 0f 59 d8              	mulsd	xmm3, xmm8
140001ada: f2 0f 58 df                 	addsd	xmm3, xmm7
140001ade: 0f 57 ff                    	xorps	xmm7, xmm7
140001ae1: f2 0f 51 fb                 	sqrtsd	xmm7, xmm3
140001ae5: f2 0f 59 fb                 	mulsd	xmm7, xmm3
140001ae9: f2 44 0f 58 5c 24 48        	addsd	xmm11, qword ptr [rsp + 0x48]
140001af0: 66 41 0f 28 d9              	movapd	xmm3, xmm9
140001af5: f2 0f 5e df                 	divsd	xmm3, xmm7
140001af9: 66 45 0f 28 f4              	movapd	xmm14, xmm12
140001afe: f2 0f 10 3d 0a 59 01 00     	movsd	xmm7, qword ptr [rip + 0x1590a] # 0x140017410
140001b06: f2 44 0f 59 f7              	mulsd	xmm14, xmm7
140001b0b: f2 44 0f 59 f3              	mulsd	xmm14, xmm3
140001b10: f2 45 0f 58 f7              	addsd	xmm14, xmm15
140001b15: 66 44 0f 28 c9              	movapd	xmm9, xmm1
140001b1a: f2 44 0f 59 cf              	mulsd	xmm9, xmm7
140001b1f: f2 44 0f 59 cb              	mulsd	xmm9, xmm3
140001b24: f2 44 0f 58 ce              	addsd	xmm9, xmm6
140001b29: 66 41 0f 28 f0              	movapd	xmm6, xmm8
140001b2e: f2 0f 59 f7                 	mulsd	xmm6, xmm7
140001b32: 66 44 0f 28 ff              	movapd	xmm15, xmm7
140001b37: f2 0f 59 f3                 	mulsd	xmm6, xmm3
140001b3b: f2 0f 58 f5                 	addsd	xmm6, xmm5
140001b3f: f2 0f 10 2d d9 58 01 00     	movsd	xmm5, qword ptr [rip + 0x158d9] # 0x140017420
140001b47: f2 44 0f 59 e5              	mulsd	xmm12, xmm5
140001b4c: f2 44 0f 59 e3              	mulsd	xmm12, xmm3
140001b51: f2 45 0f 58 e2              	addsd	xmm12, xmm10
140001b56: f2 0f 59 cd                 	mulsd	xmm1, xmm5
140001b5a: f2 0f 59 cb                 	mulsd	xmm1, xmm3
140001b5e: f2 0f 58 cc                 	addsd	xmm1, xmm4
140001b62: f2 44 0f 59 c5              	mulsd	xmm8, xmm5
140001b67: f2 44 0f 59 c3              	mulsd	xmm8, xmm3
140001b6c: f2 45 0f 58 c3              	addsd	xmm8, xmm11
140001b71: f2 0f 10 7c 24 60           	movsd	xmm7, qword ptr [rsp + 0x60]
140001b77: f2 0f 5c 7c 24 20           	subsd	xmm7, qword ptr [rsp + 0x20]
140001b7d: f2 0f 10 64 24 68           	movsd	xmm4, qword ptr [rsp + 0x68]
140001b83: f2 0f 5c 64 24 28           	subsd	xmm4, qword ptr [rsp + 0x28]
140001b89: 66 0f 28 dc                 	movapd	xmm3, xmm4
140001b8d: f2 0f 59 dc                 	mulsd	xmm3, xmm4
140001b91: 66 0f 28 ef                 	movapd	xmm5, xmm7
140001b95: f2 0f 59 ef                 	mulsd	xmm5, xmm7
140001b99: f2 0f 58 eb                 	addsd	xmm5, xmm3
140001b9d: f2 44 0f 10 54 24 58        	movsd	xmm10, qword ptr [rsp + 0x58]
140001ba4: f2 44 0f 5c 54 24 50        	subsd	xmm10, qword ptr [rsp + 0x50]
140001bab: 66 41 0f 28 da              	movapd	xmm3, xmm10
140001bb0: f2 41 0f 59 da              	mulsd	xmm3, xmm10
140001bb5: f2 0f 58 dd                 	addsd	xmm3, xmm5
140001bb9: 0f 57 ed                    	xorps	xmm5, xmm5
140001bbc: f2 0f 51 eb                 	sqrtsd	xmm5, xmm3
140001bc0: f2 0f 59 eb                 	mulsd	xmm5, xmm3
140001bc4: f2 0f 10 1d 1c 58 01 00     	movsd	xmm3, qword ptr [rip + 0x1581c] # 0x1400173e8
140001bcc: f2 0f 5e dd                 	divsd	xmm3, xmm5
140001bd0: 66 0f 28 ef                 	movapd	xmm5, xmm7
140001bd4: f2 41 0f 59 ef              	mulsd	xmm5, xmm15
140001bd9: f2 0f 59 eb                 	mulsd	xmm5, xmm3
140001bdd: f2 0f 58 e8                 	addsd	xmm5, xmm0
140001be1: 66 44 0f 28 dc              	movapd	xmm11, xmm4
140001be6: f2 45 0f 59 df              	mulsd	xmm11, xmm15
140001beb: f2 44 0f 59 db              	mulsd	xmm11, xmm3
140001bf0: f2 45 0f 58 dd              	addsd	xmm11, xmm13
140001bf5: 66 45 0f 28 ea              	movapd	xmm13, xmm10
140001bfa: f2 45 0f 59 ef              	mulsd	xmm13, xmm15
140001bff: f2 44 0f 59 eb              	mulsd	xmm13, xmm3
140001c04: f2 44 0f 58 ea              	addsd	xmm13, xmm2
140001c09: f2 0f 10 05 17 58 01 00     	movsd	xmm0, qword ptr [rip + 0x15817] # 0x140017428
140001c11: f2 0f 59 f8                 	mulsd	xmm7, xmm0
140001c15: f2 0f 59 fb                 	mulsd	xmm7, xmm3
140001c19: f2 41 0f 58 fc              	addsd	xmm7, xmm12
140001c1e: f2 0f 59 e0                 	mulsd	xmm4, xmm0
140001c22: f2 0f 59 e3                 	mulsd	xmm4, xmm3
140001c26: f2 0f 58 e1                 	addsd	xmm4, xmm1
140001c2a: f2 44 0f 59 d0              	mulsd	xmm10, xmm0
140001c2f: f2 44 0f 59 d3              	mulsd	xmm10, xmm3
140001c34: f2 45 0f 58 d0              	addsd	xmm10, xmm8
140001c39: f2 44 0f 10 84 24 a8 00 00 00       	movsd	xmm8, qword ptr [rsp + 0xa8]
140001c43: f2 0f 10 05 9d 57 01 00     	movsd	xmm0, qword ptr [rip + 0x1579d] # 0x1400173e8
140001c4b: f2 44 0f 59 c0              	mulsd	xmm8, xmm0
140001c50: f2 44 0f 58 84 24 b8 00 00 00       	addsd	xmm8, qword ptr [rsp + 0xb8]
140001c5a: f2 0f 10 9c 24 b0 00 00 00  	movsd	xmm3, qword ptr [rsp + 0xb0]
140001c63: f2 0f 59 d8                 	mulsd	xmm3, xmm0
140001c67: f2 0f 58 9c 24 e8 00 00 00  	addsd	xmm3, qword ptr [rsp + 0xe8]
140001c70: f2 44 0f 10 bc 24 a0 00 00 00       	movsd	xmm15, qword ptr [rsp + 0xa0]
140001c7a: f2 44 0f 59 f8              	mulsd	xmm15, xmm0
140001c7f: f2 44 0f 58 bc 24 d8 00 00 00       	addsd	xmm15, qword ptr [rsp + 0xd8]
140001c89: f2 0f 10 94 24 90 00 00 00  	movsd	xmm2, qword ptr [rsp + 0x90]
140001c92: f2 0f 59 d0                 	mulsd	xmm2, xmm0
140001c96: f2 0f 58 94 24 d0 00 00 00  	addsd	xmm2, qword ptr [rsp + 0xd0]
140001c9f: f2 44 0f 10 a4 24 88 00 00 00       	movsd	xmm12, qword ptr [rsp + 0x88]
140001ca9: f2 44 0f 59 e0              	mulsd	xmm12, xmm0
140001cae: f2 44 0f 58 a4 24 e0 00 00 00       	addsd	xmm12, qword ptr [rsp + 0xe0]
140001cb8: f2 0f 10 4c 24 30           	movsd	xmm1, qword ptr [rsp + 0x30]
140001cbe: f2 0f 59 c8                 	mulsd	xmm1, xmm0
140001cc2: f2 0f 58 8c 24 98 00 00 00  	addsd	xmm1, qword ptr [rsp + 0x98]
140001ccb: f2 0f 11 8c 24 98 00 00 00  	movsd	qword ptr [rsp + 0x98], xmm1
140001cd4: 66 41 0f 28 ce              	movapd	xmm1, xmm14
140001cd9: f2 0f 59 c8                 	mulsd	xmm1, xmm0
140001cdd: f2 0f 58 4c 24 78           	addsd	xmm1, qword ptr [rsp + 0x78]
140001ce3: f2 0f 11 4c 24 78           	movsd	qword ptr [rsp + 0x78], xmm1
140001ce9: 66 41 0f 28 c9              	movapd	xmm1, xmm9
140001cee: f2 0f 59 c8                 	mulsd	xmm1, xmm0
140001cf2: f2 0f 58 8c 24 80 00 00 00  	addsd	xmm1, qword ptr [rsp + 0x80]
140001cfb: f2 0f 11 8c 24 80 00 00 00  	movsd	qword ptr [rsp + 0x80], xmm1
140001d04: f2 0f 11 74 24 38           	movsd	qword ptr [rsp + 0x38], xmm6
140001d0a: f2 0f 59 f0                 	mulsd	xmm6, xmm0
140001d0e: f2 0f 58 74 24 70           	addsd	xmm6, qword ptr [rsp + 0x70]
140001d14: f2 0f 11 74 24 70           	movsd	qword ptr [rsp + 0x70], xmm6
140001d1a: 66 0f 28 cd                 	movapd	xmm1, xmm5
140001d1e: f2 0f 59 c8                 	mulsd	xmm1, xmm0
140001d22: f2 0f 58 4c 24 60           	addsd	xmm1, qword ptr [rsp + 0x60]
140001d28: f2 0f 11 4c 24 60           	movsd	qword ptr [rsp + 0x60], xmm1
140001d2e: 66 41 0f 28 cb              	movapd	xmm1, xmm11
140001d33: f2 0f 59 c8                 	mulsd	xmm1, xmm0
140001d37: f2 0f 58 4c 24 68           	addsd	xmm1, qword ptr [rsp + 0x68]
140001d3d: f2 0f 11 4c 24 68           	movsd	qword ptr [rsp + 0x68], xmm1
140001d43: f2 44 0f 11 6c 24 40        	movsd	qword ptr [rsp + 0x40], xmm13
140001d4a: f2 44 0f 59 e8              	mulsd	xmm13, xmm0
140001d4f: f2 44 0f 58 6c 24 58        	addsd	xmm13, qword ptr [rsp + 0x58]
140001d56: f2 44 0f 11 6c 24 58        	movsd	qword ptr [rsp + 0x58], xmm13
140001d5d: 66 0f 28 cf                 	movapd	xmm1, xmm7
140001d61: f2 0f 59 c8                 	mulsd	xmm1, xmm0
140001d65: f2 0f 58 4c 24 20           	addsd	xmm1, qword ptr [rsp + 0x20]
140001d6b: f2 0f 11 4c 24 20           	movsd	qword ptr [rsp + 0x20], xmm1
140001d71: 66 0f 28 cc                 	movapd	xmm1, xmm4
140001d75: f2 0f 59 c8                 	mulsd	xmm1, xmm0
140001d79: f2 0f 58 4c 24 28           	addsd	xmm1, qword ptr [rsp + 0x28]
140001d7f: f2 0f 11 4c 24 28           	movsd	qword ptr [rsp + 0x28], xmm1
140001d85: f2 44 0f 11 54 24 48        	movsd	qword ptr [rsp + 0x48], xmm10
140001d8c: f2 44 0f 59 d0              	mulsd	xmm10, xmm0
140001d91: f2 44 0f 58 54 24 50        	addsd	xmm10, qword ptr [rsp + 0x50]
140001d98: f2 44 0f 11 54 24 50        	movsd	qword ptr [rsp + 0x50], xmm10
140001d9f: 48 ff ca                    	dec	rdx
140001da2: 0f 85 78 f4 ff ff           	jne	0x140001220 <.text+0x220>
