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
    fftCos:     Array'f32     // cos(2π j / m) for the first half of the FFT circle.
    fftSin:     Array'f32     // sin(2π j / m) for the first half of the FFT circle.
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

        result.fftCos.resize(m / 2)
        result.fftSin.resize(m / 2)
        for j in m / 2
        {
            let angle = 2.0 * Math.ConstF64.Pi * cast(f64, j) / cast(f64, m)
            result.fftCos[j] = cast(f32, Math.cos(angle))
            result.fftSin[j] = cast(f32, Math.sin(angle))
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
        for k in m
        {
            let first  = spectrum[2 * k]
            let second = spectrum[half - 1 - 2 * k]
            let c      = .twiddleCos[k]
            let s      = .twiddleSin[k]
            let index  = .reverse[k]
            re[index] = first * c + second * s
            im[index] = second * c - first * s
        }

        .fft(-1)

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

        let quarter = m / 2
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

    private mtd fft(sign: f32)
    {
        let m      = .n / 4
        let re     = .real.storage()
        let im     = .imaginary.storage()
        var length = 2'u32
        while length <= m
        {
            let halfLength = length / 2
            let stride     = m / length
            var start      = 0'u32
            while start < m
            {
                for j in halfLength
                {
                    let wr = .fftCos[j * stride]
                    let wi = sign * .fftSin[j * stride]
                    let a  = start + j
                    let b  = a + halfLength
                    let tr = re[b] * wr - im[b] * wi
                    let ti = re[b] * wi + im[b] * wr
                    re[b] = re[a] - tr
                    im[b] = im[a] - ti
                    re[a] += tr
                    im[a] += ti
                }

                start += length
            }

            length *= 2
        }
    }
}
