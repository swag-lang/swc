140009e80:     	vmovups	xmm2, xmmword ptr [rsp + 0x300]
140009e89:     	vmovups	xmm4, xmmword ptr [rsp + 0x320]
140009e92:     	vmovups	xmm5, xmmword ptr [rsp + 0x330]
140009e9b:     	vmovups	xmm10, xmm13
140009ea0:     	vmovups	xmmword ptr [rsp + 0x370], xmm7
140009ea9:     	vmovups	xmm12, xmm11
140009eae:     	vmovups	xmm13, xmm3
140009eb2:     	vmovups	xmm3, xmmword ptr [rsp + 0x310]
140009ebb:     	vmovups	xmm7, xmmword ptr [rsp + 0x340]
140009ec4:     	vsubpd	xmm14, xmm3, xmm5
140009ec8:     	vpsrldq	xmm6, xmm14, 0x8        # xmm6 = xmm14[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009ece:     	vmovsd	xmm15, qword ptr [rbx + 0x10]
140009ed3:     	vmovsd	qword ptr [rsp + 0x3a0], xmm15
140009edc:     	vmovsd	xmm0, qword ptr [rbx + 0x48]
140009ee1:     	vmovsd	qword ptr [rsp + 0x3a8], xmm0
140009eea:     	vsubsd	xmm5, xmm15, xmm0
140009eee:     	vmulsd	xmm0, xmm14, xmm14
140009ef3:     	vfmadd231sd	xmm0, xmm6, xmm6 # xmm0 = (xmm6 * xmm6) + xmm0
140009ef8:     	vmulsd	xmm6, xmm5, xmm5
140009efc:     	vaddsd	xmm0, xmm0, xmm6
140009f00:     	vsubpd	xmm6, xmm3, xmm8
140009f05:     	vmulsd	xmm8, xmm6, xmm6
140009f09:     	vmovups	xmmword ptr [rsp + 0x390], xmm13
140009f12:     	vpsrldq	xmm13, xmm6, 0x8        # xmm13 = xmm6[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009f17:     	vfmadd231sd	xmm8, xmm13, xmm13 # xmm8 = (xmm13 * xmm13) + xmm8
140009f1c:     	vmovsd	xmm13, qword ptr [rbx + 0x80]
140009f24:     	vmovsd	qword ptr [rsp + 0x3b0], xmm13
140009f2d:     	vsubsd	xmm1, xmm15, xmm13
140009f32:     	vfmadd231sd	xmm8, xmm1, xmm1 # xmm8 = (xmm1 * xmm1) + xmm8
140009f37:     	vpunpcklqdq	xmm0, xmm0, xmm8 # xmm0 = xmm0[0],xmm8[0]
140009f3c:     	vsqrtpd	xmm8, xmm0
140009f40:     	vmulpd	xmm0, xmm0, xmm8
140009f45:     	vdivpd	xmm0, xmm2, xmm0
140009f49:     	vpshufd	xmm8, xmm0, 0x44        # xmm8 = xmm0[0,1,0,1]
140009f4e:     	vmovsd	xmm13, qword ptr [rsp + 0x68]
140009f54:     	vpshufd	xmm13, xmm13, 0x44      # xmm13 = xmm13[0,1,0,1]
140009f5a:     	vmulpd	xmm11, xmm14, xmm13
140009f5f:     	vmovups	xmmword ptr [rsp + 0x3c0], xmm13
140009f68:     	vmovsd	xmm13, qword ptr [rbx + 0x68]
140009f6d:     	vmovsd	qword ptr [rsp + 0x3d0], xmm13
140009f76:     	vfnmadd231pd	xmm4, xmm11, xmm8 # xmm4 = -(xmm11 * xmm8) + xmm4
140009f7b:     	vmulsd	xmm11, xmm5, xmm13
140009f80:     	vfnmadd213sd	xmm11, xmm0, qword ptr [rbx + 0x28] # xmm11 = -(xmm0 * xmm11) + mem
140009f86:     	vmovsd	xmm13, qword ptr [rsp + 0x30]
140009f8c:     	vpshufd	xmm13, xmm13, 0x44      # xmm13 = xmm13[0,1,0,1]
140009f92:     	vmulpd	xmm14, xmm14, xmm13
140009f97:     	vmulpd	xmm8, xmm14, xmm8
140009f9c:     	vmovsd	xmm14, qword ptr [rbx + 0x30]
140009fa1:     	vaddpd	xmm7, xmm7, xmm8
140009fa6:     	vmovups	xmmword ptr [rsp + 0x3e0], xmm7
140009faf:     	vmulsd	xmm5, xmm5, xmm14
140009fb4:     	vmovsd	xmm8, qword ptr [rbx + 0x60]
140009fb9:     	vfmadd213sd	xmm5, xmm0, xmm8 # xmm5 = (xmm0 * xmm5) + xmm8
140009fbe:     	vmovsd	qword ptr [rsp + 0x3f0], xmm5
140009fc7:     	vmulpd	xmm8, xmm6, xmm13
140009fcc:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009fd1:     	vpshufd	xmm5, xmm0, 0x44        # xmm5 = xmm0[0,1,0,1]
140009fd6:     	vmulpd	xmm8, xmm8, xmm5
140009fda:     	vmovsd	xmm2, qword ptr [rsp + 0xa0]
140009fe3:     	vpshufd	xmm2, xmm2, 0x44        # xmm2 = xmm2[0,1,0,1]
140009fe8:     	vmulpd	xmm6, xmm6, xmm2
140009fec:     	vfnmadd231pd	xmm4, xmm6, xmm5 # xmm4 = -(xmm6 * xmm5) + xmm4
140009ff1:     	vmovsd	xmm5, qword ptr [rbx + 0xa0]
140009ff9:     	vmovsd	qword ptr [rsp + 0x410], xmm5
14000a002:     	vmulsd	xmm6, xmm1, xmm5
14000a006:     	vfnmadd213sd	xmm6, xmm0, xmm11 # xmm6 = -(xmm0 * xmm6) + xmm11
14000a00b:     	vaddpd	xmm8, xmm9, xmm8
14000a010:     	vmovups	xmmword ptr [rsp + 0x420], xmm8
14000a019:     	vmulsd	xmm1, xmm1, xmm14
14000a01e:     	vmulsd	xmm0, xmm1, xmm0
14000a022:     	vmovsd	xmm1, qword ptr [rbx + 0x98]
14000a02a:     	vaddsd	xmm0, xmm1, xmm0
14000a02e:     	vmovsd	qword ptr [rsp + 0x430], xmm0
14000a037:     	vsubpd	xmm1, xmm3, xmm10
14000a03c:     	vxorpd	xmm9, xmm9, xmm9
14000a041:     	vmulpd	xmm9, xmm1, xmm13
14000a046:     	vpsrldq	xmm0, xmm1, 0x8         # xmm0 = xmm1[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a04b:     	vmovsd	xmm11, qword ptr [rbx + 0xb8]
14000a053:     	vmovsd	qword ptr [rsp + 0x438], xmm11
14000a05c:     	vsubsd	xmm5, xmm15, xmm11
14000a061:     	vmulsd	xmm8, xmm1, xmm1
14000a065:     	vfmadd213sd	xmm0, xmm0, xmm8 # xmm0 = (xmm0 * xmm0) + xmm8
14000a06a:     	vmulsd	xmm8, xmm5, xmm5
14000a06e:     	vaddsd	xmm0, xmm0, xmm8
14000a073:     	vsubpd	xmm8, xmm3, xmm12
14000a078:     	vmulsd	xmm12, xmm8, xmm8
14000a07d:     	vpsrldq	xmm7, xmm8, 0x8         # xmm7 = xmm8[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a083:     	vmulsd	xmm7, xmm7, xmm7
14000a087:     	vaddsd	xmm7, xmm12, xmm7
14000a08b:     	vmovsd	xmm12, qword ptr [rbx + 0xf0]
14000a093:     	vmovsd	qword ptr [rsp + 0x440], xmm12
14000a09c:     	vsubsd	xmm11, xmm15, xmm12
14000a0a1:     	vfmadd231sd	xmm7, xmm11, xmm11 # xmm7 = (xmm11 * xmm11) + xmm7
14000a0a6:     	vpunpcklqdq	xmm0, xmm0, xmm7 # xmm0 = xmm0[0],xmm7[0]
14000a0aa:     	vsqrtpd	xmm7, xmm0
14000a0ae:     	vmulpd	xmm0, xmm0, xmm7
14000a0b2:     	vmovups	xmm15, xmmword ptr [rsp + 0x300]
14000a0bb:     	vdivpd	xmm0, xmm15, xmm0
14000a0bf:     	vpshufd	xmm7, xmm0, 0x44        # xmm7 = xmm0[0,1,0,1]
14000a0c4:     	vmulpd	xmm9, xmm9, xmm7
14000a0c8:     	vmovsd	xmm12, qword ptr [rsp + 0xd8]
14000a0d1:     	vpshufd	xmm12, xmm12, 0x44      # xmm12 = xmm12[0,1,0,1]
14000a0d7:     	vmulpd	xmm1, xmm1, xmm12
14000a0dc:     	vfnmadd213pd	xmm1, xmm7, xmm4 # xmm1 = -(xmm7 * xmm1) + xmm4
14000a0e1:     	vmovsd	xmm7, qword ptr [rbx + 0xd8]
14000a0e9:     	vmovsd	qword ptr [rsp + 0x460], xmm7
14000a0f2:     	vmulsd	xmm4, xmm5, xmm7
14000a0f6:     	vfnmadd231sd	xmm6, xmm4, xmm0 # xmm6 = -(xmm4 * xmm0) + xmm6
14000a0fb:     	vmovups	xmm4, xmmword ptr [rsp + 0x370]
14000a104:     	vaddpd	xmm9, xmm4, xmm9
14000a109:     	vmulsd	xmm4, xmm5, xmm14
14000a10e:     	vmulsd	xmm4, xmm4, xmm0
14000a112:     	vmovsd	xmm5, qword ptr [rbx + 0xd0]
14000a11a:     	vaddsd	xmm5, xmm5, xmm4
14000a11e:     	vmovsd	qword ptr [rsp + 0x468], xmm5
14000a127:     	vmulpd	xmm4, xmm8, xmm13
14000a12c:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a131:     	vpshufd	xmm13, xmm0, 0x44       # xmm13 = xmm0[0,1,0,1]
14000a136:     	vmulpd	xmm4, xmm4, xmm13
14000a13b:     	vmovsd	xmm5, qword ptr [rsp + 0x110]
14000a144:     	vpshufd	xmm5, xmm5, 0x44        # xmm5 = xmm5[0,1,0,1]
14000a149:     	vmovups	xmmword ptr [rsp + 0x470], xmm5
14000a152:     	vmulpd	xmm8, xmm8, xmm5
14000a156:     	vmulpd	xmm8, xmm8, xmm13
14000a15b:     	vmovups	xmm13, xmm4
14000a15f:     	vsubpd	xmm4, xmm1, xmm8
14000a164:     	vfmadd231pd	xmm3, xmm4, xmmword ptr [rsp + 0x2f0] # xmm3 = (xmm4 * mem) + xmm3
14000a16e:     	vmovsd	xmm8, qword ptr [rbx + 0x110]
14000a176:     	vmovups	xmmword ptr [rsp + 0x310], xmm3
14000a17f:     	vmovups	xmm3, xmmword ptr [rsp + 0x390]
14000a188:     	vmovsd	qword ptr [rsp + 0x480], xmm8
14000a191:     	vaddpd	xmm3, xmm3, xmm13
14000a196:     	vmovups	xmmword ptr [rsp + 0x490], xmm3
14000a19f:     	vmulsd	xmm13, xmm11, xmm8
14000a1a4:     	vfnmadd231sd	xmm6, xmm13, xmm0 # xmm6 = -(xmm13 * xmm0) + xmm6
14000a1a9:     	vmovsd	qword ptr [rbx + 0x28], xmm6
14000a1ae:     	vmulsd	xmm11, xmm11, xmm14
14000a1b3:     	vmulsd	xmm0, xmm11, xmm0
14000a1b7:     	vaddsd	xmm0, xmm0, qword ptr [rbx + 0x108]
14000a1bf:     	vmovups	xmm13, xmmword ptr [rsp + 0x330]
14000a1c8:     	vmovups	xmm11, xmmword ptr [rsp + 0x350]
14000a1d1:     	vmovsd	qword ptr [rsp + 0x4a8], xmm0
14000a1da:     	vsubpd	xmm14, xmm13, xmm11
14000a1df:     	vmovups	xmmword ptr [rsp + 0x320], xmm4
14000a1e8:     	vxorpd	xmm4, xmm4, xmm4
14000a1ec:     	vmulpd	xmm4, xmm14, xmm2
14000a1f0:     	vmovups	xmm6, xmmword ptr [rsp + 0x3c0]
14000a1f9:     	vmovups	xmmword ptr [rsp + 0x400], xmm2
14000a202:     	vmulpd	xmm2, xmm14, xmm6
14000a206:     	vpsrldq	xmm8, xmm14, 0x8        # xmm8 = xmm14[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a20c:     	vmovsd	xmm0, qword ptr [rsp + 0x3a8]
14000a215:     	vsubsd	xmm1, xmm0, qword ptr [rsp + 0x3b0]
14000a21e:     	vmulsd	xmm3, xmm14, xmm14
14000a223:     	vfmadd231sd	xmm3, xmm8, xmm8 # xmm3 = (xmm8 * xmm8) + xmm3
14000a228:     	vmulsd	xmm8, xmm1, xmm1
14000a22c:     	vaddsd	xmm3, xmm3, xmm8
14000a231:     	vsubpd	xmm8, xmm13, xmm10
14000a236:     	vmulsd	xmm14, xmm8, xmm8
14000a23b:     	vpsrldq	xmm10, xmm8, 0x8        # xmm10 = xmm8[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a241:     	vmulsd	xmm10, xmm10, xmm10
14000a246:     	vaddsd	xmm10, xmm14, xmm10
14000a24b:     	vsubsd	xmm11, xmm0, qword ptr [rsp + 0x438]
14000a254:     	vfmadd231sd	xmm10, xmm11, xmm11 # xmm10 = (xmm11 * xmm11) + xmm10
14000a259:     	vpunpcklqdq	xmm3, xmm3, xmm10 # xmm3 = xmm3[0],xmm10[0]
14000a25e:     	vsqrtpd	xmm10, xmm3
14000a262:     	vmulpd	xmm3, xmm3, xmm10
14000a267:     	vdivpd	xmm3, xmm15, xmm3
14000a26b:     	vpshufd	xmm10, xmm3, 0x44       # xmm10 = xmm3[0,1,0,1]
14000a270:     	vfnmadd213pd	xmm4, xmm10, xmmword ptr [rsp + 0x3e0] # xmm4 = -(xmm10 * xmm4) + mem
14000a27a:     	vmulpd	xmm2, xmm2, xmm10
14000a27f:     	vmovups	xmm10, xmmword ptr [rsp + 0x420]
14000a288:     	vaddpd	xmm2, xmm10, xmm2
14000a28c:     	vmovsd	xmm10, qword ptr [rsp + 0x410]
14000a295:     	vmovups	xmmword ptr [rsp + 0x4b0], xmm2
14000a29e:     	vmulsd	xmm14, xmm1, xmm10
14000a2a3:     	vmovsd	xmm10, qword ptr [rsp + 0x3f0]
14000a2ac:     	vfnmadd231sd	xmm10, xmm14, xmm3 # xmm10 = -(xmm14 * xmm3) + xmm10
14000a2b1:     	vmovsd	xmm14, qword ptr [rsp + 0x3d0]
14000a2ba:     	vmulsd	xmm1, xmm1, xmm14
14000a2bf:     	vmovsd	xmm2, qword ptr [rsp + 0x430]
14000a2c8:     	vfmadd213sd	xmm1, xmm3, xmm2 # xmm1 = (xmm3 * xmm1) + xmm2
14000a2cd:     	vmovsd	qword ptr [rsp + 0x4c0], xmm1
14000a2d6:     	vmulpd	xmm2, xmm8, xmm12
14000a2db:     	vmulpd	xmm8, xmm8, xmm6
14000a2df:     	vpsrldq	xmm3, xmm3, 0x8         # xmm3 = xmm3[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a2e4:     	vpshufd	xmm1, xmm3, 0x44        # xmm1 = xmm3[0,1,0,1]
14000a2e9:     	vfnmadd213pd	xmm2, xmm1, xmm4 # xmm2 = -(xmm1 * xmm2) + xmm4
14000a2ee:     	vfmadd213pd	xmm1, xmm8, xmm9 # xmm1 = (xmm8 * xmm1) + xmm9
14000a2f3:     	vmulsd	xmm4, xmm11, xmm7
14000a2f7:     	vmulsd	xmm4, xmm4, xmm3
14000a2fb:     	vsubsd	xmm4, xmm10, xmm4
14000a2ff:     	vmulsd	xmm8, xmm11, xmm14
14000a304:     	vmulsd	xmm3, xmm8, xmm3
14000a308:     	vaddsd	xmm3, xmm3, qword ptr [rsp + 0x468]
14000a311:     	vmovups	xmm8, xmmword ptr [rsp + 0x380]
14000a31a:     	vmovsd	qword ptr [rsp + 0x4c8], xmm3
14000a323:     	vsubpd	xmm9, xmm13, xmm8
14000a328:     	vxorpd	xmm10, xmm10, xmm10
14000a32d:     	vmulpd	xmm10, xmm9, xmm5
14000a331:     	vmulpd	xmm6, xmm9, xmm6
14000a335:     	vpsrldq	xmm7, xmm9, 0x8         # xmm7 = xmm9[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a33b:     	vmovsd	xmm11, qword ptr [rsp + 0x440]
14000a344:     	vsubsd	xmm5, xmm0, xmm11
14000a349:     	vmulsd	xmm0, xmm9, xmm9
14000a34e:     	vfmadd231sd	xmm0, xmm7, xmm7 # xmm0 = (xmm7 * xmm7) + xmm0
14000a353:     	vfmadd231sd	xmm0, xmm5, xmm5 # xmm0 = (xmm5 * xmm5) + xmm0
14000a358:     	vmovups	xmm9, xmmword ptr [rsp + 0x350]
14000a361:     	vmovups	xmm7, xmmword ptr [rsp + 0x360]
14000a36a:     	vsubpd	xmm11, xmm9, xmm7
14000a36e:     	vmulsd	xmm7, xmm11, xmm11
14000a373:     	vpsrldq	xmm8, xmm11, 0x8        # xmm8 = xmm11[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a379:     	vfmadd231sd	xmm7, xmm8, xmm8 # xmm7 = (xmm8 * xmm8) + xmm7
14000a37e:     	vmovsd	xmm8, qword ptr [rsp + 0x3b0]
14000a387:     	vsubsd	xmm3, xmm8, qword ptr [rsp + 0x438]
14000a390:     	vfmadd231sd	xmm7, xmm3, xmm3 # xmm7 = (xmm3 * xmm3) + xmm7
14000a395:     	vpunpcklqdq	xmm0, xmm0, xmm7 # xmm0 = xmm0[0],xmm7[0]
14000a399:     	vsqrtpd	xmm7, xmm0
14000a39d:     	vmulpd	xmm0, xmm0, xmm7
14000a3a1:     	vdivpd	xmm0, xmm15, xmm0
14000a3a5:     	vpshufd	xmm9, xmm0, 0x44        # xmm9 = xmm0[0,1,0,1]
14000a3aa:     	vmulpd	xmm7, xmm10, xmm9
14000a3af:     	vmovsd	xmm15, qword ptr [rsp + 0x460]
14000a3b8:     	vsubpd	xmm7, xmm2, xmm7
14000a3bc:     	vmovups	xmm2, xmmword ptr [rsp + 0x2f0]
14000a3c5:     	vfmadd231pd	xmm13, xmm7, xmm2 # xmm13 = (xmm7 * xmm2) + xmm13
14000a3ca:     	vmovups	xmmword ptr [rsp + 0x330], xmm13
14000a3d3:     	vmulpd	xmm6, xmm6, xmm9
14000a3d8:     	vmovups	xmm9, xmmword ptr [rsp + 0x490]
14000a3e1:     	vaddpd	xmm6, xmm9, xmm6
14000a3e5:     	vmovsd	xmm10, qword ptr [rsp + 0x480]
14000a3ee:     	vmulsd	xmm9, xmm5, xmm10
14000a3f3:     	vfnmadd231sd	xmm4, xmm9, xmm0 # xmm4 = -(xmm9 * xmm0) + xmm4
14000a3f8:     	vmovsd	qword ptr [rbx + 0x60], xmm4
14000a3fd:     	vmulsd	xmm5, xmm5, xmm14
14000a402:     	vmovsd	xmm9, qword ptr [rsp + 0x4a8]
14000a40b:     	vfmadd213sd	xmm5, xmm0, xmm9 # xmm5 = (xmm0 * xmm5) + xmm9
14000a410:     	vmulpd	xmm9, xmm11, xmm12
14000a415:     	vmovups	xmm14, xmmword ptr [rsp + 0x400]
14000a41e:     	vmulpd	xmm11, xmm11, xmm14
14000a423:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a428:     	vpshufd	xmm13, xmm0, 0x44       # xmm13 = xmm0[0,1,0,1]
14000a42d:     	vmovups	xmmword ptr [rsp + 0x340], xmm7
14000a436:     	vmovups	xmm7, xmmword ptr [rsp + 0x4b0]
14000a43f:     	vfnmadd231pd	xmm7, xmm9, xmm13 # xmm7 = -(xmm9 * xmm13) + xmm7
14000a444:     	vfmadd231pd	xmm1, xmm11, xmm13 # xmm1 = (xmm11 * xmm13) + xmm1
14000a449:     	vmovups	xmmword ptr [rsp + 0x4e0], xmm1
14000a452:     	vmulsd	xmm9, xmm3, xmm15
14000a457:     	vmovsd	xmm11, qword ptr [rsp + 0x4c0]
14000a460:     	vfnmadd231sd	xmm11, xmm9, xmm0 # xmm11 = -(xmm9 * xmm0) + xmm11
14000a465:     	vmovsd	xmm13, qword ptr [rsp + 0x410]
14000a46e:     	vmulsd	xmm3, xmm3, xmm13
14000a473:     	vmulsd	xmm0, xmm3, xmm0
14000a477:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x4c8]
14000a480:     	vmovups	xmm9, xmmword ptr [rsp + 0x350]
14000a489:     	vmovups	xmm3, xmmword ptr [rsp + 0x380]
14000a492:     	vmovsd	qword ptr [rsp + 0x4f0], xmm0
14000a49b:     	vsubpd	xmm4, xmm9, xmm3
14000a49f:     	vmovups	xmm9, xmmword ptr [rsp + 0x470]
14000a4a8:     	vmulpd	xmm15, xmm4, xmm9
14000a4ad:     	vmulpd	xmm14, xmm4, xmm14
14000a4b2:     	vpsrldq	xmm0, xmm4, 0x8         # xmm0 = xmm4[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a4b7:     	vmovsd	xmm9, qword ptr [rsp + 0x440]
14000a4c0:     	vsubsd	xmm1, xmm8, xmm9
14000a4c5:     	vxorpd	xmm8, xmm8, xmm8
14000a4ca:     	vmulsd	xmm4, xmm4, xmm4
14000a4ce:     	vfmadd213sd	xmm0, xmm0, xmm4 # xmm0 = (xmm0 * xmm0) + xmm4
14000a4d3:     	vfmadd231sd	xmm0, xmm1, xmm1 # xmm0 = (xmm1 * xmm1) + xmm0
14000a4d8:     	vmovups	xmm4, xmmword ptr [rsp + 0x360]
14000a4e1:     	vsubpd	xmm8, xmm4, xmm3
14000a4e5:     	vmovups	xmmword ptr [rsp + 0x500], xmm8
14000a4ee:     	vmulsd	xmm3, xmm8, xmm8
14000a4f3:     	vpsrldq	xmm4, xmm8, 0x8         # xmm4 = xmm8[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a4f9:     	vfmadd231sd	xmm3, xmm4, xmm4 # xmm3 = (xmm4 * xmm4) + xmm3
14000a4fe:     	vmovsd	xmm4, qword ptr [rsp + 0x438]
14000a507:     	vmovups	xmmword ptr [rsp + 0x450], xmm12
14000a510:     	vsubsd	xmm12, xmm4, xmm9
14000a515:     	vmovsd	qword ptr [rsp + 0x510], xmm12
14000a51e:     	vfmadd231sd	xmm3, xmm12, xmm12 # xmm3 = (xmm12 * xmm12) + xmm3
14000a523:     	vpunpcklqdq	xmm0, xmm0, xmm3 # xmm0 = xmm0[0],xmm3[0]
14000a527:     	vsqrtpd	xmm3, xmm0
14000a52b:     	vmulpd	xmm0, xmm0, xmm3
14000a52f:     	vmovups	xmm4, xmmword ptr [rsp + 0x300]
14000a538:     	vdivpd	xmm0, xmm4, xmm0
14000a53c:     	vpshufd	xmm3, xmm0, 0x44        # xmm3 = xmm0[0,1,0,1]
14000a541:     	vmulpd	xmm15, xmm15, xmm3
14000a545:     	vmovups	xmm8, xmmword ptr [rsp + 0x350]
14000a54e:     	vmovups	xmm4, xmm9
14000a553:     	vmovups	xmm12, xmmword ptr [rsp + 0x470]
14000a55c:     	vsubpd	xmm9, xmm7, xmm15
14000a561:     	vmulpd	xmm7, xmm9, xmm2
14000a565:     	vaddpd	xmm8, xmm8, xmm7
14000a569:     	vmovups	xmmword ptr [rsp + 0x350], xmm8
14000a572:     	vfmadd213pd	xmm3, xmm14, xmm6 # xmm3 = (xmm14 * xmm3) + xmm6
14000a577:     	vmulsd	xmm6, xmm1, xmm10
14000a57c:     	vfnmadd213sd	xmm6, xmm0, xmm11 # xmm6 = -(xmm0 * xmm6) + xmm11
14000a581:     	vmovsd	qword ptr [rbx + 0x98], xmm6
14000a589:     	vmulsd	xmm1, xmm1, xmm13
14000a58e:     	vfmadd213sd	xmm1, xmm0, xmm5 # xmm1 = (xmm0 * xmm1) + xmm5
14000a593:     	vmovups	xmm5, xmmword ptr [rsp + 0x500]
14000a59c:     	vmulpd	xmm7, xmm5, xmm12
14000a5a1:     	vmovups	xmm12, xmmword ptr [rsp + 0x450]
14000a5aa:     	vmulpd	xmm5, xmm5, xmm12
14000a5af:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a5b4:     	vpshufd	xmm11, xmm0, 0x44       # xmm11 = xmm0[0,1,0,1]
14000a5b9:     	vfnmadd213pd	xmm7, xmm11, xmmword ptr [rsp + 0x4e0] # xmm7 = -(xmm11 * xmm7) + mem
14000a5c3:     	vmovups	xmm13, xmmword ptr [rsp + 0x360]
14000a5cc:     	vfmadd231pd	xmm13, xmm7, xmm2 # xmm13 = (xmm7 * xmm2) + xmm13
14000a5d1:     	vmovups	xmmword ptr [rsp + 0x360], xmm13
14000a5da:     	vmulpd	xmm5, xmm5, xmm11
14000a5df:     	vmovups	xmm11, xmmword ptr [rsp + 0x380]
14000a5e8:     	vmovsd	xmm12, qword ptr [rsp + 0x3b0]
14000a5f1:     	vaddpd	xmm3, xmm3, xmm5
14000a5f5:     	vfmadd231pd	xmm11, xmm3, xmm2 # xmm11 = (xmm3 * xmm2) + xmm11
14000a5fa:     	vmovsd	xmm5, qword ptr [rsp + 0x510]
14000a603:     	vmovups	xmmword ptr [rsp + 0x380], xmm11
14000a60c:     	vmulsd	xmm10, xmm5, xmm10
14000a611:     	vfnmadd213sd	xmm10, xmm0, qword ptr [rsp + 0x4f0] # xmm10 = -(xmm0 * xmm10) + mem
14000a61b:     	vmovsd	qword ptr [rbx + 0xd0], xmm10
14000a623:     	vmulsd	xmm5, xmm5, qword ptr [rsp + 0x460]
14000a62c:     	vfmadd213sd	xmm0, xmm5, xmm1 # xmm0 = (xmm5 * xmm0) + xmm1
14000a631:     	vmovsd	qword ptr [rbx + 0x108], xmm0
14000a639:     	vmovsd	xmm5, qword ptr [rip + 0x2c1f] # 0x14000d260
14000a641:     	vmovsd	xmm1, qword ptr [rbx + 0x28]
14000a646:     	vfmadd213sd	xmm1, xmm5, qword ptr [rsp + 0x3a0] # xmm1 = (xmm5 * xmm1) + mem
14000a650:     	vmovsd	qword ptr [rbx + 0x10], xmm1
14000a655:     	vmovsd	xmm1, qword ptr [rbx + 0x60]
14000a65a:     	vmovsd	xmm14, qword ptr [rsp + 0x3a8]
14000a663:     	vfmadd213sd	xmm1, xmm5, xmm14 # xmm1 = (xmm5 * xmm1) + xmm14
14000a668:     	vmovsd	qword ptr [rbx + 0x48], xmm1
14000a66d:     	vmulsd	xmm1, xmm6, xmm5
14000a671:     	vaddsd	xmm1, xmm12, xmm1
14000a675:     	vmovsd	qword ptr [rbx + 0x80], xmm1
14000a67d:     	vmulsd	xmm1, xmm10, xmm5
14000a681:     	vaddsd	xmm1, xmm1, qword ptr [rsp + 0x438]
14000a68a:     	vmovsd	qword ptr [rbx + 0xb8], xmm1
14000a692:     	vfmadd213sd	xmm0, xmm5, xmm4 # xmm0 = (xmm5 * xmm0) + xmm4
14000a697:     	vmovsd	qword ptr [rbx + 0xf0], xmm0
14000a69f:     	add	rax, 0x1
14000a6a3:     	cmp	rax, 0x7a120
14000a6aa:     	jl	0x140009e80 <.text+0x8e80>
