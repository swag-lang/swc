#global private
using Swag

// A pointer stepped in place inside an unrolled inner loop, then used with a
// constant offset: the address peephole must not fold the step into the
// consumer's displacement, which reads the stepped pointer already. The shape
// is the chroma upsampling loop of the JPEG decoder, where the fold used to be
// applied once per optimization sweep until the loop gave up.

var Samples: [8 * 64] u8
var Out: [256] u8

func fillSamples()
{
    for i in 8 * 64 do
        Samples[i] = cast(u8) ((i * 13 + 5) & 0xFF)
}

#[Swag.Optimize(true)]
func upsample(dst: [*] u8, luma: const [*] u8, units: u64)
{
    var d = dst
    var y = luma
    var c = luma + 2 * 64
    for i in units
    {
        for l in 2
        {
            d[0] = y[0]
            d[1] = c[0]
            d[2] = y[8]
            d += 3
            c += 4
            y += 64
        }
        y += 64 * 4 - 64 * 2
        c += 64 * 4 - 8
    }
}

func referenceUpsample(dst: [*] u8, luma: const [*] u8, units: u64)
{
    var d: u64
    var y: u64
    var c: u64 = 2 * 64
    for i in units
    {
        for l in 2
        {
            dst[d]     = luma[y]
            dst[d + 1] = luma[c]
            dst[d + 2] = luma[y + 8]
            d += 3
            c += 4
            y += 64
        }
        y += 64 * 4 - 64 * 2
        c += 64 * 4 - 8
    }
}

#test
{
    fillSamples()
    var expected: [256] u8
    let luma = cast(const [*] u8) &Samples[0]
    upsample(&Out[0], luma, 2)
    referenceUpsample(&expected[0], luma, 2)
    for i in 12 do
        Swag.assert(Out[i] == expected[i])
}
