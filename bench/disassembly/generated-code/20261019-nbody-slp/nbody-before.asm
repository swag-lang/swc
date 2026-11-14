140009d80: c5 fb 10 8c 24 e8 02 00 00  	vmovsd	xmm1, qword ptr [rsp + 0x2e8]
140009d89: c5 fb 10 13                 	vmovsd	xmm2, qword ptr [rbx]
140009d8d: c5 eb 5c 53 38              	vsubsd	xmm2, xmm2, qword ptr [rbx + 0x38]
140009d92: c5 fb 10 63 08              	vmovsd	xmm4, qword ptr [rbx + 0x8]
140009d97: c5 db 5c 63 40              	vsubsd	xmm4, xmm4, qword ptr [rbx + 0x40]
140009d9c: c5 fb 10 7b 10              	vmovsd	xmm7, qword ptr [rbx + 0x10]
140009da1: c5 c3 5c 7b 48              	vsubsd	xmm7, xmm7, qword ptr [rbx + 0x48]
140009da6: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
140009daa: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
140009daf: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
140009db4: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
140009db9: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
140009dbe: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
140009dc3: c5 7b 10 5b 68              	vmovsd	xmm11, qword ptr [rbx + 0x68]
140009dc8: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
140009dcd: c5 7b 10 63 18              	vmovsd	xmm12, qword ptr [rbx + 0x18]
140009dd2: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
140009dd7: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
140009ddc: c5 7b 10 6b 20              	vmovsd	xmm13, qword ptr [rbx + 0x20]
140009de1: c4 42 a9 bd e9              	vfnmadd231sd	xmm13, xmm10, xmm9 # xmm13 = -(xmm10 * xmm9) + xmm13
140009de6: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
140009deb: c5 7b 10 73 28              	vmovsd	xmm14, qword ptr [rbx + 0x28]
140009df0: c4 42 a9 bd f1              	vfnmadd231sd	xmm14, xmm10, xmm9 # xmm14 = -(xmm10 * xmm9) + xmm14
140009df5: c5 7b 10 7b 30              	vmovsd	xmm15, qword ptr [rbx + 0x30]
140009dfa: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
140009dff: c5 7b 10 5b 50              	vmovsd	xmm11, qword ptr [rbx + 0x50]
140009e04: c4 42 e9 b9 d9              	vfmadd231sd	xmm11, xmm2, xmm9 # xmm11 = (xmm2 * xmm9) + xmm11
140009e09: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
140009e0e: c5 7b 10 53 58              	vmovsd	xmm10, qword ptr [rbx + 0x58]
140009e13: c4 42 e9 b9 d1              	vfmadd231sd	xmm10, xmm2, xmm9 # xmm10 = (xmm2 * xmm9) + xmm10
140009e18: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
140009e1d: c4 c1 6b 59 d1              	vmulsd	xmm2, xmm2, xmm9
140009e22: c5 6b 58 43 60              	vaddsd	xmm8, xmm2, qword ptr [rbx + 0x60]
140009e27: c5 fb 10 13                 	vmovsd	xmm2, qword ptr [rbx]
140009e2b: c5 eb 5c 53 70              	vsubsd	xmm2, xmm2, qword ptr [rbx + 0x70]
140009e30: c5 fb 10 63 08              	vmovsd	xmm4, qword ptr [rbx + 0x8]
140009e35: c5 db 5c 63 78              	vsubsd	xmm4, xmm4, qword ptr [rbx + 0x78]
140009e3a: c5 fb 10 7b 10              	vmovsd	xmm7, qword ptr [rbx + 0x10]
140009e3f: c5 c3 5c bb 80 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0x80]
140009e47: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
140009e4b: c4 c1 78 10 ea              	vmovups	xmm5, xmm10
140009e50: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
140009e55: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
140009e5a: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
140009e5f: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
140009e64: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
140009e69: c4 c1 78 10 db              	vmovups	xmm3, xmm11
140009e6e: c5 7b 10 9b a0 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xa0]
140009e76: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
140009e7b: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
140009e80: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
140009e85: c4 42 a9 bd e9              	vfnmadd231sd	xmm13, xmm10, xmm9 # xmm13 = -(xmm10 * xmm9) + xmm13
140009e8a: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
140009e8f: c4 42 a9 bd f1              	vfnmadd231sd	xmm14, xmm10, xmm9 # xmm14 = -(xmm10 * xmm9) + xmm14
140009e94: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
140009e99: c5 7b 10 9b 88 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0x88]
140009ea1: c4 42 e9 b9 d9              	vfmadd231sd	xmm11, xmm2, xmm9 # xmm11 = (xmm2 * xmm9) + xmm11
140009ea6: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
140009eab: c5 7b 10 93 90 00 00 00     	vmovsd	xmm10, qword ptr [rbx + 0x90]
140009eb3: c4 42 e9 b9 d1              	vfmadd231sd	xmm10, xmm2, xmm9 # xmm10 = (xmm2 * xmm9) + xmm10
140009eb8: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
140009ebd: c4 e2 b1 a9 93 98 00 00 00  	vfmadd213sd	xmm2, xmm9, qword ptr [rbx + 0x98] # xmm2 = (xmm9 * xmm2) + mem
140009ec6: c5 78 10 ca                 	vmovups	xmm9, xmm2
140009eca: c5 fb 10 13                 	vmovsd	xmm2, qword ptr [rbx]
140009ece: c5 eb 5c 93 a8 00 00 00     	vsubsd	xmm2, xmm2, qword ptr [rbx + 0xa8]
140009ed6: c5 fb 10 63 08              	vmovsd	xmm4, qword ptr [rbx + 0x8]
140009edb: c5 db 5c a3 b0 00 00 00     	vsubsd	xmm4, xmm4, qword ptr [rbx + 0xb0]
140009ee3: c5 fb 10 7b 10              	vmovsd	xmm7, qword ptr [rbx + 0x10]
140009ee8: c4 c1 78 10 f0              	vmovups	xmm6, xmm8
140009eed: c5 c3 5c bb b8 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0xb8]
140009ef5: c4 41 78 10 c1              	vmovups	xmm8, xmm9
140009efa: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
140009efe: c5 7b 11 94 24 f8 02 00 00  	vmovsd	qword ptr [rsp + 0x2f8], xmm10
140009f07: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
140009f0c: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
140009f11: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
140009f16: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
140009f1b: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
140009f20: c4 c1 78 10 c3              	vmovups	xmm0, xmm11
140009f25: c5 7b 10 9b d8 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xd8]
140009f2d: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
140009f32: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
140009f37: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
140009f3c: c4 42 a9 bd e9              	vfnmadd231sd	xmm13, xmm10, xmm9 # xmm13 = -(xmm10 * xmm9) + xmm13
140009f41: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
140009f46: c4 42 a9 bd f1              	vfnmadd231sd	xmm14, xmm10, xmm9 # xmm14 = -(xmm10 * xmm9) + xmm14
140009f4b: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
140009f50: c5 7b 10 9b c0 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xc0]
140009f58: c4 42 e9 b9 d9              	vfmadd231sd	xmm11, xmm2, xmm9 # xmm11 = (xmm2 * xmm9) + xmm11
140009f5d: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
140009f62: c5 7b 10 93 c8 00 00 00     	vmovsd	xmm10, qword ptr [rbx + 0xc8]
140009f6a: c4 42 e9 b9 d1              	vfmadd231sd	xmm10, xmm2, xmm9 # xmm10 = (xmm2 * xmm9) + xmm10
140009f6f: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
140009f74: c4 e2 b1 a9 93 d0 00 00 00  	vfmadd213sd	xmm2, xmm9, qword ptr [rbx + 0xd0] # xmm2 = (xmm9 * xmm2) + mem
140009f7d: c5 78 10 ca                 	vmovups	xmm9, xmm2
140009f81: c5 fb 10 13                 	vmovsd	xmm2, qword ptr [rbx]
140009f85: c5 eb 5c 93 e0 00 00 00     	vsubsd	xmm2, xmm2, qword ptr [rbx + 0xe0]
140009f8d: c5 fb 10 63 08              	vmovsd	xmm4, qword ptr [rbx + 0x8]
140009f92: c5 db 5c a3 e8 00 00 00     	vsubsd	xmm4, xmm4, qword ptr [rbx + 0xe8]
140009f9a: c5 fb 10 7b 10              	vmovsd	xmm7, qword ptr [rbx + 0x10]
140009f9f: c5 7b 11 84 24 00 03 00 00  	vmovsd	qword ptr [rsp + 0x300], xmm8
140009fa8: c5 c3 5c bb f0 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0xf0]
140009fb0: c4 41 78 10 c1              	vmovups	xmm8, xmm9
140009fb5: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
140009fb9: c5 7b 11 94 24 10 03 00 00  	vmovsd	qword ptr [rsp + 0x310], xmm10
140009fc2: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
140009fc7: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
140009fcc: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
140009fd1: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
140009fd6: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
140009fdb: c5 7b 11 9c 24 08 03 00 00  	vmovsd	qword ptr [rsp + 0x308], xmm11
140009fe4: c5 7b 10 9b 10 01 00 00     	vmovsd	xmm11, qword ptr [rbx + 0x110]
140009fec: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
140009ff1: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
140009ff6: c5 7b 11 63 18              	vmovsd	qword ptr [rbx + 0x18], xmm12
140009ffb: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a000: c4 42 a9 bd e9              	vfnmadd231sd	xmm13, xmm10, xmm9 # xmm13 = -(xmm10 * xmm9) + xmm13
14000a005: c5 7b 11 6b 20              	vmovsd	qword ptr [rbx + 0x20], xmm13
14000a00a: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a00f: c4 42 a9 bd f1              	vfnmadd231sd	xmm14, xmm10, xmm9 # xmm14 = -(xmm10 * xmm9) + xmm14
14000a014: c5 7b 11 73 28              	vmovsd	qword ptr [rbx + 0x28], xmm14
14000a019: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a01e: c5 7b 10 9b f8 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xf8]
14000a026: c4 42 e9 b9 d9              	vfmadd231sd	xmm11, xmm2, xmm9 # xmm11 = (xmm2 * xmm9) + xmm11
14000a02b: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a030: c5 7b 10 93 00 01 00 00     	vmovsd	xmm10, qword ptr [rbx + 0x100]
14000a038: c4 42 e9 b9 d1              	vfmadd231sd	xmm10, xmm2, xmm9 # xmm10 = (xmm2 * xmm9) + xmm10
14000a03d: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a042: c5 7b 10 bb 08 01 00 00     	vmovsd	xmm15, qword ptr [rbx + 0x108]
14000a04a: c4 42 e9 b9 f9              	vfmadd231sd	xmm15, xmm2, xmm9 # xmm15 = (xmm2 * xmm9) + xmm15
14000a04f: c5 fb 10 53 38              	vmovsd	xmm2, qword ptr [rbx + 0x38]
14000a054: c5 78 10 cb                 	vmovups	xmm9, xmm3
14000a058: c5 eb 5c 53 70              	vsubsd	xmm2, xmm2, qword ptr [rbx + 0x70]
14000a05d: c5 fb 10 63 40              	vmovsd	xmm4, qword ptr [rbx + 0x40]
14000a062: c5 f8 10 dd                 	vmovups	xmm3, xmm5
14000a066: c5 db 5c 63 78              	vsubsd	xmm4, xmm4, qword ptr [rbx + 0x78]
14000a06b: c5 fb 10 7b 48              	vmovsd	xmm7, qword ptr [rbx + 0x48]
14000a070: c4 c1 78 10 e8              	vmovups	xmm5, xmm8
14000a075: c5 c3 5c bb 80 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0x80]
14000a07d: c4 41 78 10 c1              	vmovups	xmm8, xmm9
14000a082: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a086: c4 41 78 10 f2              	vmovups	xmm14, xmm10
14000a08b: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a090: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a095: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a09a: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a09f: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
14000a0a4: c4 41 78 10 eb              	vmovups	xmm13, xmm11
14000a0a9: c5 7b 10 9b a0 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xa0]
14000a0b1: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a0b6: c4 42 a9 bd c1              	vfnmadd231sd	xmm8, xmm10, xmm9 # xmm8 = -(xmm10 * xmm9) + xmm8
14000a0bb: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a0c0: c4 c2 a9 bd d9              	vfnmadd231sd	xmm3, xmm10, xmm9 # xmm3 = -(xmm10 * xmm9) + xmm3
14000a0c5: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a0ca: c4 c2 a9 bd f1              	vfnmadd231sd	xmm6, xmm10, xmm9 # xmm6 = -(xmm10 * xmm9) + xmm6
14000a0cf: c4 41 78 10 df              	vmovups	xmm11, xmm15
14000a0d4: c5 7b 10 7b 68              	vmovsd	xmm15, qword ptr [rbx + 0x68]
14000a0d9: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a0de: c4 c2 e9 b9 c1              	vfmadd231sd	xmm0, xmm2, xmm9 # xmm0 = (xmm2 * xmm9) + xmm0
14000a0e3: c5 fb 11 84 24 30 03 00 00  	vmovsd	qword ptr [rsp + 0x330], xmm0
14000a0ec: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a0f1: c4 c1 6b 59 d1              	vmulsd	xmm2, xmm2, xmm9
14000a0f6: c5 6b 58 94 24 f8 02 00 00  	vaddsd	xmm10, xmm2, qword ptr [rsp + 0x2f8]
14000a0ff: c5 7b 11 94 24 38 03 00 00  	vmovsd	qword ptr [rsp + 0x338], xmm10
14000a108: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a10d: c4 62 e9 a9 8c 24 00 03 00 00       	vfmadd213sd	xmm9, xmm2, qword ptr [rsp + 0x300] # xmm9 = (xmm2 * xmm9) + mem
14000a117: c5 fb 10 53 38              	vmovsd	xmm2, qword ptr [rbx + 0x38]
14000a11c: c5 f8 10 fb                 	vmovups	xmm7, xmm3
14000a120: c5 eb 5c 93 a8 00 00 00     	vsubsd	xmm2, xmm2, qword ptr [rbx + 0xa8]
14000a128: c5 fb 10 63 40              	vmovsd	xmm4, qword ptr [rbx + 0x40]
14000a12d: c5 f8 10 dd                 	vmovups	xmm3, xmm5
14000a131: c5 db 5c a3 b0 00 00 00     	vsubsd	xmm4, xmm4, qword ptr [rbx + 0xb0]
14000a139: c5 f8 10 ef                 	vmovups	xmm5, xmm7
14000a13d: c5 fb 10 7b 48              	vmovsd	xmm7, qword ptr [rbx + 0x48]
14000a142: c4 41 78 10 e0              	vmovups	xmm12, xmm8
14000a147: c5 c3 5c bb b8 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0xb8]
14000a14f: c4 41 78 10 c1              	vmovups	xmm8, xmm9
14000a154: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a158: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a15d: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a162: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a167: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a16c: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
14000a171: c4 c1 78 10 c3              	vmovups	xmm0, xmm11
14000a176: c5 7b 10 9b d8 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xd8]
14000a17e: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a183: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
14000a188: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a18d: c4 c2 a9 bd e9              	vfnmadd231sd	xmm5, xmm10, xmm9 # xmm5 = -(xmm10 * xmm9) + xmm5
14000a192: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a197: c4 c2 a9 bd f1              	vfnmadd231sd	xmm6, xmm10, xmm9 # xmm6 = -(xmm10 * xmm9) + xmm6
14000a19c: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a1a1: c5 7b 10 9c 24 08 03 00 00  	vmovsd	xmm11, qword ptr [rsp + 0x308]
14000a1aa: c4 42 e9 b9 d9              	vfmadd231sd	xmm11, xmm2, xmm9 # xmm11 = (xmm2 * xmm9) + xmm11
14000a1af: c5 7b 11 9c 24 40 03 00 00  	vmovsd	qword ptr [rsp + 0x340], xmm11
14000a1b8: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a1bd: c5 7b 10 94 24 10 03 00 00  	vmovsd	xmm10, qword ptr [rsp + 0x310]
14000a1c6: c4 42 e9 b9 d1              	vfmadd231sd	xmm10, xmm2, xmm9 # xmm10 = (xmm2 * xmm9) + xmm10
14000a1cb: c5 7b 11 94 24 48 03 00 00  	vmovsd	qword ptr [rsp + 0x348], xmm10
14000a1d4: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a1d9: c4 62 e9 a9 cb              	vfmadd213sd	xmm9, xmm2, xmm3 # xmm9 = (xmm2 * xmm9) + xmm3
14000a1de: c5 fb 10 53 38              	vmovsd	xmm2, qword ptr [rbx + 0x38]
14000a1e3: c5 eb 5c 93 e0 00 00 00     	vsubsd	xmm2, xmm2, qword ptr [rbx + 0xe0]
14000a1eb: c5 fb 10 63 40              	vmovsd	xmm4, qword ptr [rbx + 0x40]
14000a1f0: c5 f8 10 dd                 	vmovups	xmm3, xmm5
14000a1f4: c5 db 5c a3 e8 00 00 00     	vsubsd	xmm4, xmm4, qword ptr [rbx + 0xe8]
14000a1fc: c5 fb 10 7b 48              	vmovsd	xmm7, qword ptr [rbx + 0x48]
14000a201: c4 c1 78 10 e8              	vmovups	xmm5, xmm8
14000a206: c5 c3 5c bb f0 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0xf0]
14000a20e: c4 41 78 10 c1              	vmovups	xmm8, xmm9
14000a213: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a217: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a21c: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a221: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a226: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a22b: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
14000a230: c5 7b 10 9b 10 01 00 00     	vmovsd	xmm11, qword ptr [rbx + 0x110]
14000a238: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a23d: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
14000a242: c5 7b 11 63 50              	vmovsd	qword ptr [rbx + 0x50], xmm12
14000a247: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a24c: c4 c2 a9 bd d9              	vfnmadd231sd	xmm3, xmm10, xmm9 # xmm3 = -(xmm10 * xmm9) + xmm3
14000a251: c5 fb 11 5b 58              	vmovsd	qword ptr [rbx + 0x58], xmm3
14000a256: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a25b: c4 c2 a9 bd f1              	vfnmadd231sd	xmm6, xmm10, xmm9 # xmm6 = -(xmm10 * xmm9) + xmm6
14000a260: c5 fb 11 73 60              	vmovsd	qword ptr [rbx + 0x60], xmm6
14000a265: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a26a: c4 42 e9 b9 e9              	vfmadd231sd	xmm13, xmm2, xmm9 # xmm13 = (xmm2 * xmm9) + xmm13
14000a26f: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a274: c4 42 e9 b9 f1              	vfmadd231sd	xmm14, xmm2, xmm9 # xmm14 = (xmm2 * xmm9) + xmm14
14000a279: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a27e: c4 c2 e9 b9 c1              	vfmadd231sd	xmm0, xmm2, xmm9 # xmm0 = (xmm2 * xmm9) + xmm0
14000a283: c5 fb 10 53 70              	vmovsd	xmm2, qword ptr [rbx + 0x70]
14000a288: c5 eb 5c 93 a8 00 00 00     	vsubsd	xmm2, xmm2, qword ptr [rbx + 0xa8]
14000a290: c5 fb 10 63 78              	vmovsd	xmm4, qword ptr [rbx + 0x78]
14000a295: c5 f8 10 dd                 	vmovups	xmm3, xmm5
14000a299: c5 db 5c a3 b0 00 00 00     	vsubsd	xmm4, xmm4, qword ptr [rbx + 0xb0]
14000a2a1: c5 fb 10 bb 80 00 00 00     	vmovsd	xmm7, qword ptr [rbx + 0x80]
14000a2a9: c4 c1 78 10 e8              	vmovups	xmm5, xmm8
14000a2ae: c5 c3 5c bb b8 00 00 00     	vsubsd	xmm7, xmm7, qword ptr [rbx + 0xb8]
14000a2b6: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a2ba: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a2bf: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a2c4: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a2c9: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a2ce: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
14000a2d3: c5 7b 10 9b d8 00 00 00     	vmovsd	xmm11, qword ptr [rbx + 0xd8]
14000a2db: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a2e0: c5 7b 10 84 24 30 03 00 00  	vmovsd	xmm8, qword ptr [rsp + 0x330]
14000a2e9: c4 42 a9 bd c1              	vfnmadd231sd	xmm8, xmm10, xmm9 # xmm8 = -(xmm10 * xmm9) + xmm8
14000a2ee: c5 7b 11 84 24 68 03 00 00  	vmovsd	qword ptr [rsp + 0x368], xmm8
14000a2f7: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a2fc: c5 7b 10 84 24 38 03 00 00  	vmovsd	xmm8, qword ptr [rsp + 0x338]
14000a305: c4 42 a9 bd c1              	vfnmadd231sd	xmm8, xmm10, xmm9 # xmm8 = -(xmm10 * xmm9) + xmm8
14000a30a: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a30f: c4 41 2b 59 d1              	vmulsd	xmm10, xmm10, xmm9
14000a314: c4 41 63 5c da              	vsubsd	xmm11, xmm3, xmm10
14000a319: c5 7b 10 bb a0 00 00 00     	vmovsd	xmm15, qword ptr [rbx + 0xa0]
14000a321: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a326: c5 fb 10 9c 24 40 03 00 00  	vmovsd	xmm3, qword ptr [rsp + 0x340]
14000a32f: c4 c2 e9 b9 d9              	vfmadd231sd	xmm3, xmm2, xmm9 # xmm3 = (xmm2 * xmm9) + xmm3
14000a334: c5 fb 11 9c 24 70 03 00 00  	vmovsd	qword ptr [rsp + 0x370], xmm3
14000a33d: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a342: c5 fb 10 a4 24 48 03 00 00  	vmovsd	xmm4, qword ptr [rsp + 0x348]
14000a34b: c4 c2 e9 b9 e1              	vfmadd231sd	xmm4, xmm2, xmm9 # xmm4 = (xmm2 * xmm9) + xmm4
14000a350: c5 fb 11 a4 24 78 03 00 00  	vmovsd	qword ptr [rsp + 0x378], xmm4
14000a359: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a35e: c4 62 e9 a9 cd              	vfmadd213sd	xmm9, xmm2, xmm5 # xmm9 = (xmm2 * xmm9) + xmm5
14000a363: c5 7b 11 8c 24 80 03 00 00  	vmovsd	qword ptr [rsp + 0x380], xmm9
14000a36c: c5 fb 10 53 70              	vmovsd	xmm2, qword ptr [rbx + 0x70]
14000a371: c5 fb 10 9b e0 00 00 00     	vmovsd	xmm3, qword ptr [rbx + 0xe0]
14000a379: c5 eb 5c d3                 	vsubsd	xmm2, xmm2, xmm3
14000a37d: c5 fb 10 63 78              	vmovsd	xmm4, qword ptr [rbx + 0x78]
14000a382: c5 fb 10 ab e8 00 00 00     	vmovsd	xmm5, qword ptr [rbx + 0xe8]
14000a38a: c5 db 5c e5                 	vsubsd	xmm4, xmm4, xmm5
14000a38e: c5 fb 10 bb 80 00 00 00     	vmovsd	xmm7, qword ptr [rbx + 0x80]
14000a396: c5 7b 10 a4 24 68 03 00 00  	vmovsd	xmm12, qword ptr [rsp + 0x368]
14000a39f: c4 c1 78 10 f0              	vmovups	xmm6, xmm8
14000a3a4: c5 7b 10 83 f0 00 00 00     	vmovsd	xmm8, qword ptr [rbx + 0xf0]
14000a3ac: c4 c1 43 5c f8              	vsubsd	xmm7, xmm7, xmm8
14000a3b1: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a3b5: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a3ba: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a3bf: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a3c4: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a3c9: c4 41 73 5e c9              	vdivsd	xmm9, xmm1, xmm9
14000a3ce: c4 c1 78 10 cb              	vmovups	xmm1, xmm11
14000a3d3: c5 7b 10 9b 10 01 00 00     	vmovsd	xmm11, qword ptr [rbx + 0x110]
14000a3db: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a3e0: c4 42 a9 bd e1              	vfnmadd231sd	xmm12, xmm10, xmm9 # xmm12 = -(xmm10 * xmm9) + xmm12
14000a3e5: c5 7b 11 a3 88 00 00 00     	vmovsd	qword ptr [rbx + 0x88], xmm12
14000a3ed: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a3f2: c4 c2 a9 bd f1              	vfnmadd231sd	xmm6, xmm10, xmm9 # xmm6 = -(xmm10 * xmm9) + xmm6
14000a3f7: c5 fb 11 b3 90 00 00 00     	vmovsd	qword ptr [rbx + 0x90], xmm6
14000a3ff: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a404: c4 c2 a9 bd c9              	vfnmadd231sd	xmm1, xmm10, xmm9 # xmm1 = -(xmm10 * xmm9) + xmm1
14000a409: c5 fb 11 8b 98 00 00 00     	vmovsd	qword ptr [rbx + 0x98], xmm1
14000a411: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a416: c4 42 e9 b9 e9              	vfmadd231sd	xmm13, xmm2, xmm9 # xmm13 = (xmm2 * xmm9) + xmm13
14000a41b: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a420: c4 42 e9 b9 f1              	vfmadd231sd	xmm14, xmm2, xmm9 # xmm14 = (xmm2 * xmm9) + xmm14
14000a425: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a42a: c4 c2 e9 b9 c1              	vfmadd231sd	xmm0, xmm2, xmm9 # xmm0 = (xmm2 * xmm9) + xmm0
14000a42f: c5 fb 10 93 a8 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0xa8]
14000a437: c5 eb 5c d3                 	vsubsd	xmm2, xmm2, xmm3
14000a43b: c5 fb 10 a3 b0 00 00 00     	vmovsd	xmm4, qword ptr [rbx + 0xb0]
14000a443: c5 db 5c e5                 	vsubsd	xmm4, xmm4, xmm5
14000a447: c5 fb 10 bb b8 00 00 00     	vmovsd	xmm7, qword ptr [rbx + 0xb8]
14000a44f: c4 c1 43 5c f8              	vsubsd	xmm7, xmm7, xmm8
14000a454: c5 6b 59 ca                 	vmulsd	xmm9, xmm2, xmm2
14000a458: c4 62 d9 b9 cc              	vfmadd231sd	xmm9, xmm4, xmm4 # xmm9 = (xmm4 * xmm4) + xmm9
14000a45d: c4 62 c1 b9 cf              	vfmadd231sd	xmm9, xmm7, xmm7 # xmm9 = (xmm7 * xmm7) + xmm9
14000a462: c4 41 33 51 d1              	vsqrtsd	xmm10, xmm9, xmm9
14000a467: c4 41 33 59 ca              	vmulsd	xmm9, xmm9, xmm10
14000a46c: c5 7b 10 bc 24 e8 02 00 00  	vmovsd	xmm15, qword ptr [rsp + 0x2e8]
14000a475: c4 41 03 5e c9              	vdivsd	xmm9, xmm15, xmm9
14000a47a: c4 41 6b 59 d3              	vmulsd	xmm10, xmm2, xmm11
14000a47f: c5 7b 10 bc 24 70 03 00 00  	vmovsd	xmm15, qword ptr [rsp + 0x370]
14000a488: c4 42 a9 bd f9              	vfnmadd231sd	xmm15, xmm10, xmm9 # xmm15 = -(xmm10 * xmm9) + xmm15
14000a48d: c5 7b 11 bb c0 00 00 00     	vmovsd	qword ptr [rbx + 0xc0], xmm15
14000a495: c4 41 5b 59 d3              	vmulsd	xmm10, xmm4, xmm11
14000a49a: c5 7b 10 bc 24 78 03 00 00  	vmovsd	xmm15, qword ptr [rsp + 0x378]
14000a4a3: c4 42 a9 bd f9              	vfnmadd231sd	xmm15, xmm10, xmm9 # xmm15 = -(xmm10 * xmm9) + xmm15
14000a4a8: c5 7b 11 bb c8 00 00 00     	vmovsd	qword ptr [rbx + 0xc8], xmm15
14000a4b0: c4 41 43 59 d3              	vmulsd	xmm10, xmm7, xmm11
14000a4b5: c4 62 b1 ad 94 24 80 03 00 00       	vfnmadd213sd	xmm10, xmm9, qword ptr [rsp + 0x380] # xmm10 = -(xmm9 * xmm10) + mem
14000a4bf: c5 7b 11 93 d0 00 00 00     	vmovsd	qword ptr [rbx + 0xd0], xmm10
14000a4c7: c5 7b 11 84 24 f0 02 00 00  	vmovsd	qword ptr [rsp + 0x2f0], xmm8
14000a4d0: c5 7b 10 83 c0 00 00 00     	vmovsd	xmm8, qword ptr [rbx + 0xc0]
14000a4d8: c4 41 78 10 df              	vmovups	xmm11, xmm15
14000a4dd: c5 7b 10 bb d8 00 00 00     	vmovsd	xmm15, qword ptr [rbx + 0xd8]
14000a4e5: c4 c1 6b 59 d7              	vmulsd	xmm2, xmm2, xmm15
14000a4ea: c4 42 e9 b9 e9              	vfmadd231sd	xmm13, xmm2, xmm9 # xmm13 = (xmm2 * xmm9) + xmm13
14000a4ef: c5 7b 11 ab f8 00 00 00     	vmovsd	qword ptr [rbx + 0xf8], xmm13
14000a4f7: c4 c1 5b 59 d7              	vmulsd	xmm2, xmm4, xmm15
14000a4fc: c4 c1 6b 59 d1              	vmulsd	xmm2, xmm2, xmm9
14000a501: c5 8b 58 e2                 	vaddsd	xmm4, xmm14, xmm2
14000a505: c5 fb 11 a3 00 01 00 00     	vmovsd	qword ptr [rbx + 0x100], xmm4
14000a50d: c4 c1 43 59 d7              	vmulsd	xmm2, xmm7, xmm15
14000a512: c4 c2 e9 b9 c1              	vfmadd231sd	xmm0, xmm2, xmm9 # xmm0 = (xmm2 * xmm9) + xmm0
14000a517: c5 fb 11 83 08 01 00 00     	vmovsd	qword ptr [rbx + 0x108], xmm0
14000a51f: c5 fb 10 3d 39 2d 00 00     	vmovsd	xmm7, qword ptr [rip + 0x2d39] # 0x14000d260
14000a527: c5 fb 10 53 18              	vmovsd	xmm2, qword ptr [rbx + 0x18]
14000a52c: c5 7b 10 0b                 	vmovsd	xmm9, qword ptr [rbx]
14000a530: c4 62 e9 b9 cf              	vfmadd231sd	xmm9, xmm2, xmm7 # xmm9 = (xmm2 * xmm7) + xmm9
14000a535: c5 7b 11 0b                 	vmovsd	qword ptr [rbx], xmm9
14000a539: c5 fb 10 53 20              	vmovsd	xmm2, qword ptr [rbx + 0x20]
14000a53e: c5 7b 10 4b 08              	vmovsd	xmm9, qword ptr [rbx + 0x8]
14000a543: c4 62 e9 b9 cf              	vfmadd231sd	xmm9, xmm2, xmm7 # xmm9 = (xmm2 * xmm7) + xmm9
14000a548: c5 7b 11 4b 08              	vmovsd	qword ptr [rbx + 0x8], xmm9
14000a54d: c5 7b 10 73 28              	vmovsd	xmm14, qword ptr [rbx + 0x28]
14000a552: c5 7b 10 4b 10              	vmovsd	xmm9, qword ptr [rbx + 0x10]
14000a557: c4 62 89 b9 cf              	vfmadd231sd	xmm9, xmm14, xmm7 # xmm9 = (xmm14 * xmm7) + xmm9
14000a55c: c5 7b 11 4b 10              	vmovsd	qword ptr [rbx + 0x10], xmm9
14000a561: c5 fb 10 53 50              	vmovsd	xmm2, qword ptr [rbx + 0x50]
14000a566: c5 7b 10 4b 38              	vmovsd	xmm9, qword ptr [rbx + 0x38]
14000a56b: c4 62 e9 b9 cf              	vfmadd231sd	xmm9, xmm2, xmm7 # xmm9 = (xmm2 * xmm7) + xmm9
14000a570: c5 7b 11 4b 38              	vmovsd	qword ptr [rbx + 0x38], xmm9
14000a575: c5 fb 10 53 58              	vmovsd	xmm2, qword ptr [rbx + 0x58]
14000a57a: c5 7b 10 4b 40              	vmovsd	xmm9, qword ptr [rbx + 0x40]
14000a57f: c4 62 e9 b9 cf              	vfmadd231sd	xmm9, xmm2, xmm7 # xmm9 = (xmm2 * xmm7) + xmm9
14000a584: c5 7b 11 4b 40              	vmovsd	qword ptr [rbx + 0x40], xmm9
14000a589: c5 fb 10 53 60              	vmovsd	xmm2, qword ptr [rbx + 0x60]
14000a58e: c5 7b 10 4b 48              	vmovsd	xmm9, qword ptr [rbx + 0x48]
14000a593: c4 62 e9 b9 cf              	vfmadd231sd	xmm9, xmm2, xmm7 # xmm9 = (xmm2 * xmm7) + xmm9
14000a598: c5 7b 11 4b 48              	vmovsd	qword ptr [rbx + 0x48], xmm9
14000a59d: c5 7b 10 4b 70              	vmovsd	xmm9, qword ptr [rbx + 0x70]
14000a5a2: c4 62 99 b9 cf              	vfmadd231sd	xmm9, xmm12, xmm7 # xmm9 = (xmm12 * xmm7) + xmm9
14000a5a7: c5 7b 11 4b 70              	vmovsd	qword ptr [rbx + 0x70], xmm9
14000a5ac: c5 cb 59 d7                 	vmulsd	xmm2, xmm6, xmm7
14000a5b0: c5 fb 10 73 78              	vmovsd	xmm6, qword ptr [rbx + 0x78]
14000a5b5: c5 cb 58 f2                 	vaddsd	xmm6, xmm6, xmm2
14000a5b9: c5 fb 11 73 78              	vmovsd	qword ptr [rbx + 0x78], xmm6
14000a5be: c5 fb 10 93 80 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0x80]
14000a5c6: c4 e2 f1 b9 d7              	vfmadd231sd	xmm2, xmm1, xmm7 # xmm2 = (xmm1 * xmm7) + xmm2
14000a5cb: c5 fb 11 93 80 00 00 00     	vmovsd	qword ptr [rbx + 0x80], xmm2
14000a5d3: c5 fb 10 93 a8 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0xa8]
14000a5db: c4 e2 b9 b9 d7              	vfmadd231sd	xmm2, xmm8, xmm7 # xmm2 = (xmm8 * xmm7) + xmm2
14000a5e0: c5 fb 11 93 a8 00 00 00     	vmovsd	qword ptr [rbx + 0xa8], xmm2
14000a5e8: c5 fb 10 93 b0 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0xb0]
14000a5f0: c4 e2 a1 b9 d7              	vfmadd231sd	xmm2, xmm11, xmm7 # xmm2 = (xmm11 * xmm7) + xmm2
14000a5f5: c5 fb 11 93 b0 00 00 00     	vmovsd	qword ptr [rbx + 0xb0], xmm2
14000a5fd: c5 fb 10 93 b8 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0xb8]
14000a605: c4 e2 a9 b9 d7              	vfmadd231sd	xmm2, xmm10, xmm7 # xmm2 = (xmm10 * xmm7) + xmm2
14000a60a: c5 fb 11 93 b8 00 00 00     	vmovsd	qword ptr [rbx + 0xb8], xmm2
14000a612: c5 93 59 cf                 	vmulsd	xmm1, xmm13, xmm7
14000a616: c5 e3 58 c9                 	vaddsd	xmm1, xmm3, xmm1
14000a61a: c5 fb 11 8b e0 00 00 00     	vmovsd	qword ptr [rbx + 0xe0], xmm1
14000a622: c5 db 59 cf                 	vmulsd	xmm1, xmm4, xmm7
14000a626: c5 d3 58 c9                 	vaddsd	xmm1, xmm5, xmm1
14000a62a: c5 fb 11 8b e8 00 00 00     	vmovsd	qword ptr [rbx + 0xe8], xmm1
14000a632: c4 e2 c1 a9 84 24 f0 02 00 00       	vfmadd213sd	xmm0, xmm7, qword ptr [rsp + 0x2f0] # xmm0 = (xmm7 * xmm0) + mem
14000a63c: c5 fb 11 83 f0 00 00 00     	vmovsd	qword ptr [rbx + 0xf0], xmm0
14000a644: 48 83 c0 01                 	add	rax, 0x1
14000a648: 48 81 f8 20 a1 07 00        	cmp	rax, 0x7a120
14000a64f: 0f 8c 2b f7 ff ff           	jl	0x140009d80 <.text+0x8d80>
