.code
dirtyAvx PROC
    vmovdqa xmm0, xmm15
    vpcmpeqd ymm15, ymm15, ymm15
    movdqa xmm15, xmm0
    ret
dirtyAvx ENDP
cleanAvx PROC
    vzeroupper
    ret
cleanAvx ENDP
END
