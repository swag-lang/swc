//! Format: Forward and inverse modified discrete cosine transforms.
//! Supported: Power-of-two lengths from sixteen up, computed through a quarter-length complex FFT.
//! Not supported: The composite lengths a CELT frame uses.
//! Role: This file owns the lapped transform the transform codecs share and the tables it needs.
//
using Core, Core.Math

// One MDCT of a fixed length, holding the tables and bounded scratch it needs.
//
// The transform reconstructs `n` time samples from `n / 2` spectral coefficients as the sum
// `y[i] = Σ X[k] cos(2π / n · (i + 1/2 + n/4) · (k + 1/2))`, with no scale factor of its own: a
// codec applies its window and normalization afterwards. The sum is folded onto a complex FFT
// of `n / 4` points, so one block costs `O(n log n)` rather than the `O(n²)` of the definition.
struct Mdct
{
    n:          u32
    twiddleCos: Array'f32     // cos(2π (k + 1/8) / n), one entry per FFT point.
    twiddleSin: Array'f32     // sin(2π (k + 1/8) / n), one entry per FFT point.
    fftCos:     Array'f32     // Cosines packed in butterfly order for every FFT stage.
    fftSin:     Array'f32     // Sines packed in butterfly order for every FFT stage.
    reverse:    Array'u32     // Bit-reversed index of every FFT point.
    real:       Array'f32     // FFT scratch.
    imaginary:  Array'f32     // FFT scratch.
}

impl Mdct
{
    // Prepares a transform of `n` outputs, a power of two of at least sixteen.
    func create(n: u32)->Mdct
    {
        Swag.assert(n >= 16 and (n & (n - 1)) == 0)
        var result: #returntype
        result.n = n

        let m = n / 4
        result.twiddleCos.resize(m)
        result.twiddleSin.resize(m)
        for k in m
        {
            let angle = 2.0 * Math.ConstF64.Pi * (cast(f64, k) + 0.125) / cast(f64, n)
            result.twiddleCos[k] = cast(f32, Math.cos(angle))
            result.twiddleSin[k] = cast(f32, Math.sin(angle))
        }

        // Each stage holds one contiguous half-span of twiddles. Earlier stages select
        // every second, fourth, and later entry from the final stage.
        result.fftCos.resize(m - 1)
        result.fftSin.resize(m - 1)
        let finalStage = m / 2 - 1
        for j in m / 2
        {
            let angle = 2.0 * Math.ConstF64.Pi * cast(f64, j) / cast(f64, m)
            result.fftCos[finalStage + j] = cast(f32, Math.cos(angle))
            result.fftSin[finalStage + j] = cast(f32, Math.sin(angle))
        }

        var halfLength = 1'u32
        while halfLength < m / 2
        {
            let stride = (m / 2) / halfLength
            for j in halfLength
            {
                let source = finalStage + j * stride
                let target = halfLength - 1 + j
                result.fftCos[target] = result.fftCos[source]
                result.fftSin[target] = result.fftSin[source]
            }

            halfLength *= 2
        }

        var bits = 0'u32
        while (1'u32 << bits) < m do
            bits += 1
        result.reverse.resize(m)
        for k in m
        {
            var reversed = 0'u32
            for bit in bits where k & (1'u32 << bit) do
                reversed |= 1'u32 << (bits - 1 - bit)
            result.reverse[k] = reversed
        }

        result.real.resize(m)
        result.imaginary.resize(m)
        return result
    }

    // Writes the `n` samples the `n / 2` coefficients of `spectrum` reconstruct into `output`.
    mtd inverse(spectrum: const [*] f32, output: [*] f32)
    {
        let m    = .n / 4
        let half = .n / 2
        let re   = .real.storage()
        let im   = .imaginary.storage()

        // Pair the coefficients from both ends of the spectrum into complex points, rotate them
        // by an eighth-bin twiddle, and store them bit-reversed for the in-place FFT.
        let cos   = .twiddleCos.storage()
        let sin   = .twiddleSin.storage()
        let order = .reverse.storage()
        const Reverse = cast(Simd.U32x4, [3'u32, 2, 1, 0])

        #[Swag.Inline]
        func rotate(spectrum, cos, sin: const [*] f32, half, k: u32)->{re, im: Simd.F32x4}
        {
            let front  = spectrum + 2 * k
            let back   = spectrum + (half - 2 * k - 8)
            let front0 = cast #bit(Simd.U32x4, Simd.load(front))
            let front1 = cast #bit(Simd.U32x4, Simd.load(front + 4))
            let back0  = cast #bit(Simd.U32x4, Simd.load(back))
            let back1  = cast #bit(Simd.U32x4, Simd.load(back + 4))
            let first  = cast #bit(Simd.F32x4, Simd.deinterleaveEven(front0, front1))
            let second = Simd.permute(cast #bit(Simd.F32x4, Simd.deinterleaveOdd(back0, back1)), Reverse)
            let c      = Simd.load(cos + k)
            let s      = Simd.load(sin + k)
            return {first * c + second * s, second * c - first * s}
        }

        var k = 0'u32
        let fuseFirstStages = m >= 16
        if fuseFirstStages
        {
            #[Swag.Inline]
            func storeFourGroups(target: [*] f32, order: const [*] u32, a, b, c, d: Simd.F32x4)
            {
                let av     = cast #bit(Simd.U32x4, a)
                let bv     = cast #bit(Simd.U32x4, b)
                let cv     = cast #bit(Simd.U32x4, c)
                let dv     = cast #bit(Simd.U32x4, d)
                let abLow  = cast #bit(Simd.U64x2, Simd.interleaveLow(av, bv))
                let cdLow  = cast #bit(Simd.U64x2, Simd.interleaveLow(cv, dv))
                let abHigh = cast #bit(Simd.U64x2, Simd.interleaveHigh(av, bv))
                let cdHigh = cast #bit(Simd.U64x2, Simd.interleaveHigh(cv, dv))
                Simd.store(target + order[0], cast #bit(Simd.F32x4, Simd.interleaveLow(abLow, cdLow)))
                Simd.store(target + order[1], cast #bit(Simd.F32x4, Simd.interleaveHigh(abLow, cdLow)))
                Simd.store(target + order[2], cast #bit(Simd.F32x4, Simd.interleaveLow(abHigh, cdHigh)))
                Simd.store(target + order[3], cast #bit(Simd.F32x4, Simd.interleaveHigh(abHigh, cdHigh)))
            }

            // Bit reversal puts points from the four quarters into each group in
            // 0, 2, 1, 3 order. Rotate four groups at once, then transpose the SIMD
            // lanes after their first two butterfly stages.
            let span       = m / 4
            let quarterCos = .fftCos[2]
            let quarterSin = -.fftSin[2]
            let zero       = Simd.splat(0'f32)
            while k < span
            {
                let a        = rotate(spectrum, cos, sin, half, k)
                let b        = rotate(spectrum, cos, sin, half, k + 2 * span)
                let c        = rotate(spectrum, cos, sin, half, k + span)
                let d        = rotate(spectrum, cos, sin, half, k + 3 * span)
                let sumReal  = a.re + b.re
                let sumImag  = a.im + b.im
                let diffReal = a.re - b.re
                let diffImag = a.im - b.im

                let dcReal = c.re + d.re
                let dcImag = c.im + d.im
                let dcR    = dcReal - dcImag * zero
                let dcI    = dcReal * zero + dcImag
                let acReal = c.re - d.re
                let acImag = c.im - d.im
                let acR    = acReal * quarterCos - acImag * quarterSin
                let acI    = acReal * quarterSin + acImag * quarterCos
                storeFourGroups(re, order + k, sumReal + dcR, diffReal + acR, sumReal - dcR, diffReal - acR)
                storeFourGroups(im, order + k, sumImag + dcI, diffImag + acI, sumImag - dcI, diffImag - acI)
                k += 4
            }
        }
        else
        {
            while k < m
            {
                let rotated     = rotate(spectrum, cos, sin, half, k)
                let firstIndex  = order[k]
                let secondIndex = order[k + 1]
                let thirdIndex  = order[k + 2]
                let fourthIndex = order[k + 3]
                re[firstIndex]  = rotated.re[0]
                im[firstIndex]  = rotated.im[0]
                re[secondIndex] = rotated.re[1]
                im[secondIndex] = rotated.im[1]
                re[thirdIndex]  = rotated.re[2]
                im[thirdIndex]  = rotated.im[2]
                re[fourthIndex] = rotated.re[3]
                im[fourthIndex] = rotated.im[3]
                k += 4
            }
        }

        .fft(-1, not fuseFirstStages)

        let quarter = m / 2
        if quarter >= 4
        {
            // Unfold both rotations directly to the four quarters of the signal.
            #[Swag.Inline]
            func storePairs(target: [*] f32, even, odd: Simd.F32x4)
            {
                let first  = cast #bit(Simd.U32x4, even)
                let second = cast #bit(Simd.U32x4, odd)
                Simd.store(target, cast #bit(Simd.F32x4, Simd.interleaveLow(first, second)))
                Simd.store(target + 4, cast #bit(Simd.F32x4, Simd.interleaveHigh(first, second)))
            }

            k = 0
            while k < quarter
            {
                let low      = quarter - k - 4
                let high     = quarter + k
                let lowCos   = Simd.load(cos + low)
                let lowSin   = Simd.load(sin + low)
                let highCos  = Simd.load(cos + high)
                let highSin  = Simd.load(sin + high)
                let lowReal  = Simd.load(re + low)
                let lowImag  = Simd.load(im + low)
                let highReal = Simd.load(re + high)
                let highImag = Simd.load(im + high)
                let lowR     = lowReal * lowCos + lowImag * lowSin
                let lowI     = lowImag * lowCos - lowReal * lowSin
                let highR    = highReal * highCos + highImag * highSin
                let highI    = highImag * highCos - highReal * highSin
                let first    = 2 * k
                let second   = half - first - 8
                storePairs(output + first, highR, -Simd.permute(lowI, Reverse))
                storePairs(output + second, lowI, -Simd.permute(highR, Reverse))
                storePairs(output + half + first, highI, -Simd.permute(lowR, Reverse))
                storePairs(output + half + second, -lowR, Simd.permute(highI, Reverse))
                k += 4
            }

            return
        }

        // Rotate the FFT output by the same twiddle, then unfold its real and imaginary parts
        // onto the four quarters of the time signal.
        for k in m
        {
            let c = .twiddleCos[k]
            let s = .twiddleSin[k]
            let r = re[k] * c + im[k] * s
            let i = im[k] * c - re[k] * s
            re[k] = r
            im[k] = i
        }

        for k in quarter
        {
            output[2 * k]             = re[quarter + k]
            output[2 * k + 1]         = -im[quarter - 1 - k]
            output[m + 2 * k]         = im[k]
            output[m + 2 * k + 1]     = -re[m - 1 - k]
            output[2 * m + 2 * k]     = im[quarter + k]
            output[2 * m + 2 * k + 1] = -re[quarter - 1 - k]
            output[3 * m + 2 * k]     = -re[k]
            output[3 * m + 2 * k + 1] = im[m - 1 - k]
        }
    }

    // Writes `n / 2` spectral coefficients from `n` already-windowed input samples.
    //
    // This is the transpose of `inverse`, with no normalization. It computes the defining
    // cosine sum in O(n log n), using the same quarter-length FFT and rotations.
    mtd forward(input: const [*] f32, spectrum: [*] f32)
    {
        let m       = .n / 4
        let quarter = m / 2
        let re      = .real.storage()
        let im      = .imaginary.storage()
        for k in m do
            re[k], im[k] = 0
        for k in quarter
        {
            re[quarter + k]     += input[2 * k]
            im[quarter - 1 - k] -= input[2 * k + 1]
            im[k]               += input[m + 2 * k]
            re[m - 1 - k]       -= input[m + 2 * k + 1]
            im[quarter + k]     += input[2 * m + 2 * k]
            re[quarter - 1 - k] -= input[2 * m + 2 * k + 1]
            re[k]               -= input[3 * m + 2 * k]
            im[m - 1 - k]       += input[3 * m + 2 * k + 1]
        }

        for k in m
        {
            let c = .twiddleCos[k]
            let s = .twiddleSin[k]
            let r = re[k] * c - im[k] * s
            let i = im[k] * c + re[k] * s
            re[k] = r
            im[k] = i
        }

        for k in m
        {
            let other = .reverse[k]
            if other > k
            {
                let r = re[k]
                let i = im[k]
                re[k]     = re[other]
                im[k]     = im[other]
                re[other] = r
                im[other] = i
            }
        }

        .fft(1)
        for k in m
        {
            let c = .twiddleCos[k]
            let s = .twiddleSin[k]
            spectrum[2 * k] = re[k] * c - im[k] * s
            spectrum[.n / 2 - 1 - 2 * k] = im[k] * c + re[k] * s
        }
    }

    private mtd fft(sign: f32, firstStages = true)
    {
        let m   = .n / 4
        let re  = .real.storage()
        let im  = .imaginary.storage()
        let cos = .fftCos.storage()
        let sin = .fftSin.storage()

        if firstStages
        {
            // Fuse the first two stages inside each four-point group.
            const Even       = cast(Simd.U32x4, [0'u32, 0, 2, 2])
            const Odd        = cast(Simd.U32x4, [1'u32, 1, 3, 3])
            const LowPair    = cast(Simd.U32x4, [0'u32, 1, 0, 1])
            const HighPair   = cast(Simd.U32x4, [2'u32, 3, 2, 3])
            const NegateOdd  = cast(Simd.U32x4, [0'u32, 0x8000_0000, 0, 0x8000_0000])
            const NegateHigh = cast(Simd.U32x4, [0'u32, 0, 0x8000_0000, 0x8000_0000])
            let quarterCos = cos[2]
            let quarterSin = sign * sin[2]
            let wr         = cast(Simd.F32x4, [1'f32, quarterCos, 1, quarterCos])
            let wi         = cast(Simd.F32x4, [0'f32, quarterSin, 0, quarterSin])
            var point      = 0'u32
            while point < m
            {
                let real      = Simd.load(re + point)
                let imag      = Simd.load(im + point)
                let oddReal   = cast #bit(Simd.F32x4, cast #bit(Simd.U32x4, Simd.permute(real, Odd)) ^ NegateOdd)
                let oddImag   = cast #bit(Simd.F32x4, cast #bit(Simd.U32x4, Simd.permute(imag, Odd)) ^ NegateOdd)
                let firstReal = Simd.permute(real, Even) + oddReal
                let firstImag = Simd.permute(imag, Even) + oddImag
                let br        = Simd.permute(firstReal, HighPair)
                let bi        = Simd.permute(firstImag, HighPair)
                let tr        = cast #bit(Simd.F32x4, cast #bit(Simd.U32x4, br * wr - bi * wi) ^ NegateHigh)
                let ti        = cast #bit(Simd.F32x4, cast #bit(Simd.U32x4, br * wi + bi * wr) ^ NegateHigh)
                Simd.store(re + point, Simd.permute(firstReal, LowPair) + tr)
                Simd.store(im + point, Simd.permute(firstImag, LowPair) + ti)
                point += 4
            }
        }

        // Later stages pair contiguous spans. Four butterflies use the same arithmetic
        // as above, with four adjacent samples and twiddles in each vector.
        var halfLength = 4'u32
        while halfLength < m
        {
            let length = 2 * halfLength
            let offset = halfLength - 1
            var start  = 0'u32
            while start < m
            {
                var j = 0'u32
                while j < halfLength
                {
                    let wr = Simd.load(cos + offset + j)
                    let wi = Simd.load(sin + offset + j) * sign
                    let a  = start + j
                    let b  = a + halfLength
                    let ar = Simd.load(re + a)
                    let ai = Simd.load(im + a)
                    let br = Simd.load(re + b)
                    let bi = Simd.load(im + b)
                    let tr = br * wr - bi * wi
                    let ti = br * wi + bi * wr
                    Simd.store(re + b, ar - tr)
                    Simd.store(im + b, ai - ti)
                    Simd.store(re + a, ar + tr)
                    Simd.store(im + a, ai + ti)
                    j += 4
                }

                start += length
            }

            halfLength = length
        }
    }
}
