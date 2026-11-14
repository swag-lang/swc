140006de0:     	vmovups	xmm2, xmm13
140006de5:     	vmovups	xmm4, xmmword ptr [rsp + 0x320]
140006dee:     	vmovups	xmm5, xmmword ptr [rsp + 0x330]
140006df7:     	vmovups	xmm7, xmmword ptr [rsp + 0x340]
140006e00:     	vmovups	xmm10, xmm14
140006e05:     	vmovups	xmmword ptr [rsp + 0x370], xmm11
140006e0e:     	vmovups	xmm13, xmm3
140006e12:     	vmovups	xmm3, xmmword ptr [rsp + 0x310]
140006e1b:     	vsubsd	xmm14, xmm3, xmm5
140006e1f:     	vpsrldq	xmm15, xmm3, 0x8        # xmm15 = xmm3[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006e24:     	vpsrldq	xmm6, xmm5, 0x8         # xmm6 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006e29:     	vmovups	xmmword ptr [rsp + 0x3a0], xmm6
140006e32:     	vsubsd	xmm0, xmm15, xmm6
140006e36:     	vpunpcklqdq	xmm6, xmm14, xmm0 # xmm6 = xmm14[0],xmm0[0]
140006e3a:     	vmovsd	xmm5, qword ptr [rbx + 0x10]
140006e3f:     	vmovups	xmmword ptr [rsp + 0x390], xmm13
140006e48:     	vmovsd	qword ptr [rsp + 0x3b0], xmm5
140006e51:     	vmovsd	xmm13, qword ptr [rbx + 0x48]
140006e56:     	vmovsd	qword ptr [rsp + 0x3b8], xmm13
140006e5f:     	vsubsd	xmm1, xmm5, xmm13
140006e64:     	vmulsd	xmm13, xmm14, xmm14
140006e69:     	vfmadd213sd	xmm0, xmm0, xmm13 # xmm0 = (xmm0 * xmm0) + xmm13
140006e6e:     	vfmadd231sd	xmm0, xmm1, xmm1 # xmm0 = (xmm1 * xmm1) + xmm0
140006e73:     	vsubsd	xmm13, xmm3, xmm8
140006e78:     	vmulsd	xmm14, xmm13, xmm13
140006e7d:     	vpsrldq	xmm11, xmm8, 0x8        # xmm11 = xmm8[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006e83:     	vmovups	xmmword ptr [rsp + 0x3c0], xmm11
140006e8c:     	vsubsd	xmm8, xmm15, xmm11
140006e91:     	vmulsd	xmm11, xmm8, xmm8
140006e96:     	vaddsd	xmm11, xmm14, xmm11
140006e9b:     	vmovsd	xmm14, qword ptr [rbx + 0x80]
140006ea3:     	vmovsd	qword ptr [rsp + 0x3d0], xmm14
140006eac:     	vsubsd	xmm12, xmm5, xmm14
140006eb1:     	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
140006eb6:     	vpunpcklqdq	xmm0, xmm0, xmm11 # xmm0 = xmm0[0],xmm11[0]
140006ebb:     	vsqrtpd	xmm11, xmm0
140006ebf:     	vmulpd	xmm0, xmm0, xmm11
140006ec4:     	vdivpd	xmm0, xmm2, xmm0
140006ec8:     	vpshufd	xmm11, xmm0, 0x44       # xmm11 = xmm0[0,1,0,1]
140006ecd:     	vmovsd	xmm14, qword ptr [rsp + 0x68]
140006ed3:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140006ed9:     	vmulpd	xmm2, xmm6, xmm14
140006ede:     	vmovups	xmmword ptr [rsp + 0x3e0], xmm14
140006ee7:     	vmovsd	xmm14, qword ptr [rbx + 0x68]
140006eec:     	vmovsd	qword ptr [rsp + 0x3f0], xmm14
140006ef5:     	vfnmadd213pd	xmm2, xmm11, xmm4 # xmm2 = -(xmm11 * xmm2) + xmm4
140006efa:     	vmulsd	xmm4, xmm1, xmm14
140006eff:     	vfnmadd213sd	xmm4, xmm0, qword ptr [rbx + 0x28] # xmm4 = -(xmm0 * xmm4) + mem
140006f05:     	vmovsd	xmm14, qword ptr [rsp + 0x30]
140006f0b:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140006f11:     	vmulpd	xmm6, xmm6, xmm14
140006f16:     	vmulpd	xmm6, xmm6, xmm11
140006f1b:     	vmovsd	xmm11, qword ptr [rbx + 0x30]
140006f20:     	vaddpd	xmm6, xmm7, xmm6
140006f24:     	vmovups	xmmword ptr [rsp + 0x400], xmm6
140006f2d:     	vmulsd	xmm1, xmm1, xmm11
140006f32:     	vfmadd213sd	xmm1, xmm0, qword ptr [rbx + 0x60] # xmm1 = (xmm0 * xmm1) + mem
140006f38:     	vmovsd	qword ptr [rsp + 0x410], xmm1
140006f41:     	vpunpcklqdq	xmm7, xmm13, xmm8 # xmm7 = xmm13[0],xmm8[0]
140006f46:     	vmulpd	xmm8, xmm7, xmm14
140006f4b:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006f50:     	vpshufd	xmm13, xmm0, 0x44       # xmm13 = xmm0[0,1,0,1]
140006f55:     	vmulpd	xmm8, xmm8, xmm13
140006f5a:     	vmovsd	xmm1, qword ptr [rsp + 0xa0]
140006f63:     	vpshufd	xmm1, xmm1, 0x44        # xmm1 = xmm1[0,1,0,1]
140006f68:     	vmulpd	xmm7, xmm7, xmm1
140006f6c:     	vfnmadd231pd	xmm2, xmm7, xmm13 # xmm2 = -(xmm7 * xmm13) + xmm2
140006f71:     	vmovsd	xmm13, qword ptr [rbx + 0xa0]
140006f79:     	vmovsd	qword ptr [rsp + 0x430], xmm13
140006f82:     	vmulsd	xmm7, xmm12, xmm13
140006f87:     	vmulsd	xmm7, xmm7, xmm0
140006f8b:     	vsubsd	xmm4, xmm4, xmm7
140006f8f:     	vaddpd	xmm7, xmm9, xmm8
140006f94:     	vmovups	xmmword ptr [rsp + 0x440], xmm7
140006f9d:     	vmulsd	xmm8, xmm12, xmm11
140006fa2:     	vmulsd	xmm0, xmm8, xmm0
140006fa6:     	vaddsd	xmm0, xmm0, qword ptr [rbx + 0x98]
140006fae:     	vmovsd	qword ptr [rsp + 0x450], xmm0
140006fb7:     	vsubsd	xmm8, xmm3, xmm10
140006fbc:     	vpsrldq	xmm9, xmm10, 0x8        # xmm9 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006fc2:     	vmovups	xmmword ptr [rsp + 0x460], xmm9
140006fcb:     	vsubsd	xmm12, xmm15, xmm9
140006fd0:     	vpunpcklqdq	xmm0, xmm8, xmm12 # xmm0 = xmm8[0],xmm12[0]
140006fd5:     	vmulpd	xmm13, xmm0, xmm14
140006fda:     	vmovsd	xmm7, qword ptr [rbx + 0xb8]
140006fe2:     	vmovsd	qword ptr [rsp + 0x470], xmm7
140006feb:     	vsubsd	xmm6, xmm5, xmm7
140006fef:     	vmulsd	xmm7, xmm8, xmm8
140006ff4:     	vfmadd231sd	xmm7, xmm12, xmm12 # xmm7 = (xmm12 * xmm12) + xmm7
140006ff9:     	vfmadd231sd	xmm7, xmm6, xmm6 # xmm7 = (xmm6 * xmm6) + xmm7
140006ffe:     	vmovups	xmm12, xmmword ptr [rsp + 0x380]
140007007:     	vsubsd	xmm8, xmm3, xmm12
14000700c:     	vmulsd	xmm9, xmm8, xmm8
140007011:     	vpsrldq	xmm10, xmm12, 0x8       # xmm10 = xmm12[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007017:     	vmovups	xmmword ptr [rsp + 0x480], xmm10
140007020:     	vsubsd	xmm12, xmm15, xmm10
140007025:     	vfmadd231sd	xmm9, xmm12, xmm12 # xmm9 = (xmm12 * xmm12) + xmm9
14000702a:     	vmovsd	xmm15, qword ptr [rbx + 0xf0]
140007032:     	vmovsd	qword ptr [rsp + 0x490], xmm15
14000703b:     	vsubsd	xmm10, xmm5, xmm15
140007040:     	vmulsd	xmm5, xmm10, xmm10
140007045:     	vaddsd	xmm5, xmm9, xmm5
140007049:     	vpunpcklqdq	xmm5, xmm7, xmm5 # xmm5 = xmm7[0],xmm5[0]
14000704d:     	vsqrtpd	xmm7, xmm5
140007051:     	vmulpd	xmm5, xmm5, xmm7
140007055:     	vmovups	xmm9, xmmword ptr [rsp + 0x300]
14000705e:     	vdivpd	xmm5, xmm9, xmm5
140007062:     	vpshufd	xmm7, xmm5, 0x44        # xmm7 = xmm5[0,1,0,1]
140007067:     	vmulpd	xmm13, xmm13, xmm7
14000706b:     	vmovsd	xmm15, qword ptr [rsp + 0xd8]
140007074:     	vpshufd	xmm15, xmm15, 0x44      # xmm15 = xmm15[0,1,0,1]
14000707a:     	vmulpd	xmm0, xmm0, xmm15
14000707f:     	vfnmadd213pd	xmm0, xmm7, xmm2 # xmm0 = -(xmm7 * xmm0) + xmm2
140007084:     	vmovsd	xmm2, qword ptr [rbx + 0xd8]
14000708c:     	vmovsd	qword ptr [rsp + 0x4b0], xmm2
140007095:     	vmulsd	xmm7, xmm6, xmm2
140007099:     	vfnmadd213sd	xmm7, xmm5, xmm4 # xmm7 = -(xmm5 * xmm7) + xmm4
14000709e:     	vmovups	xmm4, xmmword ptr [rsp + 0x370]
1400070a7:     	vaddpd	xmm13, xmm4, xmm13
1400070ac:     	vmulsd	xmm4, xmm6, xmm11
1400070b1:     	vmovsd	xmm6, qword ptr [rbx + 0xd0]
1400070b9:     	vfmadd231sd	xmm6, xmm4, xmm5 # xmm6 = (xmm4 * xmm5) + xmm6
1400070be:     	vpunpcklqdq	xmm4, xmm8, xmm12 # xmm4 = xmm8[0],xmm12[0]
1400070c3:     	vmulpd	xmm8, xmm4, xmm14
1400070c8:     	vpsrldq	xmm5, xmm5, 0x8         # xmm5 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
1400070cd:     	vpshufd	xmm12, xmm5, 0x44       # xmm12 = xmm5[0,1,0,1]
1400070d2:     	vmulpd	xmm8, xmm8, xmm12
1400070d7:     	vmovsd	xmm14, qword ptr [rsp + 0x110]
1400070e0:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
1400070e6:     	vmovups	xmmword ptr [rsp + 0x4c0], xmm14
1400070ef:     	vmulpd	xmm4, xmm4, xmm14
1400070f4:     	vfnmadd213pd	xmm4, xmm12, xmm0 # xmm4 = -(xmm12 * xmm4) + xmm0
1400070f9:     	vfmadd231pd	xmm3, xmm4, xmmword ptr [rsp + 0x2f0] # xmm3 = (xmm4 * mem) + xmm3
140007103:     	vmovsd	xmm12, qword ptr [rbx + 0x110]
14000710b:     	vmovups	xmmword ptr [rsp + 0x310], xmm3
140007114:     	vmovups	xmm3, xmmword ptr [rsp + 0x390]
14000711d:     	vmovsd	qword ptr [rsp + 0x4d0], xmm12
140007126:     	vaddpd	xmm3, xmm3, xmm8
14000712b:     	vmovups	xmmword ptr [rsp + 0x4e0], xmm3
140007134:     	vmulsd	xmm8, xmm10, xmm12
140007139:     	vfnmadd213sd	xmm8, xmm5, xmm7 # xmm8 = -(xmm5 * xmm8) + xmm7
14000713e:     	vmovsd	qword ptr [rbx + 0x28], xmm8
140007143:     	vmulsd	xmm7, xmm10, xmm11
140007148:     	vmulsd	xmm5, xmm7, xmm5
14000714c:     	vaddsd	xmm5, xmm5, qword ptr [rbx + 0x108]
140007154:     	vmovsd	qword ptr [rsp + 0x4f8], xmm5
14000715d:     	vmovups	xmm10, xmmword ptr [rsp + 0x330]
140007166:     	vmovups	xmm11, xmmword ptr [rsp + 0x350]
14000716f:     	vsubsd	xmm7, xmm10, xmm11
140007174:     	vmovups	xmmword ptr [rsp + 0x320], xmm4
14000717d:     	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
140007186:     	vmovups	xmm4, xmmword ptr [rsp + 0x3c0]
14000718f:     	vsubsd	xmm5, xmm8, xmm4
140007193:     	vpunpcklqdq	xmm12, xmm7, xmm5 # xmm12 = xmm7[0],xmm5[0]
140007197:     	vmulpd	xmm3, xmm12, xmm1
14000719b:     	vmovups	xmmword ptr [rsp + 0x420], xmm1
1400071a4:     	vmovups	xmm1, xmmword ptr [rsp + 0x3e0]
1400071ad:     	vmulpd	xmm12, xmm12, xmm1
1400071b1:     	vmovsd	xmm0, qword ptr [rsp + 0x3b8]
1400071ba:     	vsubsd	xmm11, xmm0, qword ptr [rsp + 0x3d0]
1400071c3:     	vmulsd	xmm4, xmm7, xmm7
1400071c7:     	vfmadd231sd	xmm4, xmm5, xmm5 # xmm4 = (xmm5 * xmm5) + xmm4
1400071cc:     	vfmadd231sd	xmm4, xmm11, xmm11 # xmm4 = (xmm11 * xmm11) + xmm4
1400071d1:     	vmovups	xmm5, xmmword ptr [rsp + 0x360]
1400071da:     	vsubsd	xmm7, xmm10, xmm5
1400071de:     	vmulsd	xmm5, xmm7, xmm7
1400071e2:     	vmovups	xmm14, xmmword ptr [rsp + 0x460]
1400071eb:     	vsubsd	xmm10, xmm8, xmm14
1400071f0:     	vfmadd231sd	xmm5, xmm10, xmm10 # xmm5 = (xmm10 * xmm10) + xmm5
1400071f5:     	vsubsd	xmm8, xmm0, qword ptr [rsp + 0x470]
1400071fe:     	vfmadd231sd	xmm5, xmm8, xmm8 # xmm5 = (xmm8 * xmm8) + xmm5
140007203:     	vpunpcklqdq	xmm4, xmm4, xmm5 # xmm4 = xmm4[0],xmm5[0]
140007207:     	vsqrtpd	xmm5, xmm4
14000720b:     	vmulpd	xmm4, xmm4, xmm5
14000720f:     	vdivpd	xmm4, xmm9, xmm4
140007213:     	vpshufd	xmm5, xmm4, 0x44        # xmm5 = xmm4[0,1,0,1]
140007218:     	vfnmadd213pd	xmm3, xmm5, xmmword ptr [rsp + 0x400] # xmm3 = -(xmm5 * xmm3) + mem
140007222:     	vmulpd	xmm5, xmm12, xmm5
140007226:     	vmovups	xmm12, xmmword ptr [rsp + 0x440]
14000722f:     	vaddpd	xmm5, xmm12, xmm5
140007233:     	vmovsd	xmm12, qword ptr [rsp + 0x430]
14000723c:     	vmovups	xmmword ptr [rsp + 0x500], xmm5
140007245:     	vmulsd	xmm14, xmm11, xmm12
14000724a:     	vmovsd	xmm12, qword ptr [rsp + 0x410]
140007253:     	vfnmadd231sd	xmm12, xmm14, xmm4 # xmm12 = -(xmm14 * xmm4) + xmm12
140007258:     	vmovsd	xmm14, qword ptr [rsp + 0x3f0]
140007261:     	vmulsd	xmm5, xmm11, xmm14
140007266:     	vfmadd213sd	xmm5, xmm4, qword ptr [rsp + 0x450] # xmm5 = (xmm4 * xmm5) + mem
140007270:     	vmovsd	qword ptr [rsp + 0x510], xmm5
140007279:     	vpunpcklqdq	xmm7, xmm7, xmm10 # xmm7 = xmm7[0],xmm10[0]
14000727e:     	vmulpd	xmm10, xmm7, xmm15
140007283:     	vmulpd	xmm7, xmm7, xmm1
140007287:     	vpsrldq	xmm4, xmm4, 0x8         # xmm4 = xmm4[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000728c:     	vpshufd	xmm11, xmm4, 0x44       # xmm11 = xmm4[0,1,0,1]
140007291:     	vmulpd	xmm10, xmm10, xmm11
140007296:     	vsubpd	xmm3, xmm3, xmm10
14000729b:     	vmulpd	xmm7, xmm7, xmm11
1400072a0:     	vaddpd	xmm10, xmm13, xmm7
1400072a4:     	vmovups	xmmword ptr [rsp + 0x520], xmm10
1400072ad:     	vmulsd	xmm7, xmm8, xmm2
1400072b1:     	vmulsd	xmm7, xmm7, xmm4
1400072b5:     	vsubsd	xmm11, xmm12, xmm7
1400072b9:     	vmulsd	xmm7, xmm8, xmm14
1400072be:     	vmulsd	xmm4, xmm7, xmm4
1400072c2:     	vaddsd	xmm4, xmm6, xmm4
1400072c6:     	vmovups	xmm6, xmmword ptr [rsp + 0x330]
1400072cf:     	vmovups	xmm12, xmmword ptr [rsp + 0x380]
1400072d8:     	vmovsd	qword ptr [rsp + 0x530], xmm4
1400072e1:     	vsubsd	xmm7, xmm6, xmm12
1400072e6:     	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
1400072ef:     	vmovups	xmm13, xmmword ptr [rsp + 0x480]
1400072f8:     	vsubsd	xmm8, xmm8, xmm13
1400072fd:     	vpunpcklqdq	xmm13, xmm7, xmm8 # xmm13 = xmm7[0],xmm8[0]
140007302:     	vmovups	xmm12, xmmword ptr [rsp + 0x4c0]
14000730b:     	vmulpd	xmm4, xmm13, xmm12
140007310:     	vmulpd	xmm1, xmm13, xmm1
140007314:     	vsubsd	xmm12, xmm0, qword ptr [rsp + 0x490]
14000731d:     	vmulsd	xmm0, xmm7, xmm7
140007321:     	vfmadd231sd	xmm0, xmm8, xmm8 # xmm0 = (xmm8 * xmm8) + xmm0
140007326:     	vfmadd231sd	xmm0, xmm12, xmm12 # xmm0 = (xmm12 * xmm12) + xmm0
14000732b:     	vmovups	xmm8, xmmword ptr [rsp + 0x360]
140007334:     	vmovups	xmm7, xmmword ptr [rsp + 0x350]
14000733d:     	vsubsd	xmm13, xmm7, xmm8
140007342:     	vmulsd	xmm7, xmm13, xmm13
140007347:     	vmovups	xmm8, xmmword ptr [rsp + 0x460]
140007350:     	vmovups	xmm5, xmmword ptr [rsp + 0x3c0]
140007359:     	vsubsd	xmm2, xmm5, xmm8
14000735e:     	vfmadd231sd	xmm7, xmm2, xmm2 # xmm7 = (xmm2 * xmm2) + xmm7
140007363:     	vmovsd	xmm8, qword ptr [rsp + 0x3d0]
14000736c:     	vsubsd	xmm10, xmm8, qword ptr [rsp + 0x470]
140007375:     	vmulsd	xmm5, xmm10, xmm10
14000737a:     	vaddsd	xmm5, xmm7, xmm5
14000737e:     	vpunpcklqdq	xmm0, xmm0, xmm5 # xmm0 = xmm0[0],xmm5[0]
140007382:     	vsqrtpd	xmm5, xmm0
140007386:     	vmulpd	xmm0, xmm0, xmm5
14000738a:     	vdivpd	xmm0, xmm9, xmm0
14000738e:     	vpshufd	xmm5, xmm0, 0x44        # xmm5 = xmm0[0,1,0,1]
140007393:     	vmulpd	xmm4, xmm4, xmm5
140007397:     	vmovups	xmm8, xmmword ptr [rsp + 0x350]
1400073a0:     	vsubpd	xmm7, xmm3, xmm4
1400073a4:     	vmovups	xmm4, xmmword ptr [rsp + 0x2f0]
1400073ad:     	vfmadd231pd	xmm6, xmm7, xmm4 # xmm6 = (xmm7 * xmm4) + xmm6
1400073b2:     	vmovups	xmmword ptr [rsp + 0x330], xmm6
1400073bb:     	vfmadd213pd	xmm1, xmm5, xmmword ptr [rsp + 0x4e0] # xmm1 = (xmm5 * xmm1) + mem
1400073c5:     	vmovsd	xmm5, qword ptr [rsp + 0x4d0]
1400073ce:     	vmulsd	xmm3, xmm12, xmm5
1400073d2:     	vfnmadd231sd	xmm11, xmm3, xmm0 # xmm11 = -(xmm3 * xmm0) + xmm11
1400073d7:     	vmovsd	qword ptr [rbx + 0x60], xmm11
1400073dc:     	vmulsd	xmm3, xmm12, xmm14
1400073e1:     	vmulsd	xmm3, xmm3, xmm0
1400073e5:     	vmovsd	xmm12, qword ptr [rsp + 0x4f8]
1400073ee:     	vaddsd	xmm3, xmm12, xmm3
1400073f2:     	vmovsd	qword ptr [rsp + 0x540], xmm3
1400073fb:     	vxorpd	xmm12, xmm12, xmm12
140007400:     	vpunpcklqdq	xmm2, xmm13, xmm2 # xmm2 = xmm13[0],xmm2[0]
140007404:     	vmulpd	xmm12, xmm2, xmm15
140007409:     	vmovups	xmm13, xmmword ptr [rsp + 0x420]
140007412:     	vmulpd	xmm2, xmm2, xmm13
140007417:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000741c:     	vpshufd	xmm14, xmm0, 0x44       # xmm14 = xmm0[0,1,0,1]
140007421:     	vmovups	xmm6, xmmword ptr [rsp + 0x500]
14000742a:     	vfnmadd231pd	xmm6, xmm12, xmm14 # xmm6 = -(xmm12 * xmm14) + xmm6
14000742f:     	vfmadd213pd	xmm2, xmm14, xmmword ptr [rsp + 0x520] # xmm2 = (xmm14 * xmm2) + mem
140007439:     	vmovsd	xmm12, qword ptr [rsp + 0x4b0]
140007442:     	vmovups	xmmword ptr [rsp + 0x550], xmm2
14000744b:     	vmulsd	xmm14, xmm10, xmm12
140007450:     	vmovups	xmmword ptr [rsp + 0x340], xmm7
140007459:     	vmovsd	xmm7, qword ptr [rsp + 0x510]
140007462:     	vfnmadd231sd	xmm7, xmm14, xmm0 # xmm7 = -(xmm14 * xmm0) + xmm7
140007467:     	vmulsd	xmm10, xmm10, qword ptr [rsp + 0x430]
140007470:     	vmulsd	xmm0, xmm10, xmm0
140007474:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x530]
14000747d:     	vmovsd	qword ptr [rsp + 0x560], xmm0
140007486:     	vmovups	xmm10, xmmword ptr [rsp + 0x380]
14000748f:     	vsubsd	xmm11, xmm8, xmm10
140007494:     	vmovups	xmm12, xmmword ptr [rsp + 0x3c0]
14000749d:     	vmovups	xmm0, xmmword ptr [rsp + 0x480]
1400074a6:     	vsubsd	xmm12, xmm12, xmm0
1400074aa:     	vpunpcklqdq	xmm2, xmm11, xmm12 # xmm2 = xmm11[0],xmm12[0]
1400074af:     	vmovups	xmmword ptr [rsp + 0x4a0], xmm15
1400074b8:     	vmovups	xmm15, xmmword ptr [rsp + 0x4c0]
1400074c1:     	vmulpd	xmm3, xmm2, xmm15
1400074c6:     	vmulpd	xmm2, xmm2, xmm13
1400074cb:     	vmovsd	xmm13, qword ptr [rsp + 0x490]
1400074d4:     	vmovsd	xmm15, qword ptr [rsp + 0x3d0]
1400074dd:     	vsubsd	xmm14, xmm15, xmm13
1400074e2:     	vmulsd	xmm11, xmm11, xmm11
1400074e7:     	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
1400074ec:     	vfmadd231sd	xmm11, xmm14, xmm14 # xmm11 = (xmm14 * xmm14) + xmm11
1400074f1:     	vmovups	xmm12, xmmword ptr [rsp + 0x360]
1400074fa:     	vsubsd	xmm15, xmm12, xmm10
1400074ff:     	vmovsd	qword ptr [rsp + 0x568], xmm15
140007508:     	vmulsd	xmm10, xmm15, xmm15
14000750d:     	vmovups	xmm12, xmmword ptr [rsp + 0x460]
140007516:     	vsubsd	xmm0, xmm12, xmm0
14000751a:     	vfmadd231sd	xmm10, xmm0, xmm0 # xmm10 = (xmm0 * xmm0) + xmm10
14000751f:     	vmovsd	xmm12, qword ptr [rsp + 0x470]
140007528:     	vsubsd	xmm15, xmm12, xmm13
14000752d:     	vfmadd231sd	xmm10, xmm15, xmm15 # xmm10 = (xmm15 * xmm15) + xmm10
140007532:     	vpunpcklqdq	xmm10, xmm11, xmm10 # xmm10 = xmm11[0],xmm10[0]
140007537:     	vsqrtpd	xmm11, xmm10
14000753c:     	vmulpd	xmm10, xmm10, xmm11
140007541:     	vdivpd	xmm10, xmm9, xmm10
140007546:     	vpshufd	xmm11, xmm10, 0x44      # xmm11 = xmm10[0,1,0,1]
14000754c:     	vmulpd	xmm3, xmm3, xmm11
140007551:     	vmovups	xmm13, xmm9
140007556:     	vsubpd	xmm9, xmm6, xmm3
14000755a:     	vfmadd231pd	xmm8, xmm9, xmm4 # xmm8 = (xmm9 * xmm4) + xmm8
14000755f:     	vmovups	xmmword ptr [rsp + 0x350], xmm8
140007568:     	vfmadd231pd	xmm1, xmm2, xmm11 # xmm1 = (xmm2 * xmm11) + xmm1
14000756d:     	vmulsd	xmm2, xmm14, xmm5
140007571:     	vfnmadd213sd	xmm2, xmm10, xmm7 # xmm2 = -(xmm10 * xmm2) + xmm7
140007576:     	vmovsd	qword ptr [rbx + 0x98], xmm2
14000757e:     	vmovsd	xmm3, qword ptr [rsp + 0x430]
140007587:     	vmulsd	xmm3, xmm14, xmm3
14000758b:     	vmovsd	xmm6, qword ptr [rsp + 0x540]
140007594:     	vfmadd231sd	xmm6, xmm3, xmm10 # xmm6 = (xmm3 * xmm10) + xmm6
140007599:     	vmovsd	xmm3, qword ptr [rsp + 0x568]
1400075a2:     	vpunpcklqdq	xmm0, xmm3, xmm0 # xmm0 = xmm3[0],xmm0[0]
1400075a6:     	vmovups	xmm3, xmmword ptr [rsp + 0x4c0]
1400075af:     	vmulpd	xmm3, xmm0, xmm3
1400075b3:     	vmovups	xmm7, xmmword ptr [rsp + 0x4a0]
1400075bc:     	vmulpd	xmm0, xmm0, xmm7
1400075c0:     	vpsrldq	xmm7, xmm10, 0x8        # xmm7 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
1400075c6:     	vpshufd	xmm10, xmm7, 0x44       # xmm10 = xmm7[0,1,0,1]
1400075cb:     	vmulpd	xmm3, xmm3, xmm10
1400075d0:     	vmovups	xmm11, xmmword ptr [rsp + 0x550]
1400075d9:     	vsubpd	xmm11, xmm11, xmm3
1400075dd:     	vmulpd	xmm3, xmm11, xmm4
1400075e1:     	vmovups	xmm14, xmmword ptr [rsp + 0x360]
1400075ea:     	vaddpd	xmm14, xmm14, xmm3
1400075ee:     	vmovups	xmmword ptr [rsp + 0x360], xmm14
1400075f7:     	vmulpd	xmm0, xmm0, xmm10
1400075fc:     	vaddpd	xmm3, xmm1, xmm0
140007600:     	vmovups	xmm10, xmmword ptr [rsp + 0x380]
140007609:     	vfmadd231pd	xmm10, xmm3, xmm4 # xmm10 = (xmm3 * xmm4) + xmm10
14000760e:     	vmovups	xmmword ptr [rsp + 0x380], xmm10
140007617:     	vmulsd	xmm0, xmm15, xmm5
14000761b:     	vfnmadd213sd	xmm0, xmm7, qword ptr [rsp + 0x560] # xmm0 = -(xmm7 * xmm0) + mem
140007625:     	vmovsd	qword ptr [rbx + 0xd0], xmm0
14000762d:     	vmovsd	xmm1, qword ptr [rsp + 0x4b0]
140007636:     	vmulsd	xmm1, xmm15, xmm1
14000763a:     	vfmadd213sd	xmm1, xmm7, xmm6 # xmm1 = (xmm7 * xmm1) + xmm6
14000763f:     	vmovsd	qword ptr [rbx + 0x108], xmm1
140007647:     	vmovsd	xmm6, qword ptr [rip + 0x6321] # 0x14000d970
14000764f:     	vmovsd	xmm5, qword ptr [rbx + 0x28]
140007654:     	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b0] # xmm5 = (xmm6 * xmm5) + mem
14000765e:     	vmovsd	qword ptr [rbx + 0x10], xmm5
140007663:     	vmovsd	xmm5, qword ptr [rbx + 0x60]
140007668:     	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b8] # xmm5 = (xmm6 * xmm5) + mem
140007672:     	vmovsd	qword ptr [rbx + 0x48], xmm5
140007677:     	vfmadd213sd	xmm2, xmm6, qword ptr [rsp + 0x3d0] # xmm2 = (xmm6 * xmm2) + mem
140007681:     	vmovsd	qword ptr [rbx + 0x80], xmm2
140007689:     	vfmadd213sd	xmm0, xmm6, xmm12 # xmm0 = (xmm6 * xmm0) + xmm12
14000768e:     	vmovsd	qword ptr [rbx + 0xb8], xmm0
140007696:     	vmulsd	xmm0, xmm1, xmm6
14000769a:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x490]
1400076a3:     	vmovsd	qword ptr [rbx + 0xf0], xmm0
1400076ab:     	add	rax, 0x1
1400076af:     	cmp	rax, 0x7a120
1400076b6:     	jl	0x140006de0 <.text+0x5de0>
