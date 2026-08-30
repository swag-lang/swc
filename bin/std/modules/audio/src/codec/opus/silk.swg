//! Format: Opus SILK layer decoder.
//! Supported: The linear-prediction layer of RFC 6716 clause 4.2 at 8, 12, and 16 kHz: side information, shell-coded excitation, the NLSF codebooks, LTP and LPC synthesis with gain and coefficient interpolation, mid/side stereo with its predictor interpolation, redundant frames consumed in place, and the fixed-point resampler that brings every band to 48 kHz.
//! Not supported: Packet-loss concealment and comfort noise, which a file never needs, and the neural enhancement of recent reference builds.
//! Role: This file owns SILK frame syntax, its integer synthesis, and the upsampler.
//
#global namespace Opus

using Core, Core.Errors, Core.Math

private const MaxLpcOrder                     = 16'u32
private const MinLpcOrder                     = 10'u32
private const LtpOrder                        = 5'u32
private const MaxNbSubfr                      = 4'u32
private const MaxFrameLength                  = 320'u32
private const MaxSubFrameLength               = 80'u32
private const LtpMemLengthMs                  = 20'u32
private const SubFrameLengthMs                = 5'u32
private const ShellCodecFrameLength           = 16'u32
private const MaxNbShellBlocks                = 20'u32
private const SilkMaxPulses                   = 16'u32
private const NRateLevels                     = 10'u32
private const NlsfQuantMaxAmplitude           = 4's32
private const MaxLpcStabilizeIterations       = 16'u32
private const QuantLevelAdjustQ10             = 80's32
private const NLevelsQGain                    = 64's32
private const MaxDeltaGainQuant               = 36's32
private const MinDeltaGainQuant               = -4's32
private const TypeNoVoiceActivity             = 0's32
private const TypeVoiced                      = 2's32
internal const CodeIndependently              = 0'u32
internal const CodeIndependentlyNoLtpScaling  = 1'u32
internal const CodeConditionally              = 2'u32
private const StereoQuantSubSteps             = 5's32
private const StereoInterpLenMs               = 8'u32
private const PeMinLagMs                      = 2's32
private const PeMaxLagMs                      = 18's32
private const LsfCosTabSize                   = 128's32
private const RandMultiplier                  = 196314165'u32
private const RandIncrement                   = 907633515'u32
private const GainOffset                      = 2090's32
private const InverseGainScaleQ16             = 1907825's32
private const NlsfQuantLevelAdjQ10            = 102's32
private const MaxLoops                        = 20'u32
private const NlsfQA                          = 16'u32
private const LpcQA                           = 24'u32
private const LpcALimit                       = 16773022's32
private const MaxPredictionPowerGainQ30       = 107374's32
private const ResamplerOrderFir12             = 8'u32
private const ResamplerMaxBatchSizeMs         = 10'u32
private const ResamplerUp2Hq0:       [3] s32  = [1746, 14986, 39083 - 65536]
private const ResamplerUp2Hq1:       [3] s32  = [6854, 25769, 55542 - 65536]
private const ResamplerDelayDecoder: [3] s32  = [0, 4, 7]
private const Nlsf2aOrdering16:      [16] u32 = [0, 15, 8, 7, 4, 11, 12, 3, 2, 13, 10, 5, 6, 9, 14, 1]
private const Nlsf2aOrdering10:      [10] u32 = [0, 9, 6, 3, 4, 5, 8, 1, 2, 7]

// Fixed-point primitives of the reference, with the truncations and wraps it relies on.
#[Swag.Safety(.Overflow, false)]
private func smulwb(a, b: s32)->s32 => cast(s32) ((cast(s64) a * cast(s64) cast #wrap (s16) b) >> 16)

#[Swag.Safety(.Overflow, false)]
private func smlawb(a, b, c: s32)->s32 => a + smulwb(b, c)

#[Swag.Safety(.Overflow, false)]
private func smulww(a, b: s32)->s32 => cast(s32) ((cast(s64) a * cast(s64) b) >> 16)

#[Swag.Safety(.Overflow, false)]
private func smlaww(a, b, c: s32)->s32 => a + smulww(b, c)

#[Swag.Safety(.Overflow, false)]
private func smulbb(a, b: s32)->s32 => cast(s32) cast #wrap (s16) a * cast(s32) cast #wrap (s16) b

#[Swag.Safety(.Overflow, false)]
private func smlabb(a, b, c: s32)->s32 => a + smulbb(b, c)

#[Swag.Safety(.Overflow, false)]
private func smmul(a, b: s32)->s32 => cast(s32) ((cast(s64) a * cast(s64) b) >> 32)

private func rshiftRound(a: s32, shift: u32)->s32 => shift == 1 ? (a >> 1) + (a & 1) : ((a >> (shift - 1)) + 1) >> 1

private func rshiftRound64(a: s64, shift: u32)->s64 => shift == 1 ? (a >> 1) + (a & 1) : ((a >> (shift - 1)) + 1) >> 1

private func sat16(a: s32)->s32 => Math.clamp(a, -32768, 32767)

private func addSat32(a, b: s32)->s32 => cast(s32) Math.clamp(cast(s64) a + cast(s64) b, -2147483648, 2147483647)

private func subSat32(a, b: s32)->s32 => cast(s32) Math.clamp(cast(s64) a - cast(s64) b, -2147483648, 2147483647)

private func lshiftSat32(a: s32, shift: u32)->s32 => Math.clamp(a, Swag.S32.Min >> shift, Swag.S32.Max >> shift) << shift

private func clz32(value: s32)->s32 => cast(s32) (32 - ilog(cast #bit (u32) value))

#[Swag.Safety(.Overflow, false)]
private func silkRand(seed: s32)->s32 => cast #bit (s32) (RandIncrement + cast #bit (u32) seed * RandMultiplier)

private func log2lin(inLogQ7: s32)->s32
{
    if inLogQ7 < 0 do
        return 0
    if inLogQ7 >= 3967 do
        return Swag.S32.Max
    var out    = 1's32 << cast(u32) (inLogQ7 >> 7)
    let fracQ7 = inLogQ7 & 0x7F
    let curve  = smlawb(fracQ7, smulbb(fracQ7, 128 - fracQ7), -174)
    if inLogQ7 < 2048 do
        out = out + ((out * curve) >> 7)
    else do
        out = out + (out >> 7) * curve
    return out
}

// A good approximation of `(1 << qres) / b32`.
private func inverse32VarQ(b32: s32, qres: u32)->s32
{
    let headroom = clz32(Math.abs(b32)) - 1
    let normal   = b32 << cast(u32) headroom
    let inverse  = (Swag.S32.Max >> 2) / (normal >> 16)
    var result   = inverse << 16
    let errorQ32 = ((1's32 << 29) - smulwb(normal, inverse)) << 3
    result = smlaww(result, errorQ32, inverse)
    let lshift = 61 - headroom - cast(s32) qres
    if lshift <= 0 do
        return lshiftSat32(result, cast(u32) -lshift)
    if lshift < 32 do
        return result >> cast(u32) lshift
    return 0
}

// A good approximation of `(a32 << qres) / b32`.
#[Swag.Safety(.Overflow, false)]
private func div32VarQ(a32, b32: s32, qres: u32)->s32
{
    let aHeadroom = clz32(Math.abs(a32)) - 1
    var aNormal   = a32 << cast(u32) aHeadroom
    let bHeadroom = clz32(Math.abs(b32)) - 1
    let bNormal   = b32 << cast(u32) bHeadroom
    let inverse   = (Swag.S32.Max >> 2) / (bNormal >> 16)
    var result    = smulwb(aNormal, inverse)
    aNormal = aNormal - (smmul(bNormal, result) << 3)
    result  = smlawb(result, aNormal, inverse)
    let lshift = 29 + aHeadroom - bHeadroom - cast(s32) qres
    if lshift < 0 do
        return lshiftSat32(result, cast(u32) -lshift)
    if lshift < 32 do
        return result >> cast(u32) lshift
    return 0
}

// The NLSF codebook a channel quantizes its spectral envelope with: one for narrow and medium
// band, one for wideband.
private struct NlsfCodebook
{
    wideband: bool
    vectors:  u32
    order:    u32
    stepQ16:  s32
}

private impl NlsfCodebook
{
    mtd const cb1Q8()->const [..] u8
    {
        if .wideband do
            return SilkNlsfCb1WbQ8
        return SilkNlsfCb1NbMbQ8
    }

    mtd const weightsQ9()->const [..] s16
    {
        if .wideband do
            return SilkNlsfCb1WbWghtQ9
        return SilkNlsfCb1NbMbWghtQ9
    }

    mtd const cb1Icdf()->const [..] u8
    {
        if .wideband do
            return SilkNlsfCb1IcdfWb
        return SilkNlsfCb1IcdfNbMb
    }

    mtd const predQ8()->const [..] u8
    {
        if .wideband do
            return SilkNlsfPredWbQ8
        return SilkNlsfPredNbMbQ8
    }

    mtd const selection()->const [..] u8
    {
        if .wideband do
            return SilkNlsfCb2SelectWb
        return SilkNlsfCb2SelectNbMb
    }

    mtd const cb2Icdf()->const [..] u8
    {
        if .wideband do
            return SilkNlsfCb2IcdfWb
        return SilkNlsfCb2IcdfNbMb
    }

    mtd const deltaMinQ15()->const [..] s16
    {
        if .wideband do
            return SilkNlsfDeltaMinWbQ15
        return SilkNlsfDeltaMinNbMbQ15
    }
}

private func nlsfCodebook(wideband: bool)->NlsfCodebook
{
    if wideband do
        return NlsfCodebook{true, 32, 16, 9830}
    return NlsfCodebook{false, 32, 10, 11796}
}

// The side information of one frame.
private struct SideInfo
{
    gainsIndices:     [MaxNbSubfr] s32
    ltpIndex:         [MaxNbSubfr] s32
    nlsfIndices:      [MaxLpcOrder + 1] s32
    lagIndex:         s32
    contourIndex:     s32
    signalType:       s32
    quantOffsetType:  s32
    nlsfInterpCoefQ2: s32
    perIndex:         s32
    ltpScaleIndex:    s32
    seed:             s32
}

// The parameters one frame decodes into before synthesis.
private struct FrameControl
{
    pitchLags:   [MaxNbSubfr] s32
    gainsQ16:    [MaxNbSubfr] s32
    predCoefQ12: [2, MaxLpcOrder] s32
    ltpCoefQ14:  [LtpOrder * MaxNbSubfr] s32
    ltpScaleQ14: s32
}

// The fixed-point resampler that takes one band to 48 kHz: a two-fold IIR upsampler followed by
// fractional FIR interpolation.
private struct Resampler
{
    iir:         [6] s32
    fir:         [ResamplerOrderFir12] s16
    delay:       [48] s16
    batchSize:   u32
    invRatioQ16: s32
    fsInKHz:     u32
    inputDelay:  u32
    buffer:      Array's16
}

private impl Resampler
{
    mtd initialize(fsInHz: u32)
    {
        Memory.set(&.iir, 0, #sizeof(.iir))
        Memory.set(&.fir, 0, #sizeof(.fir))
        Memory.set(&.delay, 0, #sizeof(.delay))
        .fsInKHz     = fsInHz / 1000
        .inputDelay  = cast(u32) ResamplerDelayDecoder[.fsInKHz == 8 ? 0 : (.fsInKHz == 12 ? 1 : 2)]
        .batchSize   = .fsInKHz * ResamplerMaxBatchSizeMs
        .invRatioQ16 = ((cast(s32) fsInHz << 15) / cast(s32) OutputRate) << 2
        while smulww(.invRatioQ16, cast(s32) OutputRate) < cast(s32) (fsInHz << 1) do
            .invRatioQ16 += 1
        .buffer.resize(2 * .batchSize + ResamplerOrderFir12)
    }

    #[Swag.Safety(.Overflow, false)]
    mtd up2(out: [*] s16, input: const [*] s16, len: u32)
    {
        for k in len
        {
            let in32 = cast(s32) input[k] << 10
            var y    = in32 - .iir[0]
            var x    = smulwb(y, ResamplerUp2Hq0[0])
            var out1 = .iir[0] + x
            .iir[0] = in32 + x
            y       = out1 - .iir[1]
            x       = smulwb(y, ResamplerUp2Hq0[1])
            var out2 = .iir[1] + x
            .iir[1]    = out1 + x
            y          = out2 - .iir[2]
            x          = smlawb(y, y, ResamplerUp2Hq0[2])
            out1       = .iir[2] + x
            .iir[2]    = out2 + x
            out[2 * k] = cast(s16) sat16(rshiftRound(out1, 10))

            y              = in32 - .iir[3]
            x              = smulwb(y, ResamplerUp2Hq1[0])
            out1           = .iir[3] + x
            .iir[3]        = in32 + x
            y              = out1 - .iir[4]
            x              = smulwb(y, ResamplerUp2Hq1[1])
            out2           = .iir[4] + x
            .iir[4]        = out1 + x
            y              = out2 - .iir[5]
            x              = smlawb(y, y, ResamplerUp2Hq1[2])
            out1           = .iir[5] + x
            .iir[5]        = out2 + x
            out[2 * k + 1] = cast(s16) sat16(rshiftRound(out1, 10))
        }
    }

    #[Swag.Safety(.Overflow, false)]
    mtd interpolate(out: [*] s16, buffer: const [*] s16, maxIndexQ16, incrementQ16: s32)->u32
    {
        var written  = 0'u32
        var indexQ16 = 0's32
        while indexQ16 < maxIndexQ16
        {
            let tableIndex = cast(u32) smulwb(indexQ16 & 0xFFFF, 12)
            let at         = cast(u32) (indexQ16 >> 16)
            var res        = smulbb(cast(s32) buffer[at], cast(s32) SilkResamplerFracFir12[tableIndex, 0])
            res          = smlabb(res, cast(s32) buffer[at + 1], cast(s32) SilkResamplerFracFir12[tableIndex, 1])
            res          = smlabb(res, cast(s32) buffer[at + 2], cast(s32) SilkResamplerFracFir12[tableIndex, 2])
            res          = smlabb(res, cast(s32) buffer[at + 3], cast(s32) SilkResamplerFracFir12[tableIndex, 3])
            res          = smlabb(res, cast(s32) buffer[at + 4], cast(s32) SilkResamplerFracFir12[11 - tableIndex, 3])
            res          = smlabb(res, cast(s32) buffer[at + 5], cast(s32) SilkResamplerFracFir12[11 - tableIndex, 2])
            res          = smlabb(res, cast(s32) buffer[at + 6], cast(s32) SilkResamplerFracFir12[11 - tableIndex, 1])
            res          = smlabb(res, cast(s32) buffer[at + 7], cast(s32) SilkResamplerFracFir12[11 - tableIndex, 0])
            out[written] = cast(s16) sat16(rshiftRound(res, 15))
            written      += 1
            indexQ16     += incrementQ16
        }

        return written
    }

    // Upsamples `inLen` input samples, batch by batch, and returns the output count.
    mtd iirFir(out: [*] s16, input: const [*] s16, inLen: u32)->u32
    {
        let buffer = .buffer.buffer!
        for i in ResamplerOrderFir12 do
            buffer[i] = .fir[i]
        var written   = 0'u32
        var remaining = inLen
        var at        = 0'u32
        var count     = 0'u32
        while true
        {
            count = Math.min(remaining, .batchSize)
            .up2(buffer + ResamplerOrderFir12, input + at, count)
            let maxIndexQ16 = cast(s32) count << 17
            written   += .interpolate(out + written, buffer, maxIndexQ16, .invRatioQ16)
            at        += count
            remaining -= count
            if remaining > 0
            {
                for i in ResamplerOrderFir12 do
                    buffer[i] = buffer[count * 2 + i]
            }
            else do
                break
        }

        for i in ResamplerOrderFir12 do
            .fir[i] = buffer[count * 2 + i]
        return written
    }

    // Resamples `inLen` samples, which is at least one millisecond, and returns the output count.
    mtd process(out: [*] s16, input: const [*] s16, inLen: u32)->u32
    {
        let samples = .fsInKHz - .inputDelay
        for i in samples do
            .delay[.inputDelay + i] = input[i]
        var written = .iirFir(out, &.delay[0], .fsInKHz)
        written += .iirFir(out + written, input + samples, inLen - .fsInKHz)
        for i in .inputDelay do
            .delay[i] = input[inLen - .inputDelay + i]
        return written
    }
}

// The decoder state of one SILK channel.
private struct SilkChannel
{
    prevGainQ16:          s32
    excQ14:               [MaxFrameLength] s32
    lpcStateQ14:          [MaxLpcOrder] s32
    outBuf:               [MaxFrameLength + 2 * MaxSubFrameLength] s16
    lagPrev:              s32
    lastGainIndex:        s32
    fsKHz:                u32
    nbSubfr:              u32
    frameLength:          u32
    subfrLength:          u32
    ltpMemLength:         u32
    lpcOrder:             u32
    prevNlsfQ15:          [MaxLpcOrder] s32
    firstFrameAfterReset: bool
    nFramesDecoded:       u32
    nFramesPerPacket:     u32
    ecPrevSignalType:     s32
    ecPrevLagIndex:       s32
    vadFlags:             [3] bool
    lbrrFlag:             bool
    lbrrFlags:            [3] bool
    resampler:            Resampler
    codebook:             NlsfCodebook
    indices:              SideInfo
    prevSignalType:       s32
}

private impl SilkChannel
{
    mtd reset()
    {
        .prevGainQ16 = 65536
        Memory.set(&.excQ14, 0, #sizeof(.excQ14))
        Memory.set(&.lpcStateQ14, 0, #sizeof(.lpcStateQ14))
        Memory.set(&.outBuf, 0, #sizeof(.outBuf))
        .lagPrev       = 0
        .lastGainIndex = 0
        .fsKHz         = 0
        .nbSubfr       = 0
        .frameLength   = 0
        .subfrLength   = 0
        .ltpMemLength  = 0
        .lpcOrder      = 0
        Memory.set(&.prevNlsfQ15, 0, #sizeof(.prevNlsfQ15))
        .firstFrameAfterReset = true
        .nFramesDecoded       = 0
        .nFramesPerPacket     = 0
        .ecPrevSignalType     = 0
        .ecPrevLagIndex       = 0
        .lbrrFlag             = false
        .prevSignalType       = 0
        for i in 3
        {
            .vadFlags[i]  = false
            .lbrrFlags[i] = false
        }
    }

    // Selects the internal sampling rate and everything that follows from it.
    mtd setSampleRate(fsKHz: u32)
    {
        .subfrLength = SubFrameLengthMs * fsKHz
        let frameLength = .nbSubfr * .subfrLength
        if .fsKHz != fsKHz do
            .resampler.initialize(fsKHz * 1000)
        if .fsKHz != fsKHz or frameLength != .frameLength
        {
            if .fsKHz != fsKHz
            {
                .ltpMemLength = LtpMemLengthMs * fsKHz
                if fsKHz == 8 or fsKHz == 12
                {
                    .lpcOrder = MinLpcOrder
                    .codebook = nlsfCodebook(false)
                }
                else
                {
                    .lpcOrder = MaxLpcOrder
                    .codebook = nlsfCodebook(true)
                }

                .firstFrameAfterReset = true
                .lagPrev              = 100
                .lastGainIndex        = 10
                .prevSignalType       = TypeNoVoiceActivity
                Memory.set(&.outBuf, 0, #sizeof(.outBuf))
                Memory.set(&.lpcStateQ14, 0, #sizeof(.lpcStateQ14))
            }

            .fsKHz       = fsKHz
            .frameLength = frameLength
        }
    }

    mtd pitchContourIcdf()->const [..] u8
    {
        if .fsKHz == 8 do
            return .nbSubfr == MaxNbSubfr ? SilkPitchContourNbIcdf : SilkPitchContour10MsNbIcdf
        return .nbSubfr == MaxNbSubfr ? SilkPitchContourIcdf : SilkPitchContour10MsIcdf
    }

    mtd pitchLagLowBitsIcdf()->const [..] u8
    {
        if .fsKHz == 16 do
            return SilkUniform8Icdf
        if .fsKHz == 12 do
            return SilkUniform6Icdf
        return SilkUniform4Icdf
    }

    // Reads the side information of one frame, clause 4.2.7.
    mtd decodeIndices(dec: *RangeDecoder, frameIndex: u32, decodeLbrr: bool, condCoding: u32)
    {
        var ix: s32
        if decodeLbrr or .vadFlags[frameIndex] do
            ix = cast(s32) dec.decodeIcdf(SilkTypeOffsetVadIcdf, 8) + 2
        else do
            ix = cast(s32) dec.decodeIcdf(SilkTypeOffsetNoVadIcdf, 8)
        .indices.signalType      = ix >> 1
        .indices.quantOffsetType = ix & 1

        if condCoding == CodeConditionally do
            .indices.gainsIndices[0] = cast(s32) dec.decodeIcdf(SilkDeltaGainIcdf, 8)
        else
        {
            .indices.gainsIndices[0] = cast(s32) dec.decodeIcdf(SilkGainIcdf[cast(u32) .indices.signalType], 8) << 3
            .indices.gainsIndices[0] += cast(s32) dec.decodeIcdf(SilkUniform8Icdf, 8)
        }

        for i in 1'u32 until .nbSubfr do
            .indices.gainsIndices[i] = cast(s32) dec.decodeIcdf(SilkDeltaGainIcdf, 8)

        let cb        = &.codebook
        let cb1Offset = cast(u32) (.indices.signalType >> 1) * cb.vectors
        .indices.nlsfIndices[0] = cast(s32) dec.decodeIcdf(cb.cb1Icdf()[cb1Offset until cb1Offset + cb.vectors], 8)
        var ecIx:   [MaxLpcOrder] u32
        var predQ8: [MaxLpcOrder] s32
        .unpackNlsf(&ecIx[0], &predQ8[0], cast(u32) .indices.nlsfIndices[0])
        for i in cb.order
        {
            var value = cast(s32) dec.decodeIcdf(cb.cb2Icdf()[ecIx[i] until ecIx[i] + 9], 8)
            if value == 0 do
                value -= cast(s32) dec.decodeIcdf(SilkNlsfExtIcdf, 8)
            elif value == 2 * NlsfQuantMaxAmplitude do
                value += cast(s32) dec.decodeIcdf(SilkNlsfExtIcdf, 8)
            .indices.nlsfIndices[i + 1] = value - NlsfQuantMaxAmplitude
        }

        if .nbSubfr == MaxNbSubfr do
            .indices.nlsfInterpCoefQ2 = cast(s32) dec.decodeIcdf(SilkNlsfInterpolationFactorIcdf, 8)
        else do
            .indices.nlsfInterpCoefQ2 = 4

        if .indices.signalType == TypeVoiced
        {
            var absolute = true
            if condCoding == CodeConditionally and .ecPrevSignalType == TypeVoiced
            {
                var delta = cast(s32) dec.decodeIcdf(SilkPitchDeltaIcdf, 8)
                if delta > 0
                {
                    delta             -= 9
                    .indices.lagIndex = .ecPrevLagIndex + delta
                    absolute          = false
                }
            }

            if absolute
            {
                .indices.lagIndex = cast(s32) dec.decodeIcdf(SilkPitchLagIcdf, 8) * cast(s32) (.fsKHz >> 1)
                .indices.lagIndex += cast(s32) dec.decodeIcdf(.pitchLagLowBitsIcdf(), 8)
            }

            .ecPrevLagIndex       = .indices.lagIndex
            .indices.contourIndex = cast(s32) dec.decodeIcdf(.pitchContourIcdf(), 8)
            .indices.perIndex     = cast(s32) dec.decodeIcdf(SilkLtpPerIndexIcdf, 8)
            for k in .nbSubfr
            {
                if .indices.perIndex == 0 do
                    .indices.ltpIndex[k] = cast(s32) dec.decodeIcdf(SilkLtpGainIcdf0, 8)
                elif .indices.perIndex == 1 do
                    .indices.ltpIndex[k] = cast(s32) dec.decodeIcdf(SilkLtpGainIcdf1, 8)
                else do
                    .indices.ltpIndex[k] = cast(s32) dec.decodeIcdf(SilkLtpGainIcdf2, 8)
            }

            if condCoding == CodeIndependently do
                .indices.ltpScaleIndex = cast(s32) dec.decodeIcdf(SilkLtpScaleIcdf, 8)
            else do
                .indices.ltpScaleIndex = 0
        }

        .ecPrevSignalType = .indices.signalType
        .indices.seed     = cast(s32) dec.decodeIcdf(SilkUniform4Icdf, 8)
    }

    mtd unpackNlsf(ecIx: [*] u32, predQ8: [*] s32, cb1Index: u32)
    {
        let cb = &.codebook
        var at = cb1Index * cb.order / 2
        var i  = 0'u32
        while i < cb.order
        {
            let entry = cast(u32) cb.selection()[at]
            at            += 1
            ecIx[i]       = ((entry >> 1) & 7) * cast(u32) (2 * NlsfQuantMaxAmplitude + 1)
            predQ8[i]     = cast(s32) cb.predQ8()[i + (entry & 1) * (cb.order - 1)]
            ecIx[i + 1]   = ((entry >> 5) & 7) * cast(u32) (2 * NlsfQuantMaxAmplitude + 1)
            predQ8[i + 1] = cast(s32) cb.predQ8()[i + ((entry >> 4) & 1) * (cb.order - 1) + 1]
            i             += 2
        }
    }

    // Rebuilds the normalized line spectral frequencies from their indices, clause 4.2.7.5.
    mtd decodeNlsf(nlsfQ15: [*] s32)
    {
        let cb = &.codebook
        var ecIx:   [MaxLpcOrder] u32
        var predQ8: [MaxLpcOrder] s32
        .unpackNlsf(&ecIx[0], &predQ8[0], cast(u32) .indices.nlsfIndices[0])

        var resQ10: [MaxLpcOrder] s32
        var outQ10 = 0's32
        var i      = cb.order
        while i > 0
        {
            i -= 1
            let predQ10 = smulbb(outQ10, predQ8[i]) >> 8
            outQ10 = .indices.nlsfIndices[i + 1] << 10
            if outQ10 > 0 do
                outQ10 -= NlsfQuantLevelAdjQ10
            elif outQ10 < 0 do
                outQ10 += NlsfQuantLevelAdjQ10
            outQ10    = smlawb(predQ10, outQ10, cb.stepQ16)
            resQ10[i] = outQ10
        }

        let base = cast(u32) .indices.nlsfIndices[0] * cb.order
        for k in cb.order
        {
            let value = ((resQ10[k] << 14) / cast(s32) cb.weightsQ9()[base + k]) + (cast(s32) cb.cb1Q8()[base + k] << 7)
            nlsfQ15[k] = Math.clamp(value, 0, 32767)
        }

        stabilizeNlsf(nlsfQ15, cb.deltaMinQ15(), cb.order)
    }

    // Reads the gains, the two coefficient sets, and the long-term predictor, clause 4.2.7.
    mtd decodeParameters(control: *FrameControl, condCoding: u32)
    {
        // Gains are coded on a logarithmic scale, the first one absolutely or as a delta.
        for k in .nbSubfr
        {
            if k == 0 and condCoding != CodeConditionally do
                .lastGainIndex = Math.max(.indices.gainsIndices[k], .lastGainIndex - 16)
            else
            {
                let delta     = .indices.gainsIndices[k] + MinDeltaGainQuant
                let threshold = 2 * MaxDeltaGainQuant - NLevelsQGain + .lastGainIndex
                if delta > threshold do
                    .lastGainIndex += (delta << 1) - threshold
                else do
                    .lastGainIndex += delta
            }

            .lastGainIndex      = Math.clamp(.lastGainIndex, 0, NLevelsQGain - 1)
            control.gainsQ16[k] = log2lin(Math.min(smulwb(InverseGainScaleQ16, .lastGainIndex) + GainOffset, 3967))
        }

        var nlsfQ15: [MaxLpcOrder] s32
        .decodeNlsf(&nlsfQ15[0])
        nlsfToLpc(&control.predCoefQ12[1, 0], &nlsfQ15[0], .lpcOrder)

        if .firstFrameAfterReset do
            .indices.nlsfInterpCoefQ2 = 4
        if .indices.nlsfInterpCoefQ2 < 4
        {
            var nlsf0Q15: [MaxLpcOrder] s32
            for i in .lpcOrder do
                nlsf0Q15[i] = .prevNlsfQ15[i] + ((.indices.nlsfInterpCoefQ2 * (nlsfQ15[i] - .prevNlsfQ15[i])) >> 2)
            nlsfToLpc(&control.predCoefQ12[0, 0], &nlsf0Q15[0], .lpcOrder)
        }
        else
        {
            for i in .lpcOrder do
                control.predCoefQ12[0, i] = control.predCoefQ12[1, i]
        }

        for i in .lpcOrder do
            .prevNlsfQ15[i] = nlsfQ15[i]

        if .indices.signalType == TypeVoiced
        {
            .decodePitch(&control.pitchLags[0])
            for k in .nbSubfr
            {
                let ix = cast(u32) .indices.ltpIndex[k]
                for i in LtpOrder
                {
                    var coef: s32
                    if .indices.perIndex == 0 do
                        coef = cast(s32) SilkLtpGainVq0[ix, i]
                    elif .indices.perIndex == 1 do
                        coef = cast(s32) SilkLtpGainVq1[ix, i]
                    else do
                        coef = cast(s32) SilkLtpGainVq2[ix, i]
                    control.ltpCoefQ14[k * LtpOrder + i] = coef << 7
                }
            }

            control.ltpScaleQ14 = cast(s32) SilkLtpScalesTableQ14[cast(u32) .indices.ltpScaleIndex]
        }
        else
        {
            for k in .nbSubfr do
                control.pitchLags[k] = 0
            for i in LtpOrder * .nbSubfr do
                control.ltpCoefQ14[i] = 0
            .indices.perIndex   = 0
            control.ltpScaleQ14 = 0
        }
    }

    mtd decodePitch(pitchLags: [*] s32)
    {
        let minLag  = PeMinLagMs * cast(s32) .fsKHz
        let maxLag  = PeMaxLagMs * cast(s32) .fsKHz
        let lag     = minLag + .indices.lagIndex
        let contour = cast(u32) .indices.contourIndex
        for k in .nbSubfr
        {
            var offset: s32
            if .fsKHz == 8 do
                offset = .nbSubfr == MaxNbSubfr ? cast(s32) SilkCbLagsStage2[k, contour] : cast(s32) SilkCbLagsStage2For10Ms[k, contour]
            else do
                offset = .nbSubfr == MaxNbSubfr ? cast(s32) SilkCbLagsStage3[k, contour] : cast(s32) SilkCbLagsStage3For10Ms[k, contour]
            pitchLags[k] = Math.clamp(lag + offset, minLag, maxLag)
        }
    }

    // Runs the excitation through the long-term and short-term predictors, clause 4.2.7.9.
    #[Swag.Safety(.Overflow, false)]
    mtd decodeCore(control: *FrameControl, out: [*] s16, pulses: const [*] s32)
    {
        var sLtp:    [MaxFrameLength + MaxSubFrameLength] s16
        var sLtpQ15: [2 * MaxFrameLength + MaxSubFrameLength] s32
        var resQ14:  [MaxSubFrameLength] s32
        var sLpcQ14: [MaxSubFrameLength + MaxLpcOrder] s32
        var aQ12:    [MaxLpcOrder] s32

        let offsetQ10     = cast(s32) SilkQuantizationOffsetsQ10[cast(u32) (.indices.signalType >> 1), cast(u32) .indices.quantOffsetType]
        let interpolating = .indices.nlsfInterpCoefQ2 < 4
        var seed          = .indices.seed
        for i in .frameLength
        {
            seed = silkRand(seed)
            var exc = pulses[i] << 14
            if exc > 0 do
                exc -= QuantLevelAdjustQ10 << 4
            elif exc < 0 do
                exc += QuantLevelAdjustQ10 << 4
            exc += offsetQ10 << 4
            if seed < 0 do
                exc = -exc
            .excQ14[i] = exc
            seed       = seed + pulses[i]
        }

        for i in MaxLpcOrder do
            sLpcQ14[i] = .lpcStateQ14[i]
        var excAt      = 0'u32
        var outAt      = 0'u32
        var sLtpBufIdx = .ltpMemLength
        for k in .nbSubfr
        {
            let coefSet = k >> 1
            for i in .lpcOrder do
                aQ12[i] = control.predCoefQ12[coefSet, i]
            let ltpBase    = k * LtpOrder
            var signalType = .indices.signalType
            let gainQ10    = control.gainsQ16[k] >> 6
            var invGainQ31 = inverse32VarQ(control.gainsQ16[k], 47)
            var gainAdjQ16 = 1's32 << 16
            if control.gainsQ16[k] != .prevGainQ16
            {
                gainAdjQ16 = div32VarQ(.prevGainQ16, control.gainsQ16[k], 16)
                for i in MaxLpcOrder do
                    sLpcQ14[i] = smulww(gainAdjQ16, sLpcQ14[i])
            }

            .prevGainQ16 = control.gainsQ16[k]
            var lag = 0's32
            if signalType == TypeVoiced
            {
                lag = control.pitchLags[k]
                if k == 0 or (k == 2 and interpolating)
                {
                    let startIdx = cast(s32) .ltpMemLength - lag - cast(s32) .lpcOrder - cast(s32) LtpOrder / 2
                    if k == 2
                    {
                        for i in 2 * .subfrLength do
                            .outBuf[.ltpMemLength + i] = out[i]
                    }

                    .analysisFilter(&sLtp[cast(u32) startIdx], &.outBuf[cast(u32) startIdx + k * .subfrLength], &aQ12[0], .ltpMemLength - cast(u32) startIdx, .lpcOrder)
                    if k == 0 do
                        invGainQ31 = smulwb(invGainQ31, control.ltpScaleQ14) << 2
                    for i in cast(u32) lag + LtpOrder / 2 do
                        sLtpQ15[sLtpBufIdx - i - 1] = smulwb(invGainQ31, cast(s32) sLtp[.ltpMemLength - i - 1])
                }
                elif gainAdjQ16 != 1's32 << 16
                {
                    for i in cast(u32) lag + LtpOrder / 2 do
                        sLtpQ15[sLtpBufIdx - i - 1] = smulww(gainAdjQ16, sLtpQ15[sLtpBufIdx - i - 1])
                }
            }

            var resAt: u32
            if signalType == TypeVoiced
            {
                var predLag = sLtpBufIdx - cast(u32) lag + LtpOrder / 2
                for i in .subfrLength
                {
                    var pred = 2's32
                    pred                = smlawb(pred, sLtpQ15[predLag], control.ltpCoefQ14[ltpBase])
                    pred                = smlawb(pred, sLtpQ15[predLag - 1], control.ltpCoefQ14[ltpBase + 1])
                    pred                = smlawb(pred, sLtpQ15[predLag - 2], control.ltpCoefQ14[ltpBase + 2])
                    pred                = smlawb(pred, sLtpQ15[predLag - 3], control.ltpCoefQ14[ltpBase + 3])
                    pred                = smlawb(pred, sLtpQ15[predLag - 4], control.ltpCoefQ14[ltpBase + 4])
                    predLag             += 1
                    resQ14[i]           = .excQ14[excAt + i] + (pred << 1)
                    sLtpQ15[sLtpBufIdx] = resQ14[i] << 1
                    sLtpBufIdx          += 1
                }
            }
            else
            {
                for i in .subfrLength do
                    resQ14[i] = .excQ14[excAt + i]
            }

            for i in .subfrLength
            {
                let at   = MaxLpcOrder + i
                var pred = cast(s32) (.lpcOrder >> 1)
                pred = smlawb(pred, sLpcQ14[at - 1], aQ12[0])
                pred = smlawb(pred, sLpcQ14[at - 2], aQ12[1])
                pred = smlawb(pred, sLpcQ14[at - 3], aQ12[2])
                pred = smlawb(pred, sLpcQ14[at - 4], aQ12[3])
                pred = smlawb(pred, sLpcQ14[at - 5], aQ12[4])
                pred = smlawb(pred, sLpcQ14[at - 6], aQ12[5])
                pred = smlawb(pred, sLpcQ14[at - 7], aQ12[6])
                pred = smlawb(pred, sLpcQ14[at - 8], aQ12[7])
                pred = smlawb(pred, sLpcQ14[at - 9], aQ12[8])
                pred = smlawb(pred, sLpcQ14[at - 10], aQ12[9])
                if .lpcOrder == 16
                {
                    pred = smlawb(pred, sLpcQ14[at - 11], aQ12[10])
                    pred = smlawb(pred, sLpcQ14[at - 12], aQ12[11])
                    pred = smlawb(pred, sLpcQ14[at - 13], aQ12[12])
                    pred = smlawb(pred, sLpcQ14[at - 14], aQ12[13])
                    pred = smlawb(pred, sLpcQ14[at - 15], aQ12[14])
                    pred = smlawb(pred, sLpcQ14[at - 16], aQ12[15])
                }

                sLpcQ14[at]    = addSat32(resQ14[i], lshiftSat32(pred, 4))
                out[outAt + i] = cast(s16) sat16(rshiftRound(smulww(sLpcQ14[at], gainQ10), 8))
            }

            for i in MaxLpcOrder do
                sLpcQ14[i] = sLpcQ14[.subfrLength + i]
            excAt += .subfrLength
            outAt += .subfrLength
        }

        for i in MaxLpcOrder do
            .lpcStateQ14[i] = sLpcQ14[i]
    }

    // The whitening filter that turns past output into the residual the long-term predictor reads.
    #[Swag.Safety(.Overflow, false)]
    mtd analysisFilter(out: [*] s16, input: const [*] s16, coefficients: const [*] s32, len, order: u32)
    {
        for j in order do
            out[j] = 0
        for ix in order until len
        {
            var acc = smulbb(cast(s32) input[ix - 1], coefficients[0])
            for j in 1'u32 until order do
                acc = acc + smulbb(cast(s32) input[ix - 1 - j], coefficients[j])
            acc     = (cast(s32) input[ix] << 12) - acc
            out[ix] = cast(s16) sat16(rshiftRound(acc, 12))
        }
    }

    // Decodes one frame into `out`, which receives `frameLength` samples at the internal rate.
    mtd decodeFrame(dec: *RangeDecoder, out: [*] s16, condCoding: u32)
    {
        var control: FrameControl
        var pulses:  [MaxFrameLength] s32
        .decodeIndices(dec, .nFramesDecoded, false, condCoding)
        decodeSilkPulses(dec, &pulses[0], .indices.signalType, .indices.quantOffsetType, .frameLength)
        .decodeParameters(&control, condCoding)
        .decodeCore(&control, out, &pulses[0])

        let keep = .ltpMemLength - .frameLength
        for i in keep do
            .outBuf[i] = .outBuf[.frameLength + i]
        for i in .frameLength do
            .outBuf[keep + i] = out[i]
        .prevSignalType       = .indices.signalType
        .firstFrameAfterReset = false
        .lagPrev              = control.pitchLags[.nbSubfr - 1]
    }
}

// Reads the excitation of one frame: rate level, pulse counts per shell block, the shell
// codes, extra least significant bits, and the signs, clause 4.2.7.8.
private func decodeSilkPulses(dec: *RangeDecoder, pulses: [*] s32, signalType, quantOffsetType: s32, frameLength: u32)
{
    let rateLevel = dec.decodeIcdf(SilkRateLevelsIcdf[cast(u32) (signalType >> 1)], 8)
    var iter      = frameLength >> 4
    if iter * ShellCodecFrameLength < frameLength do
        iter += 1

    var sumPulses: [MaxNbShellBlocks] u32
    var shifts:    [MaxNbShellBlocks] u32
    for i in iter
    {
        shifts[i]    = 0
        sumPulses[i] = dec.decodeIcdf(SilkPulsesPerBlockIcdf[rateLevel], 8)
        while sumPulses[i] == SilkMaxPulses + 1
        {
            shifts[i] += 1
            let table = SilkPulsesPerBlockIcdf[NRateLevels - 1]
            let from  = shifts[i] == 10 ? 1'u32 : 0
            sumPulses[i] = dec.decodeIcdf(table[from until 18], 8)
        }
    }

    for i in iter
    {
        let base = i * ShellCodecFrameLength
        if sumPulses[i] > 0 do
            shellDecode(pulses + base, dec, sumPulses[i])
        else
        {
            for k in ShellCodecFrameLength do
                pulses[base + k] = 0
        }
    }

    for i in iter
    {
        if shifts[i] > 0
        {
            let base = i * ShellCodecFrameLength
            for k in ShellCodecFrameLength
            {
                var value = pulses[base + k]
                for shifts[i]
                {
                    value <<= 1
                    value += cast(s32) dec.decodeIcdf(SilkLsbIcdf, 8)
                }

                pulses[base + k] = value
            }

            sumPulses[i] |= shifts[i] << 5
        }
    }

    // Signs, one per non-zero pulse, with a probability that depends on the block's pulse count.
    let signBase = 7 * cast(u32) (quantOffsetType + (signalType << 1))
    let blocks   = (frameLength + ShellCodecFrameLength / 2) >> 4
    for i in blocks
    {
        let p = sumPulses[i]
        if p > 0
        {
            var icdf: [2] u8
            icdf[0] = SilkSignIcdf[signBase + Math.min(p & 0x1F, 6)]
            icdf[1] = 0
            let base = i * ShellCodecFrameLength
            for j in ShellCodecFrameLength where pulses[base + j] > 0
            {
                if dec.decodeIcdf(icdf, 8) == 0 do
                    pulses[base + j] = -pulses[base + j]
            }
        }
    }
}

private func shellSplit(dec: *RangeDecoder, total: u32, table: const [..] u8, first, second: *u32)
{
    if total > 0
    {
        let at = cast(u32) SilkShellCodeTableOffsets[total]
        first[]  = dec.decodeIcdf(table[at until table.count], 8)
        second[] = total - first[]
    }
    else
    {
        first[]  = 0
        second[] = 0
    }
}

private func shellDecode(pulses: [*] s32, dec: *RangeDecoder, total: u32)
{
    var p3: [2] u32
    var p2: [4] u32
    var p1: [8] u32
    var p0: [16] u32
    shellSplit(dec, total, SilkShellCodeTable3, &p3[0], &p3[1])
    shellSplit(dec, p3[0], SilkShellCodeTable2, &p2[0], &p2[1])
    shellSplit(dec, p2[0], SilkShellCodeTable1, &p1[0], &p1[1])
    shellSplit(dec, p1[0], SilkShellCodeTable0, &p0[0], &p0[1])
    shellSplit(dec, p1[1], SilkShellCodeTable0, &p0[2], &p0[3])
    shellSplit(dec, p2[1], SilkShellCodeTable1, &p1[2], &p1[3])
    shellSplit(dec, p1[2], SilkShellCodeTable0, &p0[4], &p0[5])
    shellSplit(dec, p1[3], SilkShellCodeTable0, &p0[6], &p0[7])
    shellSplit(dec, p3[1], SilkShellCodeTable2, &p2[2], &p2[3])
    shellSplit(dec, p2[2], SilkShellCodeTable1, &p1[4], &p1[5])
    shellSplit(dec, p1[4], SilkShellCodeTable0, &p0[8], &p0[9])
    shellSplit(dec, p1[5], SilkShellCodeTable0, &p0[10], &p0[11])
    shellSplit(dec, p2[3], SilkShellCodeTable1, &p1[6], &p1[7])
    shellSplit(dec, p1[6], SilkShellCodeTable0, &p0[12], &p0[13])
    shellSplit(dec, p1[7], SilkShellCodeTable0, &p0[14], &p0[15])
    for i in 16 do
        pulses[i] = cast(s32) p0[i]
}

// Keeps the line spectral frequencies ordered and apart by their minimum spacing.
private func stabilizeNlsf(nlsfQ15: [*] s32, deltaMinQ15: const [..] s16, order: u32)
{
    let last = order - 1
    for MaxLoops
    {
        var minDiff = nlsfQ15[0] - cast(s32) deltaMinQ15[0]
        var worst   = 0'u32
        for i in 1'u32 until order
        {
            let diff = nlsfQ15[i] - (nlsfQ15[i - 1] + cast(s32) deltaMinQ15[i])
            if diff < minDiff
            {
                minDiff = diff
                worst   = i
            }
        }

        let endDiff = (1 << 15) - (nlsfQ15[last] + cast(s32) deltaMinQ15[order])
        if endDiff < minDiff
        {
            minDiff = endDiff
            worst   = order
        }

        if minDiff >= 0 do
            return

        if worst == 0 do
            nlsfQ15[0] = cast(s32) deltaMinQ15[0]
        elif worst == order do
            nlsfQ15[last] = (1 << 15) - cast(s32) deltaMinQ15[order]
        else
        {
            var minCenter = 0's32
            for k in worst do
                minCenter += cast(s32) deltaMinQ15[k]
            minCenter += cast(s32) deltaMinQ15[worst] >> 1
            var maxCenter = 1's32 << 15
            var k         = order
            while k > worst
            {
                maxCenter -= cast(s32) deltaMinQ15[k]
                k         -= 1
            }

            maxCenter -= cast(s32) deltaMinQ15[worst] >> 1
            let center = Math.clamp(rshiftRound(nlsfQ15[worst - 1] + nlsfQ15[worst], 1), minCenter, maxCenter)
            nlsfQ15[worst - 1] = center - (cast(s32) deltaMinQ15[worst] >> 1)
            nlsfQ15[worst]     = nlsfQ15[worst - 1] + cast(s32) deltaMinQ15[worst]
        }
    }

    // Too many corrections: sort, then push every value away from its neighbours.
    for i in 1'u32 until order
    {
        let value = nlsfQ15[i]
        var j     = cast(s32) i - 1
        while j >= 0 and value < nlsfQ15[cast(u32) j]
        {
            nlsfQ15[cast(u32) j + 1] = nlsfQ15[cast(u32) j]
            j -= 1
        }

        nlsfQ15[cast(u32) (j + 1)] = value
    }

    nlsfQ15[0] = Math.max(nlsfQ15[0], cast(s32) deltaMinQ15[0])
    for i in 1'u32 until order do
        nlsfQ15[i] = Math.max(nlsfQ15[i], Math.min(nlsfQ15[i - 1] + cast(s32) deltaMinQ15[i], 32767))
    nlsfQ15[last] = Math.min(nlsfQ15[last], (1 << 15) - cast(s32) deltaMinQ15[order])
    var i = last
    while i > 0
    {
        i          -= 1
        nlsfQ15[i] = Math.min(nlsfQ15[i], nlsfQ15[i + 1] - cast(s32) deltaMinQ15[i + 1])
    }
}

#[Swag.Safety(.Overflow, false)]
private func nlsfPolynomial(out: [*] s32, cosLsf: const [*] s32, dd: u32)
{
    out[0] = 1's32 << NlsfQA
    out[1] = -cosLsf[0]
    for k in 1'u32 until dd
    {
        let ftmp = cosLsf[2 * k]
        out[k + 1] = (out[k - 1] << 1) - cast(s32) rshiftRound64(cast(s64) ftmp * cast(s64) out[k], NlsfQA)
        var n = k
        while n > 1
        {
            out[n] += out[n - 2] - cast(s32) rshiftRound64(cast(s64) ftmp * cast(s64) out[n - 1], NlsfQA)
            n      -= 1
        }

        out[1] -= ftmp
    }
}

// Converts line spectral frequencies to prediction coefficients in Q12, clause 4.2.7.5.8.
#[Swag.Safety(.Overflow, false)]
private func nlsfToLpc(aQ12: [*] s32, nlsf: const [*] s32, order: u32)
{
    var cosLsfQA: [MaxLpcOrder] s32
    for k in order
    {
        let fInt   = nlsf[k] >> 8
        let fFrac  = nlsf[k] - (fInt << 8)
        let cosVal = cast(s32) SilkLsfCosTabFixQ12[cast(u32) fInt]
        let delta  = cast(s32) SilkLsfCosTabFixQ12[cast(u32) fInt + 1] - cosVal
        let target = order == 16 ? Nlsf2aOrdering16[k] : Nlsf2aOrdering10[k]
        cosLsfQA[target] = rshiftRound((cosVal << 8) + delta * fFrac, 20 - NlsfQA)
    }

    let dd = order >> 1
    var p: [MaxLpcOrder / 2 + 1] s32
    var q: [MaxLpcOrder / 2 + 1] s32
    nlsfPolynomial(&p[0], &cosLsfQA[0], dd)
    nlsfPolynomial(&q[0], &cosLsfQA[1], dd)
    var a32: [MaxLpcOrder] s32
    for k in dd
    {
        let ptmp = p[k + 1] + p[k]
        let qtmp = q[k + 1] - q[k]
        a32[k]             = -qtmp - ptmp
        a32[order - k - 1] = qtmp - ptmp
    }

    lpcFit(aQ12, &a32[0], 12, NlsfQA + 1, order)
    var i = 0'u32
    while i < MaxLpcStabilizeIterations and inversePredictionGain(aQ12, order) == 0
    {
        bandwidthExpand32(&a32[0], order, 65536 - (2 << i))
        for k in order do
            aQ12[k] = rshiftRound(a32[k], NlsfQA + 1 - 12)
        i += 1
    }
}

#[Swag.Safety(.Overflow, false)]
private func bandwidthExpand32(ar: [*] s32, order: u32, chirpIn: s32)
{
    var chirpQ16   = chirpIn
    let chirpMinus = chirpQ16 - 65536
    for i in order - 1
    {
        ar[i]    = smulww(chirpQ16, ar[i])
        chirpQ16 += rshiftRound(chirpQ16 * chirpMinus, 16)
    }

    ar[order - 1] = smulww(chirpQ16, ar[order - 1])
}

// Scales a coefficient set down until every value fits sixteen bits.
#[Swag.Safety(.Overflow, false)]
private func lpcFit(aOut: [*] s32, aIn: [*] s32, qOut, qIn, order: u32)
{
    var iterations = 0'u32
    var index      = 0'u32
    while iterations < 10
    {
        var maxAbs = 0's32
        for k in order
        {
            let value = Math.abs(aIn[k])
            if value > maxAbs
            {
                maxAbs = value
                index  = k
            }
        }

        maxAbs = rshiftRound(maxAbs, qIn - qOut)
        if maxAbs <= 32767 do
            break
        maxAbs = Math.min(maxAbs, 163838)
        let chirpQ16 = 65470 - (((maxAbs - 32767) << 14) / ((maxAbs * cast(s32) (index + 1)) >> 2))
        bandwidthExpand32(aIn, order, chirpQ16)
        iterations += 1
    }

    if iterations == 10
    {
        for k in order
        {
            aOut[k] = sat16(rshiftRound(aIn[k], qIn - qOut))
            aIn[k]  = aOut[k] << (qIn - qOut)
        }
    }
    else
    {
        for k in order do
            aOut[k] = rshiftRound(aIn[k], qIn - qOut)
    }
}

// Returns the inverse prediction gain of a coefficient set in Q30, or zero when it is unstable.
#[Swag.Safety(.Overflow, false)]
private func inversePredictionGain(aQ12: const [*] s32, order: u32)->s32
{
    var aQA: [MaxLpcOrder] s32
    var dcResponse = 0's32
    for k in order
    {
        dcResponse += aQ12[k]
        aQA[k]     = aQ12[k] << (LpcQA - 12)
    }

    if dcResponse >= 4096 do
        return 0

    var invGainQ30 = 1's32 << 30
    var k          = order - 1
    while k > 0
    {
        if aQA[k] > LpcALimit or aQA[k] < -LpcALimit do
            return 0
        let rcQ31      = -(aQA[k] << (31 - LpcQA))
        let rcMult1Q30 = (1's32 << 30) - smmul(rcQ31, rcQ31)
        invGainQ30 = smmul(invGainQ30, rcMult1Q30) << 2
        if invGainQ30 < MaxPredictionPowerGainQ30 do
            return 0
        let mult2Q  = 32 - clz32(Math.abs(rcMult1Q30))
        let rcMult2 = inverse32VarQ(rcMult1Q30, cast(u32) mult2Q + 30)
        for n in (k + 1) >> 1
        {
            let tmp1  = aQA[n]
            let tmp2  = aQA[k - n - 1]
            let first = rshiftRound64(cast(s64) subSat32(tmp1, cast(s32) rshiftRound64(cast(s64) tmp2 * cast(s64) rcQ31, 31)) * cast(s64) rcMult2, cast(u32) mult2Q)
            if first > 2147483647 or first < -2147483648 do
                return 0
            aQA[n] = cast(s32) first
            let second = rshiftRound64(cast(s64) subSat32(tmp2, cast(s32) rshiftRound64(cast(s64) tmp1 * cast(s64) rcQ31, 31)) * cast(s64) rcMult2, cast(u32) mult2Q)
            if second > 2147483647 or second < -2147483648 do
                return 0
            aQA[k - n - 1] = cast(s32) second
        }

        k -= 1
    }

    if aQA[0] > LpcALimit or aQA[0] < -LpcALimit do
        return 0
    let rcQ31      = -(aQA[0] << (31 - LpcQA))
    let rcMult1Q30 = (1's32 << 30) - smmul(rcQ31, rcQ31)
    invGainQ30 = smmul(invGainQ30, rcMult1Q30) << 2
    if invGainQ30 < MaxPredictionPowerGainQ30 do
        return 0
    return invGainQ30
}

// The SILK decoder of one stream: up to two channels and the mid/side state between them.
internal struct SilkDecoder
{
    channels:             [2] SilkChannel
    apiChannels:          u32
    internalChannels:     u32
    predPrevQ13:          [2] s32
    sMid:                 [2] s16
    sSide:                [2] s16
    prevDecodeOnlyMiddle: bool
    scratch:              [2] Array's16     // Internal-rate output of each channel with the two-sample stereo history.
    resampled:            Array's16         // One channel at 48 kHz.
}

internal impl SilkDecoder
{
    func create(apiChannels: u32)->SilkDecoder
    {
        var result: retval
        result.apiChannels      = apiChannels
        result.internalChannels = 0
        for c in 2
        {
            result.channels[c].reset()
            result.scratch[c].resize(MaxFrameLength + 2)
        }

        result.resampled.resize(6 * MaxFrameLength)
        return result
    }

    mtd reset()
    {
        for c in 2 do
            .channels[c].reset()
        .internalChannels     = 0
        .predPrevQ13[0]       = 0
        .predPrevQ13[1]       = 0
        .sMid[0]              = 0
        .sMid[1]              = 0
        .sSide[0]             = 0
        .sSide[1]             = 0
        .prevDecodeOnlyMiddle = false
    }

    mtd decodeStereoPrediction(dec: *RangeDecoder, predQ13: [*] s32)
    {
        var ix: [2, 3] s32
        let n = cast(s32) dec.decodeIcdf(SilkStereoPredJointIcdf, 8)
        ix[0, 2] = n / 5
        ix[1, 2] = n - 5 * ix[0, 2]
        for c in 2
        {
            ix[c, 0] = cast(s32) dec.decodeIcdf(SilkUniform3Icdf, 8)
            ix[c, 1] = cast(s32) dec.decodeIcdf(SilkUniform5Icdf, 8)
        }

        for c in 2
        {
            ix[c, 0] += 3 * ix[c, 2]
            let low  = cast(s32) SilkStereoPredQuantQ13[cast(u32) ix[c, 0]]
            let step = smulwb(cast(s32) SilkStereoPredQuantQ13[cast(u32) ix[c, 0] + 1] - low, 6554)
            predQ13[c] = smlabb(low, step, 2 * ix[c, 1] + 1)
        }

        predQ13[0] -= predQ13[1]
    }

    // Turns the mid and side signals back into left and right, clause 4.2.8.
    #[Swag.Safety(.Overflow, false)]
    mtd stereoToLeftRight(x1, x2: [*] s16, predQ13: const [*] s32, fsKHz, frameLength: u32)
    {
        x1[0]     = .sMid[0]
        x1[1]     = .sMid[1]
        x2[0]     = .sSide[0]
        x2[1]     = .sSide[1]
        .sMid[0]  = x1[frameLength]
        .sMid[1]  = x1[frameLength + 1]
        .sSide[0] = x2[frameLength]
        .sSide[1] = x2[frameLength + 1]

        var pred0Q13 = .predPrevQ13[0]
        var pred1Q13 = .predPrevQ13[1]
        let interp   = StereoInterpLenMs * fsKHz
        let denomQ16 = (1's32 << 16) / cast(s32) interp
        let delta0   = rshiftRound(smulbb(predQ13[0] - .predPrevQ13[0], denomQ16), 16)
        let delta1   = rshiftRound(smulbb(predQ13[1] - .predPrevQ13[1], denomQ16), 16)
        for n in interp
        {
            pred0Q13 += delta0
            pred1Q13 += delta1
            var sum = ((cast(s32) x1[n] + cast(s32) x1[n + 2] + (cast(s32) x1[n + 1] << 1)) << 9)
            sum       = smlawb(cast(s32) x2[n + 1] << 8, sum, pred0Q13)
            sum       = smlawb(sum, cast(s32) x1[n + 1] << 11, pred1Q13)
            x2[n + 1] = cast(s16) sat16(rshiftRound(sum, 8))
        }

        pred0Q13 = predQ13[0]
        pred1Q13 = predQ13[1]
        for n in interp until frameLength
        {
            var sum = ((cast(s32) x1[n] + cast(s32) x1[n + 2] + (cast(s32) x1[n + 1] << 1)) << 9)
            sum       = smlawb(cast(s32) x2[n + 1] << 8, sum, pred0Q13)
            sum       = smlawb(sum, cast(s32) x1[n + 1] << 11, pred1Q13)
            x2[n + 1] = cast(s16) sat16(rshiftRound(sum, 8))
        }

        .predPrevQ13[0] = predQ13[0]
        .predPrevQ13[1] = predQ13[1]
        for n in frameLength
        {
            let sum  = cast(s32) x1[n + 1] + cast(s32) x2[n + 1]
            let diff = cast(s32) x1[n + 1] - cast(s32) x2[n + 1]
            x1[n + 1] = cast(s16) sat16(sum)
            x2[n + 1] = cast(s16) sat16(diff)
        }
    }

    // Decodes one SILK frame of every internal channel and writes it upsampled to 48 kHz,
    // interleaved over the API channels; returns the 48 kHz sample count.
    mtd decode(dec: *RangeDecoder, newPacket: bool, payloadMs: u32, internalRate: u32, internalChannels: u32, out: [*] s16)->u32 fail
    {
        if newPacket
        {
            for n in internalChannels do
                .channels[n].nFramesDecoded = 0
        }

        if internalChannels > .internalChannels do
            .channels[1].reset()

        if .channels[0].nFramesDecoded == 0
        {
            for n in internalChannels
            {
                var channel = &.channels[n]
                switch payloadMs
                {
                case 10:
                    channel.nFramesPerPacket = 1
                    channel.nbSubfr          = 2

                case 20:
                    channel.nFramesPerPacket = 1
                    channel.nbSubfr          = 4

                case 40:
                    channel.nFramesPerPacket = 2
                    channel.nbSubfr          = 4

                case 60:
                    channel.nFramesPerPacket = 3
                    channel.nbSubfr          = 4

                default:
                    fail InvalidFormatError{"Opus SILK frame size is not one the layer supports"}
                }

                let fsKHz = (internalRate >> 10) + 1
                if fsKHz != 8 and fsKHz != 12 and fsKHz != 16 do
                    fail InvalidFormatError{"Opus SILK sampling rate is not one the layer supports"}
                channel.setSampleRate(fsKHz)
            }
        }

        if .apiChannels == 2 and internalChannels == 2 and (.apiChannels != 2 or .internalChannels == 1)
        {
            .predPrevQ13[0]        = 0
            .predPrevQ13[1]        = 0
            .sSide[0]              = 0
            .sSide[1]              = 0
            .channels[1].resampler = .channels[0].resampler
        }

        .internalChannels = internalChannels

        var decodeOnlyMiddle = false
        var predQ13: [2] s32
        if .channels[0].nFramesDecoded == 0
        {
            for n in internalChannels
            {
                var channel = &.channels[n]
                for i in channel.nFramesPerPacket do
                    channel.vadFlags[i] = dec.decodeBit(1)
                channel.lbrrFlag = dec.decodeBit(1)
            }

            for n in internalChannels
            {
                var channel = &.channels[n]
                for i in 3 do
                    channel.lbrrFlags[i] = false
                if channel.lbrrFlag
                {
                    if channel.nFramesPerPacket == 1 do
                        channel.lbrrFlags[0] = true
                    else
                    {
                        let symbol = (channel.nFramesPerPacket == 2 ? dec.decodeIcdf(SilkLbrrFlags2Icdf, 8) : dec.decodeIcdf(SilkLbrrFlags3Icdf, 8)) + 1
                        for i in channel.nFramesPerPacket do
                            channel.lbrrFlags[i] = ((symbol >> i) & 1) != 0
                    }
                }
            }

            // Redundant copies of earlier frames are read to stay in step with the coder, and
            // otherwise discarded: nothing was lost.
            for i in .channels[0].nFramesPerPacket
            {
                for n in internalChannels
                {
                    var channel = &.channels[n]
                    if channel.lbrrFlags[i]
                    {
                        var pulses: [MaxFrameLength] s32
                        if internalChannels == 2 and n == 0
                        {
                            .decodeStereoPrediction(dec, &predQ13[0])
                            if !.channels[1].lbrrFlags[i] do
                                discard dec.decodeIcdf(SilkStereoOnlyCodeMidIcdf, 8)
                        }

                        let condCoding = i > 0 and channel.lbrrFlags[i - 1] ? CodeConditionally : CodeIndependently
                        channel.decodeIndices(dec, i, true, condCoding)
                        decodeSilkPulses(dec, &pulses[0], channel.indices.signalType, channel.indices.quantOffsetType, channel.frameLength)
                    }
                }
            }
        }

        if internalChannels == 2
        {
            .decodeStereoPrediction(dec, &predQ13[0])
            if !.channels[1].vadFlags[.channels[0].nFramesDecoded] do
                decodeOnlyMiddle = dec.decodeIcdf(SilkStereoOnlyCodeMidIcdf, 8) != 0
        }

        if internalChannels == 2 and !decodeOnlyMiddle and .prevDecodeOnlyMiddle
        {
            var side = &.channels[1]
            Memory.set(&side.outBuf, 0, #sizeof(side.outBuf))
            Memory.set(&side.lpcStateQ14, 0, #sizeof(side.lpcStateQ14))
            side.lagPrev              = 100
            side.lastGainIndex        = 10
            side.prevSignalType       = TypeNoVoiceActivity
            side.firstFrameAfterReset = true
        }

        let frameLength = .channels[0].frameLength
        let hasSide     = !decodeOnlyMiddle
        for n in internalChannels
        {
            let target = .scratch[n].buffer! + 2
            if n == 0 or hasSide
            {
                var condCoding = CodeConditionally
                let frameIndex = cast(s32) .channels[0].nFramesDecoded - cast(s32) n
                if frameIndex <= 0 do
                    condCoding = CodeIndependently
                elif n > 0 and .prevDecodeOnlyMiddle do
                    condCoding = CodeIndependentlyNoLtpScaling
                .channels[n].decodeFrame(dec, target, condCoding)
            }
            else
            {
                for i in frameLength do
                    target[i] = 0
            }

            .channels[n].nFramesDecoded += 1
        }

        let left  = .scratch[0].buffer!
        let right = .scratch[1].buffer!
        if .apiChannels == 2 and internalChannels == 2 do
            .stereoToLeftRight(left, right, &predQ13[0], .channels[0].fsKHz, frameLength)
        else
        {
            left[0]  = .sMid[0]
            left[1]  = .sMid[1]
            .sMid[0] = left[frameLength]
            .sMid[1] = left[frameLength + 1]
        }

        // Every channel goes through its own resampler to 48 kHz; a mono stream on a stereo
        // output plays on both sides.
        let outSamples = frameLength * OutputRate / (.channels[0].fsKHz * 1000)
        let resampled  = .resampled.buffer!
        for n in Math.min(.apiChannels, internalChannels)
        {
            let source = .scratch[n].buffer! + 1
            let count  = .channels[n].resampler.process(resampled, source, frameLength)
            if count != outSamples do
                fail InvalidFormatError{"Opus SILK resampler produced an unexpected sample count"}
            if .apiChannels == 2
            {
                for i in outSamples do
                    out[n + 2 * i] = resampled[i]
            }
            else
            {
                for i in outSamples do
                    out[i] = resampled[i]
            }
        }

        if .apiChannels == 2 and internalChannels == 1
        {
            for i in outSamples do
                out[1 + 2 * i] = out[2 * i]
        }

        .prevDecodeOnlyMiddle = decodeOnlyMiddle
        return outSamples
    }
}
