//! Format: MPEG-4 AAC Low Complexity software encoder.
//! Supported: 1024-sample long-window mono/stereo PCM16 at 44.1 or 48 kHz, in full or voice band.
//! Role: This file turns non-silent capture PCM into AAC access units without a runtime codec dependency.
//
#global namespace Aac
#global export

using Core, Core.Errors, Core.Math

private const EncoderFrames     = 1_024'u64
private const VoiceLines        = 176'u64
private const VoiceBands        = 23'u64
private const FullLines         = 1_024'u64
private const FullBands         = 49'u64
private const MaximumBandBoost  = 48's32
private const ShortLines        = EncoderFrames / 8
private const ShortLead         = (EncoderFrames - ShortLines) / 2
private const MaximumShortBands = 8 * 16

// AAC spectral pairs use at most 16 bits. Four bytes per band cover its
// section and scalefactor. The remaining space covers the fixed headers.
private const MaximumPacketBytes = 2 * (FullLines + 4 * MaximumShortBands + 32)

private func buildShortWindow()->[2 * ShortLines] f32
{
    var result: [2 * ShortLines] f32
    for sample in result.count do
        result[sample] = cast(f32, Math.sin(Math.ConstF64.Pi / result.count * (cast(f64, sample) + 0.5)))
    return result
}

private const ShortWindow = #run buildShortWindow()

internal enum EncodeWindow
{
    Long
    Start
    Short
    Stop
}

private const MaxMagnitude     = 15
private const SignedMagnitudes = 2 * MaxMagnitude + 1
private alias SpectralPairCodes = [SignedMagnitudes, SignedMagnitudes] u32

private func buildSpectralPairCodes()->SpectralPairCodes
{
    var entries: SpectralPairCodes
    let codes  = specCodes(10)
    let widths = specBits(10)
    for left in SignedMagnitudes
    {
        let first = cast(s32, left) - MaxMagnitude
        for right in SignedMagnitudes
        {
            let second = cast(s32, right) - MaxMagnitude
            let symbol = Math.abs(first) * 17 + Math.abs(second)
            var code   = cast(u32, codes[symbol])
            var width  = cast(u32, widths[symbol])
            if first
            {
                code  = (code << 1) | cast(u32, first < 0)
                width += 1
            }

            if second
            {
                code  = (code << 1) | cast(u32, second < 0)
                width += 1
            }

            Swag.require(width <= 16)
            entries[left, right] = (width << 16) | code
        }
    }

    return entries
}

// Book 11 puts the sign bits after the Huffman word, in coefficient order.
private const PackedSpectralPairs = #run buildSpectralPairCodes()

private const QuantizationGains = 256
private alias MagnitudeThresholds = [QuantizationGains, MaxMagnitude + 1] u32

// Each entry is the first positive binary32 MDCT coefficient that rounds to
// the requested AAC magnitude. The codec scales the coefficient by two.
private func buildMagnitudeThresholds()->MagnitudeThresholds
{
    func referenceMagnitude(bits: u32, factor: f64)->f64
    {
        let value = cast(f64, cast #bit(f32, bits)) * 2.0 / factor
        return Math.round(Math.pow(value, 0.75))
    }

    var thresholds: MagnitudeThresholds
    for magnitude in 1 until MaxMagnitude + 1
    {
        let midpoint = Math.pow(cast(f64, magnitude) - 0.5, 4.0 / 3.0)
        for scale in QuantizationGains
        {
            let factor   = Math.pow(2.0, 0.25 * (cast(f64, scale) - 100))
            var boundary = cast #bit(u32, cast(f32, midpoint * factor * 0.5))
            while referenceMagnitude(boundary, factor) < magnitude do
                boundary += 1
            while referenceMagnitude(boundary - 1, factor) >= magnitude do
                boundary -= 1
            thresholds[scale, magnitude] = boundary
        }
    }

    return thresholds
}

private var g_FirstMagnitude: MagnitudeThresholds = #run buildMagnitudeThresholds()

// Score the distortion and spectral cost of these increases in AAC gain units.
private const PeakMantissaMask = 0x007F_FFFF'u32
private const PeakGainAtOne    = 84's32

private func peakGainReference(peak: f32)->s32
{
    let limit = Math.pow(15.0'f64, 4.0'f64 / 3.0)
    return cast(s32, Math.ceil(100.0 + 4.0 * Math.log2(2.0 * cast(f64, peak) / limit)))
}

private func buildPeakGainCuts()->[4] u32
{
    let limit = Math.pow(15.0'f64, 4.0'f64 / 3.0)
    var cuts: [4] u32
    for step in cuts.count
    {
        let gain     = PeakGainAtOne + cast(s32, step)
        let boundary = (0.5 * limit) * Math.pow(2.0, (cast(f64, gain) - 100.0) / 4.0)
        var bits     = cast #bit(u32, cast(f32, boundary))
        while peakGainReference(cast #bit(f32, bits)) <= gain do
            bits += 1
        while peakGainReference(cast #bit(f32, bits - 1)) > gain do
            bits -= 1
        cuts[step] = bits & PeakMantissaMask
    }

    return cuts
}

private const PeakGainCuts = #run buildPeakGainCuts()

#[Swag.Inline]
private func gainForPeak(peak: f32)->s32
{
    if not peak do
        return 100
    let bits     = cast #bit(u32, peak)
    let exponent = cast(s32, bits >> 23) - 127
    let mantissa = bits & PeakMantissaMask
    let fraction = cast(s32, mantissa >= PeakGainCuts[0]) + cast(s32, mantissa >= PeakGainCuts[1]) +
                   cast(s32, mantissa >= PeakGainCuts[2]) + cast(s32, mantissa >= PeakGainCuts[3])
    return Math.clamp(PeakGainAtOne + 4 * exponent + fraction, 0, 255)
}

private const RateGainSteps   = [0's32, 2, 4, 8, 12, 20]
private const RateChoiceCount = RateGainSteps.count + 1
private alias RateGains = [2, FullBands] s32

private struct RateChoice
{
    gain:       s32
    bits:       u32
    distortion: f64
}

private alias RateChoices = [2, FullBands, RateChoiceCount] RateChoice

private func buildReconstructedMagnitudes()->[QuantizationGains, MaxMagnitude + 1] f32
{
    var powers: [MaxMagnitude + 1] f64
    for magnitude in powers.count do
        powers[magnitude] = Math.pow(cast(f64, magnitude), 4.0 / 3.0)
    var values: [QuantizationGains, MaxMagnitude + 1] f32
    for gain in QuantizationGains
    {
        let scale = Math.pow(2.0, 0.25 * (cast(f64, gain) - 100.0))
        for magnitude in powers.count do
            values[gain, magnitude] = cast(f32, powers[magnitude] * scale)
    }

    return values
}

private var g_ReconstructedMagnitudes: [QuantizationGains, MaxMagnitude + 1] f32 = #run buildReconstructedMagnitudes()

#[Swag.Inline]
private func rateMagnitude(absolute: u32, thresholds: const [*] u32)->s32
{
    var magnitude = 8 * cast(s32, absolute >= thresholds[8])
    magnitude += 4 * cast(s32, absolute >= thresholds[magnitude + 4])
    magnitude += 2 * cast(s32, absolute >= thresholds[magnitude + 2])
    magnitude += cast(s32, absolute >= thresholds[magnitude + 1])
    return magnitude
}

internal struct EncoderSectionCode
{
    value: u32
    width: u32
}

// Plans AAC long-window section codewords, including the 31-band escape.
internal func planEncoderSections(active: const [..] bool,
                                  codes: [..] EncoderSectionCode)->u32
{
    return planSections(active, codes, 5)
}

private func planSections(active: const [..] bool, codes: [..] EncoderSectionCode, lengthBits: u32)->u32
{
    Swag.assert(codes.count >= active.count * 2)
    var count = 0_u32
    var band  = 0_u64
    while band < active.count
    {
        let book = active[band] ? 11_u32 : 0_u32
        var next = band + 1
        while next < active.count and active[next] == active[band]
        {
            next += 1
        }

        codes[count] = {book, 4}
        count        += 1
        var length = next - band
        while length >= escape
        {
            codes[count] = {escape, lengthBits}
            count        += 1
            length       -= escape
        }

        codes[count] = {cast(u32, length), lengthBits}
        count        += 1
        band         = next
    }

    return count
}

// Selects the MDCT bandwidth of the software AAC encoder.
enum Bandwidth
{
    // Encodes all 1024 spectral lines up to the Nyquist frequency.
    Full

    // Keeps 176 lines for speech and smaller packets, ending near 4 kHz.
    Voice
}

// Encodes interleaved PCM16 into bounded AAC-LC access units.
//
// The full profile encodes all 1024 MDCT lines; the voice profile keeps 176 lines, ending near
// 4 kHz. Both use long sine windows, independent channels and bounded per-band scalefactors,
// without transient window switching.
// Each call accepts exactly 1024 frames and replaces `packet` with one raw access unit. The
// encoder holds the previous input block for AAC overlap; the caller supplies timestamps.
#[Swag.NoCopy]
struct Encoder
{
    private
    {
        transform:  Mdct
        window:     [2 * EncoderFrames] f32
        previous:   [2, 1_024] s16
        silent:     SilenceEncoder
        config:     [2] u8
        channels:   u16
        sampleRate: u32
        lineCount:  u64
        bandCount:  u64
        bitCount:   u64
        output:     Array!{u8}
    }
}

impl Encoder
{
    // Creates a full-band or voice-band software encoder for mono or stereo PCM16.
    func create(sampleRate: u32, channels: u16, bandwidth: Bandwidth = .Full)->Encoder fail
    {
        let silence = try SilenceEncoder.create(sampleRate, channels)
        if sampleRate != 44_100 and sampleRate != 48_000
        {
            fail BadParameterError{"AAC software encoder supports 44.1 and 48 kHz"}
        }

        var result: #returntype
        result.channels   = channels
        result.sampleRate = sampleRate
        result.lineCount  = bandwidth == .Voice ? VoiceLines : FullLines
        result.bandCount  = bandwidth == .Voice ? VoiceBands : FullBands
        result.silent     = silence
        Memory.copy(&result.config[0], silence.decoderConfig().buffer, 2)
        result.transform = Mdct.create(2 * cast(u32, EncoderFrames))
        for sample in 2 * EncoderFrames
        {
            result.window[sample] = cast(f32, Math.sin(Math.ConstF64.Pi / (2 * EncoderFrames) * (cast(f64, sample) + 0.5)))
        }

        return result
    }

    // Returns the two-byte AAC-LC AudioSpecificConfig.
    mtd const decoderConfig()->const [..] u8 => Swag.makeSlice(&.config[0], 2)

    // Returns the input and output frame count of each packet.
    mtd const packetFrames()->u32 => 1_024

    // Returns the configured channel count.
    mtd const channelCount()->u16 => .channels

    // Returns the configured sample rate in frames per second.
    mtd const sampleRateHz()->u32 => .sampleRate

    // Returns the approximate upper frequency retained by the selected MDCT band.
    mtd const upperFrequencyHz()->u32 => cast(u32, .lineCount * .sampleRate / (2 * EncoderFrames))

    // Encodes exactly 1024 interleaved PCM16 frames into one raw AAC-LC access unit.
    //
    // An invalid input count leaves the encoder state unchanged. `packet` may be reused by the
    // caller and is cleared before encoding. Do not alias it with internal encoder storage.
    mtd encode(samples: const [..] s16, packet: *Array!{u8}) fail
    {
        if samples.count != EncoderFrames * .channels
        {
            fail BadParameterError{"AAC software encoder needs exactly 1024 complete sample frames"}
        }

        packet.clear()
        var allZero = true
        for sample in samples where sample != 0
        {
            allZero = false
            break
        }

        if allZero
        {
            for channel in .channels
            {
                for sample in EncoderFrames where .previous[channel, sample] != 0
                {
                    allZero = false
                    break
                }

                if not allZero
                {
                    break
                }
            }
        }

        if allZero and (not Adaptive or sequence == .Long)
        {
            packet.add(.silent.packet())
            return
        }

        .wordCount   = 0
        .bitWord     = 0
        .pendingBits = 0
        if .channels == 2
        {
            .writeBits(1, 3)     // Channel pair element.
            .writeBits(0, 4)     // Element tag.
            .writeBits(0, 1)     // Independent channel windows.
        }
        else
        {
            .writeBits(0, 3)     // Single channel element.
            .writeBits(0, 4)
        }

        let rateIndex   = .sampleRate == 48_000 ? 3_u32 : 4_u32
        let isShort     = Adaptive and sequence == .Short
        let offsets     = isShort ? swbShort(rateIndex) : swbLong(rateIndex)
        let lineStride  = isShort ? ShortLines : EncoderFrames
        let windowCount = isShort ? 8_u64 : 1_u64
        var bandCount   = .bandCount
        if isShort
        {
            bandCount = offsets.count - 1
            while offsets[bandCount] > .lineCount / 8
            {
                bandCount -= 1
            }
        }

        for channel in .channels
        {
            var transformed: [FullLines] f32
            .transform.forward(&windowed[0], &transformed[0])
            var spectrum: [FullLines] f64
            var largest = 0.0_f64
            for line in .lineCount
            {
                let start = group * lineStride
                for band in bandCount
                {
                    let first = cast(const [*] f32, &transformed[start + offsets[band]])
                    let width = cast(u64, offsets[band + 1] - offsets[band])
                    var lanes = Simd.splat(0_f32)
                    for index in width / 4
                    {
                        let values = Math.abs(Simd.load(first + 4 * index))
                        lanes = Simd.select(values > lanes, values, lanes)
                    }

                    let peak = Simd.maximum(lanes)
                    peaks[group * bandCount + band] = peak
                    maximum = Math.max(maximum, peak)
                }
            }

            let largest = 2.0 * cast(f64, maximum)
            let gain    = gainForPeak(maximum)
            var quantized: [FullLines] s32
            var active:    [FullBands] bool
            var bandGain:  [FullBands] s32
            let rateIndex = .sampleRate == 48_000 ? 3_u32 : 4_u32
            let offsets   = swbLong(rateIndex)

            // Keep each band's quiet components above the global quantization floor. AAC
            // codes scalefactor differences in [-60, 60]; limiting the boost to 48 steps
            // also bounds every jump between active bands without extra side information.
            let minimumGain = Math.max(0_s32, gain - MaximumBandBoost)
            for band in .bandCount
            {
                var bandPeak = 0.0_f64
                for line in offsets[band] until offsets[band + 1]
                {
                    bandPeak = Math.max(bandPeak, Math.abs(spectrum[line]))
                }

                    // Ignore far-off leakage and numerical residue around a strong tone.
                    // A component 150x below the strongest band remains eligible.
                    if bandPeak >= largest / 512.0 and bandPeak > 0 do
                        selected = Math.clamp(gainForPeak(peaks[band]), minimumGain, gain)

                // Ignore far-off leakage and numerical residue around a strong tone.
                // A component 150x below the strongest band remains eligible.
                if bandPeak >= largest / 512.0 and bandPeak > 0
                {
                    selected = Math.clamp(cast(s32,
                                               Math.ceil(100.0 + 4.0 *
                                                         Math.log2(bandPeak / Math.pow(15.0_f64, 4.0_f64 / 3.0)))),
                                          minimumGain,
                                          gain)
                }

                bandGain[band] = selected
                let factor = Math.pow(2.0, 0.25 * cast(f64, selected - 100))
                for line in offsets[band] until offsets[band + 1]
                {
                    let value     = spectrum[line]
                    let magnitude = Math.min(15_s32, cast(s32, Math.round(Math.pow(Math.abs(value) / factor, 0.75))))
                    quantized[line] = value < 0 ? -magnitude : magnitude
                    if magnitude
                    {
                        active[band] = true
                    }
                }
            }

            .writeBits(cast(u32, gain), 8)
            .writeBits(0, 1)     // Reserved ICS bit.
            .writeBits(cast(u32, sequence), 2)
            .writeBits(0, 1)     // Sine window.
            if isShort
            {
                .writeBits(cast(u32, bandCount), 4)
                .writeBits(0, 7)     // Each short window keeps its own scalefactors.
            }
            else
            {
                .writeBits(cast(u32, bandCount), 6)
                .writeBits(0, 1)     // No predictor.
            }

            var sectionCodes: [2 * FullBands] EncoderSectionCode
            let sectionCount = planEncoderSections(Swag.makeSlice(&active[0], .bandCount),
                                                   Swag.makeSlice(&sectionCodes[0], sectionCodes.count))
            for index in sectionCount
            {
                .writeBits(sectionCodes[index].value, sectionCodes[index].width)
            }

            var previousGain = gain
            for band in windowCount * bandCount where active[band]
            {
                let difference = cast(u64, 60 + bandGain[band] - previousGain)
                .writeBits(ScfCodes[difference], ScfBits[difference])
                previousGain = bandGain[band]
            }

            .writeBits(0, 1)     // No pulse data.
            .writeBits(0, 1)     // No TNS.
            .writeBits(0, 1)     // No gain control.
            for group in windowCount
            {
                let base = group * lineStride
                for band in bandCount where active[group * bandCount + band]
                {
                    let first  = quantized[line]
                    let second = quantized[line + 1]
                    let symbol = cast(u64, Math.abs(first) * 17 + Math.abs(second))
                    .writeBits(codes[symbol], bits[symbol])
                    if first
                    {
                        .writeBits(first < 0 ? 1 : 0, 1)
                    }

                    if second
                    {
                        .writeBits(second < 0 ? 1 : 0, 1)
                    }

                    line += 2
                }
            }

            for sample in EncoderFrames
            {
                .previous[channel, sample] = samples[sample * .channels + channel]
            }
        }

        .writeBits(7, 3)     // End element.
        let output = Swag.makeSlice(cast([*] u8, &.output[0]), MaximumPacketBytes)
        var size   = .wordCount * #sizeof(u32)
        while .pendingBits >= 8
        {
            .pendingBits -= 8
            output[size] = cast(u8, (.bitWord >> .pendingBits) & 255)
            size         += 1
        }

        if .pendingBits
        {
            output[size] = cast(u8, (.bitWord << (8 - .pendingBits)) & 255)
            size         += 1
        }

        packet.add(output[until size])
    }
}

private impl Encoder
{
    mtd const prepareRateChoices(spectra: const *[2, FullLines] f32, choices: *RateChoices, initialGain: *[2] s32)->f64
    {
        let offsets   = swbLong(.sampleRate == 48_000 ? 3_u32 : 4_u32)
        var strongest = 0_f64
        for channel in .channels
        {
            let spectrum = cast(const [*] f32, &spectra[][channel, 0])
            var peaks: [FullBands] f64
            var largest  = 0_f64
            for band in .bandCount
            {
                var peak = 0_f32
                for line in offsets[band] until offsets[band + 1]
                {
                    peak = Math.max(peak, Math.abs(spectrum[line]))
                }

                peaks[band] = 2.0 * cast(f64, peak)
                largest     = Math.max(largest, peaks[band])
            }

            let globalGain = gainForPeak(cast(f32, largest * 0.5))
            initialGain[][channel] = globalGain
            let minimumGain = Math.max(0_s32, globalGain - MaximumBandBoost)

            // The total 60-step range keeps every scalefactor difference representable.
            let maximumGain = Math.min(255_s32, globalGain + 12)
            for band in .bandCount
            {
                let first    = cast(u64, offsets[band])
                let end      = cast(u64, offsets[band + 1])
                let peak     = peaks[band]
                var selected = globalGain
                if peak >= largest / 512.0 and peak > 0 do
                    selected = Math.clamp(gainForPeak(cast(f32, peak * 0.5)), minimumGain, globalGain)

                var energy = 0_f64
                for line in first until end
                {
                    let value = 2.0 * cast(f64, spectrum[line])
                    energy += value * value
                }

                strongest = Math.max(strongest, energy)
                let mute: RateChoice = {-1, 0, energy}
                var previousGain     = -1_s32
                for step in RateGainSteps.count
                {
                    let gain = Math.clamp(selected + RateGainSteps[step], minimumGain, maximumGain)
                    if gain == previousGain
                    {
                        choices[][channel, band, step] = choices[][channel, band, step - 1]
                        continue
                    }

                    previousGain = gain
                    let thresholds = cast(const [*] u32, &g_FirstMagnitude[gain, 0])
                    let peakBits   = cast #bit(u32, cast(f32, peak * 0.5))
                    if peakBits < thresholds[1]
                    {
                        for rest in step until RateGainSteps.count
                        {
                            choices[][channel, band, rest] = mute
                        }

                        break
                    }

                    let reconstructed = cast(const [*] f32, &g_ReconstructedMagnitudes[gain, 0])
                    var distortion    = 0_f64
                    var codedBits     = 0_u32
                    for pair in first / 2 until end / 2
                    {
                        let a  = Math.abs(spectrum[pair * 2])
                        let b  = Math.abs(spectrum[pair * 2 + 1])
                        let qa = rateMagnitude(cast #bit(u32, a), thresholds)
                        let qb = rateMagnitude(cast #bit(u32, b), thresholds)
                        let ea = 2.0 * cast(f64, a) - cast(f64, reconstructed[qa])
                        let eb = 2.0 * cast(f64, b) - cast(f64, reconstructed[qb])
                        distortion += ea * ea + eb * eb
                        codedBits  += PackedSpectralPairs[qa + MaxMagnitude, qb + MaxMagnitude] >> 16
                    }

                    choices[][channel, band, step] = {gain, codedBits, distortion}
                }

                choices[][channel, band, RateGainSteps.count] = mute
            }
        }

        return strongest
    }

    mtd const chooseRateGains(choices: const *RateChoices,
                              initialGain: const *[2] s32,
                              reference: f64,
                              level: s32,
                              selected: *RateGains)->u64
    {
        // Rank each gain by spectral error plus an approximate bit cost.
        // Count the resulting packet with its exact section lengths and scalefactors.
        let price    = reference * Math.pow(2.0, -0.25 * cast(f64, level))
        var bitCount = .channels == 2 ? 8_u64 : 7_u64
        for channel in .channels
        {
            bitCount += 22     // Global gain, window information and tool flags.
            var previousGain  = initialGain[][channel]
            var sectionStart  = 0_u64
            var sectionActive = false
            for band in .bandCount
            {
                var best     = choices[][channel, band, RateGainSteps.count].distortion
                var gain     = -1_s32
                var spectral = 0_u32
                for step in RateGainSteps.count
                {
                    let option = &choices[][channel, band, step]
                    if option.gain >= 0
                    {
                        let cost = option.distortion + price * cast(f64, option.bits + 8)
                        if cost < best
                        {
                            best     = cost
                            gain     = option.gain
                            spectral = option.bits
                        }
                    }
                }

                selected[][channel, band] = gain
                let active = gain >= 0
                if active
                {
                    bitCount     += spectral + ScfBits[60 + gain - previousGain]
                    previousGain = gain
                }

                if not band
                {
                    sectionActive = active
                }
                else if active != sectionActive
                {
                    bitCount      += 9 + 5 * ((band - sectionStart) / 31)
                    sectionStart  = band
                    sectionActive = active
                }
            }

            bitCount += 9 + 5 * ((.bandCount - sectionStart) / 31)
        }

        return (bitCount + 3 + 7) / 8     // End element and byte padding.
    }

    mtd(Adaptive: bool) transformChannel(samples: const [..] s16, channel: u64, sequence: EncodeWindow, transformed: [*] f32)
    {
        if Adaptive and sequence == .Short
        {
            var windowed: [2 * ShortLines] f32
            for window in 8
            {
                let start = ShortLead + window * ShortLines
                for sample in 2 * ShortLines
                {
                    let index = start + sample
                    let value = index < EncoderFrames ? .previous[channel, index] :
                                samples[(index - EncoderFrames) * .channels + channel]
                    windowed[sample] = value * ShortWindow[sample]
                }

                .shortTransform.forward(&windowed[0], transformed + window * ShortLines)
            }

            return
        }

        var windowed: [2 * EncoderFrames] f32
        for sample in EncoderFrames
        {
            let first  = .previous[channel, sample]
            let second = samples[sample * .channels + channel]
            windowed[sample] = first * .window[sample]
            windowed[EncoderFrames + sample] = second * .window[EncoderFrames + sample]
        }

        if Adaptive and sequence == .Start
        {
            for sample in ShortLead
            {
                windowed[EncoderFrames + sample] = cast(f32, samples[sample * .channels + channel])
            }

            for sample in ShortLines
            {
                windowed[EncoderFrames + ShortLead + sample] = samples[(ShortLead + sample) * .channels + channel] * ShortWindow[ShortLines + sample]
            }

            for sample in EncoderFrames + ShortLead + ShortLines until 2 * EncoderFrames
            {
                windowed[sample] = 0
            }
        }
        else if Adaptive and sequence == .Stop
        {
            for sample in ShortLead
            {
                windowed[sample] = 0
            }

            for sample in ShortLines
            {
                windowed[ShortLead + sample] = .previous[channel, ShortLead + sample] * ShortWindow[sample]
            }

            for sample in ShortLead + ShortLines until EncoderFrames
            {
                windowed[sample] = cast(f32, .previous[channel, sample])
            }
        }

        .transform.forward(&windowed[0], transformed)
    }

    mtd writeBits(value: u32, count: u32)
    {
        // At most 31 bits are pending before a codeword of at most 19 bits.
        .bitWord     = (.bitWord << count) | value
        .pendingBits += count
        if .pendingBits < 32
        {
            return
        }

        .pendingBits -= 32
        let next = cast(u32, (.bitWord >> .pendingBits) & 0xFFFF_FFFF)
        .output[.wordCount] = Math.nativeToBigEndian(next)
        .wordCount += 1
    }
}

#test
{
    for scale in QuantizationGains
    {
        let factor = Math.pow(2.0, 0.25 * (cast(f64, scale) - 100.0))
        for magnitude in 1 until MaxMagnitude + 1
        {
            if .bitCount == .output.count * 8
            {
                .output.add(0_u8)
            }

            .output[.bitCount >> 3] |= cast(u8,
                                            ((value >> (count - index - 1)) & 1) <<
                                            (7 - cast(u32, .bitCount & 7)))
            .bitCount += 1
        }
    }
}

// A power-of-two change in the positive peak shifts the AAC gain by four.
#test
{
    Swag.require(gainForPeak(0.0) == 100)
    Swag.require(gainForPeak(cast #bit(f32, 1'u32)) == 0)
    for biasedExponent in 1 until 255
    {
        for cut in PeakGainCuts
        {
            let bits  = (cast(u32, biasedExponent) << 23) | cut
            let lower = cast #bit(f32, bits - 1)
            let upper = cast #bit(f32, bits)
            Swag.require(gainForPeak(lower) == Math.clamp(peakGainReference(lower), 0, 255))
            Swag.require(gainForPeak(upper) == Math.clamp(peakGainReference(upper), 0, 255))
        }
    }
}
