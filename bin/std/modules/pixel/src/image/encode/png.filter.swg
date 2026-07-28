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
    mtd getBestFilter(size: u32)->Filter
    {
        if .encodeFlags.filterChoice == .Disabled do
            return .None

        let chl = cast(s32) .encodeFlags.filterChoice
        if !(chl & (chl - 1))
        {
            for [i] in 5
            {
                if chl == 1 << (i + 3) do
                    return cast() i
            }
        }

        var bestFilter   = 0
        var bestScore    = Swag.S32.Max
        var filterScores = [Swag.S32.Max, Swag.S32.Max, Swag.S32.Max, Swag.S32.Max, Swag.S32.Max]

        var sum: s32
        for [i] in 5
        {
            let flag = 1 << (i + 3)
            if !(chl & flag) do
                continue

            sum             = .filterSum(size, cast(Filter) i)
            filterScores[i] = Math.abs(sum)
            if filterScores[i] < bestScore
            {
                bestScore  = filterScores[i]
                bestFilter = i
            }
        }

        return cast() bestFilter
    }

    func paeth(a, b, c: s32)->s32
    {
        let p  = cast(s16) (a + b - c)
        let pa = Math.abs(cast(s16) (p - a))
        let pb = Math.abs(cast(s16) (p - b))
        let pc = Math.abs(cast(s16) (p - c))

        if pa <= pb and pa <= pc do
            return a
        elif pb <= pc do
            return b
        return c
    }

    mtd filterSum(size: u32, filter: Filter)->s32
    {
        if size > Swag.S32.Max / 128 do
            return Swag.S32.Max

        var sum:     s32
        var a, b, c: s32

        let scanline     = notnull .scanline
        let prevScanline = notnull .prevScanline
        for [i] in size
        {
            if i >= .bytesPerPixel
            {
                a = scanline[i - .bytesPerPixel]
                b = prevScanline[i]
                c = prevScanline[i - .bytesPerPixel]
            }
            else
            {
                a = 0
                b = prevScanline[i]
                c = 0
            }

            var x = cast(s32) scanline[i]

            switch filter
            {
            case .None:
                break

            case .Sub:
                x = x - a

            case .Up:
                x = x - b

            case .Average:
                let avg = (a + b) / 2
                x = x - avg

            case .Paeth:
                x = x - paeth(a, b, c)
            }

            sum += 128 - Math.abs(x - 128)
        }

        return sum
    }

    mtd filterScanline(filtered: [*] u8, size: u32, filter: Filter)
    {
        let scanline     = notnull .scanline
        let prevScanline = notnull .prevScanline
        for [i] in size
        {
            var a, b, c: s32
            if i >= .bytesPerPixel
            {
                a = scanline[i - .bytesPerPixel]
                b = prevScanline[i]
                c = prevScanline[i - .bytesPerPixel]
            }
            else
            {
                a = 0
                b = prevScanline[i]
                c = 0
            }

            var x = cast(s32) scanline[i]

            switch filter
            {
            case .Sub:
                x = x - a

            case .Up:
                x = x - b

            case .Average:
                let avg = (a + b) / 2
                x = x - avg

            case .Paeth:
                x = x - paeth(a, b, c)
            }

            filtered[i] = cast #bit (u8) x
        }
    }
}

