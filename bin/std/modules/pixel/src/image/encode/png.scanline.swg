/*
    :LICENCE
    This code is based on the libspng library by Randy (https://libspng.org/)
    The original code has been modified for Swag
    See LICENCE.md for the corresponding licence.
*/

#global namespace Png

using Core, Core.Errors

impl Encoder
{
    mtd calculateScanlineWidth(width: u32)->u32 fail
    {
        if !width do
            fail UnsupportedFormatError{"SPNG_EINTERNAL"}

        var res = cast(u64) .numChannels() * .ihdr.bitDepth
        if res > Swag.U64.Max / width do
            fail UnsupportedFormatError{"SPNG_EOVERFLOW"}
        res = res * width

        res += 15
        if res < 15 do
            fail UnsupportedFormatError{"SPNG_EOVERFLOW"}
        res /= 8
        if res > Swag.U32.Max do
            fail UnsupportedFormatError{"SPNG_EOVERFLOW"}

        return cast(u32) res
    }

    mtd numChannels()->s32
    {
        switch .ihdr.colorType
        {
        case .Color:      return 3
        case .AlphaColor: return 4
        }

        return 0
    }

    mtd calculateSubImages() fail
    {
        if .ihdr.interlaceMethod == 1
        {
            .subimage[0].width  = (.ihdr.width + 7) >> 3
            .subimage[0].height = (.ihdr.height + 7) >> 3
            .subimage[1].width  = (.ihdr.width + 3) >> 3
            .subimage[1].height = (.ihdr.height + 7) >> 3
            .subimage[2].width  = (.ihdr.width + 3) >> 2
            .subimage[2].height = (.ihdr.height + 3) >> 3
            .subimage[3].width  = (.ihdr.width + 1) >> 2
            .subimage[3].height = (.ihdr.height + 3) >> 2
            .subimage[4].width  = (.ihdr.width + 1) >> 1
            .subimage[4].height = (.ihdr.height + 1) >> 2
            .subimage[5].width  = .ihdr.width >> 1
            .subimage[5].height = (.ihdr.height + 1) >> 1
            .subimage[6].width  = .ihdr.width
            .subimage[6].height = .ihdr.height >> 1
        }
        else
        {
            .subimage[0].width  = .ihdr.width
            .subimage[0].height = .ihdr.height
        }

        for [i] in 7
        {
            if .subimage[i].width == 0 or .subimage[i].height == 0 do
                continue

            .subimage[i].scanlineWidth = .calculateScanlineWidth(.subimage[i].width)
            if .subimage[.widestPass].scanlineWidth < .subimage[i].scanlineWidth do
                .widestPass = i
            .lastPass = i
        }
    }

    mtd finishIDat() fail
    {
        var zlib: Compress.ZLib
        let cmp = zlib.compress(.bufferToCompress.toSlice(), .userOptions.compressionLevel)

        .writePtr = .writeHeader(TypeIDat, cmp.count)
        Memory.copy(.writePtr, cmp.buffer, cmp.count)
        .bufferToCompress.count = 0

        .finishChunk()
    }

    mtd writeIDatBytes(sl: [*] u8, len: u32) fail
    {
        .bufferToCompress.add(@mkslice(sl, len))
    }

    mtd encodeRow(row: [*] u8)->bool fail
    {
        let pass = .rowInfo.pass

        if !.ihdr.interlaceMethod or pass == 6 do
            return .encodeScanLine(row)

        let bitDepth = .ihdr.bitDepth
        if bitDepth < 8
        {
            let samplesPerByte = 8 / bitDepth
            let mask           = cast(u8) ((1 << bitDepth) - 1)
            let initialShift   = 8 - bitDepth
            var shiftAmount    = initialShift

            let row_uc   = row
            var scanline = notnull .scanline
            Memory.clear(cast([*] u8) scanline, cast(u64) .subimage[pass].scanlineWidth)

            for [k] in .subimage[pass].width
            {
                let ioffset = Adam7StartX[pass] + k * Adam7DeltaX[pass]

                var sample = row_uc[ioffset / samplesPerByte]
                sample = sample >> (initialShift - ioffset * bitDepth % 8)
                sample = sample & mask
                sample = sample << shiftAmount

                scanline[0] |= sample

                shiftAmount -= bitDepth

                if shiftAmount > 7
                {
                    shiftAmount = initialShift
                    scanline    += 1
                    .scanline   += 1
                }
            }

            return .encodeScanLine(cast([*] u8) scanline)
        }

        for [k] in .subimage[pass].width
        {
            let ioffset = (Adam7StartX[pass] + k * Adam7DeltaX[pass]) * .pixelSize
            let src     = row + ioffset
            let dst     = (notnull .scanline) + k * .pixelSize
            if .swapRB
            {
                dst[0] = src[2]
                dst[1] = src[1]
                dst[2] = src[0]
                if .pixelSize == 4 do
                    dst[3] = src[3]
            }
            else
            {
                Memory.copy(dst, src, .pixelSize)
            }
        }

        return .encodeScanLine(cast([*] u8) (notnull .scanline))
    }

    mtd encodeScanLine(sl: [*] u8)->bool fail
    {
        let pass = .rowInfo.pass

        let scanlineWidth = .subimage[pass].scanlineWidth
        if sl != .scanline
        {
            if .swapRB and .bytesPerPixel == 3
            {
                let scanline = notnull .scanline
                for var i = 0; i < scanlineWidth - 1; i += 3
                {
                    scanline[i]     = sl[i + 2]
                    scanline[i + 1] = sl[i + 1]
                    scanline[i + 2] = sl[i]
                }
            }
            elif .swapRB and .bytesPerPixel == 4
            {
                // Swap R and B one whole 32-bit pixel at a time: a byte-wise swizzle
                // of a full-desktop capture costs seconds in unoptimized builds.
                let src   = cast(const [*] u32) sl
                let dst   = cast([*] u32) (notnull .scanline)
                let count = (scanlineWidth - 1) / 4
                for [i] in count
                {
                    let v = src[i]
                    dst[i] = (v & 0xFF00FF00) | ((v & 0xFF) << 16) | ((v >> 16) & 0xFF)
                }
            }
            else
            {
                Memory.copy(.scanline, sl, cast(u64) scanlineWidth - 1)
            }
        }

        let requiresPrevious = .encodeFlags.filterChoice & (.Up | .Average | .Paeth)
        if !.rowInfo.scanlineIdx and requiresPrevious do
            Memory.clear(cast([*] u8) (notnull .prevScanline), cast(u64) scanlineWidth)

        var filtered_sl = cast([*] u8) (notnull .filteredScanline)
        let filter      = .getBestFilter(scanlineWidth - 1)
        if filter == .None do
            filtered_sl = cast([*] u8) (notnull .scanline)
        filtered_sl    -= 1
        filtered_sl[0] = cast(u8) filter
        filtered_sl    += 1

        if filter != .None do
            .filterScanline(filtered_sl, scanlineWidth - 1, filter)

        .writeIDatBytes(filtered_sl - 1, scanlineWidth)

        swap(&.prevScanline, &.scanline)
        if .updateRowInfo()
        {
            .finishIDat()
            return true
        }

        return false
    }

    mtd updateRowInfo()->bool
    {
        let interlacing = .ihdr.interlaceMethod
        let ri          = &.rowInfo
        var sub         = .subimage

        if ri.scanlineIdx == sub[ri.pass].height - 1
        {
            if ri.pass == .lastPass do
                return true

            ri.scanlineIdx = 0
            ri.pass        += 1

            while (!sub[ri.pass].width or !sub[ri.pass].height) and (ri.pass < .lastPass) do
                ri.pass += 1
        }
        else
        {
            ri.rowNum      += 1
            ri.scanlineIdx += 1
        }

        if interlacing do
            ri.rowNum = Adam7StartY[ri.pass] + ri.scanlineIdx * Adam7DeltaY[ri.pass]

        return false
    }
}
