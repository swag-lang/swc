140009d70: c5 fb 10 8c 24 e8 02 00 00  	vmovsd	xmm1, qword ptr [rsp + 0x2e8]
140009d79: c5 fb 10 13                 	vmovsd	xmm2, qword ptr [rbx]
140009d7d: c5 eb 5c 53 38              	vsubsd	xmm2, xmm2, qword ptr [rbx + 0x38]
140009d82: c5 fb 10 63 08              	vmovsd	xmm4, qword ptr [rbx + 0x8]
140009d87: c5 db 5c 63 40              	vsubsd	xmm4, xmm4, qword ptr [rbx + 0x40]
140009d8c: c5 fb 10 7b 10              	vmovsd	xmm7, qword ptr [rbx + 0x10]
140009d91: c5 c3 5c 7b 48              	vsubsd	xmm7, xmm7, qword ptr [rbx + 0x48]
140009d96: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
140009d9a: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
140009d9f: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
140009da4: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
140009da9: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
140009dae: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
140009db3: c5 7b 10 5b 68              	vmovsd	xmm11, qword ptr [rbx + 0x68]
140009db8: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
140009dbd: c5 7b 10 63 18              	vmovsd	xmm12, qword ptr [rbx + 0x18]
140009dc2: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
140009dc7: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
140009dcc: c5 7b 10 6b 20              	vmovsd	xmm13, qword ptr [rbx + 0x20]
140009dd1: c4 42 a9 bd e9              	vfnmadd231sd	xmm13, xmm10, xmm9 # xmm13 = -(xmm10 * xmm9) + xmm13
140009dd6: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
140009ddb: c5 7b 10 73 28              	vmovsd	xmm14, qword ptr [rbx + 0x28]
140009de0: c4 42 a9 bd f1              	vfnmadd231sd	xmm14, xmm10, xmm9 # xmm14 = -(xmm10 * xmm9) + xmm14
140009de5: c5 7b 10 7b 30              	vmovsd	xmm15, qword ptr [rbx + 0x30]
140009dea: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
140009def: c5 7b 10 5b 50              	vmovsd	xmm11, qword ptr [rbx + 0x50]
140009df4: c4 42 e9 b9 d9              	vfmadd231sd	xmm11, xmm2, xmm9 # xmm11 = (xmm2 * xmm9) + xmm11
140009df9: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
140009dfe: c5 7b 10 53 58              	vmovsd	xmm10, qword ptr [rbx + 0x58]
140009e03: c4 42 e9 b9 d1              	vfmadd231sd	xmm10, xmm2, xmm9 # xmm10 = (xmm2 * xmm9) + xmm10
140009e08: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
140009e0d: c4 c1 6b 59 d1              	vmulsd	xmm2, xmm2, xmm9
140009e12: c5 6b 58 43 60              	vaddsd	xmm8, xmm2, qword ptr [rbx + 0x60]
140009e17: c5 fb 10 13                 	vmovsd	xmm2, qword ptr [rbx]
140009e1b: c5 eb 5c 53 70              	vsubsd	xmm2, xmm2, qword ptr [rbx + 0x70]
140009e20: c5 fb 10 63 08              	vmovsd	xmm4, qword ptr [rbx + 0x8]
140009e25: c5 db 5c 63 78              	vsubsd	xmm4, xmm4, qword ptr [rbx + 0x78]
140009e2a: c5 fb 10 7b 10              	vmovsd	xmm7, qword ptr [rbx + 0x10]
140009e2f: c5 c3 5c bb 80 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0x80]
140009e37: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
140009e3b: c4 c1 78 10 ea              	vmovups	xmm5, xmm10
140009e40: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
140009e45: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
140009e4a: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
140009e4f: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
140009e54: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
140009e59: c4 c1 78 10 db              	vmovups	xmm3, xmm11
140009e5e: c5 7b 10 9b a0 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xa0]
140009e66: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
140009e6b: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
140009e70: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
140009e75: c4 42 a9 bd e9              	vfnmadd231sd	xmm13, xmm10, xmm9 # xmm13 = -(xmm10 * xmm9) + xmm13
140009e7a: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
140009e7f: c4 42 a9 bd f1              	vfnmadd231sd	xmm14, xmm10, xmm9 # xmm14 = -(xmm10 * xmm9) + xmm14
140009e84: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
140009e89: c5 7b 10 9b 88 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0x88]
140009e91: c4 42 e9 b9 d9              	vfmadd231sd	xmm11, xmm2, xmm9 # xmm11 = (xmm2 * xmm9) + xmm11
140009e96: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
140009e9b: c5 7b 10 93 90 00 00 00     	vmovsd	xmm10, qword ptr [rbx + 0x90]
140009ea3: c4 42 e9 b9 d1              	vfmadd231sd	xmm10, xmm2, xmm9 # xmm10 = (xmm2 * xmm9) + xmm10
140009ea8: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
140009ead: c4 e2 b1 a9 93 98 00 00 00  	vfmadd213sd	xmm2, xmm9, qword ptr [rbx + 0x98] # xmm2 = (xmm9 * xmm2) + mem
140009eb6: c5 78 10 ca                 	vmovups	xmm9, xmm2
140009eba: c5 fb 10 13                 	vmovsd	xmm2, qword ptr [rbx]
140009ebe: c5 eb 5c 93 a8 00 00 00     	vsubsd	xmm2, xmm2, qword ptr [rbx + 0xa8]
140009ec6: c5 fb 10 63 08              	vmovsd	xmm4, qword ptr [rbx + 0x8]
140009ecb: c5 db 5c a3 b0 00 00 00     	vsubsd	xmm4, xmm4, qword ptr [rbx + 0xb0]
140009ed3: c5 fb 10 7b 10              	vmovsd	xmm7, qword ptr [rbx + 0x10]
140009ed8: c4 c1 78 10 f0              	vmovups	xmm6, xmm8
140009edd: c5 c3 5c bb b8 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0xb8]
140009ee5: c4 41 78 10 c1              	vmovups	xmm8, xmm9
140009eea: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
140009eee: c5 7b 11 94 24 f8 02 00 00  	vmovsd	qword ptr [rsp + 0x2f8], xmm10
140009ef7: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
140009efc: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
140009f01: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
140009f06: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
140009f0b: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
140009f10: c4 c1 78 10 c3              	vmovups	xmm0, xmm11
140009f15: c5 7b 10 9b d8 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xd8]
140009f1d: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
140009f22: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
140009f27: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
140009f2c: c4 42 a9 bd e9              	vfnmadd231sd	xmm13, xmm10, xmm9 # xmm13 = -(xmm10 * xmm9) + xmm13
140009f31: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
140009f36: c4 42 a9 bd f1              	vfnmadd231sd	xmm14, xmm10, xmm9 # xmm14 = -(xmm10 * xmm9) + xmm14
140009f3b: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
140009f40: c5 7b 10 9b c0 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xc0]
140009f48: c4 42 e9 b9 d9              	vfmadd231sd	xmm11, xmm2, xmm9 # xmm11 = (xmm2 * xmm9) + xmm11
140009f4d: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
140009f52: c5 7b 10 93 c8 00 00 00     	vmovsd	xmm10, qword ptr [rbx + 0xc8]
140009f5a: c4 42 e9 b9 d1              	vfmadd231sd	xmm10, xmm2, xmm9 # xmm10 = (xmm2 * xmm9) + xmm10
140009f5f: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
140009f64: c4 e2 b1 a9 93 d0 00 00 00  	vfmadd213sd	xmm2, xmm9, qword ptr [rbx + 0xd0] # xmm2 = (xmm9 * xmm2) + mem
140009f6d: c5 78 10 ca                 	vmovups	xmm9, xmm2
140009f71: c5 fb 10 13                 	vmovsd	xmm2, qword ptr [rbx]
140009f75: c5 eb 5c 93 e0 00 00 00     	vsubsd	xmm2, xmm2, qword ptr [rbx + 0xe0]
140009f7d: c5 fb 10 63 08              	vmovsd	xmm4, qword ptr [rbx + 0x8]
140009f82: c5 db 5c a3 e8 00 00 00     	vsubsd	xmm4, xmm4, qword ptr [rbx + 0xe8]
140009f8a: c5 fb 10 7b 10              	vmovsd	xmm7, qword ptr [rbx + 0x10]
140009f8f: c5 7b 11 84 24 00 03 00 00  	vmovsd	qword ptr [rsp + 0x300], xmm8
140009f98: c5 c3 5c bb f0 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0xf0]
140009fa0: c4 41 78 10 c1              	vmovups	xmm8, xmm9
140009fa5: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
140009fa9: c5 7b 11 94 24 10 03 00 00  	vmovsd	qword ptr [rsp + 0x310], xmm10
140009fb2: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
140009fb7: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
140009fbc: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
140009fc1: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
140009fc6: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
140009fcb: c5 7b 11 9c 24 08 03 00 00  	vmovsd	qword ptr [rsp + 0x308], xmm11
140009fd4: c5 7b 10 9b 10 01 00 00     	vmovsd	xmm11, qword ptr [rbx + 0x110]
140009fdc: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
140009fe1: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
140009fe6: c5 7b 11 a4 24 18 03 00 00  	vmovsd	qword ptr [rsp + 0x318], xmm12
140009fef: c5 7b 11 63 18              	vmovsd	qword ptr [rbx + 0x18], xmm12
140009ff4: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
140009ff9: c4 42 a9 bd e9              	vfnmadd231sd	xmm13, xmm10, xmm9 # xmm13 = -(xmm10 * xmm9) + xmm13
140009ffe: c5 7b 11 ac 24 20 03 00 00  	vmovsd	qword ptr [rsp + 0x320], xmm13
14000a007: c5 7b 11 6b 20              	vmovsd	qword ptr [rbx + 0x20], xmm13
14000a00c: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a011: c4 42 a9 bd f1              	vfnmadd231sd	xmm14, xmm10, xmm9 # xmm14 = -(xmm10 * xmm9) + xmm14
14000a016: c5 7b 11 b4 24 28 03 00 00  	vmovsd	qword ptr [rsp + 0x328], xmm14
14000a01f: c5 7b 11 73 28              	vmovsd	qword ptr [rbx + 0x28], xmm14
14000a024: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a029: c5 7b 10 9b f8 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xf8]
14000a031: c4 42 e9 b9 d9              	vfmadd231sd	xmm11, xmm2, xmm9 # xmm11 = (xmm2 * xmm9) + xmm11
14000a036: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a03b: c5 7b 10 93 00 01 00 00     	vmovsd	xmm10, qword ptr [rbx + 0x100]
14000a043: c4 42 e9 b9 d1              	vfmadd231sd	xmm10, xmm2, xmm9 # xmm10 = (xmm2 * xmm9) + xmm10
14000a048: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a04d: c5 7b 10 bb 08 01 00 00     	vmovsd	xmm15, qword ptr [rbx + 0x108]
14000a055: c4 42 e9 b9 f9              	vfmadd231sd	xmm15, xmm2, xmm9 # xmm15 = (xmm2 * xmm9) + xmm15
14000a05a: c5 fb 10 53 38              	vmovsd	xmm2, qword ptr [rbx + 0x38]
14000a05f: c5 78 10 cb                 	vmovups	xmm9, xmm3
14000a063: c5 eb 5c 53 70              	vsubsd	xmm2, xmm2, qword ptr [rbx + 0x70]
14000a068: c5 fb 10 63 40              	vmovsd	xmm4, qword ptr [rbx + 0x40]
14000a06d: c5 f8 10 dd                 	vmovups	xmm3, xmm5
14000a071: c5 db 5c 63 78              	vsubsd	xmm4, xmm4, qword ptr [rbx + 0x78]
14000a076: c5 fb 10 7b 48              	vmovsd	xmm7, qword ptr [rbx + 0x48]
14000a07b: c4 c1 78 10 e8              	vmovups	xmm5, xmm8
14000a080: c5 c3 5c bb 80 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0x80]
14000a088: c4 41 78 10 c1              	vmovups	xmm8, xmm9
14000a08d: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a091: c4 41 78 10 f2              	vmovups	xmm14, xmm10
14000a096: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a09b: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a0a0: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a0a5: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a0aa: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
14000a0af: c4 41 78 10 eb              	vmovups	xmm13, xmm11
14000a0b4: c5 7b 10 9b a0 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xa0]
14000a0bc: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a0c1: c4 42 a9 bd c1              	vfnmadd231sd	xmm8, xmm10, xmm9 # xmm8 = -(xmm10 * xmm9) + xmm8
14000a0c6: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a0cb: c4 c2 a9 bd d9              	vfnmadd231sd	xmm3, xmm10, xmm9 # xmm3 = -(xmm10 * xmm9) + xmm3
14000a0d0: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a0d5: c4 c2 a9 bd f1              	vfnmadd231sd	xmm6, xmm10, xmm9 # xmm6 = -(xmm10 * xmm9) + xmm6
14000a0da: c4 41 78 10 df              	vmovups	xmm11, xmm15
14000a0df: c5 7b 10 7b 68              	vmovsd	xmm15, qword ptr [rbx + 0x68]
14000a0e4: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a0e9: c4 c2 e9 b9 c1              	vfmadd231sd	xmm0, xmm2, xmm9 # xmm0 = (xmm2 * xmm9) + xmm0
14000a0ee: c5 fb 11 84 24 30 03 00 00  	vmovsd	qword ptr [rsp + 0x330], xmm0
14000a0f7: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a0fc: c4 c1 6b 59 d1              	vmulsd	xmm2, xmm2, xmm9
14000a101: c5 6b 58 94 24 f8 02 00 00  	vaddsd	xmm10, xmm2, qword ptr [rsp + 0x2f8]
14000a10a: c5 7b 11 94 24 38 03 00 00  	vmovsd	qword ptr [rsp + 0x338], xmm10
14000a113: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a118: c4 62 e9 a9 8c 24 00 03 00 00       	vfmadd213sd	xmm9, xmm2, qword ptr [rsp + 0x300] # xmm9 = (xmm2 * xmm9) + mem
14000a122: c5 fb 10 53 38              	vmovsd	xmm2, qword ptr [rbx + 0x38]
14000a127: c5 f8 10 fb                 	vmovups	xmm7, xmm3
14000a12b: c5 eb 5c 93 a8 00 00 00     	vsubsd	xmm2, xmm2, qword ptr [rbx + 0xa8]
14000a133: c5 fb 10 63 40              	vmovsd	xmm4, qword ptr [rbx + 0x40]
14000a138: c5 f8 10 dd                 	vmovups	xmm3, xmm5
14000a13c: c5 db 5c a3 b0 00 00 00     	vsubsd	xmm4, xmm4, qword ptr [rbx + 0xb0]
14000a144: c5 f8 10 ef                 	vmovups	xmm5, xmm7
14000a148: c5 fb 10 7b 48              	vmovsd	xmm7, qword ptr [rbx + 0x48]
14000a14d: c4 41 78 10 e0              	vmovups	xmm12, xmm8
14000a152: c5 c3 5c bb b8 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0xb8]
14000a15a: c4 41 78 10 c1              	vmovups	xmm8, xmm9
14000a15f: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a163: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a168: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a16d: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a172: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a177: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
14000a17c: c4 c1 78 10 c3              	vmovups	xmm0, xmm11
14000a181: c5 7b 10 9b d8 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xd8]
14000a189: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a18e: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
14000a193: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a198: c4 c2 a9 bd e9              	vfnmadd231sd	xmm5, xmm10, xmm9 # xmm5 = -(xmm10 * xmm9) + xmm5
14000a19d: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a1a2: c4 c2 a9 bd f1              	vfnmadd231sd	xmm6, xmm10, xmm9 # xmm6 = -(xmm10 * xmm9) + xmm6
14000a1a7: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a1ac: c5 7b 10 9c 24 08 03 00 00  	vmovsd	xmm11, qword ptr [rsp + 0x308]
14000a1b5: c4 42 e9 b9 d9              	vfmadd231sd	xmm11, xmm2, xmm9 # xmm11 = (xmm2 * xmm9) + xmm11
14000a1ba: c5 7b 11 9c 24 40 03 00 00  	vmovsd	qword ptr [rsp + 0x340], xmm11
14000a1c3: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a1c8: c5 7b 10 94 24 10 03 00 00  	vmovsd	xmm10, qword ptr [rsp + 0x310]
14000a1d1: c4 42 e9 b9 d1              	vfmadd231sd	xmm10, xmm2, xmm9 # xmm10 = (xmm2 * xmm9) + xmm10
14000a1d6: c5 7b 11 94 24 48 03 00 00  	vmovsd	qword ptr [rsp + 0x348], xmm10
14000a1df: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a1e4: c4 62 e9 a9 cb              	vfmadd213sd	xmm9, xmm2, xmm3 # xmm9 = (xmm2 * xmm9) + xmm3
14000a1e9: c5 fb 10 53 38              	vmovsd	xmm2, qword ptr [rbx + 0x38]
14000a1ee: c5 eb 5c 93 e0 00 00 00     	vsubsd	xmm2, xmm2, qword ptr [rbx + 0xe0]
14000a1f6: c5 fb 10 63 40              	vmovsd	xmm4, qword ptr [rbx + 0x40]
14000a1fb: c5 f8 10 dd                 	vmovups	xmm3, xmm5
14000a1ff: c5 db 5c a3 e8 00 00 00     	vsubsd	xmm4, xmm4, qword ptr [rbx + 0xe8]
14000a207: c5 fb 10 7b 48              	vmovsd	xmm7, qword ptr [rbx + 0x48]
14000a20c: c4 c1 78 10 e8              	vmovups	xmm5, xmm8
14000a211: c5 c3 5c bb f0 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0xf0]
14000a219: c4 41 78 10 c1              	vmovups	xmm8, xmm9
14000a21e: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a222: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a227: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a22c: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a231: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a236: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
14000a23b: c5 7b 10 9b 10 01 00 00     	vmovsd	xmm11, qword ptr [rbx + 0x110]
14000a243: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a248: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
14000a24d: c5 7b 11 a4 24 50 03 00 00  	vmovsd	qword ptr [rsp + 0x350], xmm12
14000a256: c5 7b 11 63 50              	vmovsd	qword ptr [rbx + 0x50], xmm12
14000a25b: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a260: c4 c2 a9 bd d9              	vfnmadd231sd	xmm3, xmm10, xmm9 # xmm3 = -(xmm10 * xmm9) + xmm3
14000a265: c5 fb 11 9c 24 58 03 00 00  	vmovsd	qword ptr [rsp + 0x358], xmm3
14000a26e: c5 fb 11 5b 58              	vmovsd	qword ptr [rbx + 0x58], xmm3
14000a273: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a278: c4 c2 a9 bd f1              	vfnmadd231sd	xmm6, xmm10, xmm9 # xmm6 = -(xmm10 * xmm9) + xmm6
14000a27d: c5 fb 11 b4 24 60 03 00 00  	vmovsd	qword ptr [rsp + 0x360], xmm6
14000a286: c5 fb 11 73 60              	vmovsd	qword ptr [rbx + 0x60], xmm6
14000a28b: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a290: c4 42 e9 b9 e9              	vfmadd231sd	xmm13, xmm2, xmm9 # xmm13 = (xmm2 * xmm9) + xmm13
14000a295: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a29a: c4 42 e9 b9 f1              	vfmadd231sd	xmm14, xmm2, xmm9 # xmm14 = (xmm2 * xmm9) + xmm14
14000a29f: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a2a4: c4 c2 e9 b9 c1              	vfmadd231sd	xmm0, xmm2, xmm9 # xmm0 = (xmm2 * xmm9) + xmm0
14000a2a9: c5 fb 10 53 70              	vmovsd	xmm2, qword ptr [rbx + 0x70]
14000a2ae: c5 eb 5c 93 a8 00 00 00     	vsubsd	xmm2, xmm2, qword ptr [rbx + 0xa8]
14000a2b6: c5 fb 10 63 78              	vmovsd	xmm4, qword ptr [rbx + 0x78]
14000a2bb: c5 f8 10 dd                 	vmovups	xmm3, xmm5
14000a2bf: c5 db 5c a3 b0 00 00 00     	vsubsd	xmm4, xmm4, qword ptr [rbx + 0xb0]
14000a2c7: c5 fb 10 bb 80 00 00 00     	vmovsd	xmm7, qword ptr [rbx + 0x80]
14000a2cf: c4 c1 78 10 e8              	vmovups	xmm5, xmm8
14000a2d4: c5 c3 5c bb b8 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0xb8]
14000a2dc: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a2e0: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a2e5: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a2ea: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a2ef: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a2f4: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
14000a2f9: c5 7b 10 9b d8 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xd8]
14000a301: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a306: c5 7b 10 84 24 30 03 00 00  	vmovsd	xmm8, qword ptr [rsp + 0x330]
14000a30f: c4 42 a9 bd c1              	vfnmadd231sd	xmm8, xmm10, xmm9 # xmm8 = -(xmm10 * xmm9) + xmm8
14000a314: c5 7b 11 84 24 68 03 00 00  	vmovsd	qword ptr [rsp + 0x368], xmm8
14000a31d: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a322: c5 7b 10 84 24 38 03 00 00  	vmovsd	xmm8, qword ptr [rsp + 0x338]
14000a32b: c4 42 a9 bd c1              	vfnmadd231sd	xmm8, xmm10, xmm9 # xmm8 = -(xmm10 * xmm9) + xmm8
14000a330: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a335: c4 41 2b 59 d1              	vmulsd	xmm10, xmm10, xmm9
14000a33a: c4 41 63 5c da              	vsubsd	xmm11, xmm3, xmm10
14000a33f: c5 7b 10 bb a0 00 00 00     	vmovsd	xmm15, qword ptr [rbx + 0xa0]
14000a347: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a34c: c5 fb 10 9c 24 40 03 00 00  	vmovsd	xmm3, qword ptr [rsp + 0x340]
14000a355: c4 c2 e9 b9 d9              	vfmadd231sd	xmm3, xmm2, xmm9 # xmm3 = (xmm2 * xmm9) + xmm3
14000a35a: c5 fb 11 9c 24 70 03 00 00  	vmovsd	qword ptr [rsp + 0x370], xmm3
14000a363: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a368: c5 fb 10 a4 24 48 03 00 00  	vmovsd	xmm4, qword ptr [rsp + 0x348]
14000a371: c4 c2 e9 b9 e1              	vfmadd231sd	xmm4, xmm2, xmm9 # xmm4 = (xmm2 * xmm9) + xmm4
14000a376: c5 fb 11 a4 24 78 03 00 00  	vmovsd	qword ptr [rsp + 0x378], xmm4
14000a37f: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a384: c4 62 e9 a9 cd              	vfmadd213sd	xmm9, xmm2, xmm5 # xmm9 = (xmm2 * xmm9) + xmm5
14000a389: c5 7b 11 8c 24 80 03 00 00  	vmovsd	qword ptr [rsp + 0x380], xmm9
14000a392: c5 fb 10 53 70              	vmovsd	xmm2, qword ptr [rbx + 0x70]
14000a397: c5 fb 10 9b e0 00 00 00     	vmovsd	xmm3, qword ptr [rbx + 0xe0]
14000a39f: c5 eb 5c d3                 	vsubsd	xmm2, xmm2, xmm3
14000a3a3: c5 fb 10 63 78              	vmovsd	xmm4, qword ptr [rbx + 0x78]
14000a3a8: c5 fb 10 ab e8 00 00 00     	vmovsd	xmm5, qword ptr [rbx + 0xe8]
14000a3b0: c5 db 5c e5                 	vsubsd	xmm4, xmm4, xmm5
14000a3b4: c5 fb 10 bb 80 00 00 00     	vmovsd	xmm7, qword ptr [rbx + 0x80]
14000a3bc: c5 7b 10 a4 24 68 03 00 00  	vmovsd	xmm12, qword ptr [rsp + 0x368]
14000a3c5: c4 c1 78 10 f0              	vmovups	xmm6, xmm8
14000a3ca: c5 7b 10 83 f0 00 00 00     	vmovsd	xmm8, qword ptr [rbx + 0xf0]
14000a3d2: c4 c1 43 5c f8              	vsubsd	xmm7, xmm7, xmm8
14000a3d7: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a3db: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a3e0: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a3e5: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a3ea: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a3ef: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
14000a3f4: c4 c1 78 10 cb              	vmovups	xmm1, xmm11
14000a3f9: c5 7b 10 9b 10 01 00 00     	vmovsd	xmm11, qword ptr [rbx + 0x110]
14000a401: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a406: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
14000a40b: c5 7b 11 a3 88 00 00 00     	vmovsd	qword ptr [rbx + 0x88], xmm12
14000a413: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a418: c4 c2 a9 bd f1              	vfnmadd231sd	xmm6, xmm10, xmm9 # xmm6 = -(xmm10 * xmm9) + xmm6
14000a41d: c5 fb 11 b3 90 00 00 00     	vmovsd	qword ptr [rbx + 0x90], xmm6
14000a425: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a42a: c4 c2 a9 bd c9              	vfnmadd231sd	xmm1, xmm10, xmm9 # xmm1 = -(xmm10 * xmm9) + xmm1
14000a42f: c5 fb 11 8b 98 00 00 00     	vmovsd	qword ptr [rbx + 0x98], xmm1
14000a437: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a43c: c4 42 e9 b9 e9              	vfmadd231sd	xmm13, xmm2, xmm9 # xmm13 = (xmm2 * xmm9) + xmm13
14000a441: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a446: c4 42 e9 b9 f1              	vfmadd231sd	xmm14, xmm2, xmm9 # xmm14 = (xmm2 * xmm9) + xmm14
14000a44b: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a450: c4 c2 e9 b9 c1              	vfmadd231sd	xmm0, xmm2, xmm9 # xmm0 = (xmm2 * xmm9) + xmm0
14000a455: c5 fb 10 93 a8 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0xa8]
14000a45d: c5 eb 5c d3                 	vsubsd	xmm2, xmm2, xmm3
14000a461: c5 fb 10 a3 b0 00 00 00     	vmovsd	xmm4, qword ptr [rbx + 0xb0]
14000a469: c5 db 5c e5                 	vsubsd	xmm4, xmm4, xmm5
14000a46d: c5 fb 10 bb b8 00 00 00     	vmovsd	xmm7, qword ptr [rbx + 0xb8]
14000a475: c4 c1 43 5c f8              	vsubsd	xmm7, xmm7, xmm8
14000a47a: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a47e: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a483: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a488: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a48d: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a492: c5 7b 10 bc 24 e8 02 00 00  	vmovsd	xmm15, qword ptr [rsp + 0x2e8]
14000a49b: c4 41 03 5e c9              	vdivsd	xmm9, xmm15, xmm9
14000a4a0: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a4a5: c5 7b 10 bc 24 70 03 00 00  	vmovsd	xmm15, qword ptr [rsp + 0x370]
14000a4ae: c4 42 a9 bd f9              	vfnmadd231sd	xmm15, xmm10, xmm9 # xmm15 = -(xmm10 * xmm9) + xmm15
14000a4b3: c5 7b 11 bc 24 88 03 00 00  	vmovsd	qword ptr [rsp + 0x388], xmm15
14000a4bc: c5 7b 11 bb c0 00 00 00     	vmovsd	qword ptr [rbx + 0xc0], xmm15
14000a4c4: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a4c9: c5 7b 10 bc 24 78 03 00 00  	vmovsd	xmm15, qword ptr [rsp + 0x378]
14000a4d2: c4 42 a9 bd f9              	vfnmadd231sd	xmm15, xmm10, xmm9 # xmm15 = -(xmm10 * xmm9) + xmm15
14000a4d7: c5 7b 11 bb c8 00 00 00     	vmovsd	qword ptr [rbx + 0xc8], xmm15
14000a4df: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a4e4: c4 62 b1 ad 94 24 80 03 00 00       	vfnmadd213sd	xmm10, xmm9, qword ptr [rsp + 0x380] # xmm10 = -(xmm9 * xmm10) + mem
14000a4ee: c5 7b 11 93 d0 00 00 00     	vmovsd	qword ptr [rbx + 0xd0], xmm10
14000a4f6: c5 7b 11 84 24 f0 02 00 00  	vmovsd	qword ptr [rsp + 0x2f0], xmm8
14000a4ff: c5 7b 10 84 24 88 03 00 00  	vmovsd	xmm8, qword ptr [rsp + 0x388]
14000a508: c4 41 78 10 df              	vmovups	xmm11, xmm15
14000a50d: c5 7b 10 bb d8 00 00 00     	vmovsd	xmm15, qword ptr [rbx + 0xd8]
14000a515: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a51a: c4 42 e9 b9 e9              	vfmadd231sd	xmm13, xmm2, xmm9 # xmm13 = (xmm2 * xmm9) + xmm13
14000a51f: c5 7b 11 ab f8 00 00 00     	vmovsd	qword ptr [rbx + 0xf8], xmm13
14000a527: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a52c: c4 c1 6b 59 d1              	vmulsd	xmm2, xmm2, xmm9
14000a531: c5 8b 58 e2                 	vaddsd	xmm4, xmm14, xmm2
14000a535: c5 fb 11 a3 00 01 00 00     	vmovsd	qword ptr [rbx + 0x100], xmm4
14000a53d: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a542: c4 c2 e9 b9 c1              	vfmadd231sd	xmm0, xmm2, xmm9 # xmm0 = (xmm2 * xmm9) + xmm0
14000a547: c5 fb 11 83 08 01 00 00     	vmovsd	qword ptr [rbx + 0x108], xmm0
14000a54f: c5 fb 10 3d 09 2d 00 00     	vmovsd	xmm7, qword ptr [rip + 0x2d09] # 0x14000d260
14000a557: c5 fb 10 94 24 18 03 00 00  	vmovsd	xmm2, qword ptr [rsp + 0x318]
14000a560: c5 7b 10 0b                 	vmovsd	xmm9, qword ptr [rbx]
14000a564: c4 62 e9 b9 cf              	vfmadd231sd	xmm9, xmm2, xmm7 # xmm9 = (xmm2 * xmm7) + xmm9
14000a569: c5 7b 11 0b                 	vmovsd	qword ptr [rbx], xmm9
14000a56d: c5 fb 10 94 24 20 03 00 00  	vmovsd	xmm2, qword ptr [rsp + 0x320]
14000a576: c5 7b 10 4b 08              	vmovsd	xmm9, qword ptr [rbx + 0x8]
14000a57b: c4 62 e9 b9 cf              	vfmadd231sd	xmm9, xmm2, xmm7 # xmm9 = (xmm2 * xmm7) + xmm9
14000a580: c5 7b 11 4b 08              	vmovsd	qword ptr [rbx + 0x8], xmm9
14000a585: c5 7b 10 b4 24 28 03 00 00  	vmovsd	xmm14, qword ptr [rsp + 0x328]
14000a58e: c5 7b 10 4b 10              	vmovsd	xmm9, qword ptr [rbx + 0x10]
14000a593: c4 62 89 b9 cf              	vfmadd231sd	xmm9, xmm14, xmm7 # xmm9 = (xmm14 * xmm7) + xmm9
14000a598: c5 7b 11 4b 10              	vmovsd	qword ptr [rbx + 0x10], xmm9
14000a59d: c5 fb 10 94 24 50 03 00 00  	vmovsd	xmm2, qword ptr [rsp + 0x350]
14000a5a6: c5 7b 10 4b 38              	vmovsd	xmm9, qword ptr [rbx + 0x38]
14000a5ab: c4 62 e9 b9 cf              	vfmadd231sd	xmm9, xmm2, xmm7 # xmm9 = (xmm2 * xmm7) + xmm9
14000a5b0: c5 7b 11 4b 38              	vmovsd	qword ptr [rbx + 0x38], xmm9
14000a5b5: c5 fb 10 94 24 58 03 00 00  	vmovsd	xmm2, qword ptr [rsp + 0x358]
14000a5be: c5 7b 10 4b 40              	vmovsd	xmm9, qword ptr [rbx + 0x40]
14000a5c3: c4 62 e9 b9 cf              	vfmadd231sd	xmm9, xmm2, xmm7 # xmm9 = (xmm2 * xmm7) + xmm9
14000a5c8: c5 7b 11 4b 40              	vmovsd	qword ptr [rbx + 0x40], xmm9
14000a5cd: c5 fb 10 94 24 60 03 00 00  	vmovsd	xmm2, qword ptr [rsp + 0x360]
14000a5d6: c5 7b 10 4b 48              	vmovsd	xmm9, qword ptr [rbx + 0x48]
14000a5db: c4 62 e9 b9 cf              	vfmadd231sd	xmm9, xmm2, xmm7 # xmm9 = (xmm2 * xmm7) + xmm9
14000a5e0: c5 7b 11 4b 48              	vmovsd	qword ptr [rbx + 0x48], xmm9
14000a5e5: c5 7b 10 4b 70              	vmovsd	xmm9, qword ptr [rbx + 0x70]
14000a5ea: c4 62 99 b9 cf              	vfmadd231sd	xmm9, xmm12, xmm7 # xmm9 = (xmm12 * xmm7) + xmm9
14000a5ef: c5 7b 11 4b 70              	vmovsd	qword ptr [rbx + 0x70], xmm9
14000a5f4: c5 cb 59 d7                 	vmulsd	xmm2, xmm6, xmm7
14000a5f8: c5 fb 10 73 78              	vmovsd	xmm6, qword ptr [rbx + 0x78]
14000a5fd: c5 cb 58 f2                 	vaddsd	xmm6, xmm6, xmm2
14000a601: c5 fb 11 73 78              	vmovsd	qword ptr [rbx + 0x78], xmm6
14000a606: c5 fb 10 93 80 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0x80]
14000a60e: c4 e2 f1 b9 d7              	vfmadd231sd	xmm2, xmm1, xmm7 # xmm2 = (xmm1 * xmm7) + xmm2
14000a613: c5 fb 11 93 80 00 00 00     	vmovsd	qword ptr [rbx + 0x80], xmm2
14000a61b: c5 fb 10 93 a8 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0xa8]
14000a623: c4 e2 b9 b9 d7              	vfmadd231sd	xmm2, xmm8, xmm7 # xmm2 = (xmm8 * xmm7) + xmm2
14000a628: c5 fb 11 93 a8 00 00 00     	vmovsd	qword ptr [rbx + 0xa8], xmm2
14000a630: c5 fb 10 93 b0 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0xb0]
14000a638: c4 e2 a1 b9 d7              	vfmadd231sd	xmm2, xmm11, xmm7 # xmm2 = (xmm11 * xmm7) + xmm2
14000a63d: c5 fb 11 93 b0 00 00 00     	vmovsd	qword ptr [rbx + 0xb0], xmm2
14000a645: c5 fb 10 93 b8 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0xb8]
14000a64d: c4 e2 a9 b9 d7              	vfmadd231sd	xmm2, xmm10, xmm7 # xmm2 = (xmm10 * xmm7) + xmm2
14000a652: c5 fb 11 93 b8 00 00 00     	vmovsd	qword ptr [rbx + 0xb8], xmm2
14000a65a: c5 93 59 cf                 	vmulsd	xmm1, xmm13, xmm7
14000a65e: c5 e3 58 c9                 	vaddsd	xmm1, xmm3, xmm1
14000a662: c5 fb 11 8b e0 00 00 00     	vmovsd	qword ptr [rbx + 0xe0], xmm1
14000a66a: c5 db 59 cf                 	vmulsd	xmm1, xmm4, xmm7
14000a66e: c5 d3 58 c9                 	vaddsd	xmm1, xmm5, xmm1
14000a672: c5 fb 11 8b e8 00 00 00     	vmovsd	qword ptr [rbx + 0xe8], xmm1
14000a67a: c4 e2 c1 a9 84 24 f0 02 00 00       	vfmadd213sd	xmm0, xmm7, qword ptr [rsp + 0x2f0] # xmm0 = (xmm7 * xmm0) + mem
14000a684: c5 fb 11 83 f0 00 00 00     	vmovsd	qword ptr [rbx + 0xf0], xmm0
14000a68c: 48 83 c0 01                 	add	rax, 0x1
14000a690: 48 81 f8 20 a1 07 00        	cmp	rax, 0x7a120
14000a697: 0f 8c d3 f6 ff ff           	jl	0x140009d70 <.text+0x8d70>
