140006df0:     	vmovups	xmm2, xmm13
140006df5:     	vmovups	xmm4, xmmword ptr [rsp + 0x320]
140006dfe:     	vmovups	xmm5, xmmword ptr [rsp + 0x330]
140006e07:     	vmovups	xmm7, xmmword ptr [rsp + 0x340]
140006e10:     	vmovups	xmm10, xmm14
140006e15:     	vmovups	xmmword ptr [rsp + 0x370], xmm11
140006e1e:     	vmovups	xmm13, xmm3
140006e22:     	vmovups	xmm3, xmmword ptr [rsp + 0x310]
140006e2b:     	vsubsd	xmm14, xmm3, xmm5
140006e2f:     	vpsrldq	xmm15, xmm3, 0x8        # xmm15 = xmm3[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006e34:     	vpsrldq	xmm6, xmm5, 0x8         # xmm6 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006e39:     	vmovups	xmmword ptr [rsp + 0x3a0], xmm6
140006e42:     	vsubsd	xmm0, xmm15, xmm6
140006e46:     	vpunpcklqdq	xmm6, xmm14, xmm0 # xmm6 = xmm14[0],xmm0[0]
140006e4a:     	vmovsd	xmm5, qword ptr [rbx + 0x10]
140006e4f:     	vmovups	xmmword ptr [rsp + 0x390], xmm13
140006e58:     	vmovsd	qword ptr [rsp + 0x3b0], xmm5
140006e61:     	vmovsd	xmm13, qword ptr [rbx + 0x48]
140006e66:     	vmovsd	qword ptr [rsp + 0x3b8], xmm13
140006e6f:     	vsubsd	xmm1, xmm5, xmm13
140006e74:     	vmulsd	xmm13, xmm14, xmm14
140006e79:     	vfmadd213sd	xmm0, xmm0, xmm13 # xmm0 = (xmm0 * xmm0) + xmm13
140006e7e:     	vfmadd231sd	xmm0, xmm1, xmm1 # xmm0 = (xmm1 * xmm1) + xmm0
140006e83:     	vsubsd	xmm13, xmm3, xmm8
140006e88:     	vpsrldq	xmm11, xmm8, 0x8        # xmm11 = xmm8[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006e8e:     	vmovups	xmmword ptr [rsp + 0x3c0], xmm11
140006e97:     	vsubsd	xmm8, xmm15, xmm11
140006e9c:     	vmulsd	xmm11, xmm8, xmm8
140006ea1:     	vfmadd231sd	xmm11, xmm13, xmm13 # xmm11 = (xmm13 * xmm13) + xmm11
140006ea6:     	vmovsd	xmm14, qword ptr [rbx + 0x80]
140006eae:     	vmovsd	qword ptr [rsp + 0x3d0], xmm14
140006eb7:     	vsubsd	xmm12, xmm5, xmm14
140006ebc:     	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
140006ec1:     	vpunpcklqdq	xmm14, xmm0, xmm11 # xmm14 = xmm0[0],xmm11[0]
140006ec6:     	vsqrtpd	xmm14, xmm14
140006ecb:     	vmulsd	xmm0, xmm0, xmm14
140006ed0:     	vpsrldq	xmm14, xmm14, 0x8       # xmm14 = xmm14[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006ed6:     	vmulsd	xmm11, xmm11, xmm14
140006edb:     	vpunpcklqdq	xmm0, xmm0, xmm11 # xmm0 = xmm0[0],xmm11[0]
140006ee0:     	vdivpd	xmm0, xmm2, xmm0
140006ee4:     	vpshufd	xmm11, xmm0, 0x44       # xmm11 = xmm0[0,1,0,1]
140006ee9:     	vmovsd	xmm14, qword ptr [rsp + 0x68]
140006eef:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140006ef5:     	vmulpd	xmm2, xmm6, xmm14
140006efa:     	vmovups	xmmword ptr [rsp + 0x3e0], xmm14
140006f03:     	vmovsd	xmm14, qword ptr [rbx + 0x68]
140006f08:     	vmovsd	qword ptr [rsp + 0x3f0], xmm14
140006f11:     	vfnmadd213pd	xmm2, xmm11, xmm4 # xmm2 = -(xmm11 * xmm2) + xmm4
140006f16:     	vmulsd	xmm4, xmm1, xmm14
140006f1b:     	vfnmadd213sd	xmm4, xmm0, qword ptr [rbx + 0x28] # xmm4 = -(xmm0 * xmm4) + mem
140006f21:     	vmovsd	xmm14, qword ptr [rsp + 0x30]
140006f27:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140006f2d:     	vmulpd	xmm6, xmm6, xmm14
140006f32:     	vmulpd	xmm6, xmm6, xmm11
140006f37:     	vmovsd	xmm11, qword ptr [rbx + 0x30]
140006f3c:     	vaddpd	xmm6, xmm7, xmm6
140006f40:     	vmovups	xmmword ptr [rsp + 0x400], xmm6
140006f49:     	vmulsd	xmm1, xmm1, xmm11
140006f4e:     	vfmadd213sd	xmm1, xmm0, qword ptr [rbx + 0x60] # xmm1 = (xmm0 * xmm1) + mem
140006f54:     	vmovsd	qword ptr [rsp + 0x410], xmm1
140006f5d:     	vpunpcklqdq	xmm7, xmm13, xmm8 # xmm7 = xmm13[0],xmm8[0]
140006f62:     	vmulpd	xmm8, xmm7, xmm14
140006f67:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006f6c:     	vpshufd	xmm13, xmm0, 0x44       # xmm13 = xmm0[0,1,0,1]
140006f71:     	vmulpd	xmm8, xmm8, xmm13
140006f76:     	vmovsd	xmm1, qword ptr [rsp + 0xa0]
140006f7f:     	vpshufd	xmm1, xmm1, 0x44        # xmm1 = xmm1[0,1,0,1]
140006f84:     	vmulpd	xmm7, xmm7, xmm1
140006f88:     	vfnmadd231pd	xmm2, xmm7, xmm13 # xmm2 = -(xmm7 * xmm13) + xmm2
140006f8d:     	vmovsd	xmm13, qword ptr [rbx + 0xa0]
140006f95:     	vmovsd	qword ptr [rsp + 0x430], xmm13
140006f9e:     	vmulsd	xmm7, xmm12, xmm13
140006fa3:     	vmulsd	xmm7, xmm7, xmm0
140006fa7:     	vsubsd	xmm4, xmm4, xmm7
140006fab:     	vaddpd	xmm7, xmm9, xmm8
140006fb0:     	vmovups	xmmword ptr [rsp + 0x440], xmm7
140006fb9:     	vmulsd	xmm8, xmm12, xmm11
140006fbe:     	vmulsd	xmm0, xmm8, xmm0
140006fc2:     	vaddsd	xmm0, xmm0, qword ptr [rbx + 0x98]
140006fca:     	vmovsd	qword ptr [rsp + 0x450], xmm0
140006fd3:     	vsubsd	xmm8, xmm3, xmm10
140006fd8:     	vpsrldq	xmm9, xmm10, 0x8        # xmm9 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140006fde:     	vmovups	xmmword ptr [rsp + 0x460], xmm9
140006fe7:     	vsubsd	xmm12, xmm15, xmm9
140006fec:     	vpunpcklqdq	xmm0, xmm8, xmm12 # xmm0 = xmm8[0],xmm12[0]
140006ff1:     	vmulpd	xmm13, xmm0, xmm14
140006ff6:     	vmovsd	xmm7, qword ptr [rbx + 0xb8]
140006ffe:     	vmovsd	qword ptr [rsp + 0x470], xmm7
140007007:     	vsubsd	xmm6, xmm5, xmm7
14000700b:     	vmulsd	xmm7, xmm8, xmm8
140007010:     	vfmadd231sd	xmm7, xmm12, xmm12 # xmm7 = (xmm12 * xmm12) + xmm7
140007015:     	vfmadd231sd	xmm7, xmm6, xmm6 # xmm7 = (xmm6 * xmm6) + xmm7
14000701a:     	vmovups	xmm12, xmmword ptr [rsp + 0x380]
140007023:     	vsubsd	xmm8, xmm3, xmm12
140007028:     	vmulsd	xmm9, xmm8, xmm8
14000702d:     	vpsrldq	xmm10, xmm12, 0x8       # xmm10 = xmm12[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007033:     	vmovups	xmmword ptr [rsp + 0x480], xmm10
14000703c:     	vsubsd	xmm12, xmm15, xmm10
140007041:     	vfmadd231sd	xmm9, xmm12, xmm12 # xmm9 = (xmm12 * xmm12) + xmm9
140007046:     	vmovsd	xmm15, qword ptr [rbx + 0xf0]
14000704e:     	vmovsd	qword ptr [rsp + 0x490], xmm15
140007057:     	vsubsd	xmm10, xmm5, xmm15
14000705c:     	vmulsd	xmm5, xmm10, xmm10
140007061:     	vaddsd	xmm5, xmm9, xmm5
140007065:     	vpunpcklqdq	xmm9, xmm7, xmm5 # xmm9 = xmm7[0],xmm5[0]
140007069:     	vsqrtpd	xmm9, xmm9
14000706e:     	vmulsd	xmm7, xmm7, xmm9
140007073:     	vpsrldq	xmm9, xmm9, 0x8         # xmm9 = xmm9[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007079:     	vmulsd	xmm5, xmm5, xmm9
14000707e:     	vpunpcklqdq	xmm5, xmm7, xmm5 # xmm5 = xmm7[0],xmm5[0]
140007082:     	vmovups	xmm9, xmmword ptr [rsp + 0x300]
14000708b:     	vdivpd	xmm5, xmm9, xmm5
14000708f:     	vpshufd	xmm7, xmm5, 0x44        # xmm7 = xmm5[0,1,0,1]
140007094:     	vmulpd	xmm13, xmm13, xmm7
140007098:     	vmovsd	xmm15, qword ptr [rsp + 0xd8]
1400070a1:     	vpshufd	xmm15, xmm15, 0x44      # xmm15 = xmm15[0,1,0,1]
1400070a7:     	vmulpd	xmm0, xmm0, xmm15
1400070ac:     	vfnmadd213pd	xmm0, xmm7, xmm2 # xmm0 = -(xmm7 * xmm0) + xmm2
1400070b1:     	vmovsd	xmm2, qword ptr [rbx + 0xd8]
1400070b9:     	vmovsd	qword ptr [rsp + 0x4b0], xmm2
1400070c2:     	vmulsd	xmm7, xmm6, xmm2
1400070c6:     	vfnmadd213sd	xmm7, xmm5, xmm4 # xmm7 = -(xmm5 * xmm7) + xmm4
1400070cb:     	vmovups	xmm4, xmmword ptr [rsp + 0x370]
1400070d4:     	vaddpd	xmm13, xmm4, xmm13
1400070d9:     	vmulsd	xmm4, xmm6, xmm11
1400070de:     	vmovsd	xmm6, qword ptr [rbx + 0xd0]
1400070e6:     	vfmadd231sd	xmm6, xmm4, xmm5 # xmm6 = (xmm4 * xmm5) + xmm6
1400070eb:     	vpunpcklqdq	xmm4, xmm8, xmm12 # xmm4 = xmm8[0],xmm12[0]
1400070f0:     	vmulpd	xmm8, xmm4, xmm14
1400070f5:     	vpsrldq	xmm5, xmm5, 0x8         # xmm5 = xmm5[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
1400070fa:     	vpshufd	xmm12, xmm5, 0x44       # xmm12 = xmm5[0,1,0,1]
1400070ff:     	vmulpd	xmm8, xmm8, xmm12
140007104:     	vmovsd	xmm14, qword ptr [rsp + 0x110]
14000710d:     	vpshufd	xmm14, xmm14, 0x44      # xmm14 = xmm14[0,1,0,1]
140007113:     	vmovups	xmmword ptr [rsp + 0x4c0], xmm14
14000711c:     	vmulpd	xmm4, xmm4, xmm14
140007121:     	vfnmadd213pd	xmm4, xmm12, xmm0 # xmm4 = -(xmm12 * xmm4) + xmm0
140007126:     	vfmadd231pd	xmm3, xmm4, xmmword ptr [rsp + 0x2f0] # xmm3 = (xmm4 * mem) + xmm3
140007130:     	vmovsd	xmm12, qword ptr [rbx + 0x110]
140007138:     	vmovups	xmmword ptr [rsp + 0x310], xmm3
140007141:     	vmovups	xmm3, xmmword ptr [rsp + 0x390]
14000714a:     	vmovsd	qword ptr [rsp + 0x4d0], xmm12
140007153:     	vaddpd	xmm3, xmm3, xmm8
140007158:     	vmovups	xmmword ptr [rsp + 0x4e0], xmm3
140007161:     	vmulsd	xmm8, xmm10, xmm12
140007166:     	vfnmadd213sd	xmm8, xmm5, xmm7 # xmm8 = -(xmm5 * xmm8) + xmm7
14000716b:     	vmovsd	qword ptr [rbx + 0x28], xmm8
140007170:     	vmulsd	xmm7, xmm10, xmm11
140007175:     	vmulsd	xmm5, xmm7, xmm5
140007179:     	vaddsd	xmm5, xmm5, qword ptr [rbx + 0x108]
140007181:     	vmovsd	qword ptr [rsp + 0x4f8], xmm5
14000718a:     	vmovups	xmm10, xmmword ptr [rsp + 0x330]
140007193:     	vmovups	xmm11, xmmword ptr [rsp + 0x350]
14000719c:     	vsubsd	xmm7, xmm10, xmm11
1400071a1:     	vmovups	xmmword ptr [rsp + 0x320], xmm4
1400071aa:     	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
1400071b3:     	vmovups	xmm4, xmmword ptr [rsp + 0x3c0]
1400071bc:     	vsubsd	xmm5, xmm8, xmm4
1400071c0:     	vpunpcklqdq	xmm12, xmm7, xmm5 # xmm12 = xmm7[0],xmm5[0]
1400071c4:     	vmulpd	xmm3, xmm12, xmm1
1400071c8:     	vmovups	xmmword ptr [rsp + 0x420], xmm1
1400071d1:     	vmovups	xmm1, xmmword ptr [rsp + 0x3e0]
1400071da:     	vmulpd	xmm12, xmm12, xmm1
1400071de:     	vmovsd	xmm0, qword ptr [rsp + 0x3b8]
1400071e7:     	vsubsd	xmm11, xmm0, qword ptr [rsp + 0x3d0]
1400071f0:     	vmulsd	xmm4, xmm7, xmm7
1400071f4:     	vfmadd231sd	xmm4, xmm5, xmm5 # xmm4 = (xmm5 * xmm5) + xmm4
1400071f9:     	vfmadd231sd	xmm4, xmm11, xmm11 # xmm4 = (xmm11 * xmm11) + xmm4
1400071fe:     	vmovups	xmm5, xmmword ptr [rsp + 0x360]
140007207:     	vsubsd	xmm7, xmm10, xmm5
14000720b:     	vmulsd	xmm5, xmm7, xmm7
14000720f:     	vmovups	xmm14, xmmword ptr [rsp + 0x460]
140007218:     	vsubsd	xmm10, xmm8, xmm14
14000721d:     	vfmadd231sd	xmm5, xmm10, xmm10 # xmm5 = (xmm10 * xmm10) + xmm5
140007222:     	vsubsd	xmm8, xmm0, qword ptr [rsp + 0x470]
14000722b:     	vfmadd231sd	xmm5, xmm8, xmm8 # xmm5 = (xmm8 * xmm8) + xmm5
140007230:     	vpunpcklqdq	xmm14, xmm4, xmm5 # xmm14 = xmm4[0],xmm5[0]
140007234:     	vsqrtpd	xmm14, xmm14
140007239:     	vmulsd	xmm4, xmm4, xmm14
14000723e:     	vpsrldq	xmm14, xmm14, 0x8       # xmm14 = xmm14[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007244:     	vmulsd	xmm5, xmm5, xmm14
140007249:     	vpunpcklqdq	xmm4, xmm4, xmm5 # xmm4 = xmm4[0],xmm5[0]
14000724d:     	vdivpd	xmm4, xmm9, xmm4
140007251:     	vpshufd	xmm5, xmm4, 0x44        # xmm5 = xmm4[0,1,0,1]
140007256:     	vfnmadd213pd	xmm3, xmm5, xmmword ptr [rsp + 0x400] # xmm3 = -(xmm5 * xmm3) + mem
140007260:     	vmulpd	xmm5, xmm12, xmm5
140007264:     	vmovups	xmm12, xmmword ptr [rsp + 0x440]
14000726d:     	vaddpd	xmm5, xmm12, xmm5
140007271:     	vmovsd	xmm12, qword ptr [rsp + 0x430]
14000727a:     	vmovups	xmmword ptr [rsp + 0x500], xmm5
140007283:     	vmulsd	xmm14, xmm11, xmm12
140007288:     	vmovsd	xmm12, qword ptr [rsp + 0x410]
140007291:     	vfnmadd231sd	xmm12, xmm14, xmm4 # xmm12 = -(xmm14 * xmm4) + xmm12
140007296:     	vmovsd	xmm14, qword ptr [rsp + 0x3f0]
14000729f:     	vmulsd	xmm5, xmm11, xmm14
1400072a4:     	vfmadd213sd	xmm5, xmm4, qword ptr [rsp + 0x450] # xmm5 = (xmm4 * xmm5) + mem
1400072ae:     	vmovsd	qword ptr [rsp + 0x510], xmm5
1400072b7:     	vpunpcklqdq	xmm7, xmm7, xmm10 # xmm7 = xmm7[0],xmm10[0]
1400072bc:     	vmulpd	xmm10, xmm7, xmm15
1400072c1:     	vmulpd	xmm7, xmm7, xmm1
1400072c5:     	vpsrldq	xmm4, xmm4, 0x8         # xmm4 = xmm4[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
1400072ca:     	vpshufd	xmm11, xmm4, 0x44       # xmm11 = xmm4[0,1,0,1]
1400072cf:     	vmulpd	xmm10, xmm10, xmm11
1400072d4:     	vsubpd	xmm3, xmm3, xmm10
1400072d9:     	vmulpd	xmm7, xmm7, xmm11
1400072de:     	vaddpd	xmm10, xmm13, xmm7
1400072e2:     	vmovups	xmmword ptr [rsp + 0x520], xmm10
1400072eb:     	vmulsd	xmm7, xmm8, xmm2
1400072ef:     	vmulsd	xmm7, xmm7, xmm4
1400072f3:     	vsubsd	xmm11, xmm12, xmm7
1400072f7:     	vmulsd	xmm7, xmm8, xmm14
1400072fc:     	vmulsd	xmm4, xmm7, xmm4
140007300:     	vaddsd	xmm4, xmm6, xmm4
140007304:     	vmovups	xmm6, xmmword ptr [rsp + 0x330]
14000730d:     	vmovups	xmm12, xmmword ptr [rsp + 0x380]
140007316:     	vmovsd	qword ptr [rsp + 0x530], xmm4
14000731f:     	vsubsd	xmm7, xmm6, xmm12
140007324:     	vmovups	xmm8, xmmword ptr [rsp + 0x3a0]
14000732d:     	vmovups	xmm13, xmmword ptr [rsp + 0x480]
140007336:     	vsubsd	xmm8, xmm8, xmm13
14000733b:     	vpunpcklqdq	xmm13, xmm7, xmm8 # xmm13 = xmm7[0],xmm8[0]
140007340:     	vmovups	xmm12, xmmword ptr [rsp + 0x4c0]
140007349:     	vmulpd	xmm4, xmm13, xmm12
14000734e:     	vmulpd	xmm1, xmm13, xmm1
140007352:     	vsubsd	xmm12, xmm0, qword ptr [rsp + 0x490]
14000735b:     	vmulsd	xmm0, xmm7, xmm7
14000735f:     	vfmadd231sd	xmm0, xmm8, xmm8 # xmm0 = (xmm8 * xmm8) + xmm0
140007364:     	vfmadd231sd	xmm0, xmm12, xmm12 # xmm0 = (xmm12 * xmm12) + xmm0
140007369:     	vmovups	xmm8, xmmword ptr [rsp + 0x360]
140007372:     	vmovups	xmm7, xmmword ptr [rsp + 0x350]
14000737b:     	vsubsd	xmm13, xmm7, xmm8
140007380:     	vmulsd	xmm7, xmm13, xmm13
140007385:     	vmovups	xmm8, xmmword ptr [rsp + 0x460]
14000738e:     	vmovups	xmm5, xmmword ptr [rsp + 0x3c0]
140007397:     	vsubsd	xmm2, xmm5, xmm8
14000739c:     	vfmadd231sd	xmm7, xmm2, xmm2 # xmm7 = (xmm2 * xmm2) + xmm7
1400073a1:     	vmovsd	xmm8, qword ptr [rsp + 0x3d0]
1400073aa:     	vsubsd	xmm10, xmm8, qword ptr [rsp + 0x470]
1400073b3:     	vmulsd	xmm5, xmm10, xmm10
1400073b8:     	vaddsd	xmm5, xmm7, xmm5
1400073bc:     	vpunpcklqdq	xmm7, xmm0, xmm5 # xmm7 = xmm0[0],xmm5[0]
1400073c0:     	vsqrtpd	xmm7, xmm7
1400073c4:     	vmulsd	xmm0, xmm0, xmm7
1400073c8:     	vpsrldq	xmm7, xmm7, 0x8         # xmm7 = xmm7[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
1400073cd:     	vmulsd	xmm5, xmm5, xmm7
1400073d1:     	vpunpcklqdq	xmm0, xmm0, xmm5 # xmm0 = xmm0[0],xmm5[0]
1400073d5:     	vdivpd	xmm0, xmm9, xmm0
1400073d9:     	vpshufd	xmm5, xmm0, 0x44        # xmm5 = xmm0[0,1,0,1]
1400073de:     	vmulpd	xmm4, xmm4, xmm5
1400073e2:     	vmovups	xmm8, xmmword ptr [rsp + 0x350]
1400073eb:     	vsubpd	xmm7, xmm3, xmm4
1400073ef:     	vmovups	xmm4, xmmword ptr [rsp + 0x2f0]
1400073f8:     	vfmadd231pd	xmm6, xmm7, xmm4 # xmm6 = (xmm7 * xmm4) + xmm6
1400073fd:     	vmovups	xmmword ptr [rsp + 0x330], xmm6
140007406:     	vfmadd213pd	xmm1, xmm5, xmmword ptr [rsp + 0x4e0] # xmm1 = (xmm5 * xmm1) + mem
140007410:     	vmovsd	xmm5, qword ptr [rsp + 0x4d0]
140007419:     	vmulsd	xmm3, xmm12, xmm5
14000741d:     	vfnmadd231sd	xmm11, xmm3, xmm0 # xmm11 = -(xmm3 * xmm0) + xmm11
140007422:     	vmovsd	qword ptr [rbx + 0x60], xmm11
140007427:     	vmulsd	xmm3, xmm12, xmm14
14000742c:     	vmulsd	xmm3, xmm3, xmm0
140007430:     	vmovsd	xmm12, qword ptr [rsp + 0x4f8]
140007439:     	vaddsd	xmm3, xmm12, xmm3
14000743d:     	vmovsd	qword ptr [rsp + 0x540], xmm3
140007446:     	vxorpd	xmm12, xmm12, xmm12
14000744b:     	vpunpcklqdq	xmm2, xmm13, xmm2 # xmm2 = xmm13[0],xmm2[0]
14000744f:     	vmulpd	xmm12, xmm2, xmm15
140007454:     	vmovups	xmm13, xmmword ptr [rsp + 0x420]
14000745d:     	vmulpd	xmm2, xmm2, xmm13
140007462:     	vpsrldq	xmm0, xmm0, 0x8         # xmm0 = xmm0[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007467:     	vpshufd	xmm14, xmm0, 0x44       # xmm14 = xmm0[0,1,0,1]
14000746c:     	vmovups	xmm6, xmmword ptr [rsp + 0x500]
140007475:     	vfnmadd231pd	xmm6, xmm12, xmm14 # xmm6 = -(xmm12 * xmm14) + xmm6
14000747a:     	vfmadd213pd	xmm2, xmm14, xmmword ptr [rsp + 0x520] # xmm2 = (xmm14 * xmm2) + mem
140007484:     	vmovsd	xmm12, qword ptr [rsp + 0x4b0]
14000748d:     	vmovups	xmmword ptr [rsp + 0x550], xmm2
140007496:     	vmulsd	xmm14, xmm10, xmm12
14000749b:     	vmovups	xmmword ptr [rsp + 0x340], xmm7
1400074a4:     	vmovsd	xmm7, qword ptr [rsp + 0x510]
1400074ad:     	vfnmadd231sd	xmm7, xmm14, xmm0 # xmm7 = -(xmm14 * xmm0) + xmm7
1400074b2:     	vmulsd	xmm10, xmm10, qword ptr [rsp + 0x430]
1400074bb:     	vmulsd	xmm0, xmm10, xmm0
1400074bf:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x530]
1400074c8:     	vmovsd	qword ptr [rsp + 0x560], xmm0
1400074d1:     	vmovups	xmm10, xmmword ptr [rsp + 0x380]
1400074da:     	vsubsd	xmm11, xmm8, xmm10
1400074df:     	vmovups	xmm12, xmmword ptr [rsp + 0x3c0]
1400074e8:     	vmovups	xmm0, xmmword ptr [rsp + 0x480]
1400074f1:     	vsubsd	xmm12, xmm12, xmm0
1400074f5:     	vpunpcklqdq	xmm2, xmm11, xmm12 # xmm2 = xmm11[0],xmm12[0]
1400074fa:     	vmovups	xmmword ptr [rsp + 0x4a0], xmm15
140007503:     	vmovups	xmm15, xmmword ptr [rsp + 0x4c0]
14000750c:     	vmulpd	xmm3, xmm2, xmm15
140007511:     	vmulpd	xmm2, xmm2, xmm13
140007516:     	vmovsd	xmm13, qword ptr [rsp + 0x490]
14000751f:     	vmovsd	xmm15, qword ptr [rsp + 0x3d0]
140007528:     	vsubsd	xmm14, xmm15, xmm13
14000752d:     	vmulsd	xmm11, xmm11, xmm11
140007532:     	vfmadd231sd	xmm11, xmm12, xmm12 # xmm11 = (xmm12 * xmm12) + xmm11
140007537:     	vfmadd231sd	xmm11, xmm14, xmm14 # xmm11 = (xmm14 * xmm14) + xmm11
14000753c:     	vmovups	xmm12, xmmword ptr [rsp + 0x360]
140007545:     	vsubsd	xmm15, xmm12, xmm10
14000754a:     	vmovsd	qword ptr [rsp + 0x568], xmm15
140007553:     	vmulsd	xmm10, xmm15, xmm15
140007558:     	vmovups	xmm12, xmmword ptr [rsp + 0x460]
140007561:     	vsubsd	xmm0, xmm12, xmm0
140007565:     	vfmadd231sd	xmm10, xmm0, xmm0 # xmm10 = (xmm0 * xmm0) + xmm10
14000756a:     	vmovsd	xmm12, qword ptr [rsp + 0x470]
140007573:     	vsubsd	xmm15, xmm12, xmm13
140007578:     	vfmadd231sd	xmm10, xmm15, xmm15 # xmm10 = (xmm15 * xmm15) + xmm10
14000757d:     	vpunpcklqdq	xmm13, xmm11, xmm10 # xmm13 = xmm11[0],xmm10[0]
140007582:     	vsqrtpd	xmm13, xmm13
140007587:     	vmulsd	xmm11, xmm11, xmm13
14000758c:     	vpsrldq	xmm13, xmm13, 0x8       # xmm13 = xmm13[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007592:     	vmulsd	xmm10, xmm10, xmm13
140007597:     	vpunpcklqdq	xmm10, xmm11, xmm10 # xmm10 = xmm11[0],xmm10[0]
14000759c:     	vdivpd	xmm10, xmm9, xmm10
1400075a1:     	vpshufd	xmm11, xmm10, 0x44      # xmm11 = xmm10[0,1,0,1]
1400075a7:     	vmulpd	xmm3, xmm3, xmm11
1400075ac:     	vmovups	xmm13, xmm9
1400075b1:     	vsubpd	xmm9, xmm6, xmm3
1400075b5:     	vfmadd231pd	xmm8, xmm9, xmm4 # xmm8 = (xmm9 * xmm4) + xmm8
1400075ba:     	vmovups	xmmword ptr [rsp + 0x350], xmm8
1400075c3:     	vfmadd231pd	xmm1, xmm2, xmm11 # xmm1 = (xmm2 * xmm11) + xmm1
1400075c8:     	vmulsd	xmm2, xmm14, xmm5
1400075cc:     	vfnmadd213sd	xmm2, xmm10, xmm7 # xmm2 = -(xmm10 * xmm2) + xmm7
1400075d1:     	vmovsd	qword ptr [rbx + 0x98], xmm2
1400075d9:     	vmovsd	xmm3, qword ptr [rsp + 0x430]
1400075e2:     	vmulsd	xmm3, xmm14, xmm3
1400075e6:     	vmovsd	xmm6, qword ptr [rsp + 0x540]
1400075ef:     	vfmadd231sd	xmm6, xmm3, xmm10 # xmm6 = (xmm3 * xmm10) + xmm6
1400075f4:     	vmovsd	xmm3, qword ptr [rsp + 0x568]
1400075fd:     	vpunpcklqdq	xmm0, xmm3, xmm0 # xmm0 = xmm3[0],xmm0[0]
140007601:     	vmovups	xmm3, xmmword ptr [rsp + 0x4c0]
14000760a:     	vmulpd	xmm3, xmm0, xmm3
14000760e:     	vmovups	xmm7, xmmword ptr [rsp + 0x4a0]
140007617:     	vmulpd	xmm0, xmm0, xmm7
14000761b:     	vpsrldq	xmm7, xmm10, 0x8        # xmm7 = xmm10[8,9,10,11,12,13,14,15],zero,zero,zero,zero,zero,zero,zero,zero
140007621:     	vpshufd	xmm10, xmm7, 0x44       # xmm10 = xmm7[0,1,0,1]
140007626:     	vmulpd	xmm3, xmm3, xmm10
14000762b:     	vmovups	xmm11, xmmword ptr [rsp + 0x550]
140007634:     	vsubpd	xmm11, xmm11, xmm3
140007638:     	vmulpd	xmm3, xmm11, xmm4
14000763c:     	vmovups	xmm14, xmmword ptr [rsp + 0x360]
140007645:     	vaddpd	xmm14, xmm14, xmm3
140007649:     	vmovups	xmmword ptr [rsp + 0x360], xmm14
140007652:     	vmulpd	xmm0, xmm0, xmm10
140007657:     	vaddpd	xmm3, xmm1, xmm0
14000765b:     	vmovups	xmm10, xmmword ptr [rsp + 0x380]
140007664:     	vfmadd231pd	xmm10, xmm3, xmm4 # xmm10 = (xmm3 * xmm4) + xmm10
140007669:     	vmovups	xmmword ptr [rsp + 0x380], xmm10
140007672:     	vmulsd	xmm0, xmm15, xmm5
140007676:     	vfnmadd213sd	xmm0, xmm7, qword ptr [rsp + 0x560] # xmm0 = -(xmm7 * xmm0) + mem
140007680:     	vmovsd	qword ptr [rbx + 0xd0], xmm0
140007688:     	vmovsd	xmm1, qword ptr [rsp + 0x4b0]
140007691:     	vmulsd	xmm1, xmm15, xmm1
140007695:     	vfmadd213sd	xmm1, xmm7, xmm6 # xmm1 = (xmm7 * xmm1) + xmm6
14000769a:     	vmovsd	qword ptr [rbx + 0x108], xmm1
1400076a2:     	vmovsd	xmm6, qword ptr [rip + 0x62c6] # 0x14000d970
1400076aa:     	vmovsd	xmm5, qword ptr [rbx + 0x28]
1400076af:     	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b0] # xmm5 = (xmm6 * xmm5) + mem
1400076b9:     	vmovsd	qword ptr [rbx + 0x10], xmm5
1400076be:     	vmovsd	xmm5, qword ptr [rbx + 0x60]
1400076c3:     	vfmadd213sd	xmm5, xmm6, qword ptr [rsp + 0x3b8] # xmm5 = (xmm6 * xmm5) + mem
1400076cd:     	vmovsd	qword ptr [rbx + 0x48], xmm5
1400076d2:     	vfmadd213sd	xmm2, xmm6, qword ptr [rsp + 0x3d0] # xmm2 = (xmm6 * xmm2) + mem
1400076dc:     	vmovsd	qword ptr [rbx + 0x80], xmm2
1400076e4:     	vfmadd213sd	xmm0, xmm6, xmm12 # xmm0 = (xmm6 * xmm0) + xmm12
1400076e9:     	vmovsd	qword ptr [rbx + 0xb8], xmm0
1400076f1:     	vmulsd	xmm0, xmm1, xmm6
1400076f5:     	vaddsd	xmm0, xmm0, qword ptr [rsp + 0x490]
1400076fe:     	vmovsd	qword ptr [rbx + 0xf0], xmm0
140007706:     	add	rax, 0x1
14000770a:     	cmp	rax, 0x7a120
140007711:     	jl	0x140006df0 <.text+0x5df0>
