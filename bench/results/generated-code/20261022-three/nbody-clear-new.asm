140009e90:     	vmovups	xmm2, xmm13
140009e95:     	vmovups	xmm4, xmmword ptr [rsp + 0x320]
140009e9e:     	vmovups	xmm5, xmmword ptr [rsp + 0x330]
140009ea7:     	vmovups	xmm7, xmmword ptr [rsp + 0x340]
140009eb0:     	vmovups	xmm10, xmm14
140009eb5:     	vmovups	xmmword ptr [rsp + 0x370], xmm11
140009ebe:     	vmovups	xmm13, xmm3
140009ec2:     	vmovups	xmm3, xmmword ptr [rsp + 0x310]
140009ecb:     	vsubsd	xmm14, xmm3, xmm5
140009ecf:     	vpsrldq	xmm15, xmm3, 0x8        # xmm15 = xmm3[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009ed4:     	vpsrldq	xmm6, xmm5, 0x8         # xmm6 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009ed9:     	vmovups	xmmword ptr [rsp + 0x3a0], xmm6
140009ee2:     	vsubsd	xmm0, xmm15, xmm6
140009ee6:     	vpunpcklqdq	xmm6, xmm14, xmm0 # xmm6 = xmm14[0],xmm0[0]
140009eea:     	vmovsd	xmm5, qword ptr [rbx + 0x10]
140009eef:     	vmovups	xmmword ptr [rsp + 0x390], xmm13
140009ef8:     	vmovsd	qword ptr [rsp + 0x3b0], xmm5
140009f01:     	vmovsd	xmm13, qword ptr [rbx + 0x48]
140009f06:     	vmovsd	qword ptr [rsp + 0x3b8], xmm13
140009f0f:     	vsubsd	xmm1, xmm5, xmm13
140009f14:     	vmulsd	xmm13, xmm14, xmm14
140009f19:     	vfmadd213sd	xmm0, xmm0, xmm13 # xmm0 = (xmm0 * xmm0) + xmm13
140009f1e:     	vfmadd231sd	xmm0, xmm1, xmm1 # xmm0 = (xmm1 * xmm1) + xmm0
140009f23:     	vsubsd	xmm13, xmm3, xmm8
140009f28:     	vpsrldq	xmm11, xmm8, 0x8        # xmm11 = xmm8[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009f2e:     	vmovups	xmmword ptr [rsp + 0x3c0], xmm11
140009f37:     	vsubsd	xmm8, xmm15, xmm11
140009f3c:     	vmulsd	xmm11, xmm8, xmm8
140009f41:     	vfmadd231sd	xmm11, xmm13, xmm13 # xmm11 = (xmm13 * xmm13) + xmm11
140009f46:     	vmovsd	xmm14, qword ptr [rbx + 0x80]
140009f4e:     	vmovsd	qword ptr [rsp + 0x3d0], xmm14
140009f57:     	vsubsd	xmm12, xmm5, xmm14
140009f5c:     	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
140009f61:     	vpunpcklqdq	xmm14, xmm0, xmm11 # xmm14 = xmm0[0],xmm11[0]
140009f66:     	vsqrtpd	xmm14, xmm14
140009f6b:     	vmulsd	xmm0, xmm0, xmm14
140009f70:     	vpsrldq	xmm14, xmm14, 0x8       # xmm14 = xmm14[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140009f76:     	vmulsd	xmm11, xmm11, xmm14
140009f7b:     	vpunpcklqdq	xmm0, xmm0, xmm11 # xmm0 = xmm0[0],xmm11[0]
140009f80:     	vdivpd	xmm0, xmm2, xmm0
140009f84:     	vpshufd	xmm11, xmm0, 0x44       # xmm11 = xmm0[0,1,0,1]
140009f89:     	vmovsd	xmm14, qword ptr [rsp + 0x68]
140009f8f:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140009f95:     	vmulpd	xmm2, xmm6, xmm14
140009f9a:     	vmovups	xmmword ptr [rsp + 0x3e0], xmm14
140009fa3:     	vmovsd	xmm14, qword ptr [rbx + 0x68]
140009fa8:     	vmovsd	qword ptr [rsp + 0x3f0], xmm14
140009fb1:     	vfnmadd213pd	xmm2, xmm11, xmm4 # xmm2 = -(xmm11 * xmm2) + xmm4
140009fb6:     	vmulsd	xmm4, xmm1, xmm14
140009fbb:     	vfnmadd213sd	xmm4, xmm0, qword ptr [rbx + 0x28] # xmm4 = -(xmm0 * xmm4) + mem
140009fc1:     	vmovsd	xmm14, qword ptr [rsp + 0x30]
140009fc7:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140009fcd:     	vmulpd	xmm6, xmm6, xmm14
140009fd2:     	vmulpd	xmm6, xmm6, xmm11
140009fd7:     	vmovsd	xmm11, qword ptr [rbx + 0x30]
140009fdc:     	vaddpd	xmm6, xmm7, xmm6
140009fe0:     	vmovups	xmmword ptr [rsp + 0x400], xmm6
140009fe9:     	vmulsd	xmm1, xmm1, xmm11
140009fee:     	vfmadd213sd	xmm1, xmm0, qword ptr [rbx + 0x60] # xmm1 = (xmm0 * xmm1) + mem
140009ff4:     	vmovsd	qword ptr [rsp + 0x410], xmm1
140009ffd:     	vpunpcklqdq	xmm7, xmm13, xmm8 # xmm7 = xmm13[0],xmm8[0]
14000a002:     	vmulpd	xmm8, xmm7, xmm14
14000a007:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a00c:     	vpshufd	xmm13, xmm0, 0x44       # xmm13 = xmm0[0,1,0,1]
14000a011:     	vmulpd	xmm8, xmm8, xmm13
14000a016:     	vmovsd	xmm1, qword ptr [rsp + 0xa0]
14000a01f:     	vpshufd	xmm1, xmm1, 0x44        # xmm1 = xmm1[0,1,0,1]
14000a024:     	vmulpd	xmm7, xmm7, xmm1
14000a028:     	vfnmadd231pd	xmm2, xmm7, xmm13 # xmm2 = -(xmm7 * xmm13) + xmm2
14000a02d:     	vmovsd	xmm13, qword ptr [rbx + 0xa0]
14000a035:     	vmovsd	qword ptr [rsp + 0x430], xmm13
14000a03e:     	vmulsd	xmm7, xmm12, xmm13
14000a043:     	vmulsd	xmm7, xmm7, xmm0
14000a047:     	vsubsd	xmm4, xmm4, xmm7
14000a04b:     	vaddpd	xmm7, xmm9, xmm8
14000a050:     	vmovups	xmmword ptr [rsp + 0x440], xmm7
14000a059:     	vmulsd	xmm8, xmm12, xmm11
14000a05e:     	vmulsd	xmm0, xmm8, xmm0
14000a062:     	vaddsd	xmm0, xmm0, qword ptr [rbx + 0x98]
14000a06a:     	vmovsd	qword ptr [rsp + 0x450], xmm0
14000a073:     	vsubsd	xmm8, xmm3, xmm10
14000a078:     	vpsrldq	xmm9, xmm10, 0x8        # xmm9 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a07e:     	vmovups	xmmword ptr [rsp + 0x460], xmm9
14000a087:     	vsubsd	xmm12, xmm15, xmm9
14000a08c:     	vpunpcklqdq	xmm0, xmm8, xmm12 # xmm0 = xmm8[0],xmm12[0]
14000a091:     	vmulpd	xmm13, xmm0, xmm14
14000a096:     	vmovsd	xmm7, qword ptr [rbx + 0xb8]
14000a09e:     	vmovsd	qword ptr [rsp + 0x470], xmm7
14000a0a7:     	vsubsd	xmm6, xmm5, xmm7
14000a0ab:     	vmulsd	xmm7, xmm8, xmm8
14000a0b0:     	vfmadd231sd	xmm7, xmm12, xmm12 # xmm7 = (xmm12 * xmm12) + xmm7
14000a0b5:     	vfmadd231sd	xmm7, xmm6, xmm6 # xmm7 = (xmm6 * xmm6) + xmm7
14000a0ba:     	vmovups	xmm12, xmmword ptr [rsp + 0x380]
14000a0c3:     	vsubsd	xmm8, xmm3, xmm12
14000a0c8:     	vmulsd	xmm9, xmm8, xmm8
14000a0cd:     	vpsrldq	xmm10, xmm12, 0x8       # xmm10 = xmm12[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a0d3:     	vmovups	xmmword ptr [rsp + 0x480], xmm10
14000a0dc:     	vsubsd	xmm12, xmm15, xmm10
14000a0e1:     	vfmadd231sd	xmm9, xmm12, xmm12 # xmm9 = (xmm12 * xmm12) + xmm9
14000a0e6:     	vmovsd	xmm15, qword ptr [rbx + 0xf0]
14000a0ee:     	vmovsd	qword ptr [rsp + 0x490], xmm15
14000a0f7:     	vsubsd	xmm10, xmm5, xmm15
14000a0fc:     	vmulsd	xmm5, xmm10, xmm10
14000a101:     	vaddsd	xmm5, xmm9, xmm5
14000a105:     	vpunpcklqdq	xmm9, xmm7, xmm5 # xmm9 = xmm7[0],xmm5[0]
14000a109:     	vsqrtpd	xmm9, xmm9
14000a10e:     	vmulsd	xmm7, xmm7, xmm9
14000a113:     	vpsrldq	xmm9, xmm9, 0x8         # xmm9 = xmm9[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a119:     	vmulsd	xmm5, xmm5, xmm9
14000a11e:     	vpunpcklqdq	xmm5, xmm7, xmm5 # xmm5 = xmm7[0],xmm5[0]
14000a122:     	vmovups	xmm9, xmmword ptr [rsp + 0x300]
14000a12b:     	vdivpd	xmm5, xmm9, xmm5
14000a12f:     	vpshufd	xmm7, xmm5, 0x44        # xmm7 = xmm5[0,1,0,1]
14000a134:     	vmulpd	xmm13, xmm13, xmm7
14000a138:     	vmovsd	xmm15, qword ptr [rsp + 0xd8]
14000a141:     	vpshufd	xmm15, xmm15, 0x44      # xmm15 = xmm15[0,1,0,1]
14000a147:     	vmulpd	xmm0, xmm0, xmm15
14000a14c:     	vfnmadd213pd	xmm0, xmm7, xmm2 # xmm0 = -(xmm7 * xmm0) + xmm2
14000a151:     	vmovsd	xmm2, qword ptr [rbx + 0xd8]
14000a159:     	vmovsd	qword ptr [rsp + 0x4b0], xmm2
14000a162:     	vmulsd	xmm7, xmm6, xmm2
14000a166:     	vfnmadd213sd	xmm7, xmm5, xmm4 # xmm7 = -(xmm5 * xmm7) + xmm4
14000a16b:     	vmovups	xmm4, xmmword ptr [rsp + 0x370]
14000a174:     	vaddpd	xmm13, xmm4, xmm13
14000a179:     	vmulsd	xmm4, xmm6, xmm11
14000a17e:     	vmovsd	xmm6, qword ptr [rbx + 0xd0]
14000a186:     	vfmadd231sd	xmm6, xmm4, xmm5 # xmm6 = (xmm4 * xmm5) + xmm6
14000a18b:     	vpunpcklqdq	xmm4, xmm8, xmm12 # xmm4 = xmm8[0],xmm12[0]
14000a190:     	vmulpd	xmm8, xmm4, xmm14
14000a195:     	vpsrldq	xmm5, xmm5, 0x8         # xmm5 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a19a:     	vpshufd	xmm12, xmm5, 0x44       # xmm12 = xmm5[0,1,0,1]
14000a19f:     	vmulpd	xmm8, xmm8, xmm12
14000a1a4:     	vmovsd	xmm14, qword ptr [rsp + 0x110]
14000a1ad:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
14000a1b3:     	vmovups	xmmword ptr [rsp + 0x4c0], xmm14
14000a1bc:     	vmulpd	xmm4, xmm4, xmm14
14000a1c1:     	vfnmadd213pd	xmm4, xmm12, xmm0 # xmm4 = -(xmm12 * xmm4) + xmm0
14000a1c6:     	vfmadd231pd	xmm3, xmm4, xmmword ptr [rsp + 0x2f0] # xmm3 = (xmm4 * mem) + xmm3
14000a1d0:     	vmovsd	xmm12, qword ptr [rbx + 0x110]
14000a1d8:     	vmovups	xmmword ptr [rsp + 0x310], xmm3
14000a1e1:     	vmovups	xmm3, xmmword ptr [rsp + 0x390]
14000a1ea:     	vmovsd	qword ptr [rsp + 0x4d0], xmm12
14000a1f3:     	vaddpd	xmm3, xmm3, xmm8
14000a1f8:     	vmovups	xmmword ptr [rsp + 0x4e0], xmm3
14000a201:     	vmulsd	xmm8, xmm10, xmm12
14000a206:     	vfnmadd213sd	xmm8, xmm5, xmm7 # xmm8 = -(xmm5 * xmm8) + xmm7
14000a20b:     	vmovsd	qword ptr [rbx + 0x28], xmm8
14000a210:     	vmulsd	xmm7, xmm10, xmm11
14000a215:     	vmulsd	xmm5, xmm7, xmm5
14000a219:     	vaddsd	xmm5, xmm5, qword ptr [rbx + 0x108]
14000a221:     	vmovsd	qword ptr [rsp + 0x4f8], xmm5
14000a22a:     	vmovups	xmm10, xmmword ptr [rsp + 0x330]
14000a233:     	vmovups	xmm11, xmmword ptr [rsp + 0x350]
14000a23c:     	vsubsd	xmm7, xmm10, xmm11
14000a241:     	vmovups	xmmword ptr [rsp + 0x320], xmm4
14000a24a:     	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
14000a253:     	vmovups	xmm4, xmmword ptr [rsp + 0x3c0]
14000a25c:     	vsubsd	xmm5, xmm8, xmm4
14000a260:     	vpunpcklqdq	xmm12, xmm7, xmm5 # xmm12 = xmm7[0],xmm5[0]
14000a264:     	vmulpd	xmm3, xmm12, xmm1
14000a268:     	vmovups	xmmword ptr [rsp + 0x420], xmm1
14000a271:     	vmovups	xmm1, xmmword ptr [rsp + 0x3e0]
14000a27a:     	vmulpd	xmm12, xmm12, xmm1
14000a27e:     	vmovsd	xmm0, qword ptr [rsp + 0x3b8]
14000a287:     	vsubsd	xmm11, xmm0, qword ptr [rsp + 0x3d0]
14000a290:     	vmulsd	xmm4, xmm7, xmm7
14000a294:     	vfmadd231sd	xmm4, xmm5, xmm5 # xmm4 = (xmm5 * xmm5) + xmm4
14000a299:     	vfmadd231sd	xmm4, xmm11, xmm11 # xmm4 = (xmm11 * xmm11) + xmm4
14000a29e:     	vmovups	xmm5, xmmword ptr [rsp + 0x360]
14000a2a7:     	vsubsd	xmm7, xmm10, xmm5
14000a2ab:     	vmulsd	xmm5, xmm7, xmm7
14000a2af:     	vmovups	xmm14, xmmword ptr [rsp + 0x460]
14000a2b8:     	vsubsd	xmm10, xmm8, xmm14
14000a2bd:     	vfmadd231sd	xmm5, xmm10, xmm10 # xmm5 = (xmm10 * xmm10) + xmm5
14000a2c2:     	vsubsd	xmm8, xmm0, qword ptr [rsp + 0x470]
14000a2cb:     	vfmadd231sd	xmm5, xmm8, xmm8 # xmm5 = (xmm8 * xmm8) + xmm5
14000a2d0:     	vpunpcklqdq	xmm14, xmm4, xmm5 # xmm14 = xmm4[0],xmm5[0]
14000a2d4:     	vsqrtpd	xmm14, xmm14
14000a2d9:     	vmulsd	xmm4, xmm4, xmm14
14000a2de:     	vpsrldq	xmm14, xmm14, 0x8       # xmm14 = xmm14[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a2e4:     	vmulsd	xmm5, xmm5, xmm14
14000a2e9:     	vpunpcklqdq	xmm4, xmm4, xmm5 # xmm4 = xmm4[0],xmm5[0]
14000a2ed:     	vdivpd	xmm4, xmm9, xmm4
14000a2f1:     	vpshufd	xmm5, xmm4, 0x44        # xmm5 = xmm4[0,1,0,1]
14000a2f6:     	vfnmadd213pd	xmm3, xmm5, xmmword ptr [rsp + 0x400] # xmm3 = -(xmm5 * xmm3) + mem
14000a300:     	vmulpd	xmm5, xmm12, xmm5
14000a304:     	vmovups	xmm12, xmmword ptr [rsp + 0x440]
14000a30d:     	vaddpd	xmm5, xmm12, xmm5
14000a311:     	vmovsd	xmm12, qword ptr [rsp + 0x430]
14000a31a:     	vmovups	xmmword ptr [rsp + 0x500], xmm5
14000a323:     	vmulsd	xmm14, xmm11, xmm12
14000a328:     	vmovsd	xmm12, qword ptr [rsp + 0x410]
14000a331:     	vfnmadd231sd	xmm12, xmm14, xmm4 # xmm12 = -(xmm14 * xmm4) + xmm12
14000a336:     	vmovsd	xmm14, qword ptr [rsp + 0x3f0]
14000a33f:     	vmulsd	xmm5, xmm11, xmm14
14000a344:     	vfmadd213sd	xmm5, xmm4, qword ptr [rsp + 0x450] # xmm5 = (xmm4 * xmm5) + mem
14000a34e:     	vmovsd	qword ptr [rsp + 0x510], xmm5
14000a357:     	vpunpcklqdq	xmm7, xmm7, xmm10 # xmm7 = xmm7[0],xmm10[0]
14000a35c:     	vmulpd	xmm10, xmm7, xmm15
14000a361:     	vmulpd	xmm7, xmm7, xmm1
14000a365:     	vpsrldq	xmm4, xmm4, 0x8         # xmm4 = xmm4[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a36a:     	vpshufd	xmm11, xmm4, 0x44       # xmm11 = xmm4[0,1,0,1]
14000a36f:     	vmulpd	xmm10, xmm10, xmm11
14000a374:     	vsubpd	xmm3, xmm3, xmm10
14000a379:     	vmulpd	xmm7, xmm7, xmm11
14000a37e:     	vaddpd	xmm10, xmm13, xmm7
14000a382:     	vmovups	xmmword ptr [rsp + 0x520], xmm10
14000a38b:     	vmulsd	xmm7, xmm8, xmm2
14000a38f:     	vmulsd	xmm7, xmm7, xmm4
14000a393:     	vsubsd	xmm11, xmm12, xmm7
14000a397:     	vmulsd	xmm7, xmm8, xmm14
14000a39c:     	vmulsd	xmm4, xmm7, xmm4
14000a3a0:     	vaddsd	xmm4, xmm6, xmm4
14000a3a4:     	vmovups	xmm6, xmmword ptr [rsp + 0x330]
14000a3ad:     	vmovups	xmm12, xmmword ptr [rsp + 0x380]
14000a3b6:     	vmovsd	qword ptr [rsp + 0x530], xmm4
14000a3bf:     	vsubsd	xmm7, xmm6, xmm12
14000a3c4:     	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
14000a3cd:     	vmovups	xmm13, xmmword ptr [rsp + 0x480]
14000a3d6:     	vsubsd	xmm8, xmm8, xmm13
14000a3db:     	vpunpcklqdq	xmm13, xmm7, xmm8 # xmm13 = xmm7[0],xmm8[0]
14000a3e0:     	vmovups	xmm12, xmmword ptr [rsp + 0x4c0]
14000a3e9:     	vmulpd	xmm4, xmm13, xmm12
14000a3ee:     	vmulpd	xmm1, xmm13, xmm1
14000a3f2:     	vsubsd	xmm12, xmm0, qword ptr [rsp + 0x490]
14000a3fb:     	vmulsd	xmm0, xmm7, xmm7
14000a3ff:     	vfmadd231sd	xmm0, xmm8, xmm8 # xmm0 = (xmm8 * xmm8) + xmm0
14000a404:     	vfmadd231sd	xmm0, xmm12, xmm12 # xmm0 = (xmm12 * xmm12) + xmm0
14000a409:     	vmovups	xmm8, xmmword ptr [rsp + 0x360]
14000a412:     	vmovups	xmm7, xmmword ptr [rsp + 0x350]
14000a41b:     	vsubsd	xmm13, xmm7, xmm8
14000a420:     	vmulsd	xmm7, xmm13, xmm13
14000a425:     	vmovups	xmm8, xmmword ptr [rsp + 0x460]
14000a42e:     	vmovups	xmm5, xmmword ptr [rsp + 0x3c0]
14000a437:     	vsubsd	xmm2, xmm5, xmm8
14000a43c:     	vfmadd231sd	xmm7, xmm2, xmm2 # xmm7 = (xmm2 * xmm2) + xmm7
14000a441:     	vmovsd	xmm8, qword ptr [rsp + 0x3d0]
14000a44a:     	vsubsd	xmm10, xmm8, qword ptr [rsp + 0x470]
14000a453:     	vmulsd	xmm5, xmm10, xmm10
14000a458:     	vaddsd	xmm5, xmm7, xmm5
14000a45c:     	vpunpcklqdq	xmm7, xmm0, xmm5 # xmm7 = xmm0[0],xmm5[0]
14000a460:     	vsqrtpd	xmm7, xmm7
14000a464:     	vmulsd	xmm0, xmm0, xmm7
14000a468:     	vpsrldq	xmm7, xmm7, 0x8         # xmm7 = xmm7[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a46d:     	vmulsd	xmm5, xmm5, xmm7
14000a471:     	vpunpcklqdq	xmm0, xmm0, xmm5 # xmm0 = xmm0[0],xmm5[0]
14000a475:     	vdivpd	xmm0, xmm9, xmm0
14000a479:     	vpshufd	xmm5, xmm0, 0x44        # xmm5 = xmm0[0,1,0,1]
14000a47e:     	vmulpd	xmm4, xmm4, xmm5
14000a482:     	vmovups	xmm8, xmmword ptr [rsp + 0x350]
14000a48b:     	vsubpd	xmm7, xmm3, xmm4
14000a48f:     	vmovups	xmm4, xmmword ptr [rsp + 0x2f0]
14000a498:     	vfmadd231pd	xmm6, xmm7, xmm4 # xmm6 = (xmm7 * xmm4) + xmm6
14000a49d:     	vmovups	xmmword ptr [rsp + 0x330], xmm6
14000a4a6:     	vfmadd213pd	xmm1, xmm5, xmmword ptr [rsp + 0x4e0] # xmm1 = (xmm5 * xmm1) + mem
14000a4b0:     	vmovsd	xmm5, qword ptr [rsp + 0x4d0]
14000a4b9:     	vmulsd	xmm3, xmm12, xmm5
14000a4bd:     	vfnmadd231sd	xmm11, xmm3, xmm0 # xmm11 = -(xmm3 * xmm0) + xmm11
14000a4c2:     	vmovsd	qword ptr [rbx + 0x60], xmm11
14000a4c7:     	vmulsd	xmm3, xmm12, xmm14
14000a4cc:     	vmulsd	xmm3, xmm3, xmm0
14000a4d0:     	vmovsd	xmm12, qword ptr [rsp + 0x4f8]
14000a4d9:     	vaddsd	xmm3, xmm12, xmm3
14000a4dd:     	vmovsd	qword ptr [rsp + 0x540], xmm3
14000a4e6:     	vxorpd	xmm12, xmm12, xmm12
14000a4eb:     	vpunpcklqdq	xmm2, xmm13, xmm2 # xmm2 = xmm13[0],xmm2[0]
14000a4ef:     	vmulpd	xmm12, xmm2, xmm15
14000a4f4:     	vmovups	xmm13, xmmword ptr [rsp + 0x420]
14000a4fd:     	vmulpd	xmm2, xmm2, xmm13
14000a502:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a507:     	vpshufd	xmm14, xmm0, 0x44       # xmm14 = xmm0[0,1,0,1]
14000a50c:     	vmovups	xmm6, xmmword ptr [rsp + 0x500]
14000a515:     	vfnmadd231pd	xmm6, xmm12, xmm14 # xmm6 = -(xmm12 * xmm14) + xmm6
14000a51a:     	vfmadd213pd	xmm2, xmm14, xmmword ptr [rsp + 0x520] # xmm2 = (xmm14 * xmm2) + mem
14000a524:     	vmovsd	xmm12, qword ptr [rsp + 0x4b0]
14000a52d:     	vmovups	xmmword ptr [rsp + 0x550], xmm2
14000a536:     	vmulsd	xmm14, xmm10, xmm12
14000a53b:     	vmovups	xmmword ptr [rsp + 0x340], xmm7
14000a544:     	vmovsd	xmm7, qword ptr [rsp + 0x510]
14000a54d:     	vfnmadd231sd	xmm7, xmm14, xmm0 # xmm7 = -(xmm14 * xmm0) + xmm7
14000a552:     	vmulsd	xmm10, xmm10, qword ptr [rsp + 0x430]
14000a55b:     	vmulsd	xmm0, xmm10, xmm0
14000a55f:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x530]
14000a568:     	vmovsd	qword ptr [rsp + 0x560], xmm0
14000a571:     	vmovups	xmm10, xmmword ptr [rsp + 0x380]
14000a57a:     	vsubsd	xmm11, xmm8, xmm10
14000a57f:     	vmovups	xmm12, xmmword ptr [rsp + 0x3c0]
14000a588:     	vmovups	xmm0, xmmword ptr [rsp + 0x480]
14000a591:     	vsubsd	xmm12, xmm12, xmm0
14000a595:     	vpunpcklqdq	xmm2, xmm11, xmm12 # xmm2 = xmm11[0],xmm12[0]
14000a59a:     	vmovups	xmmword ptr [rsp + 0x4a0], xmm15
14000a5a3:     	vmovups	xmm15, xmmword ptr [rsp + 0x4c0]
14000a5ac:     	vmulpd	xmm3, xmm2, xmm15
14000a5b1:     	vmulpd	xmm2, xmm2, xmm13
14000a5b6:     	vmovsd	xmm13, qword ptr [rsp + 0x490]
14000a5bf:     	vmovsd	xmm15, qword ptr [rsp + 0x3d0]
14000a5c8:     	vsubsd	xmm14, xmm15, xmm13
14000a5cd:     	vmulsd	xmm11, xmm11, xmm11
14000a5d2:     	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
14000a5d7:     	vfmadd231sd	xmm11, xmm14, xmm14 # xmm11 = (xmm14 * xmm14) + xmm11
14000a5dc:     	vmovups	xmm12, xmmword ptr [rsp + 0x360]
14000a5e5:     	vsubsd	xmm15, xmm12, xmm10
14000a5ea:     	vmovsd	qword ptr [rsp + 0x568], xmm15
14000a5f3:     	vmulsd	xmm10, xmm15, xmm15
14000a5f8:     	vmovups	xmm12, xmmword ptr [rsp + 0x460]
14000a601:     	vsubsd	xmm0, xmm12, xmm0
14000a605:     	vfmadd231sd	xmm10, xmm0, xmm0 # xmm10 = (xmm0 * xmm0) + xmm10
14000a60a:     	vmovsd	xmm12, qword ptr [rsp + 0x470]
14000a613:     	vsubsd	xmm15, xmm12, xmm13
14000a618:     	vfmadd231sd	xmm10, xmm15, xmm15 # xmm10 = (xmm15 * xmm15) + xmm10
14000a61d:     	vpunpcklqdq	xmm13, xmm11, xmm10 # xmm13 = xmm11[0],xmm10[0]
14000a622:     	vsqrtpd	xmm13, xmm13
14000a627:     	vmulsd	xmm11, xmm11, xmm13
14000a62c:     	vpsrldq	xmm13, xmm13, 0x8       # xmm13 = xmm13[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a632:     	vmulsd	xmm10, xmm10, xmm13
14000a637:     	vpunpcklqdq	xmm10, xmm11, xmm10 # xmm10 = xmm11[0],xmm10[0]
14000a63c:     	vdivpd	xmm10, xmm9, xmm10
14000a641:     	vpshufd	xmm11, xmm10, 0x44      # xmm11 = xmm10[0,1,0,1]
14000a647:     	vmulpd	xmm3, xmm3, xmm11
14000a64c:     	vmovups	xmm13, xmm9
14000a651:     	vsubpd	xmm9, xmm6, xmm3
14000a655:     	vfmadd231pd	xmm8, xmm9, xmm4 # xmm8 = (xmm9 * xmm4) + xmm8
14000a65a:     	vmovups	xmmword ptr [rsp + 0x350], xmm8
14000a663:     	vfmadd231pd	xmm1, xmm2, xmm11 # xmm1 = (xmm2 * xmm11) + xmm1
14000a668:     	vmulsd	xmm2, xmm14, xmm5
14000a66c:     	vfnmadd213sd	xmm2, xmm10, xmm7 # xmm2 = -(xmm10 * xmm2) + xmm7
14000a671:     	vmovsd	qword ptr [rbx + 0x98], xmm2
14000a679:     	vmovsd	xmm3, qword ptr [rsp + 0x430]
14000a682:     	vmulsd	xmm3, xmm14, xmm3
14000a686:     	vmovsd	xmm6, qword ptr [rsp + 0x540]
14000a68f:     	vfmadd231sd	xmm6, xmm3, xmm10 # xmm6 = (xmm3 * xmm10) + xmm6
14000a694:     	vmovsd	xmm3, qword ptr [rsp + 0x568]
14000a69d:     	vpunpcklqdq	xmm0, xmm3, xmm0 # xmm0 = xmm3[0],xmm0[0]
14000a6a1:     	vmovups	xmm3, xmmword ptr [rsp + 0x4c0]
14000a6aa:     	vmulpd	xmm3, xmm0, xmm3
14000a6ae:     	vmovups	xmm7, xmmword ptr [rsp + 0x4a0]
14000a6b7:     	vmulpd	xmm0, xmm0, xmm7
14000a6bb:     	vpsrldq	xmm7, xmm10, 0x8        # xmm7 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000a6c1:     	vpshufd	xmm10, xmm7, 0x44       # xmm10 = xmm7[0,1,0,1]
14000a6c6:     	vmulpd	xmm3, xmm3, xmm10
14000a6cb:     	vmovups	xmm11, xmmword ptr [rsp + 0x550]
14000a6d4:     	vsubpd	xmm11, xmm11, xmm3
14000a6d8:     	vmulpd	xmm3, xmm11, xmm4
14000a6dc:     	vmovups	xmm14, xmmword ptr [rsp + 0x360]
14000a6e5:     	vaddpd	xmm14, xmm14, xmm3
14000a6e9:     	vmovups	xmmword ptr [rsp + 0x360], xmm14
14000a6f2:     	vmulpd	xmm0, xmm0, xmm10
14000a6f7:     	vaddpd	xmm3, xmm1, xmm0
14000a6fb:     	vmovups	xmm10, xmmword ptr [rsp + 0x380]
14000a704:     	vfmadd231pd	xmm10, xmm3, xmm4 # xmm10 = (xmm3 * xmm4) + xmm10
14000a709:     	vmovups	xmmword ptr [rsp + 0x380], xmm10
14000a712:     	vmulsd	xmm0, xmm15, xmm5
14000a716:     	vfnmadd213sd	xmm0, xmm7, qword ptr [rsp + 0x560] # xmm0 = -(xmm7 * xmm0) + mem
14000a720:     	vmovsd	qword ptr [rbx + 0xd0], xmm0
14000a728:     	vmovsd	xmm1, qword ptr [rsp + 0x4b0]
14000a731:     	vmulsd	xmm1, xmm15, xmm1
14000a735:     	vfmadd213sd	xmm1, xmm7, xmm6 # xmm1 = (xmm7 * xmm1) + xmm6
14000a73a:     	vmovsd	qword ptr [rbx + 0x108], xmm1
14000a742:     	vmovsd	xmm6, qword ptr [rip + 0x2b16] # 0x14000d260
14000a74a:     	vmovsd	xmm5, qword ptr [rbx + 0x28]
14000a74f:     	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b0] # xmm5 = (xmm6 * xmm5) + mem
14000a759:     	vmovsd	qword ptr [rbx + 0x10], xmm5
14000a75e:     	vmovsd	xmm5, qword ptr [rbx + 0x60]
14000a763:     	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b8] # xmm5 = (xmm6 * xmm5) + mem
14000a76d:     	vmovsd	qword ptr [rbx + 0x48], xmm5
14000a772:     	vfmadd213sd	xmm2, xmm6, qword ptr [rsp + 0x3d0] # xmm2 = (xmm6 * xmm2) + mem
14000a77c:     	vmovsd	qword ptr [rbx + 0x80], xmm2
14000a784:     	vfmadd213sd	xmm0, xmm6, xmm12 # xmm0 = (xmm6 * xmm0) + xmm12
14000a789:     	vmovsd	qword ptr [rbx + 0xb8], xmm0
14000a791:     	vmulsd	xmm0, xmm1, xmm6
14000a795:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x490]
14000a79e:     	vmovsd	qword ptr [rbx + 0xf0], xmm0
14000a7a6:     	add	rax, 0x1
14000a7aa:     	cmp	rax, 0x7a120
14000a7b1:     	jl	0x140009e90 <.text+0x8e90>
