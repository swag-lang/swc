//! Format: Portable Network Graphics (PNG) encoder component.
//! Supported: 8- or 16-bit grayscale and RGB images with optional alpha, PNG filters, Deflate compression, and optional Adam7 interlacing.
//! Not supported: APNG animation and palette generation.
//! Role: This file owns PNG scanline packing and Adam7 pass traversal.
//
// @LICENCE: BSD-2-Clause
// @ORIGIN: libspng, https://github.com/randy408/libspng
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#libspng

#global namespace Png

using Core, Core.Errors

impl Encoder
{
    mtd calculateScanlineWidth(width: u32)->u32 fail
    {
        if not width
        {
            fail UnsupportedFormatError{"SPNG_EINTERNAL"}
        }

        var res = cast(u64, .numChannels()) * .ihdr.bitDepth
        if res > Swag.U64.Max / width
        {
            fail UnsupportedFormatError{"SPNG_EOVERFLOW"}
        }

        res = res * width

        res += 15
        if res < 15
        {
            fail UnsupportedFormatError{"SPNG_EOVERFLOW"}
        }

        res /= 8
        if res > Swag.U32.Max
        {
            fail UnsupportedFormatError{"SPNG_EOVERFLOW"}
        }

        return cast(u32, res)
    }

    mtd numChannels()->s32
    {
        if .ihdr.colorType == .AlphaColor
        {
            return 4
        }

        if .ihdr.colorType == .Color
        {
            return 3
        }

        if .ihdr.colorType == .Alpha
        {
            return 2
        }

        return 1
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

        for i in 7
        {
            if .subimage[i].width == 0 or .subimage[i].height == 0
            {
                continue
            }

            .subimage[i].scanlineWidth = try .calculateScanlineWidth(.subimage[i].width)
            if .subimage[.widestPass].scanlineWidth < .subimage[i].scanlineWidth
            {
                .widestPass = i
            }

            .lastPass = i
        }
    }

    mtd finishIDat(deferHeader: bool) fail
    {
        var zlib: Compress.ZLib
        let cmp = try zlib.compress(.bufferToCompress.toSlice(), .userOptions.compressionLevel)

        if deferHeader
        {
            // Signature, 13-byte IHDR, and the framing of IHDR, IDAT, and IEND.
            const PngOverhead = #sizeof(PngSignature) + 13 + 3 * 12
            if cmp.count <= MaxPngChunkLength do
                .stream!.grow(cmp.count + PngOverhead)
            try .writeChunksBeforeIDat()
        }

        .writePtr = try .writeHeader(TypeIDat, cmp.count)
        Memory.copy(.writePtr, cmp.storage(), cmp.count)
        .bufferToCompress.count = 0

        .finishChunk()
    }

    mtd encodeRow(row: [*] u8)->bool fail
    {
        let pass = .rowInfo.pass

        if not .ihdr.interlaceMethod or pass == 6
        {
            return try .encodeScanLine(row)
        }

        let bitDepth = .ihdr.bitDepth
        if bitDepth < 8
        {
            let samplesPerByte = 8 / bitDepth
            let mask           = cast(u8, ((1 << bitDepth) - 1))
            let initialShift   = 8 - bitDepth
            var shiftAmount    = initialShift

            var scanline = unwrap .scanline
            Memory.clear(cast([*] u8, scanline), cast(u64, .subimage[pass].scanlineWidth))

            for k in .subimage[pass].width
            {
                let ioffset = Adam7StartX[pass] + k * Adam7DeltaX[pass]

                var sample = row[ioffset / samplesPerByte]
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

            return try .encodeScanLine(cast([*] u8, scanline))
        }

        let inputStep = Adam7DeltaX[pass] * .pixelSize
        var src       = row + Adam7StartX[pass] * .pixelSize
        var dst       = unwrap .scanline
        for .subimage[pass].width
        {
            if .encodeFlags.toBigEndian
            {
                let input  = cast(const [*] u16, src)
                let output = cast([*] u16, dst)
                for sample in .pixelSize / 2 do
                    output[sample] = Swag.byteSwap(input[sample])
            }
            else if .swapRB
            {
                dst[0] = src[2]
                dst[1] = src[1]
                dst[2] = src[0]
                if .pixelSize == 4
                {
                    dst[3] = src[3]
                }
            }
            else
            {
                Memory.copy(dst, src, .pixelSize)
            }

            src += inputStep
            dst += .pixelSize
        }

        return try .encodeScanLine(.scanline)
    }

    mtd encodeScanLine(sl: [*] u8)->bool fail
    {
        let pass = .rowInfo.pass

        let scanlineWidth = .subimage[pass].scanlineWidth
        if sl != .scanline
        {
            if .encodeFlags.toBigEndian
            {
                let scanline = unwrap .scanline
                for var i = 0; i < scanlineWidth - 1; i += 2
                {
                    scanline[i]     = sl[i + 1]
                    scanline[i + 1] = sl[i]
                }
            }
            else if .swapRB and .bytesPerPixel == 3
            {
                let scanline = unwrap .scanline
                for var i = 0; i < scanlineWidth - 1; i += 3
                {
                    scanline[i]     = sl[i + 2]
                    scanline[i + 1] = sl[i + 1]
                    scanline[i + 2] = sl[i]
                }
            }
            else if .swapRB and .bytesPerPixel == 4
            {
                // Swap R and B one whole 32-bit pixel at a time: a byte-wise swizzle
                // of a full-desktop capture costs seconds in unoptimized builds.
                let src   = cast(const [*] u32, sl)
                let dst   = cast([*] u32, unwrap .scanline)
                let count = (scanlineWidth - 1) / 4
                for i in count
                {
                    let v = src[i]
                    dst[i] = (v & 0xFF00FF00) | ((v & 0xFF) << 16) | ((v >> 16) & 0xFF)
                }
            }
            else
            {
                Memory.copy(unwrap .scanline, sl, cast(u64, scanlineWidth) - 1)
        }

        let requiresPrevious = .encodeFlags.filterChoice & (.Up | .Average | .Paeth)
        if not .rowInfo.scanlineIdx and requiresPrevious
        {
            Memory.clear(cast([*] u8, unwrap .prevScanline), cast(u64, scanlineWidth))
        }

        var filtered = cast([*] u8, unwrap .filteredScanline)
        let filter   = .getBestFilter(scanlineWidth - 1)
        if filter == .None
        {
            filtered = cast([*] u8, unwrap .scanline)
        }

        filtered    -= 1
        filtered[0] = cast(u8, filter)
        filtered    += 1

        if filter != .None
        {
            .filterScanline(filtered, scanlineWidth - 1, filter)
        }

        try .writeIDatBytes(filtered - 1, scanlineWidth)

        swap(&.prevScanline, &.scanline)
        return .updateRowInfo()
    }

    mtd updateRowInfo()->bool
    {
        let interlacing = .ihdr.interlaceMethod
        let ri          = &.rowInfo
        var sub         = .subimage

        if ri.scanlineIdx == sub[ri.pass].height - 1
        {
            if ri.pass == .lastPass
            {
                return true
            }

            ri.scanlineIdx = 0
            ri.pass        += 1

            while (not sub[ri.pass].width or not sub[ri.pass].height) and (ri.pass < .lastPass)
            {
                ri.pass += 1
            }
        }
        else
        {
            ri.rowNum      += 1
            ri.scanlineIdx += 1
        }

        if interlacing
        {
            ri.rowNum = Adam7StartY[ri.pass] + ri.scanlineIdx * Adam7DeltaY[ri.pass]
        }

        return false
    }
}
