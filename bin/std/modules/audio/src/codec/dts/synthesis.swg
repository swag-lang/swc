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
// before and after the FFT provides the half-sample offsets of the DCT-IV.
func synthesisDct(bands: const [*] f64, stride: u64, output: *[32] f64)
{
    const BitReverse: [16] u32 = [0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15]
    var real, imaginary: [16] f64
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

    for half in [1'u32, 2, 4, 8]
    {
        let step = 8 / half
        for group in step
        {
            let start = group * 2 * half
            for index in half
            {
                let cosine    = Rotations.fftCosine[index * step]
                let sine      = Rotations.fftSine[index * step]
                let first     = start + index
                let second    = first + half
                let rightReal = real[second] * cosine - imaginary[second] * sine
                let rightImag = real[second] * sine + imaginary[second] * cosine
                real[second]      = real[first] - rightReal
                imaginary[second] = imaginary[first] - rightImag
                real[first]       += rightReal
                imaginary[first]  += rightImag
            }
        }
    }

    for index in 16
    {
        let cosine = Rotations.cosine[index]
        let sine   = Rotations.sine[index]
        output[][2 * index]      = (real[index] * cosine + imaginary[index] * sine) * 0.25
        output[][31 - 2 * index] = (real[index] * sine - imaginary[index] * cosine) * 0.25
    }
}
