140009e80:     	vmovups	xmm2, xmm13
140009e85:     	vmovups	xmm4, xmmword ptr [rsp + 0x320]
140009e8e:     	vmovups	xmm5, xmmword ptr [rsp + 0x330]
140009e97:     	vmovups	xmm7, xmmword ptr [rsp + 0x340]
140009ea0:     	vmovups	xmm10, xmm14
140009ea5:     	vmovups	xmmword ptr [rsp + 0x370], xmm11
140009eae:     	vmovups	xmm13, xmm3
140009eb2:     	vmovups	xmm3, xmmword ptr [rsp + 0x310]
140009ebb:     	vsubsd	xmm14, xmm3, xmm5
140009ebf:     	vpsrldq	xmm15, xmm3, 0x8        # xmm15 = xmm3[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009ec4:     	vpsrldq	xmm6, xmm5, 0x8         # xmm6 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009ec9:     	vmovups	xmmword ptr [rsp + 0x3a0], xmm6
140009ed2:     	vsubsd	xmm0, xmm15, xmm6
140009ed6:     	vpunpcklqdq	xmm6, xmm14, xmm0 # xmm6 = xmm14[0],xmm0[0]
140009eda:     	vmovsd	xmm5, qword ptr [rbx + 0x10]
140009edf:     	vmovups	xmmword ptr [rsp + 0x390], xmm13
140009ee8:     	vmovsd	qword ptr [rsp + 0x3b0], xmm5
140009ef1:     	vmovsd	xmm13, qword ptr [rbx + 0x48]
140009ef6:     	vmovsd	qword ptr [rsp + 0x3b8], xmm13
140009eff:     	vsubsd	xmm1, xmm5, xmm13
140009f04:     	vmulsd	xmm13, xmm14, xmm14
140009f09:     	vfmadd213sd	xmm0, xmm0, xmm13 # xmm0 = (xmm0 * xmm0) + xmm13
140009f0e:     	vfmadd231sd	xmm0, xmm1, xmm1 # xmm0 = (xmm1 * xmm1) + xmm0
140009f13:     	vsubsd	xmm13, xmm3, xmm8
140009f18:     	vmulsd	xmm14, xmm13, xmm13
140009f1d:     	vpsrldq	xmm11, xmm8, 0x8        # xmm11 = xmm8[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009f23:     	vmovups	xmmword ptr [rsp + 0x3c0], xmm11
140009f2c:     	vsubsd	xmm8, xmm15, xmm11
140009f31:     	vmulsd	xmm11, xmm8, xmm8
140009f36:     	vaddsd	xmm11, xmm14, xmm11
140009f3b:     	vmovsd	xmm14, qword ptr [rbx + 0x80]
140009f43:     	vmovsd	qword ptr [rsp + 0x3d0], xmm14
140009f4c:     	vsubsd	xmm12, xmm5, xmm14
140009f51:     	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
140009f56:     	vpunpcklqdq	xmm0, xmm0, xmm11 # xmm0 = xmm0[0],xmm11[0]
140009f5b:     	vsqrtpd	xmm11, xmm0
140009f5f:     	vmulpd	xmm0, xmm0, xmm11
140009f64:     	vdivpd	xmm0, xmm2, xmm0
140009f68:     	vpshufd	xmm11, xmm0, 0x44       # xmm11 = xmm0[0,1,0,1]
140009f6d:     	vmovsd	xmm14, qword ptr [rsp + 0x68]
140009f73:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140009f79:     	vmulpd	xmm2, xmm6, xmm14
140009f7e:     	vmovups	xmmword ptr [rsp + 0x3e0], xmm14
140009f87:     	vmovsd	xmm14, qword ptr [rbx + 0x68]
140009f8c:     	vmovsd	qword ptr [rsp + 0x3f0], xmm14
140009f95:     	vfnmadd213pd	xmm2, xmm11, xmm4 # xmm2 = -(xmm11 * xmm2) + xmm4
140009f9a:     	vmulsd	xmm4, xmm1, xmm14
140009f9f:     	vfnmadd213sd	xmm4, xmm0, qword ptr [rbx + 0x28] # xmm4 = -(xmm0 * xmm4) + mem
140009fa5:     	vmovsd	xmm14, qword ptr [rsp + 0x30]
140009fab:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140009fb1:     	vmulpd	xmm6, xmm6, xmm14
140009fb6:     	vmulpd	xmm6, xmm6, xmm11
140009fbb:     	vmovsd	xmm11, qword ptr [rbx + 0x30]
140009fc0:     	vaddpd	xmm6, xmm7, xmm6
140009fc4:     	vmovups	xmmword ptr [rsp + 0x400], xmm6
140009fcd:     	vmulsd	xmm1, xmm1, xmm11
140009fd2:     	vfmadd213sd	xmm1, xmm0, qword ptr [rbx + 0x60] # xmm1 = (xmm0 * xmm1) + mem
140009fd8:     	vmovsd	qword ptr [rsp + 0x410], xmm1
140009fe1:     	vpunpcklqdq	xmm7, xmm13, xmm8 # xmm7 = xmm13[0],xmm8[0]
140009fe6:     	vmulpd	xmm8, xmm7, xmm14
140009feb:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009ff0:     	vpshufd	xmm13, xmm0, 0x44       # xmm13 = xmm0[0,1,0,1]
140009ff5:     	vmulpd	xmm8, xmm8, xmm13
140009ffa:     	vmovsd	xmm1, qword ptr [rsp + 0xa0]
14000a003:     	vpshufd	xmm1, xmm1, 0x44        # xmm1 = xmm1[0,1,0,1]
14000a008:     	vmulpd	xmm7, xmm7, xmm1
14000a00c:     	vfnmadd231pd	xmm2, xmm7, xmm13 # xmm2 = -(xmm7 * xmm13) + xmm2
14000a011:     	vmovsd	xmm13, qword ptr [rbx + 0xa0]
14000a019:     	vmovsd	qword ptr [rsp + 0x430], xmm13
14000a022:     	vmulsd	xmm7, xmm12, xmm13
14000a027:     	vmulsd	xmm7, xmm7, xmm0
14000a02b:     	vsubsd	xmm4, xmm4, xmm7
14000a02f:     	vaddpd	xmm7, xmm9, xmm8
14000a034:     	vmovups	xmmword ptr [rsp + 0x440], xmm7
14000a03d:     	vmulsd	xmm8, xmm12, xmm11
14000a042:     	vmulsd	xmm0, xmm8, xmm0
14000a046:     	vaddsd	xmm0, xmm0, qword ptr [rbx + 0x98]
14000a04e:     	vmovsd	qword ptr [rsp + 0x450], xmm0
14000a057:     	vsubsd	xmm8, xmm3, xmm10
14000a05c:     	vpsrldq	xmm9, xmm10, 0x8        # xmm9 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a062:     	vmovups	xmmword ptr [rsp + 0x460], xmm9
14000a06b:     	vsubsd	xmm12, xmm15, xmm9
14000a070:     	vpunpcklqdq	xmm0, xmm8, xmm12 # xmm0 = xmm8[0],xmm12[0]
14000a075:     	vmulpd	xmm13, xmm0, xmm14
14000a07a:     	vmovsd	xmm7, qword ptr [rbx + 0xb8]
14000a082:     	vmovsd	qword ptr [rsp + 0x470], xmm7
14000a08b:     	vsubsd	xmm6, xmm5, xmm7
14000a08f:     	vmulsd	xmm7, xmm8, xmm8
14000a094:     	vfmadd231sd	xmm7, xmm12, xmm12 # xmm7 = (xmm12 * xmm12) + xmm7
14000a099:     	vfmadd231sd	xmm7, xmm6, xmm6 # xmm7 = (xmm6 * xmm6) + xmm7
14000a09e:     	vmovups	xmm12, xmmword ptr [rsp + 0x380]
14000a0a7:     	vsubsd	xmm8, xmm3, xmm12
14000a0ac:     	vmulsd	xmm9, xmm8, xmm8
14000a0b1:     	vpsrldq	xmm10, xmm12, 0x8       # xmm10 = xmm12[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a0b7:     	vmovups	xmmword ptr [rsp + 0x480], xmm10
14000a0c0:     	vsubsd	xmm12, xmm15, xmm10
14000a0c5:     	vfmadd231sd	xmm9, xmm12, xmm12 # xmm9 = (xmm12 * xmm12) + xmm9
14000a0ca:     	vmovsd	xmm15, qword ptr [rbx + 0xf0]
14000a0d2:     	vmovsd	qword ptr [rsp + 0x490], xmm15
14000a0db:     	vsubsd	xmm10, xmm5, xmm15
14000a0e0:     	vmulsd	xmm5, xmm10, xmm10
14000a0e5:     	vaddsd	xmm5, xmm9, xmm5
14000a0e9:     	vpunpcklqdq	xmm5, xmm7, xmm5 # xmm5 = xmm7[0],xmm5[0]
14000a0ed:     	vsqrtpd	xmm7, xmm5
14000a0f1:     	vmulpd	xmm5, xmm5, xmm7
14000a0f5:     	vmovups	xmm9, xmmword ptr [rsp + 0x300]
14000a0fe:     	vdivpd	xmm5, xmm9, xmm5
14000a102:     	vpshufd	xmm7, xmm5, 0x44        # xmm7 = xmm5[0,1,0,1]
14000a107:     	vmulpd	xmm13, xmm13, xmm7
14000a10b:     	vmovsd	xmm15, qword ptr [rsp + 0xd8]
14000a114:     	vpshufd	xmm15, xmm15, 0x44      # xmm15 = xmm15[0,1,0,1]
14000a11a:     	vmulpd	xmm0, xmm0, xmm15
14000a11f:     	vfnmadd213pd	xmm0, xmm7, xmm2 # xmm0 = -(xmm7 * xmm0) + xmm2
14000a124:     	vmovsd	xmm2, qword ptr [rbx + 0xd8]
14000a12c:     	vmovsd	qword ptr [rsp + 0x4b0], xmm2
14000a135:     	vmulsd	xmm7, xmm6, xmm2
14000a139:     	vfnmadd213sd	xmm7, xmm5, xmm4 # xmm7 = -(xmm5 * xmm7) + xmm4
14000a13e:     	vmovups	xmm4, xmmword ptr [rsp + 0x370]
14000a147:     	vaddpd	xmm13, xmm4, xmm13
14000a14c:     	vmulsd	xmm4, xmm6, xmm11
14000a151:     	vmovsd	xmm6, qword ptr [rbx + 0xd0]
14000a159:     	vfmadd231sd	xmm6, xmm4, xmm5 # xmm6 = (xmm4 * xmm5) + xmm6
14000a15e:     	vpunpcklqdq	xmm4, xmm8, xmm12 # xmm4 = xmm8[0],xmm12[0]
14000a163:     	vmulpd	xmm8, xmm4, xmm14
14000a168:     	vpsrldq	xmm5, xmm5, 0x8         # xmm5 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a16d:     	vpshufd	xmm12, xmm5, 0x44       # xmm12 = xmm5[0,1,0,1]
14000a172:     	vmulpd	xmm8, xmm8, xmm12
14000a177:     	vmovsd	xmm14, qword ptr [rsp + 0x110]
14000a180:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
14000a186:     	vmovups	xmmword ptr [rsp + 0x4c0], xmm14
14000a18f:     	vmulpd	xmm4, xmm4, xmm14
14000a194:     	vfnmadd213pd	xmm4, xmm12, xmm0 # xmm4 = -(xmm12 * xmm4) + xmm0
14000a199:     	vfmadd231pd	xmm3, xmm4, xmmword ptr [rsp + 0x2f0] # xmm3 = (xmm4 * mem) + xmm3
14000a1a3:     	vmovsd	xmm12, qword ptr [rbx + 0x110]
14000a1ab:     	vmovups	xmmword ptr [rsp + 0x310], xmm3
14000a1b4:     	vmovups	xmm3, xmmword ptr [rsp + 0x390]
14000a1bd:     	vmovsd	qword ptr [rsp + 0x4d0], xmm12
14000a1c6:     	vaddpd	xmm3, xmm3, xmm8
14000a1cb:     	vmovups	xmmword ptr [rsp + 0x4e0], xmm3
14000a1d4:     	vmulsd	xmm8, xmm10, xmm12
14000a1d9:     	vfnmadd213sd	xmm8, xmm5, xmm7 # xmm8 = -(xmm5 * xmm8) + xmm7
14000a1de:     	vmovsd	qword ptr [rbx + 0x28], xmm8
14000a1e3:     	vmulsd	xmm7, xmm10, xmm11
14000a1e8:     	vmulsd	xmm5, xmm7, xmm5
14000a1ec:     	vaddsd	xmm5, xmm5, qword ptr [rbx + 0x108]
14000a1f4:     	vmovsd	qword ptr [rsp + 0x4f8], xmm5
14000a1fd:     	vmovups	xmm10, xmmword ptr [rsp + 0x330]
14000a206:     	vmovups	xmm11, xmmword ptr [rsp + 0x350]
14000a20f:     	vsubsd	xmm7, xmm10, xmm11
14000a214:     	vmovups	xmmword ptr [rsp + 0x320], xmm4
14000a21d:     	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
14000a226:     	vmovups	xmm4, xmmword ptr [rsp + 0x3c0]
14000a22f:     	vsubsd	xmm5, xmm8, xmm4
14000a233:     	vpunpcklqdq	xmm12, xmm7, xmm5 # xmm12 = xmm7[0],xmm5[0]
14000a237:     	vmulpd	xmm3, xmm12, xmm1
14000a23b:     	vmovups	xmmword ptr [rsp + 0x420], xmm1
14000a244:     	vmovups	xmm1, xmmword ptr [rsp + 0x3e0]
14000a24d:     	vmulpd	xmm12, xmm12, xmm1
14000a251:     	vmovsd	xmm0, qword ptr [rsp + 0x3b8]
14000a25a:     	vsubsd	xmm11, xmm0, qword ptr [rsp + 0x3d0]
14000a263:     	vmulsd	xmm4, xmm7, xmm7
14000a267:     	vfmadd231sd	xmm4, xmm5, xmm5 # xmm4 = (xmm5 * xmm5) + xmm4
14000a26c:     	vfmadd231sd	xmm4, xmm11, xmm11 # xmm4 = (xmm11 * xmm11) + xmm4
14000a271:     	vmovups	xmm5, xmmword ptr [rsp + 0x360]
14000a27a:     	vsubsd	xmm7, xmm10, xmm5
14000a27e:     	vmulsd	xmm5, xmm7, xmm7
14000a282:     	vmovups	xmm14, xmmword ptr [rsp + 0x460]
14000a28b:     	vsubsd	xmm10, xmm8, xmm14
14000a290:     	vfmadd231sd	xmm5, xmm10, xmm10 # xmm5 = (xmm10 * xmm10) + xmm5
14000a295:     	vsubsd	xmm8, xmm0, qword ptr [rsp + 0x470]
14000a29e:     	vfmadd231sd	xmm5, xmm8, xmm8 # xmm5 = (xmm8 * xmm8) + xmm5
14000a2a3:     	vpunpcklqdq	xmm4, xmm4, xmm5 # xmm4 = xmm4[0],xmm5[0]
14000a2a7:     	vsqrtpd	xmm5, xmm4
14000a2ab:     	vmulpd	xmm4, xmm4, xmm5
14000a2af:     	vdivpd	xmm4, xmm9, xmm4
14000a2b3:     	vpshufd	xmm5, xmm4, 0x44        # xmm5 = xmm4[0,1,0,1]
14000a2b8:     	vfnmadd213pd	xmm3, xmm5, xmmword ptr [rsp + 0x400] # xmm3 = -(xmm5 * xmm3) + mem
14000a2c2:     	vmulpd	xmm5, xmm12, xmm5
14000a2c6:     	vmovups	xmm12, xmmword ptr [rsp + 0x440]
14000a2cf:     	vaddpd	xmm5, xmm12, xmm5
14000a2d3:     	vmovsd	xmm12, qword ptr [rsp + 0x430]
14000a2dc:     	vmovups	xmmword ptr [rsp + 0x500], xmm5
14000a2e5:     	vmulsd	xmm14, xmm11, xmm12
14000a2ea:     	vmovsd	xmm12, qword ptr [rsp + 0x410]
14000a2f3:     	vfnmadd231sd	xmm12, xmm14, xmm4 # xmm12 = -(xmm14 * xmm4) + xmm12
14000a2f8:     	vmovsd	xmm14, qword ptr [rsp + 0x3f0]
14000a301:     	vmulsd	xmm5, xmm11, xmm14
14000a306:     	vfmadd213sd	xmm5, xmm4, qword ptr [rsp + 0x450] # xmm5 = (xmm4 * xmm5) + mem
14000a310:     	vmovsd	qword ptr [rsp + 0x510], xmm5
14000a319:     	vpunpcklqdq	xmm7, xmm7, xmm10 # xmm7 = xmm7[0],xmm10[0]
14000a31e:     	vmulpd	xmm10, xmm7, xmm15
14000a323:     	vmulpd	xmm7, xmm7, xmm1
14000a327:     	vpsrldq	xmm4, xmm4, 0x8         # xmm4 = xmm4[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a32c:     	vpshufd	xmm11, xmm4, 0x44       # xmm11 = xmm4[0,1,0,1]
14000a331:     	vmulpd	xmm10, xmm10, xmm11
14000a336:     	vsubpd	xmm3, xmm3, xmm10
14000a33b:     	vmulpd	xmm7, xmm7, xmm11
14000a340:     	vaddpd	xmm10, xmm13, xmm7
14000a344:     	vmovups	xmmword ptr [rsp + 0x520], xmm10
14000a34d:     	vmulsd	xmm7, xmm8, xmm2
14000a351:     	vmulsd	xmm7, xmm7, xmm4
14000a355:     	vsubsd	xmm11, xmm12, xmm7
14000a359:     	vmulsd	xmm7, xmm8, xmm14
14000a35e:     	vmulsd	xmm4, xmm7, xmm4
14000a362:     	vaddsd	xmm4, xmm6, xmm4
14000a366:     	vmovups	xmm6, xmmword ptr [rsp + 0x330]
14000a36f:     	vmovups	xmm12, xmmword ptr [rsp + 0x380]
14000a378:     	vmovsd	qword ptr [rsp + 0x530], xmm4
14000a381:     	vsubsd	xmm7, xmm6, xmm12
14000a386:     	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
14000a38f:     	vmovups	xmm13, xmmword ptr [rsp + 0x480]
14000a398:     	vsubsd	xmm8, xmm8, xmm13
14000a39d:     	vpunpcklqdq	xmm13, xmm7, xmm8 # xmm13 = xmm7[0],xmm8[0]
14000a3a2:     	vmovups	xmm12, xmmword ptr [rsp + 0x4c0]
14000a3ab:     	vmulpd	xmm4, xmm13, xmm12
14000a3b0:     	vmulpd	xmm1, xmm13, xmm1
14000a3b4:     	vsubsd	xmm12, xmm0, qword ptr [rsp + 0x490]
14000a3bd:     	vmulsd	xmm0, xmm7, xmm7
14000a3c1:     	vfmadd231sd	xmm0, xmm8, xmm8 # xmm0 = (xmm8 * xmm8) + xmm0
14000a3c6:     	vfmadd231sd	xmm0, xmm12, xmm12 # xmm0 = (xmm12 * xmm12) + xmm0
14000a3cb:     	vmovups	xmm8, xmmword ptr [rsp + 0x360]
14000a3d4:     	vmovups	xmm7, xmmword ptr [rsp + 0x350]
14000a3dd:     	vsubsd	xmm13, xmm7, xmm8
14000a3e2:     	vmulsd	xmm7, xmm13, xmm13
14000a3e7:     	vmovups	xmm8, xmmword ptr [rsp + 0x460]
14000a3f0:     	vmovups	xmm5, xmmword ptr [rsp + 0x3c0]
14000a3f9:     	vsubsd	xmm2, xmm5, xmm8
14000a3fe:     	vfmadd231sd	xmm7, xmm2, xmm2 # xmm7 = (xmm2 * xmm2) + xmm7
14000a403:     	vmovsd	xmm8, qword ptr [rsp + 0x3d0]
14000a40c:     	vsubsd	xmm10, xmm8, qword ptr [rsp + 0x470]
14000a415:     	vmulsd	xmm5, xmm10, xmm10
14000a41a:     	vaddsd	xmm5, xmm7, xmm5
14000a41e:     	vpunpcklqdq	xmm0, xmm0, xmm5 # xmm0 = xmm0[0],xmm5[0]
14000a422:     	vsqrtpd	xmm5, xmm0
14000a426:     	vmulpd	xmm0, xmm0, xmm5
14000a42a:     	vdivpd	xmm0, xmm9, xmm0
14000a42e:     	vpshufd	xmm5, xmm0, 0x44        # xmm5 = xmm0[0,1,0,1]
14000a433:     	vmulpd	xmm4, xmm4, xmm5
14000a437:     	vmovups	xmm8, xmmword ptr [rsp + 0x350]
14000a440:     	vsubpd	xmm7, xmm3, xmm4
14000a444:     	vmovups	xmm4, xmmword ptr [rsp + 0x2f0]
14000a44d:     	vfmadd231pd	xmm6, xmm7, xmm4 # xmm6 = (xmm7 * xmm4) + xmm6
14000a452:     	vmovups	xmmword ptr [rsp + 0x330], xmm6
14000a45b:     	vfmadd213pd	xmm1, xmm5, xmmword ptr [rsp + 0x4e0] # xmm1 = (xmm5 * xmm1) + mem
14000a465:     	vmovsd	xmm5, qword ptr [rsp + 0x4d0]
14000a46e:     	vmulsd	xmm3, xmm12, xmm5
14000a472:     	vfnmadd231sd	xmm11, xmm3, xmm0 # xmm11 = -(xmm3 * xmm0) + xmm11
14000a477:     	vmovsd	qword ptr [rbx + 0x60], xmm11
14000a47c:     	vmulsd	xmm3, xmm12, xmm14
14000a481:     	vmulsd	xmm3, xmm3, xmm0
14000a485:     	vmovsd	xmm12, qword ptr [rsp + 0x4f8]
14000a48e:     	vaddsd	xmm3, xmm12, xmm3
14000a492:     	vmovsd	qword ptr [rsp + 0x540], xmm3
14000a49b:     	vxorpd	xmm12, xmm12, xmm12
14000a4a0:     	vpunpcklqdq	xmm2, xmm13, xmm2 # xmm2 = xmm13[0],xmm2[0]
14000a4a4:     	vmulpd	xmm12, xmm2, xmm15
14000a4a9:     	vmovups	xmm13, xmmword ptr [rsp + 0x420]
14000a4b2:     	vmulpd	xmm2, xmm2, xmm13
14000a4b7:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a4bc:     	vpshufd	xmm14, xmm0, 0x44       # xmm14 = xmm0[0,1,0,1]
14000a4c1:     	vmovups	xmm6, xmmword ptr [rsp + 0x500]
14000a4ca:     	vfnmadd231pd	xmm6, xmm12, xmm14 # xmm6 = -(xmm12 * xmm14) + xmm6
14000a4cf:     	vfmadd213pd	xmm2, xmm14, xmmword ptr [rsp + 0x520] # xmm2 = (xmm14 * xmm2) + mem
14000a4d9:     	vmovsd	xmm12, qword ptr [rsp + 0x4b0]
14000a4e2:     	vmovups	xmmword ptr [rsp + 0x550], xmm2
14000a4eb:     	vmulsd	xmm14, xmm10, xmm12
14000a4f0:     	vmovups	xmmword ptr [rsp + 0x340], xmm7
14000a4f9:     	vmovsd	xmm7, qword ptr [rsp + 0x510]
14000a502:     	vfnmadd231sd	xmm7, xmm14, xmm0 # xmm7 = -(xmm14 * xmm0) + xmm7
14000a507:     	vmulsd	xmm10, xmm10, qword ptr [rsp + 0x430]
14000a510:     	vmulsd	xmm0, xmm10, xmm0
14000a514:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x530]
14000a51d:     	vmovsd	qword ptr [rsp + 0x560], xmm0
14000a526:     	vmovups	xmm10, xmmword ptr [rsp + 0x380]
14000a52f:     	vsubsd	xmm11, xmm8, xmm10
14000a534:     	vmovups	xmm12, xmmword ptr [rsp + 0x3c0]
14000a53d:     	vmovups	xmm0, xmmword ptr [rsp + 0x480]
14000a546:     	vsubsd	xmm12, xmm12, xmm0
14000a54a:     	vpunpcklqdq	xmm2, xmm11, xmm12 # xmm2 = xmm11[0],xmm12[0]
14000a54f:     	vmovups	xmmword ptr [rsp + 0x4a0], xmm15
14000a558:     	vmovups	xmm15, xmmword ptr [rsp + 0x4c0]
14000a561:     	vmulpd	xmm3, xmm2, xmm15
14000a566:     	vmulpd	xmm2, xmm2, xmm13
14000a56b:     	vmovsd	xmm13, qword ptr [rsp + 0x490]
14000a574:     	vmovsd	xmm15, qword ptr [rsp + 0x3d0]
14000a57d:     	vsubsd	xmm14, xmm15, xmm13
14000a582:     	vmulsd	xmm11, xmm11, xmm11
14000a587:     	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
14000a58c:     	vfmadd231sd	xmm11, xmm14, xmm14 # xmm11 = (xmm14 * xmm14) + xmm11
14000a591:     	vmovups	xmm12, xmmword ptr [rsp + 0x360]
14000a59a:     	vsubsd	xmm15, xmm12, xmm10
14000a59f:     	vmovsd	qword ptr [rsp + 0x568], xmm15
14000a5a8:     	vmulsd	xmm10, xmm15, xmm15
14000a5ad:     	vmovups	xmm12, xmmword ptr [rsp + 0x460]
14000a5b6:     	vsubsd	xmm0, xmm12, xmm0
14000a5ba:     	vfmadd231sd	xmm10, xmm0, xmm0 # xmm10 = (xmm0 * xmm0) + xmm10
14000a5bf:     	vmovsd	xmm12, qword ptr [rsp + 0x470]
14000a5c8:     	vsubsd	xmm15, xmm12, xmm13
14000a5cd:     	vfmadd231sd	xmm10, xmm15, xmm15 # xmm10 = (xmm15 * xmm15) + xmm10
14000a5d2:     	vpunpcklqdq	xmm10, xmm11, xmm10 # xmm10 = xmm11[0],xmm10[0]
14000a5d7:     	vsqrtpd	xmm11, xmm10
14000a5dc:     	vmulpd	xmm10, xmm10, xmm11
14000a5e1:     	vdivpd	xmm10, xmm9, xmm10
14000a5e6:     	vpshufd	xmm11, xmm10, 0x44      # xmm11 = xmm10[0,1,0,1]
14000a5ec:     	vmulpd	xmm3, xmm3, xmm11
14000a5f1:     	vmovups	xmm13, xmm9
14000a5f6:     	vsubpd	xmm9, xmm6, xmm3
14000a5fa:     	vfmadd231pd	xmm8, xmm9, xmm4 # xmm8 = (xmm9 * xmm4) + xmm8
14000a5ff:     	vmovups	xmmword ptr [rsp + 0x350], xmm8
14000a608:     	vfmadd231pd	xmm1, xmm2, xmm11 # xmm1 = (xmm2 * xmm11) + xmm1
14000a60d:     	vmulsd	xmm2, xmm14, xmm5
14000a611:     	vfnmadd213sd	xmm2, xmm10, xmm7 # xmm2 = -(xmm10 * xmm2) + xmm7
14000a616:     	vmovsd	qword ptr [rbx + 0x98], xmm2
14000a61e:     	vmovsd	xmm3, qword ptr [rsp + 0x430]
14000a627:     	vmulsd	xmm3, xmm14, xmm3
14000a62b:     	vmovsd	xmm6, qword ptr [rsp + 0x540]
14000a634:     	vfmadd231sd	xmm6, xmm3, xmm10 # xmm6 = (xmm3 * xmm10) + xmm6
14000a639:     	vmovsd	xmm3, qword ptr [rsp + 0x568]
14000a642:     	vpunpcklqdq	xmm0, xmm3, xmm0 # xmm0 = xmm3[0],xmm0[0]
14000a646:     	vmovups	xmm3, xmmword ptr [rsp + 0x4c0]
14000a64f:     	vmulpd	xmm3, xmm0, xmm3
14000a653:     	vmovups	xmm7, xmmword ptr [rsp + 0x4a0]
14000a65c:     	vmulpd	xmm0, xmm0, xmm7
14000a660:     	vpsrldq	xmm7, xmm10, 0x8        # xmm7 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a666:     	vpshufd	xmm10, xmm7, 0x44       # xmm10 = xmm7[0,1,0,1]
14000a66b:     	vmulpd	xmm3, xmm3, xmm10
14000a670:     	vmovups	xmm11, xmmword ptr [rsp + 0x550]
14000a679:     	vsubpd	xmm11, xmm11, xmm3
14000a67d:     	vmulpd	xmm3, xmm11, xmm4
14000a681:     	vmovups	xmm14, xmmword ptr [rsp + 0x360]
14000a68a:     	vaddpd	xmm14, xmm14, xmm3
14000a68e:     	vmovups	xmmword ptr [rsp + 0x360], xmm14
14000a697:     	vmulpd	xmm0, xmm0, xmm10
14000a69c:     	vaddpd	xmm3, xmm1, xmm0
14000a6a0:     	vmovups	xmm10, xmmword ptr [rsp + 0x380]
14000a6a9:     	vfmadd231pd	xmm10, xmm3, xmm4 # xmm10 = (xmm3 * xmm4) + xmm10
14000a6ae:     	vmovups	xmmword ptr [rsp + 0x380], xmm10
14000a6b7:     	vmulsd	xmm0, xmm15, xmm5
14000a6bb:     	vfnmadd213sd	xmm0, xmm7, qword ptr [rsp + 0x560] # xmm0 = -(xmm7 * xmm0) + mem
14000a6c5:     	vmovsd	qword ptr [rbx + 0xd0], xmm0
14000a6cd:     	vmovsd	xmm1, qword ptr [rsp + 0x4b0]
14000a6d6:     	vmulsd	xmm1, xmm15, xmm1
14000a6da:     	vfmadd213sd	xmm1, xmm7, xmm6 # xmm1 = (xmm7 * xmm1) + xmm6
14000a6df:     	vmovsd	qword ptr [rbx + 0x108], xmm1
14000a6e7:     	vmovsd	xmm6, qword ptr [rip + 0x2b71] # 0x14000d260
14000a6ef:     	vmovsd	xmm5, qword ptr [rbx + 0x28]
14000a6f4:     	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b0] # xmm5 = (xmm6 * xmm5) + mem
14000a6fe:     	vmovsd	qword ptr [rbx + 0x10], xmm5
14000a703:     	vmovsd	xmm5, qword ptr [rbx + 0x60]
14000a708:     	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b8] # xmm5 = (xmm6 * xmm5) + mem
14000a712:     	vmovsd	qword ptr [rbx + 0x48], xmm5
14000a717:     	vfmadd213sd	xmm2, xmm6, qword ptr [rsp + 0x3d0] # xmm2 = (xmm6 * xmm2) + mem
14000a721:     	vmovsd	qword ptr [rbx + 0x80], xmm2
14000a729:     	vfmadd213sd	xmm0, xmm6, xmm12 # xmm0 = (xmm6 * xmm0) + xmm12
14000a72e:     	vmovsd	qword ptr [rbx + 0xb8], xmm0
14000a736:     	vmulsd	xmm0, xmm1, xmm6
14000a73a:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x490]
14000a743:     	vmovsd	qword ptr [rbx + 0xf0], xmm0
14000a74b:     	add	rax, 0x1
14000a74f:     	cmp	rax, 0x7a120
14000a756:     	jl	0x140009e80 <.text+0x8e80>
