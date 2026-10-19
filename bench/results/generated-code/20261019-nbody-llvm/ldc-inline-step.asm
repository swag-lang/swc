140001850: 66 44 0f 29 44 24 50        	movapd	xmmword ptr [rsp + 0x50], xmm8
140001857: 66 44 0f 29 ac 24 70 03 00 00       	movapd	xmmword ptr [rsp + 0x370], xmm13
140001861: 66 0f 28 cb                 	movapd	xmm1, xmm3
140001865: 66 45 0f 28 e9              	movapd	xmm13, xmm9
14000186a: 66 44 0f 28 d6              	movapd	xmm10, xmm6
14000186f: 66 44 0f 28 de              	movapd	xmm11, xmm6
140001874: 66 0f 29 b4 24 10 02 00 00  	movapd	xmmword ptr [rsp + 0x210], xmm6
14000187d: 66 45 0f 5c d9              	subpd	xmm11, xmm9
140001882: 66 44 0f 29 8c 24 20 02 00 00       	movapd	xmmword ptr [rsp + 0x220], xmm9
14000188c: 66 41 0f 28 db              	movapd	xmm3, xmm11
140001891: 66 41 0f 59 db              	mulpd	xmm3, xmm11
140001896: 66 0f 28 f3                 	movapd	xmm6, xmm3
14000189a: 66 0f 15 f3                 	unpckhpd	xmm6, xmm3              # xmm6 = xmm6[1],xmm3[1]
14000189e: f2 0f 58 f3                 	addsd	xmm6, xmm3
1400018a2: 66 0f 28 d9                 	movapd	xmm3, xmm1
1400018a6: 66 0f 15 d9                 	unpckhpd	xmm3, xmm1              # xmm3 = xmm3[1],xmm1[1]
1400018aa: 66 44 0f 28 cb              	movapd	xmm9, xmm3
1400018af: f2 44 0f 5c c9              	subsd	xmm9, xmm1
1400018b4: 66 44 0f 29 8c 24 60 03 00 00       	movapd	xmmword ptr [rsp + 0x360], xmm9
1400018be: 66 44 0f 28 f9              	movapd	xmm15, xmm1
1400018c3: 66 0f 29 8c 24 50 02 00 00  	movapd	xmmword ptr [rsp + 0x250], xmm1
1400018cc: 66 45 0f 28 c1              	movapd	xmm8, xmm9
1400018d1: f2 45 0f 59 c1              	mulsd	xmm8, xmm9
1400018d6: f2 44 0f 58 c6              	addsd	xmm8, xmm6
1400018db: 0f 57 f6                    	xorps	xmm6, xmm6
1400018de: f2 41 0f 51 f0              	sqrtsd	xmm6, xmm8
1400018e3: f2 41 0f 59 f0              	mulsd	xmm6, xmm8
1400018e8: f2 0f 10 0d 98 5b 04 00     	movsd	xmm1, qword ptr [rip + 0x45b98] # 0x140047488
1400018f0: f2 0f 5e ce                 	divsd	xmm1, xmm6
1400018f4: 66 41 0f 28 f3              	movapd	xmm6, xmm11
1400018f9: 66 44 0f 28 8c 24 d0 01 00 00       	movapd	xmm9, xmmword ptr [rsp + 0x1d0]
140001903: 66 41 0f 59 f1              	mulpd	xmm6, xmm9
140001908: 66 0f 14 c9                 	unpcklpd	xmm1, xmm1              # xmm1 = xmm1[0,0]
14000190c: 66 0f 29 8c 24 30 02 00 00  	movapd	xmmword ptr [rsp + 0x230], xmm1
140001915: 66 0f 59 f1                 	mulpd	xmm6, xmm1
140001919: 66 0f 58 74 24 30           	addpd	xmm6, xmmword ptr [rsp + 0x30]
14000191f: 66 0f 29 74 24 30           	movapd	xmmword ptr [rsp + 0x30], xmm6
140001925: 66 44 0f 5c d0              	subpd	xmm10, xmm0
14000192a: 66 0f 28 c8                 	movapd	xmm1, xmm0
14000192e: 66 0f 29 84 24 40 02 00 00  	movapd	xmmword ptr [rsp + 0x240], xmm0
140001937: 66 41 0f 28 c2              	movapd	xmm0, xmm10
14000193c: 66 44 0f 29 94 24 90 00 00 00       	movapd	xmmword ptr [rsp + 0x90], xmm10
140001946: 66 41 0f 59 c2              	mulpd	xmm0, xmm10
14000194b: 66 44 0f 5c e9              	subpd	xmm13, xmm1
140001950: 66 41 0f 28 f5              	movapd	xmm6, xmm13
140001955: 66 41 0f 59 f5              	mulpd	xmm6, xmm13
14000195a: 66 44 0f 28 c6              	movapd	xmm8, xmm6
14000195f: 66 44 0f 14 c0              	unpcklpd	xmm8, xmm0              # xmm8 = xmm8[0],xmm0[0]
140001964: 66 0f 15 f0                 	unpckhpd	xmm6, xmm0              # xmm6 = xmm6[1],xmm0[1]
140001968: 66 41 0f 58 f0              	addpd	xmm6, xmm8
14000196d: 66 0f 28 c2                 	movapd	xmm0, xmm2
140001971: 66 0f 15 c2                 	unpckhpd	xmm0, xmm2              # xmm0 = xmm0[1],xmm2[1]
140001975: 66 0f 29 84 24 60 02 00 00  	movapd	xmmword ptr [rsp + 0x260], xmm0
14000197e: 66 45 0f 28 c7              	movapd	xmm8, xmm15
140001983: 66 44 0f 5c c0              	subpd	xmm8, xmm0
140001988: 66 41 0f 28 c0              	movapd	xmm0, xmm8
14000198d: 66 41 0f 59 c0              	mulpd	xmm0, xmm8
140001992: 66 0f 58 f0                 	addpd	xmm6, xmm0
140001996: 66 0f 51 c6                 	sqrtpd	xmm0, xmm6
14000199a: 66 0f 59 c6                 	mulpd	xmm0, xmm6
14000199e: 66 0f 28 35 ea 5a 04 00     	movapd	xmm6, xmmword ptr [rip + 0x45aea] # 0x140047490
1400019a6: 66 0f 5e f0                 	divpd	xmm6, xmm0
1400019aa: 66 45 0f 28 f8              	movapd	xmm15, xmm8
1400019af: 66 44 0f 59 bc 24 70 02 00 00       	mulpd	xmm15, xmmword ptr [rsp + 0x270]
1400019b9: 66 44 0f 59 fe              	mulpd	xmm15, xmm6
1400019be: 66 41 0f 28 c7              	movapd	xmm0, xmm15
1400019c3: 66 41 0f 15 c7              	unpckhpd	xmm0, xmm15             # xmm0 = xmm0[1],xmm15[1]
1400019c8: f2 0f 58 c2                 	addsd	xmm0, xmm2
1400019cc: 66 0f 28 c8                 	movapd	xmm1, xmm0
1400019d0: 66 45 0f 59 d1              	mulpd	xmm10, xmm9
1400019d5: 66 44 0f 28 ce              	movapd	xmm9, xmm6
1400019da: 66 44 0f 15 ce              	unpckhpd	xmm9, xmm6              # xmm9 = xmm9[1],xmm6[1]
1400019df: 66 45 0f 59 d1              	mulpd	xmm10, xmm9
1400019e4: 66 45 0f 58 d6              	addpd	xmm10, xmm14
1400019e9: 66 45 0f 28 f5              	movapd	xmm14, xmm13
1400019ee: 66 0f 28 94 24 e0 01 00 00  	movapd	xmm2, xmmword ptr [rsp + 0x1e0]
1400019f7: 66 44 0f 59 f2              	mulpd	xmm14, xmm2
1400019fc: 66 44 0f 59 ac 24 c0 01 00 00       	mulpd	xmm13, xmmword ptr [rsp + 0x1c0]
140001a06: 66 44 0f 59 c2              	mulpd	xmm8, xmm2
140001a0b: 66 44 0f 59 c6              	mulpd	xmm8, xmm6
140001a10: 66 44 0f 29 84 24 00 03 00 00       	movapd	xmmword ptr [rsp + 0x300], xmm8
140001a1a: 66 0f 14 f6                 	unpcklpd	xmm6, xmm6              # xmm6 = xmm6[0,0]
140001a1e: 66 44 0f 59 f6              	mulpd	xmm14, xmm6
140001a23: 66 44 0f 29 b4 24 e0 02 00 00       	movapd	xmmword ptr [rsp + 0x2e0], xmm14
140001a2d: 66 41 0f 59 f5              	mulpd	xmm6, xmm13
140001a32: 66 41 0f 58 f2              	addpd	xmm6, xmm10
140001a37: 66 0f 29 b4 24 30 03 00 00  	movapd	xmmword ptr [rsp + 0x330], xmm6
140001a40: f2 41 0f 58 cf              	addsd	xmm1, xmm15
140001a45: 66 0f 29 8c 24 50 03 00 00  	movapd	xmmword ptr [rsp + 0x350], xmm1
140001a4e: 66 0f 28 c7                 	movapd	xmm0, xmm7
140001a52: 66 0f 28 fc                 	movapd	xmm7, xmm4
140001a56: 66 44 0f 28 d4              	movapd	xmm10, xmm4
140001a5b: 66 0f 5c f8                 	subpd	xmm7, xmm0
140001a5f: 66 0f 28 e0                 	movapd	xmm4, xmm0
140001a63: 66 0f 28 c7                 	movapd	xmm0, xmm7
140001a67: 66 0f 59 c7                 	mulpd	xmm0, xmm7
140001a6b: 66 0f 28 c8                 	movapd	xmm1, xmm0
140001a6f: 66 0f 15 c8                 	unpckhpd	xmm1, xmm0              # xmm1 = xmm1[1],xmm0[1]
140001a73: f2 0f 58 c8                 	addsd	xmm1, xmm0
140001a77: 66 41 0f 28 c4              	movapd	xmm0, xmm12
140001a7c: 66 45 0f 15 e4              	unpckhpd	xmm12, xmm12            # xmm12 = xmm12[1,1]
140001a81: f2 44 0f 5c e0              	subsd	xmm12, xmm0
140001a86: 66 44 0f 28 e8              	movapd	xmm13, xmm0
140001a8b: 66 41 0f 28 c4              	movapd	xmm0, xmm12
140001a90: f2 41 0f 59 c4              	mulsd	xmm0, xmm12
140001a95: f2 0f 58 c8                 	addsd	xmm1, xmm0
140001a99: 0f 57 c0                    	xorps	xmm0, xmm0
140001a9c: f2 0f 51 c1                 	sqrtsd	xmm0, xmm1
140001aa0: f2 0f 59 c1                 	mulsd	xmm0, xmm1
140001aa4: f2 0f 10 35 dc 59 04 00     	movsd	xmm6, qword ptr [rip + 0x459dc] # 0x140047488
140001aac: f2 0f 5e f0                 	divsd	xmm6, xmm0
140001ab0: 66 0f 29 b4 24 f0 02 00 00  	movapd	xmmword ptr [rsp + 0x2f0], xmm6
140001ab9: 66 44 0f 59 9c 24 c0 02 00 00       	mulpd	xmm11, xmmword ptr [rsp + 0x2c0]
140001ac3: 66 44 0f 59 9c 24 30 02 00 00       	mulpd	xmm11, xmmword ptr [rsp + 0x230]
140001acd: 66 0f 28 44 24 40           	movapd	xmm0, xmmword ptr [rsp + 0x40]
140001ad3: 66 41 0f 5c c3              	subpd	xmm0, xmm11
140001ad8: 66 0f 29 44 24 40           	movapd	xmmword ptr [rsp + 0x40], xmm0
140001ade: 66 0f 28 84 24 90 00 00 00  	movapd	xmm0, xmmword ptr [rsp + 0x90]
140001ae7: 66 0f 59 c2                 	mulpd	xmm0, xmm2
140001aeb: 66 41 0f 59 c1              	mulpd	xmm0, xmm9
140001af0: 66 0f 29 84 24 90 00 00 00  	movapd	xmmword ptr [rsp + 0x90], xmm0
140001af9: 66 0f 28 94 24 10 02 00 00  	movapd	xmm2, xmmword ptr [rsp + 0x210]
140001b02: 66 0f 28 c2                 	movapd	xmm0, xmm2
140001b06: 66 41 0f 5c c2              	subpd	xmm0, xmm10
140001b0b: 66 41 0f 28 ca              	movapd	xmm1, xmm10
140001b10: 66 44 0f 29 94 24 f0 01 00 00       	movapd	xmmword ptr [rsp + 0x1f0], xmm10
140001b1a: 66 44 0f 28 d2              	movapd	xmm10, xmm2
140001b1f: 66 44 0f 5c d4              	subpd	xmm10, xmm4
140001b24: 66 0f 28 f4                 	movapd	xmm6, xmm4
140001b28: 66 0f 29 a4 24 00 02 00 00  	movapd	xmmword ptr [rsp + 0x200], xmm4
140001b31: 66 41 0f 28 e2              	movapd	xmm4, xmm10
140001b36: 66 0f 14 e0                 	unpcklpd	xmm4, xmm0              # xmm4 = xmm4[0],xmm0[0]
140001b3a: 66 0f 59 e4                 	mulpd	xmm4, xmm4
140001b3e: 66 44 0f 28 c8              	movapd	xmm9, xmm0
140001b43: 66 0f 29 84 24 40 03 00 00  	movapd	xmmword ptr [rsp + 0x340], xmm0
140001b4c: 41 0f 12 c2                 	movhlps	xmm0, xmm10             # xmm0 = xmm10[1],xmm0[1]
140001b50: 66 0f 59 c0                 	mulpd	xmm0, xmm0
140001b54: 66 0f 58 c4                 	addpd	xmm0, xmm4
140001b58: 66 41 0f 5c dd              	subpd	xmm3, xmm13
140001b5d: 66 45 0f 28 f5              	movapd	xmm14, xmm13
140001b62: 66 44 0f 29 ac 24 d0 02 00 00       	movapd	xmmword ptr [rsp + 0x2d0], xmm13
140001b6c: 66 0f 28 e3                 	movapd	xmm4, xmm3
140001b70: 66 0f 59 e3                 	mulpd	xmm4, xmm3
140001b74: 66 0f 58 e0                 	addpd	xmm4, xmm0
140001b78: 66 0f 51 c4                 	sqrtpd	xmm0, xmm4
140001b7c: 66 0f 59 c4                 	mulpd	xmm0, xmm4
140001b80: 66 0f 28 25 08 59 04 00     	movapd	xmm4, xmmword ptr [rip + 0x45908] # 0x140047490
140001b88: 66 0f 5e e0                 	divpd	xmm4, xmm0
140001b8c: 66 44 0f 28 db              	movapd	xmm11, xmm3
140001b91: 66 44 0f 28 ac 24 d0 01 00 00       	movapd	xmm13, xmmword ptr [rsp + 0x1d0]
140001b9b: 66 41 0f 59 dd              	mulpd	xmm3, xmm13
140001ba0: 66 0f 59 dc                 	mulpd	xmm3, xmm4
140001ba4: 66 0f 58 dd                 	addpd	xmm3, xmm5
140001ba8: 66 44 0f 59 9c 24 80 00 00 00       	mulpd	xmm11, xmmword ptr [rsp + 0x80]
140001bb2: 66 44 0f 59 dc              	mulpd	xmm11, xmm4
140001bb7: 44 0f 29 94 24 20 03 00 00  	movaps	xmmword ptr [rsp + 0x320], xmm10
140001bc0: 66 45 0f 59 d5              	mulpd	xmm10, xmm13
140001bc5: 66 0f 28 d4                 	movapd	xmm2, xmm4
140001bc9: 66 0f 14 e4                 	unpcklpd	xmm4, xmm4              # xmm4 = xmm4[0,0]
140001bcd: 66 0f 29 a4 24 10 03 00 00  	movapd	xmmword ptr [rsp + 0x310], xmm4
140001bd6: 66 44 0f 59 d4              	mulpd	xmm10, xmm4
140001bdb: 66 44 0f 58 54 24 50        	addpd	xmm10, xmmword ptr [rsp + 0x50]
140001be2: 66 0f 28 84 24 20 02 00 00  	movapd	xmm0, xmmword ptr [rsp + 0x220]
140001beb: 66 0f 28 e8                 	movapd	xmm5, xmm0
140001bef: 66 0f 5c e9                 	subpd	xmm5, xmm1
140001bf3: 66 0f 28 c8                 	movapd	xmm1, xmm0
140001bf7: 66 0f 5c ce                 	subpd	xmm1, xmm6
140001bfb: 66 0f 28 e1                 	movapd	xmm4, xmm1
140001bff: 66 0f 14 e5                 	unpcklpd	xmm4, xmm5              # xmm4 = xmm4[0],xmm5[0]
140001c03: 66 0f 59 e4                 	mulpd	xmm4, xmm4
140001c07: 66 44 0f 28 c5              	movapd	xmm8, xmm5
140001c0c: 66 44 0f 28 fd              	movapd	xmm15, xmm5
140001c11: 0f 12 e9                    	movhlps	xmm5, xmm1              # xmm5 = xmm1[1],xmm5[1]
140001c14: 66 0f 59 ed                 	mulpd	xmm5, xmm5
140001c18: 66 0f 58 ec                 	addpd	xmm5, xmm4
140001c1c: 66 0f 28 a4 24 50 02 00 00  	movapd	xmm4, xmmword ptr [rsp + 0x250]
140001c25: 66 0f 14 e4                 	unpcklpd	xmm4, xmm4              # xmm4 = xmm4[0,0]
140001c29: 66 41 0f 5c e6              	subpd	xmm4, xmm14
140001c2e: 66 44 0f 28 f4              	movapd	xmm14, xmm4
140001c33: 66 44 0f 59 f4              	mulpd	xmm14, xmm4
140001c38: 66 41 0f 58 ee              	addpd	xmm5, xmm14
140001c3d: 66 44 0f 51 f5              	sqrtpd	xmm14, xmm5
140001c42: 66 44 0f 59 f5              	mulpd	xmm14, xmm5
140001c47: 66 0f 28 2d 41 58 04 00     	movapd	xmm5, xmmword ptr [rip + 0x45841] # 0x140047490
140001c4f: 66 41 0f 5e ee              	divpd	xmm5, xmm14
140001c54: 66 45 0f 59 cd              	mulpd	xmm9, xmm13
140001c59: 66 0f 15 d2                 	unpckhpd	xmm2, xmm2              # xmm2 = xmm2[1,1]
140001c5d: 66 0f 29 54 24 50           	movapd	xmmword ptr [rsp + 0x50], xmm2
140001c63: 66 44 0f 59 ca              	mulpd	xmm9, xmm2
140001c68: 66 44 0f 58 4c 24 60        	addpd	xmm9, xmmword ptr [rsp + 0x60]
140001c6f: 66 44 0f 59 44 24 70        	mulpd	xmm8, xmmword ptr [rsp + 0x70]
140001c76: 66 44 0f 28 f5              	movapd	xmm14, xmm5
140001c7b: 66 44 0f 15 f5              	unpckhpd	xmm14, xmm5             # xmm14 = xmm14[1],xmm5[1]
140001c80: 66 45 0f 59 c6              	mulpd	xmm8, xmm14
140001c85: 66 0f 28 44 24 30           	movapd	xmm0, xmmword ptr [rsp + 0x30]
140001c8b: 66 41 0f 5c c0              	subpd	xmm0, xmm8
140001c90: 66 44 0f 28 e9              	movapd	xmm13, xmm1
140001c95: 66 0f 28 b4 24 a0 02 00 00  	movapd	xmm6, xmmword ptr [rsp + 0x2a0]
140001c9e: 66 44 0f 59 ee              	mulpd	xmm13, xmm6
140001ca3: 66 44 0f 28 c5              	movapd	xmm8, xmm5
140001ca8: 66 44 0f 14 c5              	unpcklpd	xmm8, xmm5              # xmm8 = xmm8[0],xmm5[0]
140001cad: 66 45 0f 59 e8              	mulpd	xmm13, xmm8
140001cb2: 66 41 0f 5c c5              	subpd	xmm0, xmm13
140001cb7: 66 0f 5c 84 24 e0 02 00 00  	subpd	xmm0, xmmword ptr [rsp + 0x2e0]
140001cc0: 66 0f 29 44 24 30           	movapd	xmmword ptr [rsp + 0x30], xmm0
140001cc6: 66 44 0f 28 ec              	movapd	xmm13, xmm4
140001ccb: 66 0f 28 94 24 c0 01 00 00  	movapd	xmm2, xmmword ptr [rsp + 0x1c0]
140001cd4: 66 44 0f 59 ea              	mulpd	xmm13, xmm2
140001cd9: 66 0f 59 a4 24 80 00 00 00  	mulpd	xmm4, xmmword ptr [rsp + 0x80]
140001ce2: 66 0f 59 e5                 	mulpd	xmm4, xmm5
140001ce6: 66 41 0f 59 ed              	mulpd	xmm5, xmm13
140001ceb: 66 44 0f 28 ac 24 70 03 00 00       	movapd	xmm13, xmmword ptr [rsp + 0x370]
140001cf5: 66 0f 58 eb                 	addpd	xmm5, xmm3
140001cf9: 66 0f 28 84 24 60 03 00 00  	movapd	xmm0, xmmword ptr [rsp + 0x360]
140001d02: 66 0f 14 c0                 	unpcklpd	xmm0, xmm0              # xmm0 = xmm0[0,0]
140001d06: 66 0f 59 84 24 80 02 00 00  	mulpd	xmm0, xmmword ptr [rsp + 0x280]
140001d0f: 66 0f 59 84 24 30 02 00 00  	mulpd	xmm0, xmmword ptr [rsp + 0x230]
140001d18: 66 41 0f 28 dd              	movapd	xmm3, xmm13
140001d1d: 66 0f 58 d8                 	addpd	xmm3, xmm0
140001d21: 66 44 0f 5c e8              	subpd	xmm13, xmm0
140001d26: f2 44 0f 10 eb              	movsd	xmm13, xmm3             # xmm13 = xmm3[0],xmm13[1]
140001d2b: 66 0f 28 dc                 	movapd	xmm3, xmm4
140001d2f: 66 41 0f 15 db              	unpckhpd	xmm3, xmm11             # xmm3 = xmm3[1],xmm11[1]
140001d34: 66 44 0f 5c eb              	subpd	xmm13, xmm3
140001d39: 66 41 0f 14 e3              	unpcklpd	xmm4, xmm11             # xmm4 = xmm4[0],xmm11[0]
140001d3e: 66 44 0f 5c ec              	subpd	xmm13, xmm4
140001d43: 66 44 0f 5c ac 24 00 03 00 00       	subpd	xmm13, xmmword ptr [rsp + 0x300]
140001d4d: 66 0f 28 da                 	movapd	xmm3, xmm2
140001d51: 66 44 0f 59 fa              	mulpd	xmm15, xmm2
140001d56: 66 45 0f 59 f7              	mulpd	xmm14, xmm15
140001d5b: 66 45 0f 58 f1              	addpd	xmm14, xmm9
140001d60: 66 0f 28 c7                 	movapd	xmm0, xmm7
140001d64: 66 0f 59 c6                 	mulpd	xmm0, xmm6
140001d68: 66 0f 28 94 24 f0 02 00 00  	movapd	xmm2, xmmword ptr [rsp + 0x2f0]
140001d71: 66 0f 14 d2                 	unpcklpd	xmm2, xmm2              # xmm2 = xmm2[0,0]
140001d75: 66 0f 59 c2                 	mulpd	xmm0, xmm2
140001d79: 66 44 0f 5c f0              	subpd	xmm14, xmm0
140001d7e: 66 0f 59 cb                 	mulpd	xmm1, xmm3
140001d82: 66 41 0f 59 c8              	mulpd	xmm1, xmm8
140001d87: 66 41 0f 58 ca              	addpd	xmm1, xmm10
140001d8c: 66 44 0f 28 54 24 70        	movapd	xmm10, xmmword ptr [rsp + 0x70]
140001d93: 66 41 0f 59 fa              	mulpd	xmm7, xmm10
140001d98: 66 0f 59 fa                 	mulpd	xmm7, xmm2
140001d9c: 66 0f 58 cf                 	addpd	xmm1, xmm7
140001da0: 66 45 0f 14 e4              	unpcklpd	xmm12, xmm12            # xmm12 = xmm12[0,0]
140001da5: 66 44 0f 59 a4 24 b0 02 00 00       	mulpd	xmm12, xmmword ptr [rsp + 0x2b0]
140001daf: 66 44 0f 59 e2              	mulpd	xmm12, xmm2
140001db4: 66 0f 28 c5                 	movapd	xmm0, xmm5
140001db8: 66 41 0f 58 c4              	addpd	xmm0, xmm12
140001dbd: 66 41 0f 5c ec              	subpd	xmm5, xmm12
140001dc2: f2 0f 10 e8                 	movsd	xmm5, xmm0              # xmm5 = xmm0[0],xmm5[1]
140001dc6: 66 0f 28 84 24 f0 01 00 00  	movapd	xmm0, xmmword ptr [rsp + 0x1f0]
140001dcf: 66 0f 28 9c 24 40 02 00 00  	movapd	xmm3, xmmword ptr [rsp + 0x240]
140001dd8: 66 0f 5c c3                 	subpd	xmm0, xmm3
140001ddc: 66 0f 28 94 24 00 02 00 00  	movapd	xmm2, xmmword ptr [rsp + 0x200]
140001de5: 66 0f 5c d3                 	subpd	xmm2, xmm3
140001de9: 66 0f 28 e2                 	movapd	xmm4, xmm2
140001ded: 66 0f 14 e0                 	unpcklpd	xmm4, xmm0              # xmm4 = xmm4[0],xmm0[0]
140001df1: 66 0f 59 e4                 	mulpd	xmm4, xmm4
140001df5: 66 0f 28 da                 	movapd	xmm3, xmm2
140001df9: 66 0f 28 fa                 	movapd	xmm7, xmm2
140001dfd: 66 0f 15 d0                 	unpckhpd	xmm2, xmm0              # xmm2 = xmm2[1],xmm0[1]
140001e01: 66 0f 59 d2                 	mulpd	xmm2, xmm2
140001e05: 66 0f 58 d4                 	addpd	xmm2, xmm4
140001e09: 66 44 0f 28 bc 24 d0 02 00 00       	movapd	xmm15, xmmword ptr [rsp + 0x2d0]
140001e13: 66 45 0f 28 cf              	movapd	xmm9, xmm15
140001e18: 66 44 0f 5c 8c 24 60 02 00 00       	subpd	xmm9, xmmword ptr [rsp + 0x260]
140001e22: 66 41 0f 28 e1              	movapd	xmm4, xmm9
140001e27: 66 41 0f 59 e1              	mulpd	xmm4, xmm9
140001e2c: 66 0f 58 d4                 	addpd	xmm2, xmm4
140001e30: 66 0f 51 e2                 	sqrtpd	xmm4, xmm2
140001e34: 66 0f 59 e2                 	mulpd	xmm4, xmm2
140001e38: 66 44 0f 28 25 4f 56 04 00  	movapd	xmm12, xmmword ptr [rip + 0x4564f] # 0x140047490
140001e41: 66 41 0f 28 d4              	movapd	xmm2, xmm12
140001e46: 66 0f 5e d4                 	divpd	xmm2, xmm4
140001e4a: 66 0f 28 e0                 	movapd	xmm4, xmm0
140001e4e: 66 0f 28 b4 24 e0 01 00 00  	movapd	xmm6, xmmword ptr [rsp + 0x1e0]
140001e57: 66 0f 59 e6                 	mulpd	xmm4, xmm6
140001e5b: 66 44 0f 28 c2              	movapd	xmm8, xmm2
140001e60: 66 44 0f 15 c2              	unpckhpd	xmm8, xmm2              # xmm8 = xmm8[1],xmm2[1]
140001e65: 66 41 0f 59 e0              	mulpd	xmm4, xmm8
140001e6a: 66 45 0f 28 de              	movapd	xmm11, xmm14
140001e6f: 66 44 0f 5c dc              	subpd	xmm11, xmm4
140001e74: 66 41 0f 59 c2              	mulpd	xmm0, xmm10
140001e79: 66 41 0f 59 c0              	mulpd	xmm0, xmm8
140001e7e: 66 0f 58 84 24 30 03 00 00  	addpd	xmm0, xmmword ptr [rsp + 0x330]
140001e87: 66 41 0f 28 e1              	movapd	xmm4, xmm9
140001e8c: 66 0f 59 e6                 	mulpd	xmm4, xmm6
140001e90: 66 0f 59 e2                 	mulpd	xmm4, xmm2
140001e94: 66 44 0f 59 8c 24 80 00 00 00       	mulpd	xmm9, xmmword ptr [rsp + 0x80]
140001e9e: 66 44 0f 59 ca              	mulpd	xmm9, xmm2
140001ea3: 66 44 0f 28 f2              	movapd	xmm14, xmm2
140001ea8: 66 0f 59 de                 	mulpd	xmm3, xmm6
140001eac: 66 44 0f 14 f2              	unpcklpd	xmm14, xmm2             # xmm14 = xmm14[0],xmm2[0]
140001eb1: 66 41 0f 59 de              	mulpd	xmm3, xmm14
140001eb6: 66 44 0f 28 c1              	movapd	xmm8, xmm1
140001ebb: 66 44 0f 5c c3              	subpd	xmm8, xmm3
140001ec0: 66 0f 5c ec                 	subpd	xmm5, xmm4
140001ec4: 66 45 0f 28 d1              	movapd	xmm10, xmm9
140001ec9: 66 45 0f 15 d1              	unpckhpd	xmm10, xmm9             # xmm10 = xmm10[1],xmm9[1]
140001ece: f2 44 0f 58 94 24 50 03 00 00       	addsd	xmm10, qword ptr [rsp + 0x350]
140001ed8: f2 45 0f 58 d1              	addsd	xmm10, xmm9
140001edd: 66 44 0f 28 4c 24 30        	movapd	xmm9, xmmword ptr [rsp + 0x30]
140001ee4: 66 41 0f 28 cc              	movapd	xmm1, xmm12
140001ee9: 66 45 0f 59 cc              	mulpd	xmm9, xmm12
140001eee: 66 44 0f 58 8c 24 20 02 00 00       	addpd	xmm9, xmmword ptr [rsp + 0x220]
140001ef8: 66 44 0f 28 e5              	movapd	xmm12, xmm5
140001efd: 66 44 0f 59 e1              	mulpd	xmm12, xmm1
140001f02: 66 45 0f 58 e7              	addpd	xmm12, xmm15
140001f07: 66 41 0f 28 dd              	movapd	xmm3, xmm13
140001f0c: 66 0f 59 d9                 	mulpd	xmm3, xmm1
140001f10: 66 0f 28 d1                 	movapd	xmm2, xmm1
140001f14: 66 0f 58 9c 24 50 02 00 00  	addpd	xmm3, xmmword ptr [rsp + 0x250]
140001f1d: 66 0f 28 8c 24 40 03 00 00  	movapd	xmm1, xmmword ptr [rsp + 0x340]
140001f26: 66 0f 59 4c 24 70           	mulpd	xmm1, xmmword ptr [rsp + 0x70]
140001f2c: 66 0f 28 64 24 50           	movapd	xmm4, xmmword ptr [rsp + 0x50]
140001f32: 66 0f 59 e1                 	mulpd	xmm4, xmm1
140001f36: 66 0f 28 74 24 40           	movapd	xmm6, xmmword ptr [rsp + 0x40]
140001f3c: 66 0f 5c f4                 	subpd	xmm6, xmm4
140001f40: 66 0f 28 8c 24 90 02 00 00  	movapd	xmm1, xmmword ptr [rsp + 0x290]
140001f49: 66 44 0f 28 bc 24 20 03 00 00       	movapd	xmm15, xmmword ptr [rsp + 0x320]
140001f53: 66 44 0f 59 f9              	mulpd	xmm15, xmm1
140001f58: 66 0f 28 a4 24 10 03 00 00  	movapd	xmm4, xmmword ptr [rsp + 0x310]
140001f61: 66 41 0f 59 e7              	mulpd	xmm4, xmm15
140001f66: 66 0f 5c f4                 	subpd	xmm6, xmm4
140001f6a: 66 0f 5c b4 24 90 00 00 00  	subpd	xmm6, xmmword ptr [rsp + 0x90]
140001f73: 66 0f 59 f9                 	mulpd	xmm7, xmm1
140001f77: 66 44 0f 59 f7              	mulpd	xmm14, xmm7
140001f7c: 66 44 0f 58 f0              	addpd	xmm14, xmm0
140001f81: 66 0f 29 74 24 40           	movapd	xmmword ptr [rsp + 0x40], xmm6
140001f87: 66 0f 59 f2                 	mulpd	xmm6, xmm2
140001f8b: 66 0f 58 b4 24 10 02 00 00  	addpd	xmm6, xmmword ptr [rsp + 0x210]
140001f94: 66 44 0f 29 5c 24 60        	movapd	xmmword ptr [rsp + 0x60], xmm11
140001f9b: 66 41 0f 28 e3              	movapd	xmm4, xmm11
140001fa0: 66 0f 59 e2                 	mulpd	xmm4, xmm2
140001fa4: 66 0f 58 a4 24 f0 01 00 00  	addpd	xmm4, xmmword ptr [rsp + 0x1f0]
140001fad: 66 41 0f 28 f8              	movapd	xmm7, xmm8
140001fb2: 66 0f 59 fa                 	mulpd	xmm7, xmm2
140001fb6: 66 0f 58 bc 24 00 02 00 00  	addpd	xmm7, xmmword ptr [rsp + 0x200]
140001fbf: 66 41 0f 28 c6              	movapd	xmm0, xmm14
140001fc4: 66 0f 59 c2                 	mulpd	xmm0, xmm2
140001fc8: 66 0f 58 84 24 40 02 00 00  	addpd	xmm0, xmmword ptr [rsp + 0x240]
140001fd1: 66 45 0f 28 da              	movapd	xmm11, xmm10
140001fd6: f2 44 0f 59 1d a9 54 04 00  	mulsd	xmm11, qword ptr [rip + 0x454a9] # 0x140047488
140001fdf: f2 44 0f 58 9c 24 60 02 00 00       	addsd	xmm11, qword ptr [rsp + 0x260]
140001fe9: 66 41 0f 28 d2              	movapd	xmm2, xmm10
140001fee: 66 41 0f 14 d3              	unpcklpd	xmm2, xmm11             # xmm2 = xmm2[0],xmm11[0]
140001ff3: 48 ff c8                    	dec	rax
140001ff6: 0f 85 54 f8 ff ff           	jne	0x140001850 <.text+0x850>
