#global namespace Dts

using Core.Math

private struct SynthesisRotations
{
    cosine:    [16] f64
    sine:      [16] f64
    fftCosine: [8] f64
    fftSine:   [8] f64
}

private const Rotations = #run buildSynthesisRotations()

private func buildSynthesisRotations()->SynthesisRotations
{
    var result: #returntype
    for index in 16
    {
        let angle = ConstF64.Pi * (cast(f64, index) + 0.125) / 32.0
        result.cosine[index] = cos(angle)
        result.sine[index]   = sin(angle)
    }

    for index in 8
    {
        let angle = -2.0 * ConstF64.Pi * cast(f64, index) / 16.0
        result.fftCosine[index] = cos(angle)
        result.fftSine[index]   = sin(angle)
    }

    return result
}

// The synthesis matrix is a 32-point DCT-IV scaled by 1/4. Pairing even coefficients with
// reversed odd coefficients folds it into a 16-point complex FFT. The eighth-bin rotation
// before and after the FFT provides the half-sample offsets of the DCT-IV. Packed lanes
// keep separate transforms for consecutive blocks, with the same order of operations.
func(T) synthesisDct(bands: const [*] T, stride: u64, output: *[32] T)
{
    const BitReverse: [16] u32 = [0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15]
    var real, imaginary: [16] T
    for index in 16
    {
        let even     = bands[2 * index * stride]
        let odd      = bands[(31 - 2 * index) * stride]
        let cosine   = Rotations.cosine[index]
        let sine     = Rotations.sine[index]
        let reversed = BitReverse[index]
        real[reversed]      = even * cosine + odd * sine
        imaginary[reversed] = odd * cosine - even * sine
    }

    fftStage'(T, 1)(&real, &imaginary)
    fftStage'(T, 2)(&real, &imaginary)
    fftStage'(T, 4)(&real, &imaginary)
    fftStage'(T, 8)(&real, &imaginary)

    for index in 16
    {
        let cosine = Rotations.cosine[index]
        let sine   = Rotations.sine[index]
        output[][2 * index]      = (real[index] * cosine + imaginary[index] * sine) * 0.25
        output[][31 - 2 * index] = (real[index] * sine - imaginary[index] * cosine) * 0.25
    }
}

private func(T, Half: u32) fftStage(real, imaginary: *[16] T)
{
    const Step = 8 / Half
    for group in Step
    {
        let start = group * 2 * Half
        for index in Half
        {
            let cosine    = Rotations.fftCosine[index * Step]
            let sine      = Rotations.fftSine[index * Step]
            let first     = start + index
            let second    = first + Half
            let rightReal = real[][second] * cosine - imaginary[][second] * sine
            let rightImag = real[][second] * sine + imaginary[][second] * cosine
            real[][second]      = real[][first] - rightReal
            imaginary[][second] = imaginary[][first] - rightImag
            real[][first]       += rightReal
            imaginary[][first]  += rightImag
        }
    }
}

// Both filter halves use the same history vector after reversing the second half.
private func buildPackedFilter(coefficients: const [..] f64)->[BandFirPerfect.count] f32
{
    var result: #returntype
    for phase in BandFirPerfect.count / 32
    {
        let offset = phase * 32
        for index in 16
        {
            result[offset + index]      = cast(f32, coefficients[offset + index])
            result[offset + 16 + index] = cast(f32, coefficients[offset + 31 - index])
        }
    }

    return result
}

private const PackedPerfectFilter    = #run buildPackedFilter(BandFirPerfect)
private const PackedNonPerfectFilter = #run buildPackedFilter(BandFirNonPerfect)

#[Swag.Inline]
private func pcmLanes(samples: Simd.F32x4)->Simd.S32x4
{
    let scaled = samples * (1.0'f32 / 256.0)
    let biased = scaled + Math.copysign(Simd.splat(0.5'f32), scaled)
    return Simd.truncateToS32(Math.clamp(biased, Simd.splat(-32_768.0'f32), Simd.splat(32_767.0'f32)))
}

#[Swag.Inline]
private func writePcmLanes(output: [*] s16, stride, index: u32, first, second: Simd.F32x4)
{
    let front = pcmLanes(first)
    let rear  = pcmLanes(second)
    for lane in 4
    {
        output[(index + lane) * stride]      = cast(s16, front[lane])
        output[(31 - index - lane) * stride] = cast(s16, rear[lane])
    }
}

func synthesisFilter(perfect: bool)->const [*] f32
{
    let coefficients: const [..] f32 = perfect ? PackedPerfectFilter : PackedNonPerfectFilter
    return coefficients.buffer
}

// Accumulate eight independent lane groups over the difference history and then the
// sum history. This keeps the coefficient walks contiguous and hides add latency.
#[Swag.Inline]
func synthesisFir(history, filter: const [*] f32, output: [*] s16, stride: u32)
{
    var first0, first1, first2, first3:     Simd.F32x4
    var second0, second1, second2, second3: Simd.F32x4
    for half in 2
    {
        let historyHalf = history + half * 48
        let filterHalf  = filter + half * 32
        for phase in 8
        {
            let tap      = phase * 64
            let samples0 = Simd.load(historyHalf + tap)
            let samples1 = Simd.load(historyHalf + tap + 4)
            let samples2 = Simd.load(historyHalf + tap + 8)
            let samples3 = Simd.load(historyHalf + tap + 12)
            first0  += samples0 * Simd.load(filterHalf + tap)
            first1  += samples1 * Simd.load(filterHalf + tap + 4)
            first2  += samples2 * Simd.load(filterHalf + tap + 8)
            first3  += samples3 * Simd.load(filterHalf + tap + 12)
            second0 += samples0 * Simd.load(filterHalf + tap + 16)
            second1 += samples1 * Simd.load(filterHalf + tap + 20)
            second2 += samples2 * Simd.load(filterHalf + tap + 24)
            second3 += samples3 * Simd.load(filterHalf + tap + 28)
        }
    }

    writePcmLanes(output, stride, 0, first0, second0)
    writePcmLanes(output, stride, 4, first1, second1)
    writePcmLanes(output, stride, 8, first2, second2)
    writePcmLanes(output, stride, 12, first3, second3)
}
