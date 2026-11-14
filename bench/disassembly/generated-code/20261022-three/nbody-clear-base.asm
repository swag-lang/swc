140006e10:     	vmovups	xmm2, xmm13
140006e15:     	vmovups	xmm4, xmmword ptr [rsp + 0x320]
140006e1e:     	vmovups	xmm5, xmmword ptr [rsp + 0x330]
140006e27:     	vmovups	xmm7, xmmword ptr [rsp + 0x340]
140006e30:     	vmovups	xmm10, xmm14
140006e35:     	vmovups	xmmword ptr [rsp + 0x370], xmm11
140006e3e:     	vmovups	xmm13, xmm3
140006e42:     	vmovups	xmm3, xmmword ptr [rsp + 0x310]
140006e4b:     	vxorpd	xmm14, xmm14, xmm14
140006e50:     	vsubsd	xmm14, xmm3, xmm5
140006e54:     	vxorpd	xmm15, xmm15, xmm15
140006e59:     	vpsrldq	xmm15, xmm3, 0x8        # xmm15 = xmm3[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006e5e:     	vpsrldq	xmm6, xmm5, 0x8         # xmm6 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006e63:     	vmovups	xmmword ptr [rsp + 0x3a0], xmm6
140006e6c:     	vsubsd	xmm0, xmm15, xmm6
140006e70:     	vpunpcklqdq	xmm6, xmm14, xmm0 # xmm6 = xmm14[0],xmm0[0]
140006e74:     	vmovsd	xmm5, qword ptr [rbx + 0x10]
140006e79:     	vmovups	xmmword ptr [rsp + 0x390], xmm13
140006e82:     	vmovsd	qword ptr [rsp + 0x3b0], xmm5
140006e8b:     	vmovsd	xmm13, qword ptr [rbx + 0x48]
140006e90:     	vmovsd	qword ptr [rsp + 0x3b8], xmm13
140006e99:     	vsubsd	xmm1, xmm5, xmm13
140006e9e:     	vxorpd	xmm13, xmm13, xmm13
140006ea3:     	vmulsd	xmm13, xmm14, xmm14
140006ea8:     	vfmadd213sd	xmm0, xmm0, xmm13 # xmm0 = (xmm0 * xmm0) + xmm13
140006ead:     	vfmadd231sd	xmm0, xmm1, xmm1 # xmm0 = (xmm1 * xmm1) + xmm0
140006eb2:     	vsubsd	xmm13, xmm3, xmm8
140006eb7:     	vpsrldq	xmm11, xmm8, 0x8        # xmm11 = xmm8[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006ebd:     	vmovups	xmmword ptr [rsp + 0x3c0], xmm11
140006ec6:     	vsubsd	xmm8, xmm15, xmm11
140006ecb:     	vmulsd	xmm11, xmm8, xmm8
140006ed0:     	vfmadd231sd	xmm11, xmm13, xmm13 # xmm11 = (xmm13 * xmm13) + xmm11
140006ed5:     	vmovsd	xmm14, qword ptr [rbx + 0x80]
140006edd:     	vmovsd	qword ptr [rsp + 0x3d0], xmm14
140006ee6:     	vsubsd	xmm12, xmm5, xmm14
140006eeb:     	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
140006ef0:     	vpunpcklqdq	xmm14, xmm0, xmm11 # xmm14 = xmm0[0],xmm11[0]
140006ef5:     	vsqrtpd	xmm14, xmm14
140006efa:     	vmulsd	xmm0, xmm0, xmm14
140006eff:     	vpsrldq	xmm14, xmm14, 0x8       # xmm14 = xmm14[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006f05:     	vmulsd	xmm11, xmm11, xmm14
140006f0a:     	vpunpcklqdq	xmm0, xmm0, xmm11 # xmm0 = xmm0[0],xmm11[0]
140006f0f:     	vdivpd	xmm0, xmm2, xmm0
140006f13:     	vpshufd	xmm11, xmm0, 0x44       # xmm11 = xmm0[0,1,0,1]
140006f18:     	vmovsd	xmm14, qword ptr [rsp + 0x68]
140006f1e:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140006f24:     	vmulpd	xmm2, xmm6, xmm14
140006f29:     	vmovups	xmmword ptr [rsp + 0x3e0], xmm14
140006f32:     	vmovsd	xmm14, qword ptr [rbx + 0x68]
140006f37:     	vmovsd	qword ptr [rsp + 0x3f0], xmm14
140006f40:     	vfnmadd213pd	xmm2, xmm11, xmm4 # xmm2 = -(xmm11 * xmm2) + xmm4
140006f45:     	vmulsd	xmm4, xmm1, xmm14
140006f4a:     	vfnmadd213sd	xmm4, xmm0, qword ptr [rbx + 0x28] # xmm4 = -(xmm0 * xmm4) + mem
140006f50:     	vmovsd	xmm14, qword ptr [rsp + 0x30]
140006f56:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140006f5c:     	vmulpd	xmm6, xmm6, xmm14
140006f61:     	vmulpd	xmm6, xmm6, xmm11
140006f66:     	vmovsd	xmm11, qword ptr [rbx + 0x30]
140006f6b:     	vaddpd	xmm6, xmm7, xmm6
140006f6f:     	vmovups	xmmword ptr [rsp + 0x400], xmm6
140006f78:     	vmulsd	xmm1, xmm1, xmm11
140006f7d:     	vfmadd213sd	xmm1, xmm0, qword ptr [rbx + 0x60] # xmm1 = (xmm0 * xmm1) + mem
140006f83:     	vmovsd	qword ptr [rsp + 0x410], xmm1
140006f8c:     	vpunpcklqdq	xmm7, xmm13, xmm8 # xmm7 = xmm13[0],xmm8[0]
140006f91:     	vmulpd	xmm8, xmm7, xmm14
140006f96:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006f9b:     	vpshufd	xmm13, xmm0, 0x44       # xmm13 = xmm0[0,1,0,1]
140006fa0:     	vmulpd	xmm8, xmm8, xmm13
140006fa5:     	vmovsd	xmm1, qword ptr [rsp + 0xa0]
140006fae:     	vpshufd	xmm1, xmm1, 0x44        # xmm1 = xmm1[0,1,0,1]
140006fb3:     	vmulpd	xmm7, xmm7, xmm1
140006fb7:     	vfnmadd231pd	xmm2, xmm7, xmm13 # xmm2 = -(xmm7 * xmm13) + xmm2
140006fbc:     	vmovsd	xmm13, qword ptr [rbx + 0xa0]
140006fc4:     	vmovsd	qword ptr [rsp + 0x430], xmm13
140006fcd:     	vmulsd	xmm7, xmm12, xmm13
140006fd2:     	vmulsd	xmm7, xmm7, xmm0
140006fd6:     	vsubsd	xmm4, xmm4, xmm7
140006fda:     	vaddpd	xmm7, xmm9, xmm8
140006fdf:     	vmovups	xmmword ptr [rsp + 0x440], xmm7
140006fe8:     	vmulsd	xmm8, xmm12, xmm11
140006fed:     	vmulsd	xmm0, xmm8, xmm0
140006ff1:     	vaddsd	xmm0, xmm0, qword ptr [rbx + 0x98]
140006ff9:     	vmovsd	qword ptr [rsp + 0x450], xmm0
140007002:     	vxorpd	xmm8, xmm8, xmm8
140007007:     	vsubsd	xmm8, xmm3, xmm10
14000700c:     	vxorpd	xmm9, xmm9, xmm9
140007011:     	vpsrldq	xmm9, xmm10, 0x8        # xmm9 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007017:     	vmovups	xmmword ptr [rsp + 0x460], xmm9
140007020:     	vsubsd	xmm12, xmm15, xmm9
140007025:     	vpunpcklqdq	xmm0, xmm8, xmm12 # xmm0 = xmm8[0],xmm12[0]
14000702a:     	vmulpd	xmm13, xmm0, xmm14
14000702f:     	vmovsd	xmm7, qword ptr [rbx + 0xb8]
140007037:     	vmovsd	qword ptr [rsp + 0x470], xmm7
140007040:     	vsubsd	xmm6, xmm5, xmm7
140007044:     	vxorpd	xmm7, xmm7, xmm7
140007048:     	vmulsd	xmm7, xmm8, xmm8
14000704d:     	vfmadd231sd	xmm7, xmm12, xmm12 # xmm7 = (xmm12 * xmm12) + xmm7
140007052:     	vfmadd231sd	xmm7, xmm6, xmm6 # xmm7 = (xmm6 * xmm6) + xmm7
140007057:     	vxorpd	xmm8, xmm8, xmm8
14000705c:     	vmovups	xmm12, xmmword ptr [rsp + 0x380]
140007065:     	vsubsd	xmm8, xmm3, xmm12
14000706a:     	vmulsd	xmm9, xmm8, xmm8
14000706f:     	vpsrldq	xmm10, xmm12, 0x8       # xmm10 = xmm12[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007075:     	vmovups	xmmword ptr [rsp + 0x480], xmm10
14000707e:     	vsubsd	xmm12, xmm15, xmm10
140007083:     	vfmadd231sd	xmm9, xmm12, xmm12 # xmm9 = (xmm12 * xmm12) + xmm9
140007088:     	vmovsd	xmm15, qword ptr [rbx + 0xf0]
140007090:     	vmovsd	qword ptr [rsp + 0x490], xmm15
140007099:     	vsubsd	xmm10, xmm5, xmm15
14000709e:     	vmulsd	xmm5, xmm10, xmm10
1400070a3:     	vaddsd	xmm5, xmm9, xmm5
1400070a7:     	vpunpcklqdq	xmm9, xmm7, xmm5 # xmm9 = xmm7[0],xmm5[0]
1400070ab:     	vsqrtpd	xmm9, xmm9
1400070b0:     	vmulsd	xmm7, xmm7, xmm9
1400070b5:     	vpsrldq	xmm9, xmm9, 0x8         # xmm9 = xmm9[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
1400070bb:     	vmulsd	xmm5, xmm5, xmm9
1400070c0:     	vpunpcklqdq	xmm5, xmm7, xmm5 # xmm5 = xmm7[0],xmm5[0]
1400070c4:     	vmovups	xmm9, xmmword ptr [rsp + 0x300]
1400070cd:     	vdivpd	xmm5, xmm9, xmm5
1400070d1:     	vpshufd	xmm7, xmm5, 0x44        # xmm7 = xmm5[0,1,0,1]
1400070d6:     	vmulpd	xmm13, xmm13, xmm7
1400070da:     	vmovsd	xmm15, qword ptr [rsp + 0xd8]
1400070e3:     	vpshufd	xmm15, xmm15, 0x44      # xmm15 = xmm15[0,1,0,1]
1400070e9:     	vmulpd	xmm0, xmm0, xmm15
1400070ee:     	vfnmadd213pd	xmm0, xmm7, xmm2 # xmm0 = -(xmm7 * xmm0) + xmm2
1400070f3:     	vmovsd	xmm2, qword ptr [rbx + 0xd8]
1400070fb:     	vmovsd	qword ptr [rsp + 0x4b0], xmm2
140007104:     	vmulsd	xmm7, xmm6, xmm2
140007108:     	vfnmadd213sd	xmm7, xmm5, xmm4 # xmm7 = -(xmm5 * xmm7) + xmm4
14000710d:     	vmovups	xmm4, xmmword ptr [rsp + 0x370]
140007116:     	vaddpd	xmm13, xmm4, xmm13
14000711b:     	vmulsd	xmm4, xmm6, xmm11
140007120:     	vmovsd	xmm6, qword ptr [rbx + 0xd0]
140007128:     	vfmadd231sd	xmm6, xmm4, xmm5 # xmm6 = (xmm4 * xmm5) + xmm6
14000712d:     	vpunpcklqdq	xmm4, xmm8, xmm12 # xmm4 = xmm8[0],xmm12[0]
140007132:     	vmulpd	xmm8, xmm4, xmm14
140007137:     	vpsrldq	xmm5, xmm5, 0x8         # xmm5 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000713c:     	vpshufd	xmm12, xmm5, 0x44       # xmm12 = xmm5[0,1,0,1]
140007141:     	vmulpd	xmm8, xmm8, xmm12
140007146:     	vmovsd	xmm14, qword ptr [rsp + 0x110]
14000714f:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140007155:     	vmovups	xmmword ptr [rsp + 0x4c0], xmm14
14000715e:     	vmulpd	xmm4, xmm4, xmm14
140007163:     	vfnmadd213pd	xmm4, xmm12, xmm0 # xmm4 = -(xmm12 * xmm4) + xmm0
140007168:     	vfmadd231pd	xmm3, xmm4, xmmword ptr [rsp + 0x2f0] # xmm3 = (xmm4 * mem) + xmm3
140007172:     	vmovsd	xmm12, qword ptr [rbx + 0x110]
14000717a:     	vmovups	xmmword ptr [rsp + 0x310], xmm3
140007183:     	vmovups	xmm3, xmmword ptr [rsp + 0x390]
14000718c:     	vmovsd	qword ptr [rsp + 0x4d0], xmm12
140007195:     	vaddpd	xmm3, xmm3, xmm8
14000719a:     	vmovups	xmmword ptr [rsp + 0x4e0], xmm3
1400071a3:     	vmulsd	xmm8, xmm10, xmm12
1400071a8:     	vfnmadd213sd	xmm8, xmm5, xmm7 # xmm8 = -(xmm5 * xmm8) + xmm7
1400071ad:     	vmovsd	qword ptr [rbx + 0x28], xmm8
1400071b2:     	vmulsd	xmm7, xmm10, xmm11
1400071b7:     	vmulsd	xmm5, xmm7, xmm5
1400071bb:     	vaddsd	xmm5, xmm5, qword ptr [rbx + 0x108]
1400071c3:     	vmovsd	qword ptr [rsp + 0x4f8], xmm5
1400071cc:     	vxorpd	xmm7, xmm7, xmm7
1400071d0:     	vmovups	xmm10, xmmword ptr [rsp + 0x330]
1400071d9:     	vxorpd	xmm7, xmm7, xmm7
1400071dd:     	vmovups	xmm11, xmmword ptr [rsp + 0x350]
1400071e6:     	vsubsd	xmm7, xmm10, xmm11
1400071eb:     	vmovups	xmmword ptr [rsp + 0x320], xmm4
1400071f4:     	vxorpd	xmm4, xmm4, xmm4
1400071f8:     	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
140007201:     	vmovups	xmm4, xmmword ptr [rsp + 0x3c0]
14000720a:     	vsubsd	xmm5, xmm8, xmm4
14000720e:     	vpunpcklqdq	xmm12, xmm7, xmm5 # xmm12 = xmm7[0],xmm5[0]
140007212:     	vmulpd	xmm3, xmm12, xmm1
140007216:     	vmovups	xmmword ptr [rsp + 0x420], xmm1
14000721f:     	vmovups	xmm1, xmmword ptr [rsp + 0x3e0]
140007228:     	vmulpd	xmm12, xmm12, xmm1
14000722c:     	vmovsd	xmm0, qword ptr [rsp + 0x3b8]
140007235:     	vsubsd	xmm11, xmm0, qword ptr [rsp + 0x3d0]
14000723e:     	vxorpd	xmm4, xmm4, xmm4
140007242:     	vmulsd	xmm4, xmm7, xmm7
140007246:     	vfmadd231sd	xmm4, xmm5, xmm5 # xmm4 = (xmm5 * xmm5) + xmm4
14000724b:     	vfmadd231sd	xmm4, xmm11, xmm11 # xmm4 = (xmm11 * xmm11) + xmm4
140007250:     	vmovups	xmm5, xmmword ptr [rsp + 0x360]
140007259:     	vsubsd	xmm7, xmm10, xmm5
14000725d:     	vmulsd	xmm5, xmm7, xmm7
140007261:     	vmovups	xmm14, xmmword ptr [rsp + 0x460]
14000726a:     	vsubsd	xmm10, xmm8, xmm14
14000726f:     	vfmadd231sd	xmm5, xmm10, xmm10 # xmm5 = (xmm10 * xmm10) + xmm5
140007274:     	vsubsd	xmm8, xmm0, qword ptr [rsp + 0x470]
14000727d:     	vfmadd231sd	xmm5, xmm8, xmm8 # xmm5 = (xmm8 * xmm8) + xmm5
140007282:     	vpunpcklqdq	xmm14, xmm4, xmm5 # xmm14 = xmm4[0],xmm5[0]
140007286:     	vsqrtpd	xmm14, xmm14
14000728b:     	vmulsd	xmm4, xmm4, xmm14
140007290:     	vpsrldq	xmm14, xmm14, 0x8       # xmm14 = xmm14[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007296:     	vmulsd	xmm5, xmm5, xmm14
14000729b:     	vpunpcklqdq	xmm4, xmm4, xmm5 # xmm4 = xmm4[0],xmm5[0]
14000729f:     	vdivpd	xmm4, xmm9, xmm4
1400072a3:     	vpshufd	xmm5, xmm4, 0x44        # xmm5 = xmm4[0,1,0,1]
1400072a8:     	vfnmadd213pd	xmm3, xmm5, xmmword ptr [rsp + 0x400] # xmm3 = -(xmm5 * xmm3) + mem
1400072b2:     	vmulpd	xmm5, xmm12, xmm5
1400072b6:     	vmovups	xmm12, xmmword ptr [rsp + 0x440]
1400072bf:     	vaddpd	xmm5, xmm12, xmm5
1400072c3:     	vmovsd	xmm12, qword ptr [rsp + 0x430]
1400072cc:     	vmovups	xmmword ptr [rsp + 0x500], xmm5
1400072d5:     	vmulsd	xmm14, xmm11, xmm12
1400072da:     	vmovsd	xmm12, qword ptr [rsp + 0x410]
1400072e3:     	vfnmadd231sd	xmm12, xmm14, xmm4 # xmm12 = -(xmm14 * xmm4) + xmm12
1400072e8:     	vmovsd	xmm14, qword ptr [rsp + 0x3f0]
1400072f1:     	vmulsd	xmm5, xmm11, xmm14
1400072f6:     	vfmadd213sd	xmm5, xmm4, qword ptr [rsp + 0x450] # xmm5 = (xmm4 * xmm5) + mem
140007300:     	vmovsd	qword ptr [rsp + 0x510], xmm5
140007309:     	vpunpcklqdq	xmm7, xmm7, xmm10 # xmm7 = xmm7[0],xmm10[0]
14000730e:     	vmulpd	xmm10, xmm7, xmm15
140007313:     	vmulpd	xmm7, xmm7, xmm1
140007317:     	vpsrldq	xmm4, xmm4, 0x8         # xmm4 = xmm4[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
14000731c:     	vpshufd	xmm11, xmm4, 0x44       # xmm11 = xmm4[0,1,0,1]
140007321:     	vmulpd	xmm10, xmm10, xmm11
140007326:     	vsubpd	xmm3, xmm3, xmm10
14000732b:     	vmulpd	xmm7, xmm7, xmm11
140007330:     	vaddpd	xmm10, xmm13, xmm7
140007334:     	vmovups	xmmword ptr [rsp + 0x520], xmm10
14000733d:     	vmulsd	xmm7, xmm8, xmm2
140007341:     	vmulsd	xmm7, xmm7, xmm4
140007345:     	vsubsd	xmm11, xmm12, xmm7
140007349:     	vmulsd	xmm7, xmm8, xmm14
14000734e:     	vmulsd	xmm4, xmm7, xmm4
140007352:     	vaddsd	xmm4, xmm6, xmm4
140007356:     	vmovups	xmm6, xmmword ptr [rsp + 0x330]
14000735f:     	vmovups	xmm12, xmmword ptr [rsp + 0x380]
140007368:     	vmovsd	qword ptr [rsp + 0x530], xmm4
140007371:     	vsubsd	xmm7, xmm6, xmm12
140007376:     	vxorpd	xmm8, xmm8, xmm8
14000737b:     	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
140007384:     	vmovups	xmm13, xmmword ptr [rsp + 0x480]
14000738d:     	vsubsd	xmm8, xmm8, xmm13
140007392:     	vpunpcklqdq	xmm13, xmm7, xmm8 # xmm13 = xmm7[0],xmm8[0]
140007397:     	vmovups	xmm12, xmmword ptr [rsp + 0x4c0]
1400073a0:     	vmulpd	xmm4, xmm13, xmm12
1400073a5:     	vmulpd	xmm1, xmm13, xmm1
1400073a9:     	vsubsd	xmm12, xmm0, qword ptr [rsp + 0x490]
1400073b2:     	vxorpd	xmm0, xmm0, xmm0
1400073b6:     	vmulsd	xmm0, xmm7, xmm7
1400073ba:     	vfmadd231sd	xmm0, xmm8, xmm8 # xmm0 = (xmm8 * xmm8) + xmm0
1400073bf:     	vfmadd231sd	xmm0, xmm12, xmm12 # xmm0 = (xmm12 * xmm12) + xmm0
1400073c4:     	vmovups	xmm8, xmmword ptr [rsp + 0x360]
1400073cd:     	vmovups	xmm7, xmmword ptr [rsp + 0x350]
1400073d6:     	vsubsd	xmm13, xmm7, xmm8
1400073db:     	vmulsd	xmm7, xmm13, xmm13
1400073e0:     	vmovups	xmm8, xmmword ptr [rsp + 0x460]
1400073e9:     	vmovups	xmm5, xmmword ptr [rsp + 0x3c0]
1400073f2:     	vsubsd	xmm2, xmm5, xmm8
1400073f7:     	vfmadd231sd	xmm7, xmm2, xmm2 # xmm7 = (xmm2 * xmm2) + xmm7
1400073fc:     	vmovsd	xmm8, qword ptr [rsp + 0x3d0]
140007405:     	vsubsd	xmm10, xmm8, qword ptr [rsp + 0x470]
14000740e:     	vmulsd	xmm5, xmm10, xmm10
140007413:     	vaddsd	xmm5, xmm7, xmm5
140007417:     	vpunpcklqdq	xmm7, xmm0, xmm5 # xmm7 = xmm0[0],xmm5[0]
14000741b:     	vsqrtpd	xmm7, xmm7
14000741f:     	vmulsd	xmm0, xmm0, xmm7
140007423:     	vpsrldq	xmm7, xmm7, 0x8         # xmm7 = xmm7[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007428:     	vmulsd	xmm5, xmm5, xmm7
14000742c:     	vpunpcklqdq	xmm0, xmm0, xmm5 # xmm0 = xmm0[0],xmm5[0]
140007430:     	vdivpd	xmm0, xmm9, xmm0
140007434:     	vpshufd	xmm5, xmm0, 0x44        # xmm5 = xmm0[0,1,0,1]
140007439:     	vmulpd	xmm4, xmm4, xmm5
14000743d:     	vmovups	xmm8, xmmword ptr [rsp + 0x350]
140007446:     	vsubpd	xmm7, xmm3, xmm4
14000744a:     	vmovups	xmm4, xmmword ptr [rsp + 0x2f0]
140007453:     	vfmadd231pd	xmm6, xmm7, xmm4 # xmm6 = (xmm7 * xmm4) + xmm6
140007458:     	vmovups	xmmword ptr [rsp + 0x330], xmm6
140007461:     	vfmadd213pd	xmm1, xmm5, xmmword ptr [rsp + 0x4e0] # xmm1 = (xmm5 * xmm1) + mem
14000746b:     	vmovsd	xmm5, qword ptr [rsp + 0x4d0]
140007474:     	vmulsd	xmm3, xmm12, xmm5
140007478:     	vfnmadd231sd	xmm11, xmm3, xmm0 # xmm11 = -(xmm3 * xmm0) + xmm11
14000747d:     	vmovsd	qword ptr [rbx + 0x60], xmm11
140007482:     	vmulsd	xmm3, xmm12, xmm14
140007487:     	vmulsd	xmm3, xmm3, xmm0
14000748b:     	vmovsd	xmm12, qword ptr [rsp + 0x4f8]
140007494:     	vaddsd	xmm3, xmm12, xmm3
140007498:     	vmovsd	qword ptr [rsp + 0x540], xmm3
1400074a1:     	vxorpd	xmm12, xmm12, xmm12
1400074a6:     	vpunpcklqdq	xmm2, xmm13, xmm2 # xmm2 = xmm13[0],xmm2[0]
1400074aa:     	vmulpd	xmm12, xmm2, xmm15
1400074af:     	vmovups	xmm13, xmmword ptr [rsp + 0x420]
1400074b8:     	vmulpd	xmm2, xmm2, xmm13
1400074bd:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
1400074c2:     	vpshufd	xmm14, xmm0, 0x44       # xmm14 = xmm0[0,1,0,1]
1400074c7:     	vmovups	xmm6, xmmword ptr [rsp + 0x500]
1400074d0:     	vfnmadd231pd	xmm6, xmm12, xmm14 # xmm6 = -(xmm12 * xmm14) + xmm6
1400074d5:     	vfmadd213pd	xmm2, xmm14, xmmword ptr [rsp + 0x520] # xmm2 = (xmm14 * xmm2) + mem
1400074df:     	vmovsd	xmm12, qword ptr [rsp + 0x4b0]
1400074e8:     	vmovups	xmmword ptr [rsp + 0x550], xmm2
1400074f1:     	vmulsd	xmm14, xmm10, xmm12
1400074f6:     	vmovups	xmmword ptr [rsp + 0x340], xmm7
1400074ff:     	vmovsd	xmm7, qword ptr [rsp + 0x510]
140007508:     	vfnmadd231sd	xmm7, xmm14, xmm0 # xmm7 = -(xmm14 * xmm0) + xmm7
14000750d:     	vmulsd	xmm10, xmm10, qword ptr [rsp + 0x430]
140007516:     	vmulsd	xmm0, xmm10, xmm0
14000751a:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x530]
140007523:     	vmovsd	qword ptr [rsp + 0x560], xmm0
14000752c:     	vmovups	xmm10, xmmword ptr [rsp + 0x380]
140007535:     	vsubsd	xmm11, xmm8, xmm10
14000753a:     	vxorpd	xmm12, xmm12, xmm12
14000753f:     	vmovups	xmm12, xmmword ptr [rsp + 0x3c0]
140007548:     	vmovups	xmm0, xmmword ptr [rsp + 0x480]
140007551:     	vsubsd	xmm12, xmm12, xmm0
140007555:     	vpunpcklqdq	xmm2, xmm11, xmm12 # xmm2 = xmm11[0],xmm12[0]
14000755a:     	vmovups	xmmword ptr [rsp + 0x4a0], xmm15
140007563:     	vmovups	xmm15, xmmword ptr [rsp + 0x4c0]
14000756c:     	vmulpd	xmm3, xmm2, xmm15
140007571:     	vmulpd	xmm2, xmm2, xmm13
140007576:     	vmovsd	xmm13, qword ptr [rsp + 0x490]
14000757f:     	vmovsd	xmm15, qword ptr [rsp + 0x3d0]
140007588:     	vsubsd	xmm14, xmm15, xmm13
14000758d:     	vxorpd	xmm15, xmm15, xmm15
140007592:     	vmulsd	xmm11, xmm11, xmm11
140007597:     	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
14000759c:     	vfmadd231sd	xmm11, xmm14, xmm14 # xmm11 = (xmm14 * xmm14) + xmm11
1400075a1:     	vmovups	xmm12, xmmword ptr [rsp + 0x360]
1400075aa:     	vsubsd	xmm15, xmm12, xmm10
1400075af:     	vmovsd	qword ptr [rsp + 0x568], xmm15
1400075b8:     	vmulsd	xmm10, xmm15, xmm15
1400075bd:     	vmovups	xmm12, xmmword ptr [rsp + 0x460]
1400075c6:     	vsubsd	xmm0, xmm12, xmm0
1400075ca:     	vfmadd231sd	xmm10, xmm0, xmm0 # xmm10 = (xmm0 * xmm0) + xmm10
1400075cf:     	vmovsd	xmm12, qword ptr [rsp + 0x470]
1400075d8:     	vsubsd	xmm15, xmm12, xmm13
1400075dd:     	vfmadd231sd	xmm10, xmm15, xmm15 # xmm10 = (xmm15 * xmm15) + xmm10
1400075e2:     	vpunpcklqdq	xmm13, xmm11, xmm10 # xmm13 = xmm11[0],xmm10[0]
1400075e7:     	vsqrtpd	xmm13, xmm13
1400075ec:     	vmulsd	xmm11, xmm11, xmm13
1400075f1:     	vpsrldq	xmm13, xmm13, 0x8       # xmm13 = xmm13[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
1400075f7:     	vmulsd	xmm10, xmm10, xmm13
1400075fc:     	vpunpcklqdq	xmm10, xmm11, xmm10 # xmm10 = xmm11[0],xmm10[0]
140007601:     	vdivpd	xmm10, xmm9, xmm10
140007606:     	vpshufd	xmm11, xmm10, 0x44      # xmm11 = xmm10[0,1,0,1]
14000760c:     	vmulpd	xmm3, xmm3, xmm11
140007611:     	vmovups	xmm13, xmm9
140007616:     	vsubpd	xmm9, xmm6, xmm3
14000761a:     	vfmadd231pd	xmm8, xmm9, xmm4 # xmm8 = (xmm9 * xmm4) + xmm8
14000761f:     	vmovups	xmmword ptr [rsp + 0x350], xmm8
140007628:     	vfmadd231pd	xmm1, xmm2, xmm11 # xmm1 = (xmm2 * xmm11) + xmm1
14000762d:     	vmulsd	xmm2, xmm14, xmm5
140007631:     	vfnmadd213sd	xmm2, xmm10, xmm7 # xmm2 = -(xmm10 * xmm2) + xmm7
140007636:     	vmovsd	qword ptr [rbx + 0x98], xmm2
14000763e:     	vmovsd	xmm3, qword ptr [rsp + 0x430]
140007647:     	vmulsd	xmm3, xmm14, xmm3
14000764b:     	vmovsd	xmm6, qword ptr [rsp + 0x540]
140007654:     	vfmadd231sd	xmm6, xmm3, xmm10 # xmm6 = (xmm3 * xmm10) + xmm6
140007659:     	vmovsd	xmm3, qword ptr [rsp + 0x568]
140007662:     	vpunpcklqdq	xmm0, xmm3, xmm0 # xmm0 = xmm3[0],xmm0[0]
140007666:     	vmovups	xmm3, xmmword ptr [rsp + 0x4c0]
14000766f:     	vmulpd	xmm3, xmm0, xmm3
140007673:     	vmovups	xmm7, xmmword ptr [rsp + 0x4a0]
14000767c:     	vmulpd	xmm0, xmm0, xmm7
140007680:     	vpsrldq	xmm7, xmm10, 0x8        # xmm7 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007686:     	vpshufd	xmm10, xmm7, 0x44       # xmm10 = xmm7[0,1,0,1]
14000768b:     	vmulpd	xmm3, xmm3, xmm10
140007690:     	vmovups	xmm11, xmmword ptr [rsp + 0x550]
140007699:     	vsubpd	xmm11, xmm11, xmm3
14000769d:     	vmulpd	xmm3, xmm11, xmm4
1400076a1:     	vmovups	xmm14, xmmword ptr [rsp + 0x360]
1400076aa:     	vaddpd	xmm14, xmm14, xmm3
1400076ae:     	vmovups	xmmword ptr [rsp + 0x360], xmm14
1400076b7:     	vmulpd	xmm0, xmm0, xmm10
1400076bc:     	vaddpd	xmm3, xmm1, xmm0
1400076c0:     	vmovups	xmm10, xmmword ptr [rsp + 0x380]
1400076c9:     	vfmadd231pd	xmm10, xmm3, xmm4 # xmm10 = (xmm3 * xmm4) + xmm10
1400076ce:     	vmovups	xmmword ptr [rsp + 0x380], xmm10
1400076d7:     	vmulsd	xmm0, xmm15, xmm5
1400076db:     	vfnmadd213sd	xmm0, xmm7, qword ptr [rsp + 0x560] # xmm0 = -(xmm7 * xmm0) + mem
1400076e5:     	vmovsd	qword ptr [rbx + 0xd0], xmm0
1400076ed:     	vmovsd	xmm1, qword ptr [rsp + 0x4b0]
1400076f6:     	vmulsd	xmm1, xmm15, xmm1
1400076fa:     	vfmadd213sd	xmm1, xmm7, xmm6 # xmm1 = (xmm7 * xmm1) + xmm6
1400076ff:     	vmovsd	qword ptr [rbx + 0x108], xmm1
140007707:     	vmovsd	xmm6, qword ptr [rip + 0x6261] # 0x14000d970
14000770f:     	vmovsd	xmm5, qword ptr [rbx + 0x28]
140007714:     	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b0] # xmm5 = (xmm6 * xmm5) + mem
14000771e:     	vmovsd	qword ptr [rbx + 0x10], xmm5
140007723:     	vmovsd	xmm5, qword ptr [rbx + 0x60]
140007728:     	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b8] # xmm5 = (xmm6 * xmm5) + mem
140007732:     	vmovsd	qword ptr [rbx + 0x48], xmm5
140007737:     	vfmadd213sd	xmm2, xmm6, qword ptr [rsp + 0x3d0] # xmm2 = (xmm6 * xmm2) + mem
140007741:     	vmovsd	qword ptr [rbx + 0x80], xmm2
140007749:     	vfmadd213sd	xmm0, xmm6, xmm12 # xmm0 = (xmm6 * xmm0) + xmm12
14000774e:     	vmovsd	qword ptr [rbx + 0xb8], xmm0
140007756:     	vmulsd	xmm0, xmm1, xmm6
14000775a:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x490]
140007763:     	vmovsd	qword ptr [rbx + 0xf0], xmm0
14000776b:     	add	rax, 0x1
14000776f:     	cmp	rax, 0x7a120
140007776:     	jl	0x140006e10 <.text+0x5e10>
