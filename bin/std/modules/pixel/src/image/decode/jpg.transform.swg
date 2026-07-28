#global namespace Jpg

using Swag, Core, Core.Errors

impl Decoder
{
    func idct(data: [*] s16, buf: [*] u8)
    {
        var pdstPtr = buf
        var dataPtr = data

        for #reverse [rowctr] in 0 to 7
        {
            // Original code:
            // if (dataPtr[1] | dataPtr[2] | dataPtr[3] | dataPtr[4] | dataPtr[5] | dataPtr[6] | dataPtr[7]) == 0
            let dataPtr64 = cast([*] u64) dataPtr
            let tst       = (dataPtr64[0] & 0xFFFFFFFF_FFFF0000) | dataPtr64[1]
            if tst == 0
            {
                let dcval = cast(s16) (cast(s32) dataPtr[0] << Pass1Bits)
                dataPtr[0] = dcval
                dataPtr[1] = dcval
                dataPtr[2] = dcval
                dataPtr[3] = dcval
                dataPtr[4] = dcval
                dataPtr[5] = dcval
                dataPtr[6] = dcval
                dataPtr[7] = dcval
                dataPtr    += 8
                continue
            }

            var z2 = cast(s32) dataPtr[2]
            var z3 = cast(s32) dataPtr[6]

            var z1   = (z2 + z3) * Fix_0_541196100
            var tmp2 = z1 + (z3 * -Fix_1_847759065)
            var tmp3 = z1 + (z2 * Fix_0_765366865)

            let s0 = cast(s32) dataPtr[0]
            let s4 = cast(s32) dataPtr[4]

            var tmp0 = (s0 + s4) << ConstBits
            var tmp1 = (s0 - s4) << ConstBits

            let tmp10 = tmp0 + tmp3
            let tmp13 = tmp0 - tmp3
            let tmp11 = tmp1 + tmp2
            let tmp12 = tmp1 - tmp2

            tmp0 = cast(s32) dataPtr[7]
            tmp1 = cast(s32) dataPtr[5]
            tmp2 = cast(s32) dataPtr[3]
            tmp3 = cast(s32) dataPtr[1]

            z1 = tmp0 + tmp3
            z2 = tmp1 + tmp2
            z3 = tmp0 + tmp2
            var z4 = tmp1 + tmp3
            let z5 = (z3 + z4) * Fix_1_175875602

            tmp0 = (tmp0 * Fix_0_298631336)
            tmp1 = (tmp1 * Fix_2_053119869)
            tmp2 = (tmp2 * Fix_3_072711026)
            tmp3 = (tmp3 * Fix_1_501321110)
            z1   = (z1 * -Fix_0_899976223)
            z2   = (z2 * -Fix_2_562915447)
            z3   = (z3 * -Fix_1_961570560)
            z4   = (z4 * -Fix_0_390180644)

            z3 += z5
            z4 += z5

            tmp0 += z1 + z3
            tmp1 += z2 + z4
            tmp2 += z2 + z3
            tmp3 += z1 + z4

            dataPtr[0] = cast(s16) descale(tmp10 + tmp3, ConstBits - Pass1Bits)
            dataPtr[7] = cast(s16) descale(tmp10 - tmp3, ConstBits - Pass1Bits)
            dataPtr[1] = cast(s16) descale(tmp11 + tmp2, ConstBits - Pass1Bits)
            dataPtr[6] = cast(s16) descale(tmp11 - tmp2, ConstBits - Pass1Bits)
            dataPtr[2] = cast(s16) descale(tmp12 + tmp1, ConstBits - Pass1Bits)
            dataPtr[5] = cast(s16) descale(tmp12 - tmp1, ConstBits - Pass1Bits)
            dataPtr[3] = cast(s16) descale(tmp13 + tmp0, ConstBits - Pass1Bits)
            dataPtr[4] = cast(s16) descale(tmp13 - tmp0, ConstBits - Pass1Bits)

            dataPtr += 8
        }

        dataPtr = data

        for #reverse [rowctr] in 0 to 7
        {
            if (dataPtr[8 * 1] | dataPtr[8 * 2] | dataPtr[8 * 3] | dataPtr[8 * 4] | dataPtr[8 * 5] | dataPtr[8 * 6] | dataPtr[8 * 7]) == 0
            {
                var dcval = descale(cast(s32) dataPtr[0], Pass1Bits + 3)
                dcval += 128
                dcval = Math.clamp(dcval, 0, 255)
                let dcval8 = cast(u8) dcval

                pdstPtr[8 * 0] = dcval8
                pdstPtr[8 * 1] = dcval8
                pdstPtr[8 * 2] = dcval8
                pdstPtr[8 * 3] = dcval8
                pdstPtr[8 * 4] = dcval8
                pdstPtr[8 * 5] = dcval8
                pdstPtr[8 * 6] = dcval8
                pdstPtr[8 * 7] = dcval8

                dataPtr += 1
                pdstPtr += 1
                continue
            }

            var z2 = cast(s32) dataPtr[8 * 2]
            var z3 = cast(s32) dataPtr[8 * 6]

            var z1   = (z2 + z3) * Fix_0_541196100
            var tmp2 = z1 + (z3 * -Fix_1_847759065)
            var tmp3 = z1 + (z2 * Fix_0_765366865)

            let s0 = cast(s32) dataPtr[8 * 0]
            let s4 = cast(s32) dataPtr[8 * 4]

            var tmp0 = (s0 + s4) << ConstBits
            var tmp1 = (s0 - s4) << ConstBits

            let tmp10 = tmp0 + tmp3
            let tmp13 = tmp0 - tmp3
            let tmp11 = tmp1 + tmp2
            let tmp12 = tmp1 - tmp2

            tmp0 = cast(s32) dataPtr[8 * 7]
            tmp1 = cast(s32) dataPtr[8 * 5]
            tmp2 = cast(s32) dataPtr[8 * 3]
            tmp3 = cast(s32) dataPtr[8 * 1]

            z1 = tmp0 + tmp3
            z2 = tmp1 + tmp2
            z3 = tmp0 + tmp2
            var z4 = tmp1 + tmp3
            let z5 = (z3 + z4) * Fix_1_175875602

            tmp0 = (tmp0 * Fix_0_298631336)
            tmp1 = (tmp1 * Fix_2_053119869)
            tmp2 = (tmp2 * Fix_3_072711026)
            tmp3 = (tmp3 * Fix_1_501321110)
            z1   = (z1 * -Fix_0_899976223)
            z2   = (z2 * -Fix_2_562915447)
            z3   = (z3 * -Fix_1_961570560)
            z4   = (z4 * -Fix_0_390180644)

            z3 += z5
            z4 += z5

            tmp0 += z1 + z3
            tmp1 += z2 + z4
            tmp2 += z2 + z3
            tmp3 += z1 + z4

            var i = descale(tmp10 + tmp3, ConstBits + Pass1Bits + 3) + 128's32
            pdstPtr[8 * 0] = clamp(i)

            i              = descale(tmp10 - tmp3, ConstBits + Pass1Bits + 3) + 128's32
            pdstPtr[8 * 7] = clamp(i)

            i              = descale(tmp11 + tmp2, ConstBits + Pass1Bits + 3) + 128's32
            pdstPtr[8 * 1] = clamp(i)

            i              = descale(tmp11 - tmp2, ConstBits + Pass1Bits + 3) + 128's32
            pdstPtr[8 * 6] = clamp(i)

            i              = descale(tmp12 + tmp1, ConstBits + Pass1Bits + 3) + 128's32
            pdstPtr[8 * 2] = clamp(i)

            i              = descale(tmp12 - tmp1, ConstBits + Pass1Bits + 3) + 128's32
            pdstPtr[8 * 5] = clamp(i)

            i              = descale(tmp13 + tmp0, ConstBits + Pass1Bits + 3) + 128's32
            pdstPtr[8 * 3] = clamp(i)

            i              = descale(tmp13 - tmp0, ConstBits + Pass1Bits + 3) + 128's32
            pdstPtr[8 * 4] = clamp(i)

            dataPtr, pdstPtr += 1
        }
    }

    mtd transformRow()
    {
        var psrcPtr = notnull .blockSeg[0]
        var pdstPtr = notnull .pSampleBuf

        for .maxBlocksPerRow
        {
            Memory.copy(.tempBlock, psrcPtr, 64'u64 * #sizeof(s16))
            idct(.tempBlock, pdstPtr)
            psrcPtr += 64
            pdstPtr += 64
        }
    }

    mtd findEoi() fail
    {
        if !.progressiveFlag
        {
            .bitsLeft = 16
            .getBits1(16)
            .getBits1(16)
            .processMarkers()
        }

        .totalBytesRead -= .inBufLeft
    }

    mtd convertGrayscale()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d   = notnull .scanLine0.buffer
        var s   = .safeSampleBuf() + row * 8
        for #reverse [i] in 1 to .maxMcusPerRow
        {
            d[0] = s[0]
            d[1] = s[1]
            d[2] = s[2]
            d[3] = s[3]
            d[4] = s[4]
            d[5] = s[5]
            d[6] = s[6]
            d[7] = s[7]

            s += 64
            d += 8
        }
    }

    mtd convertH1V1()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d   = notnull .scanLine0.buffer
        var s   = .safeSampleBuf() + row * 8
        for #reverse [i] in 1 to .maxMcusPerRow
        {
            for [j] in 8
            {
                let y  = cast(s32) s[j]
                let cb = s[64 + j]
                let cr = s[128 + j]

                d[2] = clamp(y + #wrap .crr[cr])
                d[1] = clamp(y + #wrap ((.crg[cr] + .cbg[cb]) >> 16))
                d[0] = clamp(y + #wrap .cbb[cb])
                d    += 3
            }

            s += 64 * 3
        }
    }

    mtd convertH1V2()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d0  = notnull .scanLine0.buffer
        var d1  = notnull .scanLine1.buffer

        var y: [*] u8 = undefined
        if row < 8 do
            y = .safeSampleBuf() + row * 8
        else do
            y = .safeSampleBuf() + 64 * 1 + (row & 7) * 8

        var c = .safeSampleBuf() + 64 * 2 + (row >> 1) * 8
        for #reverse [i] in 1 to .maxMcusPerRow
        {
            for [j] in 8
            {
                let cb = c[0 + j]
                let cr = c[64 + j]
                let rc = .crr[cr]
                let gc = ((.crg[cr] + .cbg[cb]) >> 16)
                let bc = .cbb[cb]
                var yy = cast(s32) y[j]

                d0[2] = clamp(yy + rc)
                d0[1] = clamp(yy + gc)
                d0[0] = clamp(yy + bc)

                yy    = y[8 + j]
                d1[2] = clamp(yy + rc)
                d1[1] = clamp(yy + gc)
                d1[0] = clamp(yy + bc)

                d0, d1 += 3
            }

            y, c += 64 * 4
        }
    }

    mtd convertH2V1()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d0  = notnull .scanLine0.buffer
        var y   = .safeSampleBuf() + row * 8
        var c   = .safeSampleBuf() + 2 * 64 + row * 8

        for #reverse [i] in 1 to .maxMcusPerRow
        {
            for [l] in 2
            {
                for [j] in 4
                {
                    let cb = c[0]
                    let cr = c[64]
                    let rc = .crr[cr]
                    let gc = (.crg[cr] + .cbg[cb]) >> 16
                    let bc = .cbb[cb]
                    var yy = cast(s32) y[j << 1]

                    d0[2] = clamp(yy + #wrap rc)
                    d0[1] = clamp(yy + #wrap gc)
                    d0[0] = clamp(yy + #wrap bc)

                    yy    = y[(j << 1) + 1]
                    d0[5] = clamp(yy + #wrap rc)
                    d0[4] = clamp(yy + #wrap gc)
                    d0[3] = clamp(yy + #wrap bc)

                    d0 += 6

                    c += 1
                }

                y += 64
            }

            y += 64 * 4 - 64 * 2
            c += 64 * 4 - 8
        }
    }

    mtd convertH2V2()
    {
        let row = .maxMcuSizeY - .mcuLinesLeft
        var d0  = notnull .scanLine0.buffer
        var d1  = notnull .scanLine1.buffer

        var y: [*] u8 = undefined
        if row < 8 do
            y = .safeSampleBuf() + row * 8
        else do
            y = .safeSampleBuf() + 64 * 2 + (row & 7) * 8
        var c = .safeSampleBuf() + 64 * 4 + (row >> 1) * 8

        for #reverse [i] in 1 to .maxMcusPerRow
        {
            for [l] in 2
            {
                for var j = 0; j < 8; j += 2
                {
                    let cb = c[0]
                    let cr = c[64]
                    let rc = .crr[cr]
                    let gc = (.crg[cr] + .cbg[cb]) >> 16
                    let bc = .cbb[cb]
                    var yy = cast(s32) y[j]

                    d0[2] = clamp(yy + #wrap rc)
                    d0[1] = clamp(yy + #wrap gc)
                    d0[0] = clamp(yy + #wrap bc)

                    yy    = y[j + 1]
                    d0[5] = clamp(yy + #wrap rc)
                    d0[4] = clamp(yy + #wrap gc)
                    d0[3] = clamp(yy + #wrap bc)

                    yy    = y[j + 8]
                    d1[2] = clamp(yy + #wrap rc)
                    d1[1] = clamp(yy + #wrap gc)
                    d1[0] = clamp(yy + #wrap bc)

                    yy    = y[j + 8 + 1]
                    d1[5] = clamp(yy + #wrap rc)
                    d1[4] = clamp(yy + #wrap gc)
                    d1[3] = clamp(yy + #wrap bc)

                    d0 += 6
                    d1 += 6

                    c += 1
                }

                y += 64
            }

            y += 64 * 6 - 64 * 2
            c += 64 * 6 - 8
        }
    }
}

