#global if #command == Swag.CompilerCommand.Test

using Core

// The defining sum of the inverse transform, evaluated term by term.
private func mdctDirect(spectrum: const [..] f32, output: [*] f64)
{
    let n    = spectrum.count * 2
    let half = spectrum.count
    for index in n
    {
        var sum = 0.0'f64
        for bin in half
        {
            let angle = 2.0 * Math.ConstF64.Pi / cast(f64) n * (cast(f64) index + 0.5 + cast(f64) n / 4.0) * (cast(f64) bin + 0.5)
            sum += cast(f64) spectrum[bin] * Math.cos(angle)
        }

        output[index] = sum
    }
}

// The folded transform agrees with the defining sum at every length a Vorbis block may take.
private func mdctAssertMatchesDefinition(n: u32)
{
    var random: Random.Generator
    random.seedU32(1234 + n)
    var spectrum: Array'f32
    spectrum.resize(n / 2)
    for index in n / 2 do
        spectrum[index] = cast(f32) (cast(f64) random.nextU32() / 4294967296.0 * 2.0 - 1.0)

    var direct: Array'f64
    direct.resize(n)
    mdctDirect(spectrum.toSlice(), direct.buffer!)

    var fast: Array'f32
    fast.resize(n)
    var transform = Mdct.create(n)
    transform.inverse(spectrum.buffer!, fast.buffer!)

    var worst = 0.0'f64
    var scale = 0.0'f64
    for index in n
    {
        worst = Math.max(worst, Math.abs(cast(f64) fast[index] - direct[index]))
        scale = Math.max(scale, Math.abs(direct[index]))
    }

    if worst > scale * 1e-4 do
        Swag.print("mdct ", n, ": worst ", worst, " against a scale of ", scale, "\n")
    Swag.assert(worst <= scale * 1e-4)
}

#test
{
    mdctAssertMatchesDefinition(64)
    mdctAssertMatchesDefinition(256)
    mdctAssertMatchesDefinition(2048)
}
