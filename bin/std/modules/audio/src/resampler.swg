#global public

using Core, Core.Errors

private const ResamplerTaps         = 96'u64
private const ResamplerPhases       = 1_024'u64
private const ResamplerHistory      = 256'u64
private const ResamplerRightContext = ResamplerTaps / 2
private const ResamplerFractionUnit = 4_294_967_296'u64

// Converts interleaved floating-point PCM between sample clocks in bounded memory.
//
// Each call to `addFrames` appends the available converted frames to the caller's array. Clear
// that array after consuming them so its size does not grow with the recording. `end` emits the
// remaining samples using the final input frame at the right boundary. A 96-tap Blackman-windowed
// sinc filter uses a fixed table of 1024 fractional phases; the internal input history is fixed.
// Changing the input clock drift preserves the fractional sample position and needs no reset.
#[Swag.NoCopy]
#[Swag.Opaque]
struct Resampler
{
    internal
    {
        coefficients:   Array'f32
        history:        Array'f32
        channels:       u32
        inputRate:      u32
        outputRate:     u32
        receivedFrames: u64
        positionFrame:  u64
        positionPart:   u64
        step:           u64
        isEnded:        bool
    }
}

impl Resampler
{
    // Creates a streaming converter for one through eight interleaved channels.
    //
    // Both sample rates must be between 8000 and 192000 frames per second. The output rate is
    // fixed for the stream; `setInputClockDriftPpm` adjusts the input consumption rate later.
    func create(inputRate, outputRate, channels: u32)->Resampler fail
    {
        if inputRate < 8_000 or inputRate > 192_000 or
           outputRate < 8_000 or outputRate > 192_000 or
           not channels or channels > 8 do
            fail BadParameterError{"resampler needs sample rates from 8000 to 192000 and one to eight channels"}

        with var result: #returntype
        {
            .inputRate  = inputRate
            .outputRate = outputRate
            .channels   = channels
            .history.resize(ResamplerHistory * channels)
            .coefficients.resize(ResamplerPhases * ResamplerTaps)
            .step = makeStep(inputRate, outputRate, 0)
        }

        let cutoff = 0.475 * Math.min(1.0, cast(f64, outputRate) / inputRate)
        for phase in ResamplerPhases
        {
            let fraction = cast(f64, phase) / ResamplerPhases
            var sum = 0.0'f64
            for tap in ResamplerTaps
            {
                let distance = cast(f64, cast(s64, tap) - cast(s64, ResamplerRightContext - 1)) - fraction
                let angle    = Math.ConstF64.TwoPi * cutoff * distance
                let sinc     = distance == 0 ? 2.0 * cutoff : Math.sin(angle) / (Math.ConstF64.Pi * distance)
                let window   = 0.42 + 0.5 * Math.cos(Math.ConstF64.Pi * distance / ResamplerRightContext) +
                               0.08 * Math.cos(Math.ConstF64.TwoPi * distance / ResamplerRightContext)
                let value = sinc * window
                result.coefficients[phase * ResamplerTaps + tap] = cast(f32, value)
                sum += value
            }
            for tap in ResamplerTaps do
                result.coefficients[phase * ResamplerTaps + tap] =
                    cast(f32, result.coefficients[phase * ResamplerTaps + tap] / sum)
        }
        return result
    }

    // Adjusts the input clock rate by at most 1000 parts per million.
    //
    // A positive value consumes input more quickly per output frame. The adjustment takes effect
    // on the next output frame without moving the current sample position or resetting history.
    mtd setInputClockDriftPpm(ppm: s32) fail
    {
        if ppm < -1_000 or ppm > 1_000 do
            fail BadParameterError{"resampler input clock drift must be within 1000 ppm"}
        .step = makeStep(.inputRate, .outputRate, ppm)
    }

    // Starts a new continuous source run without rebuilding the filter coefficients.
    //
    // Call after a capture device switch or discontinuity. The next input frame becomes sample
    // zero of the new run, the phase restarts at zero, and input-clock drift returns to nominal.
    mtd restart()
    {
        .receivedFrames = 0
        .positionFrame = 0
        .positionPart = 0
        .step = makeStep(.inputRate, .outputRate, 0)
        .isEnded = false
    }

    // Appends every output frame made available by these complete interleaved input frames.
    //
    // The caller owns `output` and may reuse its array after consuming the appended frames.
    // Up to 48 future input frames are retained before an output frame can be emitted. Input and
    // output must not alias. An empty input is valid and emits nothing.
    mtd addFrames(input: const [..] f32, output: *Array'f32) fail
    {
        if .isEnded do
            fail BadParameterError{"cannot append to an ended resampler"}
        if input.count % .channels do
            fail BadParameterError{"resampler input must contain complete interleaved frames"}
        let frames = input.count / .channels
        if frames > Swag.U64.Max - .receivedFrames do
            fail OverflowError{"resampler input frame count overflows"}

        for frame in frames
        {
            let base = (.receivedFrames % ResamplerHistory) * .channels
            for channel in .channels do
                .history[base + channel] = input[frame * .channels + channel]
            .receivedFrames += 1
            while .positionFrame < .receivedFrames and
                  .receivedFrames - .positionFrame > ResamplerRightContext do
                .emit(output)
        }
    }

    // Emits the delayed tail, extending the last input frame across the right filter boundary.
    //
    // The number of emitted frames follows the accumulated rate ratio. Repeated calls do nothing.
    mtd end(output: *Array'f32) fail
    {
        if .isEnded do
            return
        while .positionFrame < .receivedFrames do
            .emit(output)
        .isEnded = true
    }

    private func makeStep(inputRate, outputRate: u32, ppm: s32)->u64
    {
        let ratio = cast(f64, inputRate) * (1.0 + cast(f64, ppm) / 1_000_000.0) / outputRate
        return cast(u64, Math.round(ratio * ResamplerFractionUnit))
    }

    private mtd emit(output: *Array'f32)
    {
        let phase = .positionPart * ResamplerPhases / ResamplerFractionUnit
        for channel in .channels
        {
            var value = 0.0'f64
            for tap in ResamplerTaps
            {
                let relative = cast(s64, tap) - cast(s64, ResamplerRightContext - 1)
                let frame = relative < 0 and .positionFrame < cast(u64, -relative) ? 0 :
                            (relative < 0 ? .positionFrame - cast(u64, -relative) : .positionFrame + cast(u64, relative))
                let available = Math.min(frame, .receivedFrames - 1)
                let sample = .history[(available % ResamplerHistory) * .channels + channel]
                value += sample * .coefficients[phase * ResamplerTaps + tap]
            }
            output.add(cast(f32, value))
        }

        let fraction = .positionPart + (.step % ResamplerFractionUnit)
        .positionFrame += .step / ResamplerFractionUnit + fraction / ResamplerFractionUnit
        .positionPart   = fraction % ResamplerFractionUnit
    }
}
