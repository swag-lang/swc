#global namespace Jpg

using Core

impl Encoder
{
    mtd loadFromRGB(xpos: u16, ypos: u16)
    {
        var pos      = 0
        var location = cast(s32) ypos * .imageX + xpos
        let pdst     = .bufferRGB.buffer!

        for y in 8
        {
            for x in 8
            {
                let r = pdst[location].r
                let g = pdst[location].g
                let b = pdst[location].b
                .duY[pos]  = cast(s8) (((TabYR[r] + TabYG[g] + TabYB[b]) >> 16) - 128)
                .duCb[pos] = cast(s8) ((TabCbR[r] + TabCbG[g] + TabCbB[b]) >> 16)
                .duCr[pos] = cast(s8) ((TabCrR[r] + TabCrG[g] + TabCrB[b]) >> 16)
                location   += 1
                pos        += 1
            }

            location += .imageX - 8
        }
    }

    func quantization(data: [*] s8, fdtbl: [*] f32, outData: [*] s16)
    {
        var dataFloat: [64] f32
        for i in 64 do
            dataFloat[i] = data[i]

        var dataptr = cast([*] f32) &dataFloat[0]
        for ctr in rangeTo(0, 7).reversed()
        {
            let tmp0 = dataptr[0] + dataptr[7]
            let tmp7 = dataptr[0] - dataptr[7]
            let tmp1 = dataptr[1] + dataptr[6]
            let tmp6 = dataptr[1] - dataptr[6]
            let tmp2 = dataptr[2] + dataptr[5]
            let tmp5 = dataptr[2] - dataptr[5]
            let tmp3 = dataptr[3] + dataptr[4]
            let tmp4 = dataptr[3] - dataptr[4]

            var tmp10 = tmp0 + tmp3
            let tmp13 = tmp0 - tmp3
            var tmp11 = tmp1 + tmp2
            var tmp12 = tmp1 - tmp2

            dataptr[0] = tmp10 + tmp11
            dataptr[4] = tmp10 - tmp11

            let z1 = (tmp12 + tmp13) * 0.707106781
            dataptr[2] = tmp13 + z1
            dataptr[6] = tmp13 - z1

            tmp10 = tmp4 + tmp5
            tmp11 = tmp5 + tmp6
            tmp12 = tmp6 + tmp7

            let z5 = (tmp10 - tmp12) * 0.382683433
            let z2 = 0.541196100 * tmp10 + z5
            let z4 = 1.306562965 * tmp12 + z5
            let z3 = tmp11 * 0.707106781

            let z11 = tmp7 + z3
            let z13 = tmp7 - z3

            dataptr[5] = z13 + z2
            dataptr[3] = z13 - z2
            dataptr[1] = z11 + z4
            dataptr[7] = z11 - z4

            dataptr += 8
        }

        dataptr = &dataFloat[0]

        for ctr in rangeTo(0, 7).reversed()
        {
            let tmp0 = dataptr[0] + dataptr[56]
            let tmp7 = dataptr[0] - dataptr[56]
            let tmp1 = dataptr[8] + dataptr[48]
            let tmp6 = dataptr[8] - dataptr[48]
            let tmp2 = dataptr[16] + dataptr[40]
            let tmp5 = dataptr[16] - dataptr[40]
            let tmp3 = dataptr[24] + dataptr[32]
            let tmp4 = dataptr[24] - dataptr[32]

            var tmp10 = tmp0 + tmp3
            let tmp13 = tmp0 - tmp3
            var tmp11 = tmp1 + tmp2
            var tmp12 = tmp1 - tmp2

            dataptr[0]  = tmp10 + tmp11
            dataptr[32] = tmp10 - tmp11

            let z1 = (tmp12 + tmp13) * 0.707106781
            dataptr[16] = tmp13 + z1
            dataptr[48] = tmp13 - z1

            tmp10 = tmp4 + tmp5
            tmp11 = tmp5 + tmp6
            tmp12 = tmp6 + tmp7

            let z5 = (tmp10 - tmp12) * 0.382683433
            let z2 = 0.541196100 * tmp10 + z5
            let z4 = 1.306562965 * tmp12 + z5
            let z3 = tmp11 * 0.707106781

            let z11 = tmp7 + z3
            let z13 = tmp7 - z3

            dataptr[40] = z13 + z2
            dataptr[24] = z13 - z2
            dataptr[8]  = z11 + z4
            dataptr[56] = z11 - z4

            dataptr += 1
        }

        for i in 64
        {
            let temp = dataFloat[i] * fdtbl[i]
            outData[i] = cast(s16) (cast(s16) (temp + 16384.5) - 16384)
        }
    }

    mtd processDU(componentDU: [*] s8, fdtbl: [*] f32, dC: *s16, hTDC, hTAC: [*] BitString)
    {
        let eob       = hTAC[0x00]
        let m16Zeroes = hTAC[0xF0]

        quantization(componentDU, fdtbl, .duDct)

        for i in 64 do
            .du[ZigZag[i]] = .duDct[i]
        let diff = .du[0] - dC[]
        dC[] = .du[0]

        if diff == 0 do
            .writeBits(hTDC[0])
        else
        {
            let diffc    = cast #bit (u64) cast(s64) diff     // If negative
            let category = .category!
            let bitcode  = .bitcode!
            .writeBits(hTDC[category[diffc]])
            .writeBits(bitcode[diffc])
        }

        var end0pos = 63
        while (end0pos > 0) and (.du[end0pos] == 0) do
            end0pos -= 1

        if end0pos == 0
        {
            .writeBits(eob)
            return
        }

        var i = 1
        while i <= end0pos
        {
            let startpos = i
            while (i <= end0pos) and (.du[i] == 0) do
                i += 1
            var nrzeroes = i - startpos
            if nrzeroes >= 16
            {
                for nrmarker in 1 to nrzeroes / 16 do
                    .writeBits(m16Zeroes)
                nrzeroes = nrzeroes % 16
            }

            let offc     = cast #bit (u64) cast(s64) .du[i]     // If negative
            let category = .category!
            let bitcode  = .bitcode!
            .writeBits(hTAC[nrzeroes * 16 + category[offc]])
            .writeBits(bitcode[offc])
            i += 1
        }

        if end0pos != 63 do
            .writeBits(eob)
    }
}
