140009eb0: c4 c1 78 10 d5              	vmovups	xmm2, xmm13
140009eb5: c5 f8 10 a4 24 20 03 00 00  	vmovups	xmm4, xmmword ptr [rsp + 0x320]
140009ebe: c5 f8 10 ac 24 30 03 00 00  	vmovups	xmm5, xmmword ptr [rsp + 0x330]
140009ec7: c5 f8 10 bc 24 40 03 00 00  	vmovups	xmm7, xmmword ptr [rsp + 0x340]
140009ed0: c4 41 78 10 d6              	vmovups	xmm10, xmm14
140009ed5: c5 78 11 9c 24 70 03 00 00  	vmovups	xmmword ptr [rsp + 0x370], xmm11
140009ede: c5 78 10 eb                 	vmovups	xmm13, xmm3
140009ee2: c5 f8 10 9c 24 10 03 00 00  	vmovups	xmm3, xmmword ptr [rsp + 0x310]
140009eeb: c4 41 09 57 f6              	vxorpd	xmm14, xmm14, xmm14
140009ef0: c5 63 5c f5                 	vsubsd	xmm14, xmm3, xmm5
140009ef4: c4 41 01 57 ff              	vxorpd	xmm15, xmm15, xmm15
140009ef9: c5 81 73 db 08              	vpsrldq	xmm15, xmm3, 0x8        # xmm15 = xmm3[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009efe: c5 c9 73 dd 08              	vpsrldq	xmm6, xmm5, 0x8         # xmm6 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009f03: c5 f8 11 b4 24 a0 03 00 00  	vmovups	xmmword ptr [rsp + 0x3a0], xmm6
140009f0c: c5 83 5c c6                 	vsubsd	xmm0, xmm15, xmm6
140009f10: c5 89 6c f0                 	vpunpcklqdq	xmm6, xmm14, xmm0 # xmm6 = xmm14[0],xmm0[0]
140009f14: c5 fb 10 6b 10              	vmovsd	xmm5, qword ptr [rbx + 0x10]
140009f19: c5 78 11 ac 24 90 03 00 00  	vmovups	xmmword ptr [rsp + 0x390], xmm13
140009f22: c5 fb 11 ac 24 b0 03 00 00  	vmovsd	qword ptr [rsp + 0x3b0], xmm5
140009f2b: c5 7b 10 6b 48              	vmovsd	xmm13, qword ptr [rbx + 0x48]
140009f30: c5 7b 11 ac 24 b8 03 00 00  	vmovsd	qword ptr [rsp + 0x3b8], xmm13
140009f39: c4 c1 53 5c cd              	vsubsd	xmm1, xmm5, xmm13
140009f3e: c4 41 11 57 ed              	vxorpd	xmm13, xmm13, xmm13
140009f43: c4 41 0b 59 ee              	vmulsd	xmm13, xmm14, xmm14
140009f48: c4 c2 f9 a9 c5              	vfmadd213sd	xmm0, xmm0, xmm13 # xmm0 = (xmm0 * xmm0) + xmm13
140009f4d: c4 e2 f1 b9 c1              	vfmadd231sd	xmm0, xmm1, xmm1 # xmm0 = (xmm1 * xmm1) + xmm0
140009f52: c4 41 63 5c e8              	vsubsd	xmm13, xmm3, xmm8
140009f57: c4 c1 21 73 d8 08           	vpsrldq	xmm11, xmm8, 0x8        # xmm11 = xmm8[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009f5d: c5 78 11 9c 24 c0 03 00 00  	vmovups	xmmword ptr [rsp + 0x3c0], xmm11
140009f66: c4 41 03 5c c3              	vsubsd	xmm8, xmm15, xmm11
140009f6b: c4 41 3b 59 d8              	vmulsd	xmm11, xmm8, xmm8
140009f70: c4 42 91 b9 dd              	vfmadd231sd	xmm11, xmm13, xmm13 # xmm11 = (xmm13 * xmm13) + xmm11
140009f75: c5 7b 10 b3 80 00 00 00     	vmovsd	xmm14, qword ptr [rbx + 0x80]
140009f7d: c5 7b 11 b4 24 d0 03 00 00  	vmovsd	qword ptr [rsp + 0x3d0], xmm14
140009f86: c4 41 53 5c e6              	vsubsd	xmm12, xmm5, xmm14
140009f8b: c4 42 99 b9 dc              	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
140009f90: c4 41 79 6c f3              	vpunpcklqdq	xmm14, xmm0, xmm11 # xmm14 = xmm0[0],xmm11[0]
140009f95: c4 41 79 51 f6              	vsqrtpd	xmm14, xmm14
140009f9a: c4 c1 7b 59 c6              	vmulsd	xmm0, xmm0, xmm14
140009f9f: c4 c1 09 73 de 08           	vpsrldq	xmm14, xmm14, 0x8       # xmm14 = xmm14[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009fa5: c4 41 23 59 de              	vmulsd	xmm11, xmm11, xmm14
140009faa: c4 c1 79 6c c3              	vpunpcklqdq	xmm0, xmm0, xmm11 # xmm0 = xmm0[0],xmm11[0]
140009faf: c5 e9 5e c0                 	vdivpd	xmm0, xmm2, xmm0
140009fb3: c5 79 70 d8 44              	vpshufd	xmm11, xmm0, 0x44       # xmm11 = xmm0[0,1,0,1]
140009fb8: c5 7b 10 74 24 68           	vmovsd	xmm14, qword ptr [rsp + 0x68]
140009fbe: c4 41 79 70 f6 44           	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140009fc4: c4 c1 49 59 d6              	vmulpd	xmm2, xmm6, xmm14
140009fc9: c5 78 11 b4 24 e0 03 00 00  	vmovups	xmmword ptr [rsp + 0x3e0], xmm14
140009fd2: c5 7b 10 73 68              	vmovsd	xmm14, qword ptr [rbx + 0x68]
140009fd7: c5 7b 11 b4 24 f0 03 00 00  	vmovsd	qword ptr [rsp + 0x3f0], xmm14
140009fe0: c4 e2 a1 ac d4              	vfnmadd213pd	xmm2, xmm11, xmm4 # xmm2 = -(xmm11 * xmm2) + xmm4
140009fe5: c4 c1 73 59 e6              	vmulsd	xmm4, xmm1, xmm14
140009fea: c4 e2 f9 ad 63 28           	vfnmadd213sd	xmm4, xmm0, qword ptr [rbx + 0x28] # xmm4 = -(xmm0 * xmm4) + mem
140009ff0: c5 7b 10 74 24 30           	vmovsd	xmm14, qword ptr [rsp + 0x30]
140009ff6: c4 41 79 70 f6 44           	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140009ffc: c4 c1 49 59 f6              	vmulpd	xmm6, xmm6, xmm14
14000a001: c4 c1 49 59 f3              	vmulpd	xmm6, xmm6, xmm11
14000a006: c5 7b 10 5b 30              	vmovsd	xmm11, qword ptr [rbx + 0x30]
14000a00b: c5 c1 58 f6                 	vaddpd	xmm6, xmm7, xmm6
14000a00f: c5 f8 11 b4 24 00 04 00 00  	vmovups	xmmword ptr [rsp + 0x400], xmm6
14000a018: c4 c1 73 59 cb              	vmulsd	xmm1, xmm1, xmm11
14000a01d: c4 e2 f9 a9 4b 60           	vfmadd213sd	xmm1, xmm0, qword ptr [rbx + 0x60] # xmm1 = (xmm0 * xmm1) + mem
14000a023: c5 fb 11 8c 24 10 04 00 00  	vmovsd	qword ptr [rsp + 0x410], xmm1
14000a02c: c4 c1 11 6c f8              	vpunpcklqdq	xmm7, xmm13, xmm8 # xmm7 = xmm13[0],xmm8[0]
14000a031: c4 41 41 59 c6              	vmulpd	xmm8, xmm7, xmm14
14000a036: c5 f9 73 d8 08              	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a03b: c5 79 70 e8 44              	vpshufd	xmm13, xmm0, 0x44       # xmm13 = xmm0[0,1,0,1]
14000a040: c4 41 39 59 c5              	vmulpd	xmm8, xmm8, xmm13
14000a045: c5 fb 10 8c 24 a0 00 00 00  	vmovsd	xmm1, qword ptr [rsp + 0xa0]
14000a04e: c5 f9 70 c9 44              	vpshufd	xmm1, xmm1, 0x44        # xmm1 = xmm1[0,1,0,1]
14000a053: c5 c1 59 f9                 	vmulpd	xmm7, xmm7, xmm1
14000a057: c4 c2 c1 bc d5              	vfnmadd231pd	xmm2, xmm7, xmm13 # xmm2 = -(xmm7 * xmm13) + xmm2
14000a05c: c5 7b 10 ab a0 00 00 00     	vmovsd	xmm13, qword ptr [rbx + 0xa0]
14000a064: c5 7b 11 ac 24 30 04 00 00  	vmovsd	qword ptr [rsp + 0x430], xmm13
14000a06d: c4 c1 1b 59 fd              	vmulsd	xmm7, xmm12, xmm13
14000a072: c5 c3 59 f8                 	vmulsd	xmm7, xmm7, xmm0
14000a076: c5 db 5c e7                 	vsubsd	xmm4, xmm4, xmm7
14000a07a: c4 c1 31 58 f8              	vaddpd	xmm7, xmm9, xmm8
14000a07f: c5 f8 11 bc 24 40 04 00 00  	vmovups	xmmword ptr [rsp + 0x440], xmm7
14000a088: c4 41 1b 59 c3              	vmulsd	xmm8, xmm12, xmm11
14000a08d: c5 bb 59 c0                 	vmulsd	xmm0, xmm8, xmm0
14000a091: c5 fb 58 83 98 00 00 00     	vaddsd	xmm0, xmm0, qword ptr [rbx + 0x98]
14000a099: c5 fb 11 84 24 50 04 00 00  	vmovsd	qword ptr [rsp + 0x450], xmm0
14000a0a2: c4 41 39 57 c0              	vxorpd	xmm8, xmm8, xmm8
14000a0a7: c4 41 63 5c c2              	vsubsd	xmm8, xmm3, xmm10
14000a0ac: c4 41 31 57 c9              	vxorpd	xmm9, xmm9, xmm9
14000a0b1: c4 c1 31 73 da 08           	vpsrldq	xmm9, xmm10, 0x8        # xmm9 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a0b7: c5 78 11 8c 24 60 04 00 00  	vmovups	xmmword ptr [rsp + 0x460], xmm9
14000a0c0: c4 41 03 5c e1              	vsubsd	xmm12, xmm15, xmm9
14000a0c5: c4 c1 39 6c c4              	vpunpcklqdq	xmm0, xmm8, xmm12 # xmm0 = xmm8[0],xmm12[0]
14000a0ca: c4 41 79 59 ee              	vmulpd	xmm13, xmm0, xmm14
14000a0cf: c5 fb 10 bb b8 00 00 00     	vmovsd	xmm7, qword ptr [rbx + 0xb8]
14000a0d7: c5 fb 11 bc 24 70 04 00 00  	vmovsd	qword ptr [rsp + 0x470], xmm7
14000a0e0: c5 d3 5c f7                 	vsubsd	xmm6, xmm5, xmm7
14000a0e4: c5 c1 57 ff                 	vxorpd	xmm7, xmm7, xmm7
14000a0e8: c4 c1 3b 59 f8              	vmulsd	xmm7, xmm8, xmm8
14000a0ed: c4 c2 99 b9 fc              	vfmadd231sd	xmm7, xmm12, xmm12 # xmm7 = (xmm12 * xmm12) + xmm7
14000a0f2: c4 e2 c9 b9 fe              	vfmadd231sd	xmm7, xmm6, xmm6 # xmm7 = (xmm6 * xmm6) + xmm7
14000a0f7: c4 41 39 57 c0              	vxorpd	xmm8, xmm8, xmm8
14000a0fc: c5 78 10 a4 24 80 03 00 00  	vmovups	xmm12, xmmword ptr [rsp + 0x380]
14000a105: c4 41 63 5c c4              	vsubsd	xmm8, xmm3, xmm12
14000a10a: c4 41 3b 59 c8              	vmulsd	xmm9, xmm8, xmm8
14000a10f: c4 c1 29 73 dc 08           	vpsrldq	xmm10, xmm12, 0x8       # xmm10 = xmm12[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a115: c5 78 11 94 24 80 04 00 00  	vmovups	xmmword ptr [rsp + 0x480], xmm10
14000a11e: c4 41 03 5c e2              	vsubsd	xmm12, xmm15, xmm10
14000a123: c4 42 99 b9 cc              	vfmadd231sd	xmm9, xmm12, xmm12 # xmm9 = (xmm12 * xmm12) + xmm9
14000a128: c5 7b 10 bb f0 00 00 00     	vmovsd	xmm15, qword ptr [rbx + 0xf0]
14000a130: c5 7b 11 bc 24 90 04 00 00  	vmovsd	qword ptr [rsp + 0x490], xmm15
14000a139: c4 41 53 5c d7              	vsubsd	xmm10, xmm5, xmm15
14000a13e: c4 c1 2b 59 ea              	vmulsd	xmm5, xmm10, xmm10
14000a143: c5 b3 58 ed                 	vaddsd	xmm5, xmm9, xmm5
14000a147: c5 41 6c cd                 	vpunpcklqdq	xmm9, xmm7, xmm5 # xmm9 = xmm7[0],xmm5[0]
14000a14b: c4 41 79 51 c9              	vsqrtpd	xmm9, xmm9
14000a150: c4 c1 43 59 f9              	vmulsd	xmm7, xmm7, xmm9
14000a155: c4 c1 31 73 d9 08           	vpsrldq	xmm9, xmm9, 0x8         # xmm9 = xmm9[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a15b: c4 c1 53 59 e9              	vmulsd	xmm5, xmm5, xmm9
14000a160: c5 c1 6c ed                 	vpunpcklqdq	xmm5, xmm7, xmm5 # xmm5 = xmm7[0],xmm5[0]
14000a164: c5 78 10 8c 24 00 03 00 00  	vmovups	xmm9, xmmword ptr [rsp + 0x300]
14000a16d: c5 b1 5e ed                 	vdivpd	xmm5, xmm9, xmm5
14000a171: c5 f9 70 fd 44              	vpshufd	xmm7, xmm5, 0x44        # xmm7 = xmm5[0,1,0,1]
14000a176: c5 11 59 ef                 	vmulpd	xmm13, xmm13, xmm7
14000a17a: c5 7b 10 bc 24 d8 00 00 00  	vmovsd	xmm15, qword ptr [rsp + 0xd8]
14000a183: c4 41 79 70 ff 44           	vpshufd	xmm15, xmm15, 0x44      # xmm15 = xmm15[0,1,0,1]
14000a189: c4 c1 79 59 c7              	vmulpd	xmm0, xmm0, xmm15
14000a18e: c4 e2 c1 ac c2              	vfnmadd213pd	xmm0, xmm7, xmm2 # xmm0 = -(xmm7 * xmm0) + xmm2
14000a193: c5 fb 10 93 d8 00 00 00     	vmovsd	xmm2, qword ptr [rbx + 0xd8]
14000a19b: c5 fb 11 94 24 b0 04 00 00  	vmovsd	qword ptr [rsp + 0x4b0], xmm2
14000a1a4: c5 cb 59 fa                 	vmulsd	xmm7, xmm6, xmm2
14000a1a8: c4 e2 d1 ad fc              	vfnmadd213sd	xmm7, xmm5, xmm4 # xmm7 = -(xmm5 * xmm7) + xmm4
14000a1ad: c5 f8 10 a4 24 70 03 00 00  	vmovups	xmm4, xmmword ptr [rsp + 0x370]
14000a1b6: c4 41 59 58 ed              	vaddpd	xmm13, xmm4, xmm13
14000a1bb: c4 c1 4b 59 e3              	vmulsd	xmm4, xmm6, xmm11
14000a1c0: c5 fb 10 b3 d0 00 00 00     	vmovsd	xmm6, qword ptr [rbx + 0xd0]
14000a1c8: c4 e2 d9 b9 f5              	vfmadd231sd	xmm6, xmm4, xmm5 # xmm6 = (xmm4 * xmm5) + xmm6
14000a1cd: c4 c1 39 6c e4              	vpunpcklqdq	xmm4, xmm8, xmm12 # xmm4 = xmm8[0],xmm12[0]
14000a1d2: c4 41 59 59 c6              	vmulpd	xmm8, xmm4, xmm14
14000a1d7: c5 d1 73 dd 08              	vpsrldq	xmm5, xmm5, 0x8         # xmm5 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a1dc: c5 79 70 e5 44              	vpshufd	xmm12, xmm5, 0x44       # xmm12 = xmm5[0,1,0,1]
14000a1e1: c4 41 39 59 c4              	vmulpd	xmm8, xmm8, xmm12
14000a1e6: c5 7b 10 b4 24 10 01 00 00  	vmovsd	xmm14, qword ptr [rsp + 0x110]
14000a1ef: c4 41 79 70 f6 44           	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
14000a1f5: c5 78 11 b4 24 c0 04 00 00  	vmovups	xmmword ptr [rsp + 0x4c0], xmm14
14000a1fe: c4 c1 59 59 e6              	vmulpd	xmm4, xmm4, xmm14
14000a203: c4 e2 99 ac e0              	vfnmadd213pd	xmm4, xmm12, xmm0 # xmm4 = -(xmm12 * xmm4) + xmm0
14000a208: c4 e2 d9 b8 9c 24 f0 02 00 00       	vfmadd231pd	xmm3, xmm4, xmmword ptr [rsp + 0x2f0] # xmm3 = (xmm4 * mem) + xmm3
14000a212: c5 7b 10 a3 10 01 00 00     	vmovsd	xmm12, qword ptr [rbx + 0x110]
14000a21a: c5 f8 11 9c 24 10 03 00 00  	vmovups	xmmword ptr [rsp + 0x310], xmm3
14000a223: c5 f8 10 9c 24 90 03 00 00  	vmovups	xmm3, xmmword ptr [rsp + 0x390]
14000a22c: c5 7b 11 a4 24 d0 04 00 00  	vmovsd	qword ptr [rsp + 0x4d0], xmm12
14000a235: c4 c1 61 58 d8              	vaddpd	xmm3, xmm3, xmm8
14000a23a: c5 f8 11 9c 24 e0 04 00 00  	vmovups	xmmword ptr [rsp + 0x4e0], xmm3
14000a243: c4 41 2b 59 c4              	vmulsd	xmm8, xmm10, xmm12
14000a248: c4 62 d1 ad c7              	vfnmadd213sd	xmm8, xmm5, xmm7 # xmm8 = -(xmm5 * xmm8) + xmm7
14000a24d: c5 7b 11 43 28              	vmovsd	qword ptr [rbx + 0x28], xmm8
14000a252: c4 c1 2b 59 fb              	vmulsd	xmm7, xmm10, xmm11
14000a257: c5 c3 59 ed                 	vmulsd	xmm5, xmm7, xmm5
14000a25b: c5 d3 58 ab 08 01 00 00     	vaddsd	xmm5, xmm5, qword ptr [rbx + 0x108]
14000a263: c5 fb 11 ac 24 f8 04 00 00  	vmovsd	qword ptr [rsp + 0x4f8], xmm5
14000a26c: c5 c1 57 ff                 	vxorpd	xmm7, xmm7, xmm7
14000a270: c5 78 10 94 24 30 03 00 00  	vmovups	xmm10, xmmword ptr [rsp + 0x330]
14000a279: c5 c1 57 ff                 	vxorpd	xmm7, xmm7, xmm7
14000a27d: c5 78 10 9c 24 50 03 00 00  	vmovups	xmm11, xmmword ptr [rsp + 0x350]
14000a286: c4 c1 2b 5c fb              	vsubsd	xmm7, xmm10, xmm11
14000a28b: c5 f8 11 a4 24 20 03 00 00  	vmovups	xmmword ptr [rsp + 0x320], xmm4
14000a294: c5 d9 57 e4                 	vxorpd	xmm4, xmm4, xmm4
14000a298: c5 78 10 84 24 a0 03 00 00  	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
14000a2a1: c5 f8 10 a4 24 c0 03 00 00  	vmovups	xmm4, xmmword ptr [rsp + 0x3c0]
14000a2aa: c5 bb 5c ec                 	vsubsd	xmm5, xmm8, xmm4
14000a2ae: c5 41 6c e5                 	vpunpcklqdq	xmm12, xmm7, xmm5 # xmm12 = xmm7[0],xmm5[0]
14000a2b2: c5 99 59 d9                 	vmulpd	xmm3, xmm12, xmm1
14000a2b6: c5 f8 11 8c 24 20 04 00 00  	vmovups	xmmword ptr [rsp + 0x420], xmm1
14000a2bf: c5 f8 10 8c 24 e0 03 00 00  	vmovups	xmm1, xmmword ptr [rsp + 0x3e0]
14000a2c8: c5 19 59 e1                 	vmulpd	xmm12, xmm12, xmm1
14000a2cc: c5 fb 10 84 24 b8 03 00 00  	vmovsd	xmm0, qword ptr [rsp + 0x3b8]
14000a2d5: c5 7b 5c 9c 24 d0 03 00 00  	vsubsd	xmm11, xmm0, qword ptr [rsp + 0x3d0]
14000a2de: c5 d9 57 e4                 	vxorpd	xmm4, xmm4, xmm4
14000a2e2: c5 c3 59 e7                 	vmulsd	xmm4, xmm7, xmm7
14000a2e6: c4 e2 d1 b9 e5              	vfmadd231sd	xmm4, xmm5, xmm5 # xmm4 = (xmm5 * xmm5) + xmm4
14000a2eb: c4 c2 a1 b9 e3              	vfmadd231sd	xmm4, xmm11, xmm11 # xmm4 = (xmm11 * xmm11) + xmm4
14000a2f0: c5 f8 10 ac 24 60 03 00 00  	vmovups	xmm5, xmmword ptr [rsp + 0x360]
14000a2f9: c5 ab 5c fd                 	vsubsd	xmm7, xmm10, xmm5
14000a2fd: c5 c3 59 ef                 	vmulsd	xmm5, xmm7, xmm7
14000a301: c5 78 10 b4 24 60 04 00 00  	vmovups	xmm14, xmmword ptr [rsp + 0x460]
14000a30a: c4 41 3b 5c d6              	vsubsd	xmm10, xmm8, xmm14
14000a30f: c4 c2 a9 b9 ea              	vfmadd231sd	xmm5, xmm10, xmm10 # xmm5 = (xmm10 * xmm10) + xmm5
14000a314: c5 7b 5c 84 24 70 04 00 00  	vsubsd	xmm8, xmm0, qword ptr [rsp + 0x470]
14000a31d: c4 c2 b9 b9 e8              	vfmadd231sd	xmm5, xmm8, xmm8 # xmm5 = (xmm8 * xmm8) + xmm5
14000a322: c5 59 6c f5                 	vpunpcklqdq	xmm14, xmm4, xmm5 # xmm14 = xmm4[0],xmm5[0]
14000a326: c4 41 79 51 f6              	vsqrtpd	xmm14, xmm14
14000a32b: c4 c1 5b 59 e6              	vmulsd	xmm4, xmm4, xmm14
14000a330: c4 c1 09 73 de 08           	vpsrldq	xmm14, xmm14, 0x8       # xmm14 = xmm14[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a336: c4 c1 53 59 ee              	vmulsd	xmm5, xmm5, xmm14
14000a33b: c5 d9 6c e5                 	vpunpcklqdq	xmm4, xmm4, xmm5 # xmm4 = xmm4[0],xmm5[0]
14000a33f: c5 b1 5e e4                 	vdivpd	xmm4, xmm9, xmm4
14000a343: c5 f9 70 ec 44              	vpshufd	xmm5, xmm4, 0x44        # xmm5 = xmm4[0,1,0,1]
14000a348: c4 e2 d1 ac 9c 24 00 04 00 00       	vfnmadd213pd	xmm3, xmm5, xmmword ptr [rsp + 0x400] # xmm3 = -(xmm5 * xmm3) + mem
14000a352: c5 99 59 ed                 	vmulpd	xmm5, xmm12, xmm5
14000a356: c5 78 10 a4 24 40 04 00 00  	vmovups	xmm12, xmmword ptr [rsp + 0x440]
14000a35f: c5 99 58 ed                 	vaddpd	xmm5, xmm12, xmm5
14000a363: c5 7b 10 a4 24 30 04 00 00  	vmovsd	xmm12, qword ptr [rsp + 0x430]
14000a36c: c5 f8 11 ac 24 00 05 00 00  	vmovups	xmmword ptr [rsp + 0x500], xmm5
14000a375: c4 41 23 59 f4              	vmulsd	xmm14, xmm11, xmm12
14000a37a: c5 7b 10 a4 24 10 04 00 00  	vmovsd	xmm12, qword ptr [rsp + 0x410]
14000a383: c4 62 89 bd e4              	vfnmadd231sd	xmm12, xmm14, xmm4 # xmm12 = -(xmm14 * xmm4) + xmm12
14000a388: c5 7b 10 b4 24 f0 03 00 00  	vmovsd	xmm14, qword ptr [rsp + 0x3f0]
14000a391: c4 c1 23 59 ee              	vmulsd	xmm5, xmm11, xmm14
14000a396: c4 e2 d9 a9 ac 24 50 04 00 00       	vfmadd213sd	xmm5, xmm4, qword ptr [rsp + 0x450] # xmm5 = (xmm4 * xmm5) + mem
14000a3a0: c5 fb 11 ac 24 10 05 00 00  	vmovsd	qword ptr [rsp + 0x510], xmm5
14000a3a9: c4 c1 41 6c fa              	vpunpcklqdq	xmm7, xmm7, xmm10 # xmm7 = xmm7[0],xmm10[0]
14000a3ae: c4 41 41 59 d7              	vmulpd	xmm10, xmm7, xmm15
14000a3b3: c5 c1 59 f9                 	vmulpd	xmm7, xmm7, xmm1
14000a3b7: c5 d9 73 dc 08              	vpsrldq	xmm4, xmm4, 0x8         # xmm4 = xmm4[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a3bc: c5 79 70 dc 44              	vpshufd	xmm11, xmm4, 0x44       # xmm11 = xmm4[0,1,0,1]
14000a3c1: c4 41 29 59 d3              	vmulpd	xmm10, xmm10, xmm11
14000a3c6: c4 c1 61 5c da              	vsubpd	xmm3, xmm3, xmm10
14000a3cb: c4 c1 41 59 fb              	vmulpd	xmm7, xmm7, xmm11
14000a3d0: c5 11 58 d7                 	vaddpd	xmm10, xmm13, xmm7
14000a3d4: c5 78 11 94 24 20 05 00 00  	vmovups	xmmword ptr [rsp + 0x520], xmm10
14000a3dd: c5 bb 59 fa                 	vmulsd	xmm7, xmm8, xmm2
14000a3e1: c5 c3 59 fc                 	vmulsd	xmm7, xmm7, xmm4
14000a3e5: c5 1b 5c df                 	vsubsd	xmm11, xmm12, xmm7
14000a3e9: c4 c1 3b 59 fe              	vmulsd	xmm7, xmm8, xmm14
14000a3ee: c5 c3 59 e4                 	vmulsd	xmm4, xmm7, xmm4
14000a3f2: c5 cb 58 e4                 	vaddsd	xmm4, xmm6, xmm4
14000a3f6: c5 f8 10 b4 24 30 03 00 00  	vmovups	xmm6, xmmword ptr [rsp + 0x330]
14000a3ff: c5 78 10 a4 24 80 03 00 00  	vmovups	xmm12, xmmword ptr [rsp + 0x380]
14000a408: c5 fb 11 a4 24 30 05 00 00  	vmovsd	qword ptr [rsp + 0x530], xmm4
14000a411: c4 c1 4b 5c fc              	vsubsd	xmm7, xmm6, xmm12
14000a416: c4 41 39 57 c0              	vxorpd	xmm8, xmm8, xmm8
14000a41b: c5 78 10 84 24 a0 03 00 00  	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
14000a424: c5 78 10 ac 24 80 04 00 00  	vmovups	xmm13, xmmword ptr [rsp + 0x480]
14000a42d: c4 41 3b 5c c5              	vsubsd	xmm8, xmm8, xmm13
14000a432: c4 41 41 6c e8              	vpunpcklqdq	xmm13, xmm7, xmm8 # xmm13 = xmm7[0],xmm8[0]
14000a437: c5 78 10 a4 24 c0 04 00 00  	vmovups	xmm12, xmmword ptr [rsp + 0x4c0]
14000a440: c4 c1 11 59 e4              	vmulpd	xmm4, xmm13, xmm12
14000a445: c5 91 59 c9                 	vmulpd	xmm1, xmm13, xmm1
14000a449: c5 7b 5c a4 24 90 04 00 00  	vsubsd	xmm12, xmm0, qword ptr [rsp + 0x490]
14000a452: c5 f9 57 c0                 	vxorpd	xmm0, xmm0, xmm0
14000a456: c5 c3 59 c7                 	vmulsd	xmm0, xmm7, xmm7
14000a45a: c4 c2 b9 b9 c0              	vfmadd231sd	xmm0, xmm8, xmm8 # xmm0 = (xmm8 * xmm8) + xmm0
14000a45f: c4 c2 99 b9 c4              	vfmadd231sd	xmm0, xmm12, xmm12 # xmm0 = (xmm12 * xmm12) + xmm0
14000a464: c5 78 10 84 24 60 03 00 00  	vmovups	xmm8, xmmword ptr [rsp + 0x360]
14000a46d: c5 f8 10 bc 24 50 03 00 00  	vmovups	xmm7, xmmword ptr [rsp + 0x350]
14000a476: c4 41 43 5c e8              	vsubsd	xmm13, xmm7, xmm8
14000a47b: c4 c1 13 59 fd              	vmulsd	xmm7, xmm13, xmm13
14000a480: c5 78 10 84 24 60 04 00 00  	vmovups	xmm8, xmmword ptr [rsp + 0x460]
14000a489: c5 f8 10 ac 24 c0 03 00 00  	vmovups	xmm5, xmmword ptr [rsp + 0x3c0]
14000a492: c4 c1 53 5c d0              	vsubsd	xmm2, xmm5, xmm8
14000a497: c4 e2 e9 b9 fa              	vfmadd231sd	xmm7, xmm2, xmm2 # xmm7 = (xmm2 * xmm2) + xmm7
14000a49c: c5 7b 10 84 24 d0 03 00 00  	vmovsd	xmm8, qword ptr [rsp + 0x3d0]
14000a4a5: c5 3b 5c 94 24 70 04 00 00  	vsubsd	xmm10, xmm8, qword ptr [rsp + 0x470]
14000a4ae: c4 c1 2b 59 ea              	vmulsd	xmm5, xmm10, xmm10
14000a4b3: c5 c3 58 ed                 	vaddsd	xmm5, xmm7, xmm5
14000a4b7: c5 f9 6c fd                 	vpunpcklqdq	xmm7, xmm0, xmm5 # xmm7 = xmm0[0],xmm5[0]
14000a4bb: c5 f9 51 ff                 	vsqrtpd	xmm7, xmm7
14000a4bf: c5 fb 59 c7                 	vmulsd	xmm0, xmm0, xmm7
14000a4c3: c5 c1 73 df 08              	vpsrldq	xmm7, xmm7, 0x8         # xmm7 = xmm7[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a4c8: c5 d3 59 ef                 	vmulsd	xmm5, xmm5, xmm7
14000a4cc: c5 f9 6c c5                 	vpunpcklqdq	xmm0, xmm0, xmm5 # xmm0 = xmm0[0],xmm5[0]
14000a4d0: c5 b1 5e c0                 	vdivpd	xmm0, xmm9, xmm0
14000a4d4: c5 f9 70 e8 44              	vpshufd	xmm5, xmm0, 0x44        # xmm5 = xmm0[0,1,0,1]
14000a4d9: c5 d9 59 e5                 	vmulpd	xmm4, xmm4, xmm5
14000a4dd: c5 78 10 84 24 50 03 00 00  	vmovups	xmm8, xmmword ptr [rsp + 0x350]
14000a4e6: c5 e1 5c fc                 	vsubpd	xmm7, xmm3, xmm4
14000a4ea: c5 f8 10 a4 24 f0 02 00 00  	vmovups	xmm4, xmmword ptr [rsp + 0x2f0]
14000a4f3: c4 e2 c1 b8 f4              	vfmadd231pd	xmm6, xmm7, xmm4 # xmm6 = (xmm7 * xmm4) + xmm6
14000a4f8: c5 f8 11 b4 24 30 03 00 00  	vmovups	xmmword ptr [rsp + 0x330], xmm6
14000a501: c4 e2 d1 a8 8c 24 e0 04 00 00       	vfmadd213pd	xmm1, xmm5, xmmword ptr [rsp + 0x4e0] # xmm1 = (xmm5 * xmm1) + mem
14000a50b: c5 fb 10 ac 24 d0 04 00 00  	vmovsd	xmm5, qword ptr [rsp + 0x4d0]
14000a514: c5 9b 59 dd                 	vmulsd	xmm3, xmm12, xmm5
14000a518: c4 62 e1 bd d8              	vfnmadd231sd	xmm11, xmm3, xmm0 # xmm11 = -(xmm3 * xmm0) + xmm11
14000a51d: c5 7b 11 5b 60              	vmovsd	qword ptr [rbx + 0x60], xmm11
14000a522: c4 c1 1b 59 de              	vmulsd	xmm3, xmm12, xmm14
14000a527: c5 e3 59 d8                 	vmulsd	xmm3, xmm3, xmm0
14000a52b: c5 7b 10 a4 24 f8 04 00 00  	vmovsd	xmm12, qword ptr [rsp + 0x4f8]
14000a534: c5 9b 58 db                 	vaddsd	xmm3, xmm12, xmm3
14000a538: c5 fb 11 9c 24 40 05 00 00  	vmovsd	qword ptr [rsp + 0x540], xmm3
14000a541: c4 41 19 57 e4              	vxorpd	xmm12, xmm12, xmm12
14000a546: c5 91 6c d2                 	vpunpcklqdq	xmm2, xmm13, xmm2 # xmm2 = xmm13[0],xmm2[0]
14000a54a: c4 41 69 59 e7              	vmulpd	xmm12, xmm2, xmm15
14000a54f: c5 78 10 ac 24 20 04 00 00  	vmovups	xmm13, xmmword ptr [rsp + 0x420]
14000a558: c4 c1 69 59 d5              	vmulpd	xmm2, xmm2, xmm13
14000a55d: c5 f9 73 d8 08              	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a562: c5 79 70 f0 44              	vpshufd	xmm14, xmm0, 0x44       # xmm14 = xmm0[0,1,0,1]
14000a567: c5 f8 10 b4 24 00 05 00 00  	vmovups	xmm6, xmmword ptr [rsp + 0x500]
14000a570: c4 c2 99 bc f6              	vfnmadd231pd	xmm6, xmm12, xmm14 # xmm6 = -(xmm12 * xmm14) + xmm6
14000a575: c4 e2 89 a8 94 24 20 05 00 00       	vfmadd213pd	xmm2, xmm14, xmmword ptr [rsp + 0x520] # xmm2 = (xmm14 * xmm2) + mem
14000a57f: c5 7b 10 a4 24 b0 04 00 00  	vmovsd	xmm12, qword ptr [rsp + 0x4b0]
14000a588: c5 f8 11 94 24 50 05 00 00  	vmovups	xmmword ptr [rsp + 0x550], xmm2
14000a591: c4 41 2b 59 f4              	vmulsd	xmm14, xmm10, xmm12
14000a596: c5 f8 11 bc 24 40 03 00 00  	vmovups	xmmword ptr [rsp + 0x340], xmm7
14000a59f: c5 fb 10 bc 24 10 05 00 00  	vmovsd	xmm7, qword ptr [rsp + 0x510]
14000a5a8: c4 e2 89 bd f8              	vfnmadd231sd	xmm7, xmm14, xmm0 # xmm7 = -(xmm14 * xmm0) + xmm7
14000a5ad: c5 2b 59 94 24 30 04 00 00  	vmulsd	xmm10, xmm10, qword ptr [rsp + 0x430]
14000a5b6: c5 ab 59 c0                 	vmulsd	xmm0, xmm10, xmm0
14000a5ba: c5 fb 58 84 24 30 05 00 00  	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x530]
14000a5c3: c5 fb 11 84 24 60 05 00 00  	vmovsd	qword ptr [rsp + 0x560], xmm0
14000a5cc: c5 78 10 94 24 80 03 00 00  	vmovups	xmm10, xmmword ptr [rsp + 0x380]
14000a5d5: c4 41 3b 5c da              	vsubsd	xmm11, xmm8, xmm10
14000a5da: c4 41 19 57 e4              	vxorpd	xmm12, xmm12, xmm12
14000a5df: c5 78 10 a4 24 c0 03 00 00  	vmovups	xmm12, xmmword ptr [rsp + 0x3c0]
14000a5e8: c5 f8 10 84 24 80 04 00 00  	vmovups	xmm0, xmmword ptr [rsp + 0x480]
14000a5f1: c5 1b 5c e0                 	vsubsd	xmm12, xmm12, xmm0
14000a5f5: c4 c1 21 6c d4              	vpunpcklqdq	xmm2, xmm11, xmm12 # xmm2 = xmm11[0],xmm12[0]
14000a5fa: c5 78 11 bc 24 a0 04 00 00  	vmovups	xmmword ptr [rsp + 0x4a0], xmm15
14000a603: c5 78 10 bc 24 c0 04 00 00  	vmovups	xmm15, xmmword ptr [rsp + 0x4c0]
14000a60c: c4 c1 69 59 df              	vmulpd	xmm3, xmm2, xmm15
14000a611: c4 c1 69 59 d5              	vmulpd	xmm2, xmm2, xmm13
14000a616: c5 7b 10 ac 24 90 04 00 00  	vmovsd	xmm13, qword ptr [rsp + 0x490]
14000a61f: c5 7b 10 bc 24 d0 03 00 00  	vmovsd	xmm15, qword ptr [rsp + 0x3d0]
14000a628: c4 41 03 5c f5              	vsubsd	xmm14, xmm15, xmm13
14000a62d: c4 41 01 57 ff              	vxorpd	xmm15, xmm15, xmm15
14000a632: c4 41 23 59 db              	vmulsd	xmm11, xmm11, xmm11
14000a637: c4 42 99 b9 dc              	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
14000a63c: c4 42 89 b9 de              	vfmadd231sd	xmm11, xmm14, xmm14 # xmm11 = (xmm14 * xmm14) + xmm11
14000a641: c5 78 10 a4 24 60 03 00 00  	vmovups	xmm12, xmmword ptr [rsp + 0x360]
14000a64a: c4 41 1b 5c fa              	vsubsd	xmm15, xmm12, xmm10
14000a64f: c5 7b 11 bc 24 68 05 00 00  	vmovsd	qword ptr [rsp + 0x568], xmm15
14000a658: c4 41 03 59 d7              	vmulsd	xmm10, xmm15, xmm15
14000a65d: c5 78 10 a4 24 60 04 00 00  	vmovups	xmm12, xmmword ptr [rsp + 0x460]
14000a666: c5 9b 5c c0                 	vsubsd	xmm0, xmm12, xmm0
14000a66a: c4 62 f9 b9 d0              	vfmadd231sd	xmm10, xmm0, xmm0 # xmm10 = (xmm0 * xmm0) + xmm10
14000a66f: c5 7b 10 a4 24 70 04 00 00  	vmovsd	xmm12, qword ptr [rsp + 0x470]
14000a678: c4 41 1b 5c fd              	vsubsd	xmm15, xmm12, xmm13
14000a67d: c4 42 81 b9 d7              	vfmadd231sd	xmm10, xmm15, xmm15 # xmm10 = (xmm15 * xmm15) + xmm10
14000a682: c4 41 21 6c ea              	vpunpcklqdq	xmm13, xmm11, xmm10 # xmm13 = xmm11[0],xmm10[0]
14000a687: c4 41 79 51 ed              	vsqrtpd	xmm13, xmm13
14000a68c: c4 41 23 59 dd              	vmulsd	xmm11, xmm11, xmm13
14000a691: c4 c1 11 73 dd 08           	vpsrldq	xmm13, xmm13, 0x8       # xmm13 = xmm13[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a697: c4 41 2b 59 d5              	vmulsd	xmm10, xmm10, xmm13
14000a69c: c4 41 21 6c d2              	vpunpcklqdq	xmm10, xmm11, xmm10 # xmm10 = xmm11[0],xmm10[0]
14000a6a1: c4 41 31 5e d2              	vdivpd	xmm10, xmm9, xmm10
14000a6a6: c4 41 79 70 da 44           	vpshufd	xmm11, xmm10, 0x44      # xmm11 = xmm10[0,1,0,1]
14000a6ac: c4 c1 61 59 db              	vmulpd	xmm3, xmm3, xmm11
14000a6b1: c4 41 78 10 e9              	vmovups	xmm13, xmm9
14000a6b6: c5 49 5c cb                 	vsubpd	xmm9, xmm6, xmm3
14000a6ba: c4 62 b1 b8 c4              	vfmadd231pd	xmm8, xmm9, xmm4 # xmm8 = (xmm9 * xmm4) + xmm8
14000a6bf: c5 78 11 84 24 50 03 00 00  	vmovups	xmmword ptr [rsp + 0x350], xmm8
14000a6c8: c4 c2 e9 b8 cb              	vfmadd231pd	xmm1, xmm2, xmm11 # xmm1 = (xmm2 * xmm11) + xmm1
14000a6cd: c5 8b 59 d5                 	vmulsd	xmm2, xmm14, xmm5
14000a6d1: c4 e2 a9 ad d7              	vfnmadd213sd	xmm2, xmm10, xmm7 # xmm2 = -(xmm10 * xmm2) + xmm7
14000a6d6: c5 fb 11 93 98 00 00 00     	vmovsd	qword ptr [rbx + 0x98], xmm2
14000a6de: c5 fb 10 9c 24 30 04 00 00  	vmovsd	xmm3, qword ptr [rsp + 0x430]
14000a6e7: c5 8b 59 db                 	vmulsd	xmm3, xmm14, xmm3
14000a6eb: c5 fb 10 b4 24 40 05 00 00  	vmovsd	xmm6, qword ptr [rsp + 0x540]
14000a6f4: c4 c2 e1 b9 f2              	vfmadd231sd	xmm6, xmm3, xmm10 # xmm6 = (xmm3 * xmm10) + xmm6
14000a6f9: c5 fb 10 9c 24 68 05 00 00  	vmovsd	xmm3, qword ptr [rsp + 0x568]
14000a702: c5 e1 6c c0                 	vpunpcklqdq	xmm0, xmm3, xmm0 # xmm0 = xmm3[0],xmm0[0]
14000a706: c5 f8 10 9c 24 c0 04 00 00  	vmovups	xmm3, xmmword ptr [rsp + 0x4c0]
14000a70f: c5 f9 59 db                 	vmulpd	xmm3, xmm0, xmm3
14000a713: c5 f8 10 bc 24 a0 04 00 00  	vmovups	xmm7, xmmword ptr [rsp + 0x4a0]
14000a71c: c5 f9 59 c7                 	vmulpd	xmm0, xmm0, xmm7
14000a720: c4 c1 41 73 da 08           	vpsrldq	xmm7, xmm10, 0x8        # xmm7 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a726: c5 79 70 d7 44              	vpshufd	xmm10, xmm7, 0x44       # xmm10 = xmm7[0,1,0,1]
14000a72b: c4 c1 61 59 da              	vmulpd	xmm3, xmm3, xmm10
14000a730: c5 78 10 9c 24 50 05 00 00  	vmovups	xmm11, xmmword ptr [rsp + 0x550]
14000a739: c5 21 5c db                 	vsubpd	xmm11, xmm11, xmm3
14000a73d: c5 a1 59 dc                 	vmulpd	xmm3, xmm11, xmm4
14000a741: c5 78 10 b4 24 60 03 00 00  	vmovups	xmm14, xmmword ptr [rsp + 0x360]
14000a74a: c5 09 58 f3                 	vaddpd	xmm14, xmm14, xmm3
14000a74e: c5 78 11 b4 24 60 03 00 00  	vmovups	xmmword ptr [rsp + 0x360], xmm14
14000a757: c4 c1 79 59 c2              	vmulpd	xmm0, xmm0, xmm10
14000a75c: c5 f1 58 d8                 	vaddpd	xmm3, xmm1, xmm0
14000a760: c5 78 10 94 24 80 03 00 00  	vmovups	xmm10, xmmword ptr [rsp + 0x380]
14000a769: c4 62 e1 b8 d4              	vfmadd231pd	xmm10, xmm3, xmm4 # xmm10 = (xmm3 * xmm4) + xmm10
14000a76e: c5 78 11 94 24 80 03 00 00  	vmovups	xmmword ptr [rsp + 0x380], xmm10
14000a777: c5 83 59 c5                 	vmulsd	xmm0, xmm15, xmm5
14000a77b: c4 e2 c1 ad 84 24 60 05 00 00       	vfnmadd213sd	xmm0, xmm7, qword ptr [rsp + 0x560] # xmm0 = -(xmm7 * xmm0) + mem
14000a785: c5 fb 11 83 d0 00 00 00     	vmovsd	qword ptr [rbx + 0xd0], xmm0
14000a78d: c5 fb 10 8c 24 b0 04 00 00  	vmovsd	xmm1, qword ptr [rsp + 0x4b0]
14000a796: c5 83 59 c9                 	vmulsd	xmm1, xmm15, xmm1
14000a79a: c4 e2 c1 a9 ce              	vfmadd213sd	xmm1, xmm7, xmm6 # xmm1 = (xmm7 * xmm1) + xmm6
14000a79f: c5 fb 11 8b 08 01 00 00     	vmovsd	qword ptr [rbx + 0x108], xmm1
14000a7a7: c5 fb 10 35 b1 2a 00 00     	vmovsd	xmm6, qword ptr [rip + 0x2ab1] # 0x14000d260
14000a7af: c5 fb 10 6b 28              	vmovsd	xmm5, qword ptr [rbx + 0x28]
14000a7b4: c4 e2 c9 a9 ac 24 b0 03 00 00       	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b0] # xmm5 = (xmm6 * xmm5) + mem
14000a7be: c5 fb 11 6b 10              	vmovsd	qword ptr [rbx + 0x10], xmm5
14000a7c3: c5 fb 10 6b 60              	vmovsd	xmm5, qword ptr [rbx + 0x60]
14000a7c8: c4 e2 c9 a9 ac 24 b8 03 00 00       	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b8] # xmm5 = (xmm6 * xmm5) + mem
14000a7d2: c5 fb 11 6b 48              	vmovsd	qword ptr [rbx + 0x48], xmm5
14000a7d7: c4 e2 c9 a9 94 24 d0 03 00 00       	vfmadd213sd	xmm2, xmm6, qword ptr [rsp + 0x3d0] # xmm2 = (xmm6 * xmm2) + mem
14000a7e1: c5 fb 11 93 80 00 00 00     	vmovsd	qword ptr [rbx + 0x80], xmm2
14000a7e9: c4 c2 c9 a9 c4              	vfmadd213sd	xmm0, xmm6, xmm12 # xmm0 = (xmm6 * xmm0) + xmm12
14000a7ee: c5 fb 11 83 b8 00 00 00     	vmovsd	qword ptr [rbx + 0xb8], xmm0
14000a7f6: c5 f3 59 c6                 	vmulsd	xmm0, xmm1, xmm6
14000a7fa: c5 fb 58 84 24 90 04 00 00  	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x490]
14000a803: c5 fb 11 83 f0 00 00 00     	vmovsd	qword ptr [rbx + 0xf0], xmm0
14000a80b: 48 83 c0 01                 	add	rax, 0x1
14000a80f: 48 81 f8 20 a1 07 00        	cmp	rax, 0x7a120
14000a816: 0f 8c 94 f6 ff ff           	jl	0x140009eb0 <.text+0x8eb0>
