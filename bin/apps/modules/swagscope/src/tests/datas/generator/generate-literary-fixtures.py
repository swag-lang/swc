#!/usr/bin/env python3
"""Rebuild Swag Scope's original, fictional text, table, caption and MIDI fixtures.

The corpus is repository-authored and contains invented field notes, captions,
code, and MIDI arrangements. Payloads are fixed in this source so output bytes,
line endings, MIDI events and golden renderings are reproducible. No network,
system fonts, random values or external corpora are read. All contents are
covered by the repository's license.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
from pathlib import Path
import zlib

# Fixed original payloads exercise tables, UTF-8, syntax, structure, timed captions and MIDI.
PAYLOADS = {
    'viewer.csv': (
        'c-jTQ!3}^Q3<c18XZa^ix`i<=&_EL_LQO3uZ0~znV<MzI;vB;T*?Q4X>$I`!i<FRWVW(YYz4+6L1<u;(usRKC#W|W5`T+)y8cP'
    ),
    'viewer.cpp': (
        'c-mEr%?iRW5QOjh6a!w=f-TikTkFAtk0CMHLLh7)KeZsfyFsDg+-ByR*;vso8^)kxGFH+^RM)t%aIhNJs)FN%1Loo<t5vdIFxe&Lzy~UuuFGY1Z0`w5;*-PnKb)1zyrUPPNPCHe%gMv|{BUe={t?)t?Y~Um@-1sW;?&@>+6pZ?G(ElP13ZR23;'
    ),
    'viewer.tsv': (
        'c-r$z%uVGCOUx-v<#Nm^$VlWg<Z?<aN#r!*0swCp2Ym'
    ),
    'viewer.svg': (
        'c-nPQ%Wi`(5WMFrR?DS5G&YYCTHzdeX)pZ<WNd870c0E?{rWDDsA`qUhuvAv*fVxHj19~u*A4<r2>mN#(=_d;bl>@gC7g3c41~$n!3d0#0>LQTm>@9E5Jsz}w{8~5fdlOV4Uap3vQ~On8fu+wRpsA(Ra?~tu(iP9>~$p-!W@$n;j)!Ep(_ZjWmA)W2we}I)`JQwYr#*lbDb9$>4SdZ9NB$#{FkkZ>W5vj-_};+?B=}mN``-fd&*2BZJiT%_U<9NW_sLCFQxU;DUifV69jqLD!GXBn=Xo<X;oK6Uj+m7IG=e2abdD-EI#t=>%<}9CQUYUM_MjlbliOd6U%@O'
    ),
    'viewer.txt': (
        'c-qC1$!-%t5Qfj5r}){ov9TQ!g3Xo~0tONmJA^Gj&rEsTaeKz}^w=@m0U-_?kpe=B;DjJ32qA%@f'
        'Vhym&(4)Ygb+wP0%eDHK&_U#y1J^mzWOIaZE6@3kql6kq&!4M7#Rlmw#*l9|0oowMS%=_sL;2{v2'
        'IZZncNueBAd<*Co}0}W`vE<iHLnVj|r&-iZu$XX%eQ^zf#h#8EC<Us9(;9F!182UO-zI(okGPA(P'
        '5w(dhd)48h=gzKDHFSrsjUh+LD0Ci39${{H9*s$pmxEj^zGrV87ftW8oEI0e5%BpOXcm=!ugL_%>'
        '~HPoD>C8?dVM$5%g3C%cgO+08lk4@N&E!c`}*p408iCx%@J+P5P3VV@90S9pihj9c)aTV7vgX_3~'
        'o4CUe?%}>QRT)o?@aGLhdAOpwy13E4jX<ovZxQ@hsmMlmzWasOa`$U@rTe+N1SK3&HrAiLT3=ZD@'
        '%9B8qKP_nZ2X>I`1$GGucsejgm0twdhKCvrT3xtX6<ork)P?hjXy7+KVVG4;i~_}n9w9VhMkB5X{'
        '^a)dMME+oM>31@JLCAG{aXN#<nqD>GHUh42T&iX3442ne0$*-|+sC1Hy4Vs`@oKTUU)BY~Iq5iCg'
        'Wt&h62$;<4l7Cr*}5ojx-$dG_4-3+2kx#pz3zul(O|tHLU3Dpp<6(3}CQQ?jf#B;KdST9E@;XtyR'
        'D#WMQ~MJXAf'
    ),
    'viewer.md': (
        'c-n1M&2Hm15We#%rdy+k9mz?Y9tvX}z)kljK-UQpFZN(L8(JDkge6iTsYDCMLD6R@P!uTIQx7fr7'
        'JZW*7CrV6I+PS=lT?6ZYW_Gs-^}>F&#bT+4&hMcMTQpP4cE&^T}!wUc#RrjQQ1-><E2fN9>Uo*Pv'
        '9(61%gFm4YNEkLzv~Qo(CFbgj&eN17kJvoQ`wm(_QRyc#S-wZ^-ZpGf)zV_?T+1m7_i(ry6VVC!A'
        'Q7x?w!wh^toR3CoCzv13gXu0K#Ll?5Tgtc=h=ueVTH)a!ZB6P9Npbf<<0Ex|EwZz({rMDk3PNqT$'
        'hvC$|MNt)5mjz%6_2$>0q5UL0-Ja~OOxIOluIv<>Sz$Kswd4UlGJ#H-J%q)Xm!^k1xCWXJh`@v&e'
        'M(}p}(*Fuf8K%GuggpN1cMm@P_}j;y|NQ5VUz|<^|Ni>Z_kG4@V+rlG^jglhQfmt{+}Xj3yCU~Pm'
        'BX_a%?H%=f7bQj`C~DqlY_=EXETj4Qenf^=Kc2^utFUQgTOP&YFQLYTZ+laQDt;)oKN@iLwJ0VL<'
        '`SOHy1P>F?IlBSY#?(!eyxlnIYvRRMK)GsTi0SDL2BnI$X5rt$hW9Bvs#!eRe=*e3%eY$)(zkt03'
        'l#`S4aMO-Q|?z`bDkm;<oazhgdN`7o>Io9>Cga<g<qn8OM6frDF3Vx<34Xk#C$5BhM{xch*---l@'
        '`^dl;TGW%?DJbf{z(}Y4XP-t}}B81XlTxNB82*~|Lbb55+B&VV<RF@<n_bELKv;;LMxJ_HRqc<nV'
        'r_=Fd>ZFfyS3fRYH@NC?E0hFk3e;D0Atz<&NUiR>@#*Af^2%wx<62U@#tDa7EC>)(ge7JloSTab^'
        'H%3@{C0YDJaIaQG*-yi1D%M=1gW76sL~Qvsfz3d#?(_Xr@P?>&OQ(dDmt8^DKnz5o1wpX?#{y-|L'
        '#Eg-(qZ`er_NnGn9fG(5_Fx=@X*9u3O&m8$8kB%R!^T*u}+#p~=T~b_kWR!)a7Eb&JqzVN(|_xnA'
        '-FfoeioiUsOEi%S{OAX+HN!%%Ep@vNkQTka3K{sFz&s>YXyq2|DI7(k>Lw2wv_zp~-6PY90;5_b2'
        'xu>C*eL6@za`>fWkXM=O@q5m3lYAXY|lFAgEqNAkOBm1bCB!q($9T-9y_MI0nf;>DQbUf%(@5T8_'
        'Zttx-bpx_akWs3)f>`r##kUvhRp>|SpiXs{RLF3r!y5M9dL`F^Df9O$G1^^|oi#Xn1F|2OOKn#H&'
        '#2ESuz+yO*G`oMGd6Yt3rvJuEyyb^sx_tm3s^u9Ku8CgsnmWOrWagZmONtdR@J>%4Y@(HrfEzH6$'
        'DhbU8nC?_4jkwt!*??ESNWrH>%vh5u-KRq7b{z!U#D1ZNq>s=)ItG5U@Z<`+oO)&yD=Riz+9!34N'
        'c8x(hb8TyV6f&X8-G^OoxbEo0LZArhwU$$Yb&X<Ni1Y`W7?3D3gN(l&xRjcRP%Sm0FScCQy)^F;H'
        ')HT@KIUhm!^e1ox&qP9{m<C^6b@B<bR?jRm3WhKp?{_K3S=qWRwehuMeD`Z+=(I1bvbBtTs;|S;`'
        'UR)m|6_&2A-IkahAI{l-IlR&v'
    ),
    'viewer.html': (
        'c-l=;%WmT^47~R%SohkjlA?!2qUc!k(8r<u0mh<iVf8R5xlK^?-%Hy;wkHY0;cz&TzP7oor-7iaF'
        '_<eo9S|^e`-W080fg3E0q95-q3w|i)qOKoxBA=6h3ab{^Y)1yytP@R9^apz!1-exnY3EU6S36Oas'
        'xPIdx9@;In|ZJ=)-9X1yflSV()ekkvpHZaK{vP@ICh+SKkJbwnJu1yb9#%7Vd{5lpMT;8|Mz|^?C'
        ';bTI*AHCTuPmTAeLuwXCHlAG5c!_~K6Y8#6EQ;pvlD*qd`<Fz>xD;A0#s9>k2qH%3Yo=t$i9LIoy'
        'inO<&T;9TeyC=NXqF90SB2qCv9A^Y_2k5<D)S@PkWI`fb@Vg;sY`gZa>!{QNoCbw^HtUQGer7_t#'
        'ks;wG2}Fi!h31#&7{J?obK&dY&1?GaS}Or2@FmLvl{kqprjkc)sVr4BhB+a1iAbv@HpylFG(T>5y'
        'x9'
    ),
    'viewer.xhtml': (
        'c-mEu!EVDK42JK03XA)~*m_teLZwdHZ98=jK!RInDMZE#?c0wir`;_5-)H;R`}-}zj8sBSy-?k=0'
        '8C?cA)R~ibNqaI6MM7Ko*UNCRC?i=r*|o9tzCWXGM%N`?RN6MFan}oOiaRPkJcH@fg_slOzh!cOG'
        'r@IaythpGitf!TCVhv-J_Z6pP;sfmMfzt^A*U#hsOkjV<v|VEQ}t<Yn!TNB#1a;gnR<kZC~JqOju'
        'yRQziuWTdtj!)3WO52@wj~*wl-q0=5wzql3n_B10z2nI7%b9I&pQTtAdcTeJBCz!PiK'
    ),
    'viewer.xml': (
        'c-n1{&rZWI494$$3d{Gd>zGg_((Zt?6I>8HfZKSjwKN$?y0Nz>Eq?^kZlA5sKii+$eT)Xq?1MO4W'
        '4T%*u<e`{+t>K^y3Z@zHJLgH8~ws3=Oc)&(IzqEEd{Z8xor_NMXqtP-rVQqIxj11G63b;z&_ENXY'
        'mA&16x)6_GZI{DGo_LNk2sJBo=sv_COKz6ppI+vCMYQG+zcm=55On(9_g2!ek}ZI3m1HWF%f|>;~'
        '?Rtg$Iq+l?x|XK!#kvxYV~Z$LOi8PjhI=C1mWu`Y76moBF8$iUZUG*{sP0*xob0Rodr{DbpgsCAy'
        'A^H=bE7QU=hu`n`K{7JaUJ^|@Rh%W'
    ),
    'viewer.json': (
        'c-nQ5u};G<5Qg_Y#mRGvno^;Pu`m)|pklZtm&8q)z}YFPsxG_(LP!WE22l435DV;ijEa#*;OtBwA'
        'y0ST{lCw@R~-OlELvTa>JZdv#WsU68eKv#9ILM9H7{s+jF#NUpg%b11^r$yYH2k!B%B=!H6t8lRJ'
        'Mo-V_l|3&_rs0l`^_@Dg8w$)+wnjs7o>D6IxIal4Wv=U~f1Oa#3TU?b2zYjG~-kweJ2gW1<+QLjH'
        '5wAN_VBWA$7H#Y?Qt{IX?b{q#gJ%InExkOEqWYm+-?gY)x(V1{hK5Ei0tm9<Sqem_h;pWtH)&2{r'
        '8XWP6tFU@PSalPHm<L++r^?dJ&?}yu~HX;d5Cpz*U5F+Poj?!@rEFjTT#K06)9IMW{^8<dKk*E'
    ),
    'viewer.py': (
        'c-mEv!D_=W5Jd0#ieXPS6qmXwlz=b&fF9Zp5F2})h)QyhWE&dt@0IPOw0oS<yd5nOeU8p?Fy8`3Z'
        '`x!A&lc}PNGH5;G(M|hJH*6`hsi{fDk4%U2zSOGBN|-DuZbg%N1;8Qs$Km63L+g2(yhw#YgX(qOT'
        'a89Y}(6JDb-02_Axs}xmU=O`5%(T;E_%OKe|Is4L#bEv|pJS*`2Mx4(-}1u7#Fh*iyUthIPVTTba'
        'b((YF_IbjAGx)x>s`Sd=9mVa5L%Wu}-OT6=b)HJS#bwPWM8rVV!v#;2mEzZYAUV&;@PudDaC{OeK'
        'G{S}T%^#c(Bc<%'
    ),
    'viewer.swg': (
        'c-k$=u?~VT5C-7APw|gB01;eau!)np_ykQkq_JF+-c{q<TNBss>pGl+*O1sn+)~yRCntfi1d4Mb>'
        'V5|)+vf78HKpDIHf1u#Cl<v$DA`n4F=F_eUCBRbzR-)}l{AyoJhaE&n5D3XV|i2F?VG6#J;n)jzV'
        '>A;Q~'
    ),
    'viewer.rst': (
        'c-n1I&1%Ci48Hp*bPj1)+HQ=%E*<RDbx`^ON~|Q>5^Km_!`^;MT1pQyJ_zg6_ah%fQx7|g9N>*<@'
        'UWN8z5I8at2`#EpnQgpCP_^S>xcD|tE7&kXVMDZSrJ})3a*MgV-I)y<#y-XsVAT_1r8k~#Sp1U(8'
        '@5#L>`iLm8_`A=g_Fcczta}QmyPe$^nB13ZA^fv^3{og^5@T*mKt>P&7fpxKOpCbRpq@g9)HF`NF'
        'y5rHXEKJ<erU%N_o7=0D5IV!MVh%gjzs%@_H?FvqJ$1C+()+4?z9Og!3x7Qp`I$o5ri9$~zjH{CP'
        'S1VIwrq!;y5Z|Nc8_&pGOqDG@I?~!mYLCXOH)}ok1e=Wz%QoyO_2zD`mD0g$l+_l^!mN{;_e5+C;'
        '>S0n&iNZoP?}2n><v8!r{Kvxm0ey<9zy'
    ),
    'viewer.hex': (
        'c-jrku?@o@6h+aVDc%54MA9S+gf@jI_=aa231bU?Y_feQuTF7?OJ)py+lhru0)1R1;f%akFvX^|('
        '0r%qpdL5OWve>_#-FmM<N#d=WmEVq)ipy>!XhV8C_%==4q2JC4+`(bTG$8d6EBCih5Nuc^9KShEo'
        'c'
    ),
    'viewer.page.html': (
        'c-nnZJx|0i4Bh)HOc_`XDws|vtpqa&iG?|B-AhCoSBcwGh4}Bd$sHdHQ{(rZpP$pHi=H}OCj`TzY'
        'YMe}z-fP|OZ4RipzfOjK#j;6I-^5GuFIK+>wTFBw(PKZIeHAy*l7nx%Z6r#4g-$lS5;+6p{nerTI'
        '$!-Yi|E<6h6uBeq;jPC2(pUV9{=t>^cH@1llw=@Mh2hn^O%3!njLyR&RA01(xr@6LjPpc1!`n>?5'
        '>jtnY=~Wpef`E;hnDPAqJ+JqmlHs_7i=nHK90zmjDD^mjntN9h4tFx-RcsK@4VlnUB;7%-?RLEum'
        '?l5PtdX$~C%juWpS{R!+bvh|uRc?cLM^3k>qzq3pMn?(m1T*E^MdcB(WAD_hrwF2dlx~M8q$VSP0'
        'CzRY&p4zUAQQXAmwA&+vK*zu9y~=Nt8<$Nqn1DlFUbbgh`MX0mDf*Ah*#X&(7|Z7AeB5Mt16AdhA'
        '*0fB`~ojI-mL'
    ),
    'viewer.srt': (
        'c-k}MGBB_LBOOx%0|i}OI|ZnKk&c0Z0ar*yszO?3QE`bva$-SAW`3R?7ncziTnU;UQyn8y11?8};'
        '?(5)ycC!guKYZOlJb0ooXot`Vm&SZ^~@a('
    ),
    'viewer.vtt': (
        'c-l?R!A`?43<ltPp29ECD66P6hQwhAae~tXXRrO+W~A}tWb5mbwg+~zCHwR5pZDYU>10gGoV~<~R'
        'sEfVaqi%p-8n~9^-4=u+op6J{16XiTC@2O=?Hg39|!7HCdwn|OEiyk<m4muBKfSo8(@u@IYX;Z7B'
        ';@N`v<<UwR7fFfVct!-v*F^yF?N}SMf0y@TQb!p$S=$ikf)322|~c_SbAs^T6(x9}24gU04&bf)Y'
        '5Ods*Wumz+KkmcT;++aOC-MaeK5@$?VwoP93fr&p%85s_ve0`)#%)q0Q6Q5u0vXY^8zO`>s?{{R8'
        'BZ^-'
    ),
    'viewer.ass': (
        'c-noE%TDVs5Qg`DidnJ2irf$?lpP$X4v3p*Re>rNqj-{9$FZx4QwUFwlaRs!9bcqxtnu%EY;TqYn'
        '_YlwSNd16GQm;~_nyNRF0e5UN<&sdU~~-?L5%6EZWq(`S)$ajc(m9(QS+R`JX2HjlEcYdiOo7YhG'
        'pn1HLqgfxyBIXu_g%%?}9r}V?H81vZ;}~Ki>M5B`m4%PXAbVXoEG5rtkube+TwfOSlebP0>fJiHC'
        'y^yQ1C}wSSXvZcXKCazVl!a%J4@1WyyJC0x0}YvU?0$mDQICAK!mb2eyYn#!ZUN-c&q;23;i-y)t'
        '(*!P)C$9dL|G%kqE)jrzzaW}WvQD1pL4!s2};j4=A*8b<WEaMAFSkZeBm(ioI+GsnToU1ryiJI^v'
        'IaP8h=gu(7(V$#y3Ec4b6}A-t6Y2(LNtQxQfvHJ;5zfAa=Sli4eB<4uyTp1IzW^W;G=!Ekl%Avf-'
        'q2ejJ^_@X$oc'
    ),
    'viewer.ssa': (
        'c-nnZO;5ux488YP_y<H)SJn+p;s9)uKzxZ#aF{rR)@`k2$#C6`@#{&u6?Oq7QJyX9y(intG-KKb+'
        '}Ogs1q%{`6L@ee6<q0>EEI$$2Vre%%p^FJFZLT>wjG916f9qckjma*{T9p}ueEpry+#FdXT|=Yn!'
        'Y@GVp?n7UpwO(R*+)mY<`khAPb$uS2|n$U}tg#H=+$?ZNxcpr>x+y5kuC4w9>iTDY!IL+BI5HaId'
        ')}d)I^K9=x<wn@Zo|7L9_L&0J2l3_8jQOtH|75p~I=jf!J67>&o{c#x=3lAI+fI-Y@w5AVFaahD2'
        '~v#r-Y>4=wHp?9B(W@*Jb+<8AV>mQf1qVTP6d-Ey5)VpzIgFWSi7o0=`KZ*7~3zJCo&hLr!(WF{b'
        '2*&M@VTZ&(HGDLL0^%%{m4tur4v)N}F#hGeb+)H{MaXo!B$nz5#EbNs0`FKjM)1R3g~2y{D8^9'
    ),
    'viewer.lrc': (
        'c-ke*F%H5o3<c1=r|=0X1A-wVFhU2!R%LKiLrhyoaspf*i*DBc@4F`pS22Q9VvS8-C3M+pf+H1Cp'
        'bF=AnY=&@xM>mNjXbYOv;YnH!+tXu^9TcvtJ}4Ej2F_%=4v6E{^&~{%%Z%iL%YRzPd<ghH2Z@WS#'
        'c#59@${YrlQa02OMuT_5'
    ),
    'viewer.sub': (
        'c-j?>K?;K~5JmT%;-4UBP@x{7&{cbZDNZ#Ioia(45_0!WcaIP6ztYvx`|1bRHpSTY^%j&SJXXdon'
        'pZ6JSs2PRCv>j&*f=XE*Aze0GPd<9`-D4f@5l+HjKmaq#!D2Do}!dRzxHqhK1~~~a~bNtpcHm6B@'
        '^XfMYb)<X>@W>*ZcshGd6J'
    ),
    'viewer.reading.srt': (
        'c-mFa!ES>v3<lsk67S##aHk{$N_&{J<1RZ*+BuW}(P%s+sZig3hC)>iK#cI`-)O1wOo+3VXQ@zV0'
        'f)motS>aywaByY!NOodL$?5<>xUF!vOWRb`0^H-`}}yzvpmzXcyc8cYR8>WD&{_*vmxB!5-3L7LS'
        'nu#cbHrnX3{{Un{QW7KfM!H;?+|cm0<73!i5{sMv>uwT)T0pJL(}3{Vv65B4_UA^A(I=JM1_{zW2'
        'uSmk^xq*Wu+hT$L#5-S8UqJp79qYUlkI>Cf2!(YThEm?*UPV5%om<FR^W3W;UK%oZiNmbWoi3(kW'
        'X9~(rj*FeWjDhd?4zfovB&4E4>OeQkK1~1bS479ZW0|(N8%m'
    ),
    'viewer.mid': (
        'c-r#~$w*;fU|<7cM#cxeAw}6hRvN>9X0CwD#Jqfkp!}R1hW~-g><bkb{ztH|FiCJQ{EuV;Dw<%E('
        'OA%617tWP02vNIhI0&%;S6MW6f`F^cz{GApdt=2P&GC=Kq;WE|N0C73Th)o'
    ),
    'viewer.groove.mid': (
        'c-l>sSyvQS6on6?8o{NgaU?ik(~K=NOF)5c2ALGp;CRJ|#sNr_793+-*1bhHR`XI-Z}oTbOY)N6V'
        'ZM{BPJF3#>YRP{-sg1P+w(V9o`^`jR7qXcpYu02e&MZIzSh)FZ>+DseJWpX)a?4>qI|tuTU&i}w|'
        'vdWzo6<>Ky}wwAH7_+&%-%Wz8{X8%if%9=fZ2oKk1FjR;zbSvf*V@oFHWjyfu24#qJHq%+4uqOiV'
        'axN<-A#It;I<+g;wMz&By4pxSBiCgd<6dPn7GIB&M|-n_Wi;iR!oAa3v`rBn!Kj9moP?9GVlM`3F'
        'nxO;#h8pp*pg;zAXA|Jw8Q_Rrq4tTR-kA=hL0u+9SH!Q9`%o{rxj+j9&FLuxykp&d}9@2fN`YCjF'
        'YiR|YDz#9c*FMAt(=gWtbNS26wGu9v(k({fZBE+4DKqIUNO{Sd5}T=v(}_6sVaWj8UZ%y*gSL0kb'
        '7}BT*}@`v<$1QSpJ7lLmlW&T`XS62o5N49mlNBki~EGBe&+mgSjQ;PcM0S&Ll<A5#D*u>@UUzGcG'
        'tpb<2ORvO_1`Y#m@0K5MDL@0t;yJuFB3n7T{VK4wIK<7Te`}Ofs!M&@(LCEaQx*;}aD{TTtFwmb|'
        '2#huCq7xr$9Vbv=w!Y{KO~8#oJS9xDGJpe6l&u9Ch9T~I)CNmUM^`~L@5^%oyp?f9e3&Am|@rfeI'
        '^Q5T<t?Gk@ql-68Y-bL*!%C?L97-hAX755ofX)5Y4zX5g6Y=^Ay;x9($Od~J;qCF?}NQE^U^=i;7'
        'ccLC8=n?lR>QmA_se{QDV7U=x6qFGwQLENk#qEK#l!`iyJr1jzvYp~Cz)AyNzo!FSMv6HVUj|}F='
        'p||uyNYda?R>0JzvlYIjz#A+IxlW8N@<kRTv|P)WiLe<&Wk;dO^AEs_sRq=g#yJ6>5aNI=oWhe=M'
        '<U$Jx0i7WKU&2yT+<0X8HOUo?@>&t+4ueEk0laH2`*+*}~Rm{7_7Ze+&VlZrN)1&-V+Y%4saTNAA'
        'lSc{_@iFZY#u7YKI`0o$k(oZ@kvDa!iz=60#($KJL0dSmtF^UcwC2%m09Tyv~v&2iQ~#W~I8WPhx'
        'O&W*9cc-m~|;yF|0rln}&0b`#!KF<S0Yi>Z?TORgKJgRs;uj+W#l-A(6?PjGs2iMkWJZZjshR2<D'
        'lTvJf$lZ=-v|&c<yGrD86%xNb)>G_;<w887!HC!g@g-L1E{WX-IZ;kt(TUp`@vGwrg-wVXh%ajKq'
        'S)Q>xaP*C31xz5@gFiW(U4^61cm0Yc*+DFsMufWtVOBbO^JUSh7Xkm`7JDnhy~SwB*M>x_7sTbDm'
        'o*WF4wR)+l=!?mgg?94B)fk^0D5|<hEAO0e?~46Lo!+_Cq+|X@H_Qq^W7J$4J>b;P=FO-%@jH@u1'
        'l`NUhNga=NIUMG;bN*>1)lnv$(OFo37Ko*#{9PHJMkZrr!WzIwm@&rEK-d9mr&B^-#Vq{BQ6I28G'
        '$$BYFX5`0Xu=1I^a<>4U9O_204Nzf-Vpm$DzJeZ_SsS32s1!*Z>NV?4x;H7kuG4nyU6d#eXO+iN7'
        '0<Q&CS*9<aq_7om>W(IQ*hoDl1$l~3u@cQEdg_8U^m;YZD@}=>R_#kAdRh^6KcnUUlysSDWP*W&O'
        'X7LZCABEm1)aiF8DrGTxRzQ0l}?gJS?>y_96+X20CgRy@^t|AjB+j$eN6Pu3)<xx0U2(QJdWL7nr'
        '$0yda!;1lG0|yY^~aR#!md>SeRlR#UFJGX*{?=9`+`CWad6uW4*9v8BlLqTtC7iES++MAZRCT->K'
        'PEYHyUK06`k5;4{7UG<u~L2+kyW8S-W|g0oF#EAu_BZ2gulprCZ$RenI%km&u37yT~&1}96~y#'
    ),
}

ALIASES = {
    'viewer.markdown': 'viewer.md',
    'viewer.htm': 'viewer.html',
    'viewer.tab': 'viewer.tsv',
    'viewer.midi': 'viewer.mid',
}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    generated: dict[str, bytes] = {}
    for name, packed in PAYLOADS.items():
        generated[name] = zlib.decompress(base64.b85decode(''.join(packed).encode('ascii')))
    for alias, target in ALIASES.items():
        generated[alias] = generated[target]
    for name, data in generated.items():
        (args.output_dir / name).write_bytes(data)
        print(f'{hashlib.sha256(data).hexdigest()}  {name}')


if __name__ == '__main__':
    main()
