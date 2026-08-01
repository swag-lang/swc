/*
    :LICENCE
    This code is based on the libspng library by Randy (https://libspng.org/)
    The original code has been modified for Swag
    See LICENCE.md for the corresponding licence.
*/

#global namespace Png

using Core, Core.Errors

impl Decoder
{
    func filterPaeth(left, up, upLeft: u8)->u8
    {
        let aa = cast(s16) left
        let bb = cast(s16) up
        let cc = cast(s16) upLeft
        let p  = aa + bb - cc
        let pa = Math.abs(cast(s16) (p - aa))
        let pb = Math.abs(cast(s16) (p - bb))
        let pc = Math.abs(cast(s16) (p - cc))
        if pa <= pb and pa <= pc do
            return left
        if pb <= pc do
            return up
        return upLeft
    }

    mtd expand8(width, height: u32, output: [*] u8)
    {
        let rowStrideIn  = .getStrideIn(width)
        let rowStrideOut = .inChannels * width

        var orgDest   = output
        let srcOffset = rowStrideOut - rowStrideIn

        // 1 bit => 8 bits
        if .header.bitDepth == 1
        {
            let mul = .paletteCount ? 1 : 255
            for height
            {
                var dest = orgDest
                orgDest += rowStrideOut
                var src = dest + srcOffset
                var k   = rowStrideOut
                while k >= 8
                {
                    let c = src[0]
                    dest[0] = cast #bit (u8) ((c >> 7) * mul)
                    dest[1] = cast #bit (u8) (((c >> 6) & 1) * mul)
                    dest[2] = cast #bit (u8) (((c >> 5) & 1) * mul)
                    dest[3] = cast #bit (u8) (((c >> 4) & 1) * mul)
                    dest[4] = cast #bit (u8) (((c >> 3) & 1) * mul)
                    dest[5] = cast #bit (u8) (((c >> 2) & 1) * mul)
                    dest[6] = cast #bit (u8) (((c >> 1) & 1) * mul)
                    dest[7] = cast #bit (u8) ((c & 1) * mul)
                    dest    += 8
                    src     += 1
                    k       -= 8
                }

                if k > 0
                {
                    let c = src[0]
                    dest[0] = cast #bit (u8) ((c >> 7) * mul)
                    if k > 1 do
                        dest[1] = cast #bit (u8) (((c >> 6) & 1) * mul)
                    if k > 2 do
                        dest[2] = cast #bit (u8) (((c >> 5) & 1) * mul)
                    if k > 3 do
                        dest[3] = cast #bit (u8) (((c >> 4) & 1) * mul)
                    if k > 4 do
                        dest[4] = cast #bit (u8) (((c >> 3) & 1) * mul)
                    if k > 5 do
                        dest[5] = cast #bit (u8) (((c >> 2) & 1) * mul)
                    if k > 6 do
                        dest[6] = cast #bit (u8) (((c >> 1) & 1) * mul)
                }
            }
        }

        // 2 bits => 8 bits
        elif .header.bitDepth == 2
        {
            let mul = .paletteCount ? 1 : 85
            for height
            {
                var dest = orgDest
                orgDest += rowStrideOut
                var src = dest + srcOffset
                var k   = rowStrideOut
                while k >= 2
                {
                    let c = src[0]
                    dest[0] = cast #bit (u8) ((c >> 6) * mul)
                    dest[1] = cast #bit (u8) (((c >> 4) & 3) * mul)
                    dest[2] = cast #bit (u8) (((c >> 2) & 3) * mul)
                    dest[3] = cast #bit (u8) ((c & 3) * mul)
                    dest    += 4
                    src     += 1
                    k       -= 4
                }

                if k > 0
                {
                    let c = src[0]
                    dest[0] = cast #bit (u8) ((c >> 6) * mul)
                    if k > 1 do
                        dest[1] = cast #bit (u8) (((c >> 4) & 3) * mul)
                    if k > 2 do
                        dest[2] = cast #bit (u8) (((c >> 2) & 3) * mul)
                }
            }
        }

        // 4 bits => 8 bits
        elif .header.bitDepth == 4
        {
            let mul = .paletteCount ? 1 : 17
            for height
            {
                var dest = orgDest
                orgDest += rowStrideOut
                var src = dest + srcOffset
                var k   = rowStrideOut
                while k >= 2
                {
                    let c = src[0]
                    dest[0] = cast #bit (u8) ((c >> 4) * mul)
                    dest[1] = cast #bit (u8) ((c & 15) * mul)
                    dest    += 2
                    src     += 1
                    k       -= 2
                }

                if k > 0
                {
                    dest[0] = cast #bit (u8) ((src[0] >> 4) * mul)
                }
            }
        }
    }

    mtd getStrideIn(width: u32)->u64
    {
        if .header.bitDepth < 8 do
            return cast(u64) ((.inChannels * width * .header.bitDepth) + 7) / 8
        return cast(u64) .inChannels * width * (.header.bitDepth / 8)
    }

    mtd defilter8(width, height: u32, input, output: [*] u8)
    {
        let rowStrideIn  = .getStrideIn(width)
        let rowStrideOut = .header.bitDepth < 8 ? cast(u64) .inChannels * width : rowStrideIn
        let destOffset   = rowStrideOut - rowStrideIn

        var src  = input
        var dest = output
        if !.orderDefilter do
            dest += rowStrideOut * (height - 1)

        // A temporary line "before" the first one, if filter needs one
        var tmpRow: Array'u8
        tmpRow.resize(rowStrideOut)
        let tmpRowBuffer = notnull tmpRow.buffer
        Memory.clear(tmpRowBuffer, rowStrideOut)
        var up = tmpRowBuffer

        // PNG filtering references the previous byte of the same pixel. Packed
        // samples (bit depths below 8) have an effective byte offset of 1, not
        // the number of channels; otherwise narrow Adam7 passes underflow here.
        let filterOffset = .header.bitDepth < 8 ? 1'u64 : cast(u64) .inChannels * (.header.bitDepth / 8)
        let nk           = rowStrideIn > filterOffset ? rowStrideIn - filterOffset : 0
        var row          = 0'u32
        while row < height
        {
            let filter = cast(RowFilter) src[0]
            src += 1

            var destOff = dest + destOffset
            switch filter
            {
            case .None:
                Memory.copy(destOff, src, rowStrideIn)

            case .Sub:
                var i = 0'u64
                while i < filterOffset
                {
                    destOff[i] = src[i]
                    i          += 1
                }

                var k = 0'u64
                while k < nk
                {
                    let idx = filterOffset + k
                    if idx >= rowStrideIn do
                        break
                    destOff[idx] = cast #bit (u8) (src[idx] + #wrap destOff[k])
                    k            += 1
                }

            case .Up:
                var k = 0'u64
                while k < rowStrideIn
                {
                    destOff[k] = cast #bit (u8) (src[k] + #wrap up[k])
                    k          += 1
                }

            case .Average:
                var i = 0'u64
                while i < filterOffset
                {
                    let avg = up[i] >> 1
                    destOff[i] = cast #bit (u8) (src[i] + #wrap avg)
                    i          += 1
                }

                var k = 0'u64
                while k < nk
                {
                    let idx = filterOffset + k
                    if idx >= rowStrideIn do
                        break
                    let avg = cast(u8) ((cast(u16) up[idx] + cast(u16) destOff[k]) >> 1)
                    destOff[idx] = cast #bit (u8) (src[idx] + #wrap avg)
                    k            += 1
                }

            case .Paeth:
                var i = 0'u64
                while i < filterOffset
                {
                    let paeth = cast(u32) filterPaeth(0, up[i], 0)
                    destOff[i] = cast #bit (u8) (src[i] + paeth)
                    i          += 1
                }

                var k = 0'u64
                while k < nk
                {
                    let idx = filterOffset + k
                    if idx >= rowStrideIn do
                        break
                    let paeth = cast(u32) filterPaeth(destOff[k], up[idx], up[k])
                    destOff[idx] = cast #bit (u8) (src[idx] + #wrap paeth)
                    k            += 1
                }
            }

            src += rowStrideIn
            up  = destOff
            if .orderDefilter do
                dest += rowStrideOut
            else do
                dest -= rowStrideOut
            row += 1
        }
    }

    mtd defilter(width, height: u32, input, output: [*] u8)
    {
        if .header.bitDepth < 8
        {
            .defilter8(width, height, input, output)
            .expand8(width, height, output)
            return
        }

        if .header.bitDepth == 8 or .header.bitDepth == 16
        {
            .defilter8(width, height, input, output)
            return
        }
    }

    mtd adam7()
    {
        var tmpArr: Array'u8
        var input = notnull .dcmpBuf.buffer
        for [p] in 7
        {
            let x = (.header.width - Adam7OrigX[p] + Adam7SpacingX[p] - 1) / Adam7SpacingX[p]
            let y = (.header.height - Adam7OrigY[p] + Adam7SpacingY[p] - 1) / Adam7SpacingY[p]
            if x <= 0 or y <= 0 do
                continue

            let pixelBytes = cast(u64) .inChannels * (.header.bitDepth == 16 ? 2 : 1)
            tmpArr.resize(cast(u64) (x * y) * pixelBytes)
            let tmpBuffer = notnull tmpArr.buffer
            Memory.clear(tmpBuffer, tmpArr.count)

            .defilter(cast(u32) x, cast(u32) y, input, tmpBuffer)

            var t = tmpBuffer
            for [j] in y
            {
                for [i] in x
                {
                    let out_y   = .header.height - ((j * Adam7SpacingY[p]) + Adam7OrigY[p]) - 1
                    let out_x   = (i * Adam7SpacingX[p]) + Adam7OrigX[p]
                    var out_off = out_y * .header.width * pixelBytes
                    out_off += out_x * pixelBytes
                    let dstPixels = .safeDstPixels()
                    for [z] in pixelBytes do
                        dstPixels[out_off + z] = t[z]
                    t += pixelBytes
                }
            }

            let stride = (.getStrideIn(cast(u32) x) + 1) * y
            input += stride
        }
    }

    mtd defilter()
    {
        if .header.interlaceMethod != .Adam7
        {
            .orderDefilter = false
            let input = notnull .dcmpBuf.buffer
            .defilter(.header.width, .header.height, input, .safeDstPixels())
        }
        else
        {
            .orderDefilter = true
            .adam7()
        }
    }
}
