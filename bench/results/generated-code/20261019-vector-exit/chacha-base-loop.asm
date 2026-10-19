140004770:     	vpaddd	xmm3, xmm3, xmm4
140004774:     	vpxor	xmm2, xmm2, xmm3
140004778:     	vpshufb	xmm2, xmm2, xmm0
14000477d:     	vpaddd	xmm5, xmm5, xmm2
140004781:     	vpxor	xmm4, xmm4, xmm5
140004785:     	vpslld	xmm7, xmm4, 0xc
14000478a:     	vpsrld	xmm4, xmm4, 0x14
14000478f:     	vpor	xmm4, xmm7, xmm4
140004793:     	vpaddd	xmm3, xmm3, xmm4
140004797:     	vpshufd	xmm2, xmm2, 0x39        # xmm2 = xmm2[1,2,3,0]
14000479c:     	vpshufd	xmm7, xmm3, 0x39        # xmm7 = xmm3[1,2,3,0]
1400047a1:     	vpxor	xmm2, xmm2, xmm7
1400047a5:     	vpshufb	xmm2, xmm2, xmm1
1400047aa:     	vpshufd	xmm5, xmm5, 0x39        # xmm5 = xmm5[1,2,3,0]
1400047af:     	vpaddd	xmm5, xmm5, xmm2
1400047b3:     	vpshufd	xmm4, xmm4, 0x39        # xmm4 = xmm4[1,2,3,0]
1400047b8:     	vpxor	xmm4, xmm4, xmm5
1400047bc:     	vpslld	xmm7, xmm4, 0x7
1400047c1:     	vpsrld	xmm4, xmm4, 0x19
1400047c6:     	vpor	xmm4, xmm7, xmm4
1400047ca:     	vpaddd	xmm3, xmm3, xmm4
1400047ce:     	vpshufd	xmm2, xmm2, 0x4e        # xmm2 = xmm2[2,3,0,1]
1400047d3:     	vpxor	xmm2, xmm2, xmm3
1400047d7:     	vpshufb	xmm2, xmm2, xmm0
1400047dc:     	vpshufd	xmm5, xmm5, 0x39        # xmm5 = xmm5[1,2,3,0]
1400047e1:     	vpaddd	xmm5, xmm5, xmm2
1400047e5:     	vpxor	xmm4, xmm4, xmm5
1400047e9:     	vpslld	xmm7, xmm4, 0xc
1400047ee:     	vpsrld	xmm4, xmm4, 0x14
1400047f3:     	vpor	xmm4, xmm7, xmm4
1400047f7:     	vpaddd	xmm7, xmm3, xmm4
1400047fb:     	vpshufd	xmm2, xmm2, 0x93        # xmm2 = xmm2[3,0,1,2]
140004800:     	vpshufd	xmm3, xmm7, 0x93        # xmm3 = xmm7[3,0,1,2]
140004805:     	vpxor	xmm2, xmm2, xmm3
140004809:     	vpshufb	xmm2, xmm2, xmm1
14000480e:     	vpshufd	xmm3, xmm5, 0x93        # xmm3 = xmm5[3,0,1,2]
140004813:     	vpaddd	xmm3, xmm3, xmm2
140004817:     	vpshufd	xmm4, xmm4, 0x93        # xmm4 = xmm4[3,0,1,2]
14000481c:     	vpxor	xmm4, xmm4, xmm3
140004820:     	vpslld	xmm5, xmm4, 0x7
140004825:     	vpsrld	xmm4, xmm4, 0x19
14000482a:     	vpor	xmm8, xmm5, xmm4
14000482e:     	vpshufd	xmm9, xmm3, 0x93        # xmm9 = xmm3[3,0,1,2]
140004833:     	vpshufd	xmm10, xmm2, 0x4e       # xmm10 = xmm2[2,3,0,1]
140004838:     	vmovups	xmm3, xmm7
14000483c:     	vmovups	xmm4, xmm8
140004841:     	vmovups	xmm5, xmm9
140004846:     	vmovups	xmm2, xmm10
14000484b:     	add	rdx, 0x1
14000484f:     	cmp	rdx, 0xa
140004853:     	jb	0x140004770 <.text+0x3770>
