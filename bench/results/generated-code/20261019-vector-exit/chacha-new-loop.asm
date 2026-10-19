140004760:     	vpaddd	xmm3, xmm3, xmm4
140004764:     	vpxor	xmm2, xmm2, xmm3
140004768:     	vpshufb	xmm2, xmm2, xmm0
14000476d:     	vpaddd	xmm5, xmm5, xmm2
140004771:     	vpxor	xmm4, xmm4, xmm5
140004775:     	vpslld	xmm7, xmm4, 0xc
14000477a:     	vpsrld	xmm4, xmm4, 0x14
14000477f:     	vpor	xmm4, xmm7, xmm4
140004783:     	vpaddd	xmm3, xmm3, xmm4
140004787:     	vpshufd	xmm2, xmm2, 0x39        # xmm2 = xmm2[1,2,3,0]
14000478c:     	vpshufd	xmm7, xmm3, 0x39        # xmm7 = xmm3[1,2,3,0]
140004791:     	vpxor	xmm2, xmm2, xmm7
140004795:     	vpshufb	xmm2, xmm2, xmm1
14000479a:     	vpshufd	xmm5, xmm5, 0x39        # xmm5 = xmm5[1,2,3,0]
14000479f:     	vpaddd	xmm5, xmm5, xmm2
1400047a3:     	vpshufd	xmm4, xmm4, 0x39        # xmm4 = xmm4[1,2,3,0]
1400047a8:     	vpxor	xmm4, xmm4, xmm5
1400047ac:     	vpslld	xmm7, xmm4, 0x7
1400047b1:     	vpsrld	xmm4, xmm4, 0x19
1400047b6:     	vpor	xmm4, xmm7, xmm4
1400047ba:     	vpaddd	xmm3, xmm3, xmm4
1400047be:     	vpshufd	xmm2, xmm2, 0x4e        # xmm2 = xmm2[2,3,0,1]
1400047c3:     	vpxor	xmm2, xmm2, xmm3
1400047c7:     	vpshufb	xmm2, xmm2, xmm0
1400047cc:     	vpshufd	xmm5, xmm5, 0x39        # xmm5 = xmm5[1,2,3,0]
1400047d1:     	vpaddd	xmm5, xmm5, xmm2
1400047d5:     	vpxor	xmm4, xmm4, xmm5
1400047d9:     	vpslld	xmm7, xmm4, 0xc
1400047de:     	vpsrld	xmm4, xmm4, 0x14
1400047e3:     	vpor	xmm4, xmm7, xmm4
1400047e7:     	vpaddd	xmm3, xmm3, xmm4
1400047eb:     	vpshufd	xmm2, xmm2, 0x93        # xmm2 = xmm2[3,0,1,2]
1400047f0:     	vpshufd	xmm7, xmm3, 0x93        # xmm7 = xmm3[3,0,1,2]
1400047f5:     	vpxor	xmm2, xmm2, xmm7
1400047f9:     	vpshufb	xmm2, xmm2, xmm1
1400047fe:     	vpshufd	xmm5, xmm5, 0x93        # xmm5 = xmm5[3,0,1,2]
140004803:     	vpaddd	xmm5, xmm5, xmm2
140004807:     	vpshufd	xmm4, xmm4, 0x93        # xmm4 = xmm4[3,0,1,2]
14000480c:     	vpxor	xmm4, xmm4, xmm5
140004810:     	vpslld	xmm7, xmm4, 0x7
140004815:     	vpsrld	xmm4, xmm4, 0x19
14000481a:     	vpor	xmm4, xmm7, xmm4
14000481e:     	vpshufd	xmm5, xmm5, 0x93        # xmm5 = xmm5[3,0,1,2]
140004823:     	vpshufd	xmm2, xmm2, 0x4e        # xmm2 = xmm2[2,3,0,1]
140004828:     	add	rdx, 0x1
14000482c:     	cmp	rdx, 0xa
140004830:     	jb	0x140004760 <.text+0x3760>
