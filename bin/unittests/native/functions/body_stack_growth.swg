#global private

struct ImdctStackProbe
{
    size:    s32
    quarter: s32
    reverse: [512] s32
    fftReal: [512] f64
    fftImag: [512] f64
    twReal:  [512] f64
    twImag:  [512] f64
}

impl ImdctStackProbe
{
    #[Swag.NoInline]
    mtd const run(spectrum: const [*] f64, output: [*] f64)
    {
        let half    = .size / 2
        let quarter = .quarter
        var real: [512] f64
        var imag: [512] f64
        for k in cast(u64, quarter)
        {
            let a = spectrum[2 * k] * 0.5
            let b = -spectrum[cast(u64, half) - 1 - 2 * k] * 0.5
            real[k] = a * .twReal[k] + b * .twImag[k]
            imag[k] = -a * .twImag[k] + b * .twReal[k]
        }

        for i in cast(u64, quarter)
        {
            let reversed = cast(u64, .reverse[i])
            if reversed > i
            {
                let savedReal = real[i]
                let savedImag = imag[i]
                real[i]        = real[reversed]
                imag[i]        = imag[reversed]
                real[reversed] = savedReal
                imag[reversed] = savedImag
            }
        }

        var length = 2's32
        while length <= quarter
        {
            let butterfly = length >> 1
            let stride    = quarter / length
            var base      = 0's32
            while base < quarter
            {
                for j in cast(u64, butterfly)
                {
                    let a  = cast(u64, base) + j
                    let b  = a + cast(u64, butterfly)
                    let tw = j * cast(u64, stride)
                    let xr = real[b] * .fftReal[tw] - imag[b] * .fftImag[tw]
                    let xi = real[b] * .fftImag[tw] + imag[b] * .fftReal[tw]
                    real[b] = real[a] - xr
                    imag[b] = imag[a] - xi
                    real[a] += xr
                    imag[a] += xi
                }

                base += length
            }

            length <<= 1
        }

        var folded: [1024] f64
        let inverse = 2.0 / cast(f64, quarter)
        for i in cast(u64, quarter)
        {
            let realValue = real[i] * inverse
            let imagValue = imag[i] * inverse
            folded[2 * i] = realValue * .twReal[i] + imagValue * .twImag[i]
            folded[cast(u64, half) - 1 - 2 * i] = -realValue * .twImag[i] + imagValue * .twReal[i]
        }

        for i in cast(u64, quarter)
        {
            let b = folded[cast(u64, quarter) + i] * 0.5
            let a = -folded[i] * 0.5
            output[i] = b
            output[cast(u64, (2 * quarter)) - 1 - i] = -b
            output[cast(u64, (3 * quarter)) + i]     = a
            output[cast(u64, (3 * quarter)) - 1 - i] = a
        }
    }
}

private var g_ImdctStackProbe: ImdctStackProbe

func initImdctStackProbe()
{
    g_ImdctStackProbe.size    = 1024
    g_ImdctStackProbe.quarter = 256
    for i in 256
    {
        g_ImdctStackProbe.reverse[i] = cast(s32, i)
        g_ImdctStackProbe.fftReal[i] = 1.0
        g_ImdctStackProbe.fftImag[i] = 0.0
        g_ImdctStackProbe.twReal[i]  = 1.0
        g_ImdctStackProbe.twImag[i]  = 0.0
    }
}

#[Swag.NoInline]
func runNearStackGuard()->u64
{
    var padding: [32768] u64
    for i in padding.count do padding[i] = cast(u64, i)

    var spectrum: [1024] f64
    var output:   [1024] f64
    g_ImdctStackProbe.run(spectrum, output)
    return padding[0] + padding[padding.count - 1] + cast(u64, output[0])
}

#test
{
    initImdctStackProbe()
    Swag.assert(runNearStackGuard() == 32767)
}
