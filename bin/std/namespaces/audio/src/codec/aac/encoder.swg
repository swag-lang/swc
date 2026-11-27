//! Format: MPEG-4 AAC Low Complexity software encoder.
//! Supported: 1024-sample long-window mono/stereo PCM16 at 44.1 or 48 kHz, in full or voice band.
//! Role: This file turns non-silent capture PCM into AAC access units without a runtime codec dependency.
//
#global namespace Aac
#global public

using Core, Core.Errors, Core.Math

private const EncoderFrames     = 1_024_u64
private const VoiceLines        = 176_u64
private const VoiceBands        = 23_u64
private const FullLines         = 1_024_u64
private const FullBands         = 49_u64
private const MaximumBandBoost  = 48_s32
private const ShortLines        = EncoderFrames / 8
private const ShortLead         = (EncoderFrames - ShortLines) / 2
private const MaximumShortBands = 8 * 16

// AAC spectral pairs use at most 16 bits. Four bytes per band cover its
// section and scalefactor. The remaining space covers the fixed headers.
private const MaximumPacketBytes = 2 * (FullLines + 4 * MaximumShortBands + 32)

private func buildShortWindow()->[2 * ShortLines] f32
{
    var result: [2 * ShortLines] f32
    for sample in result.count
    {
        result[sample] = cast(f32, Math.sin(Math.ConstF64.Pi / result.count * (cast(f64, sample) + 0.5)))
    }

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

private func buildRateSpectralWidths()->[MaxMagnitude + 1, MaxMagnitude + 1] u32
{
    var widths: #returntype
    for first in MaxMagnitude + 1
    {
        for second in MaxMagnitude + 1
        {
            widths[first, second] = PackedSpectralPairs[first + MaxMagnitude, second + MaxMagnitude] >> 16
        }
    }

    return widths
}

private const RateSpectralWidths = #run buildRateSpectralWidths()

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
            while referenceMagnitude(boundary, factor) < magnitude
            {
                boundary += 1
            }

            while referenceMagnitude(boundary - 1, factor) >= magnitude
            {
                boundary -= 1
            }

            thresholds[scale, magnitude] = boundary
        }
    }

    return thresholds
}

private var g_FirstMagnitude: MagnitudeThresholds = #run buildMagnitudeThresholds()

// Score the distortion and spectral cost of these increases in AAC gain units.
private const PeakMantissaMask = 0x007F_FFFF_u32
private const PeakGainAtOne    = 84_s32

private func peakGainReference(peak: f32)->s32
{
    let limit = Math.pow(15.0_f64, 4.0_f64 / 3.0)
    return cast(s32, Math.ceil(100.0 + 4.0 * Math.log2(2.0 * cast(f64, peak) / limit)))
}

private func buildPeakGainCuts()->[4] u32
{
    let limit = Math.pow(15.0_f64, 4.0_f64 / 3.0)
    var cuts: [4] u32
    for step in cuts.count
    {
        let gain     = PeakGainAtOne + cast(s32, step)
        let boundary = (0.5 * limit) * Math.pow(2.0, (cast(f64, gain) - 100.0) / 4.0)
        var bits     = cast #bit(u32, cast(f32, boundary))
        while peakGainReference(cast #bit(f32, bits)) <= gain
        {
            bits += 1
        }

        while peakGainReference(cast #bit(f32, bits - 1)) > gain
        {
            bits -= 1
        }

        cuts[step] = bits & PeakMantissaMask
    }

    return cuts
}

private const PeakGainCuts = #run buildPeakGainCuts()

#[Swag.Inline]
private func gainForPeak(peak: f32)->s32
{
    if not peak
    {
        return 100
    }

    let bits     = cast #bit(u32, peak)
    let exponent = cast(s32, bits >> 23) - 127
    let mantissa = bits & PeakMantissaMask
    let fraction = cast(s32, mantissa >= PeakGainCuts[0]) + cast(s32, mantissa >= PeakGainCuts[1]) +
                   cast(s32, mantissa >= PeakGainCuts[2]) + cast(s32, mantissa >= PeakGainCuts[3])
    return Math.clamp(PeakGainAtOne + 4 * exponent + fraction, 0, 255)
}

private const RateGainSteps   = [0_s32, 2, 4, 8, 12, 20]
private const RateChoiceCount = RateGainSteps.count + 1

private struct RateSpectrum
{
    coefficients: [FullLines] f32
    peaks:        [FullBands] f32
    peak:         f32
}

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
    for magnitude in powers.count
    {
        powers[magnitude] = Math.pow(cast(f64, magnitude), 4.0 / 3.0)
    }

    var values: [QuantizationGains, MaxMagnitude + 1] f32
    for gain in QuantizationGains
    {
        let scale = Math.pow(2.0, 0.25 * (cast(f64, gain) - 100.0))
        for magnitude in powers.count
        {
            values[gain, magnitude] = cast(f32, powers[magnitude] * scale)
        }
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
    let escape = (1_u32 << lengthBits) - 1
    var count  = 0_u32
    var band   = 0_u64
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
        transform:      Mdct
        shortTransform: Mdct
        window:         [2 * EncoderFrames] f32
        previous:       [2, 1_024] s16
        silent:         SilenceEncoder
        config:         [2] u8
        channels:       u16
        sampleRate:     u32
        lineCount:      u64
        bandCount:      u64
        bitWord:        u64
        pendingBits:    u32
        wordCount:      u64
        output:         [MaximumPacketBytes / #sizeof(u32)] u32
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
        try .encodeWindowed!{false, false}(samples, packet, .Long)
    }

    internal mtd encodeLimited(samples: const [..] s16, packet: *Array!{u8}, maximumBytes: u64) fail
    {
        if samples.count != EncoderFrames * .channels
        {
            fail BadParameterError{"AAC software encoder needs exactly 1024 complete sample frames"}
        }

        var spectra: [2] RateSpectrum
        let offsets = swbLong(.sampleRate == 48_000 ? 3_u32 : 4_u32)
        for channel in .channels
        {
            let spectrum = &spectra[channel]
            .transformChannel!{false}(samples, channel, .Long, &spectrum.coefficients[0])
            spectrum.peak = collectEncoderBandPeaks(&spectrum.coefficients[0], offsets, .bandCount, &spectrum.peaks[0])
        }

        try .encodeWindowed!{false, true}(samples, packet, .Long, &spectra, trialLimit: maximumBytes)
        if not packet.count or packet.count > maximumBytes
        {
            var choices:     RateChoices
            var initialGain: [2] s32
            let reference = .prepareRateChoices(&spectra, &choices, &initialGain)
            var selected:    RateGains
            var lower     = 0_s32
            var upper     = 128_s32
            while upper - lower > 1
            {
                let middle = (upper + lower) / 2
                if .chooseRateGains(&choices, &initialGain, reference, middle, &selected) <= maximumBytes
                {
                    lower = middle
                }
                else
                {
                    upper = middle
                }
            }

            let expected = .chooseRateGains(&choices, &initialGain, reference, lower, &selected)
            try .encodeWindowed!{false, true}(samples, packet, .Long, &spectra, &selected)
            Swag.require(packet.count == expected and packet.count <= maximumBytes)
        }

        for channel in .channels
        {
            for sample in EncoderFrames
            {
                .previous[channel, sample] = samples[sample * .channels + channel]
            }
        }
    }

    internal mtd prepareShortWindows()
    {
        .shortTransform = Mdct.create(2 * cast(u32, ShortLines))
    }

    internal mtd(Adaptive: bool, Limited: bool) encodeWindowed(samples: const [..] s16,
                                                               packet: *Array!{u8},
                                                               sequence: EncodeWindow,
                                                               spectra: const *[2] RateSpectrum? = null,
                                                               choices: const *RateGains? = null,
                                                               trialLimit: u64 = MaximumPacketBytes) fail
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
            var storage:     [FullLines] f32
            var bandPeaks:   [MaximumShortBands] f32
            var transformed: const [*] f32
            var peaks:       const [*] f32
            var maximum:     f32
            #static if Limited
            {
                let spectrum = &spectra![][channel]
                transformed = &spectrum.coefficients[0]
                peaks       = &spectrum.peaks[0]
                maximum     = spectrum.peak
            }
            else
            {
                .transformChannel!{Adaptive}(samples, channel, sequence, &storage[0])
                transformed = &storage[0]
                peaks       = &bandPeaks[0]
                for group in windowCount
                {
                    let peak = collectEncoderBandPeaks(transformed + group * lineStride, offsets, bandCount, &bandPeaks[group * bandCount])
                    maximum = Math.max(maximum, peak)
                }
            }

            let largest = 2.0 * cast(f64, maximum)
            let gain    = gainForPeak(maximum)
            var quantized: [FullLines] s32
            var active:    [MaximumShortBands] bool
            var bandGain:  [MaximumShortBands] s32

            // Keep each band's quiet components above the global quantization floor. AAC
            // codes scalefactor differences in [-60, 60]; limiting the boost to 48 steps
            // also bounds every jump between active bands without extra side information.
            let minimumGain = Math.max(0_s32, gain - MaximumBandBoost)
            for group in windowCount
            {
                let base = group * lineStride
                for scaleBand in bandCount
                {
                    let band     = group * bandCount + scaleBand
                    let first    = base + offsets[scaleBand]
                    let end      = base + offsets[scaleBand + 1]
                    let bandPeak = 2.0 * cast(f64, peaks[band])
                    var selected = gain

                    // Ignore far-off leakage and numerical residue around a strong tone.
                    // A component 150x below the strongest band remains eligible.
                    if bandPeak >= largest / 512.0 and bandPeak > 0
                    {
                        selected = Math.clamp(gainForPeak(peaks[band]), minimumGain, gain)
                    }

                    #static if Limited
                    {
                        if choices
                        {
                            selected = choices![][channel, band]
                            if selected < 0
                            {
                                continue
                            }
                        }
                    }

                    // Positive IEEE binary32 bit patterns have the same ordering as their values.
                    let thresholds = cast(const [*] u32, &g_FirstMagnitude[selected, 0])

                    // A band below the first magnitude uses the AAC zero codebook.
                    if cast #bit(u32, peaks[band]) < thresholds[1]
                    {
                        continue
                    }

                    active[band]   = true
                    bandGain[band] = selected
                    for line in first until end
                    {
                        let bits      = cast #bit(u32, transformed[line])
                        let absolute  = bits & 0x7FFF_FFFF
                        var magnitude = 8 * cast(s32, absolute >= thresholds[8])
                        magnitude       += 4 * cast(s32, absolute >= thresholds[magnitude + 4])
                        magnitude       += 2 * cast(s32, absolute >= thresholds[magnitude + 2])
                        magnitude       += cast(s32, absolute >= thresholds[magnitude + 1])
                        quantized[line] = bits >> 31 != 0 ? -magnitude : magnitude
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
            for group in windowCount
            {
                let sectionCount = planSections(Swag.makeSlice(&active[group * bandCount], bandCount),
                                                Swag.makeSlice(&sectionCodes[0], sectionCodes.count),
                                                isShort ? 3 : 5)
                for index in sectionCount
                {
                    .writeBits(sectionCodes[index].value, sectionCodes[index].width)
                }
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
                    var line = base + offsets[band]
                    while line < base + offsets[band + 1]
                    {
                        let pair = PackedSpectralPairs[quantized[line] + MaxMagnitude, quantized[line + 1] + MaxMagnitude]
                        .writeBits(pair & 0xFFFF, pair >> 16)
                        line += 2
                    }
                    #static if Limited
                    {
                        // Leave the packet empty when the initial rate trial cannot fit.
                        let used = .wordCount * #sizeof(u32) + (.pendingBits + 7) / 8
                        if used > trialLimit
                        {
                            return
                        }
                    }

                }
            }

            #static if not Limited
            {
                for sample in EncoderFrames
                {
                    .previous[channel, sample] = samples[sample * .channels + channel]
                }
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

#[Swag.Inline]
private func collectEncoderBandPeaks(spectrum: const [*] f32, offsets: const [..] u16,
                                    bandCount: u64, peaks: [*] f32)->f32
{
    var bandMaximum = 0_f32
    for band in bandCount
    {
        let first = spectrum + offsets[band]
        let width = cast(u64, offsets[band + 1] - offsets[band])
        var lanes = Simd.splat(0_f32)
        for index in width / 4
        {
            let values = Math.abs(Simd.load(first + 4 * index))
            lanes = Simd.select(values > lanes, values, lanes)
        }

        let peak = Simd.maximum(lanes)
        peaks[band] = peak
        bandMaximum = Math.max(bandMaximum, peak)
    }

    return bandMaximum
}

private impl Encoder
{
    mtd const prepareRateChoices(spectra: const *[2] RateSpectrum, choices: *RateChoices, initialGain: *[2] s32)->f64
    {
        let offsets   = swbLong(.sampleRate == 48_000 ? 3_u32 : 4_u32)
        var strongest = 0_f64
        for channel in .channels
        {
            let cached     = &spectra[][channel]
            let spectrum   = cast(const [*] f32, &cached.coefficients[0])
            let largest    = 2.0 * cast(f64, cached.peak)
            let globalGain = gainForPeak(cached.peak)
            initialGain[][channel] = globalGain
            let minimumGain = Math.max(0_s32, globalGain - MaximumBandBoost)

            // The total 60-step range keeps every scalefactor difference representable.
            let maximumGain = Math.min(255_s32, globalGain + 12)
            for band in .bandCount
            {
                let first    = cast(u64, offsets[band])
                let end      = cast(u64, offsets[band + 1])
                let peak     = cached.peaks[band]
                var selected = globalGain
                if 2.0 * cast(f64, peak) >= largest / 512.0 and peak > 0
                {
                    selected = Math.clamp(gainForPeak(peak), minimumGain, globalGain)
                }

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
                    let peakBits   = cast #bit(u32, peak)
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
                        let aBits = cast #bit(u32, spectrum[pair * 2]) & 0x7FFF_FFFF
                        let bBits = cast #bit(u32, spectrum[pair * 2 + 1]) & 0x7FFF_FFFF
                        let a     = 2.0 * cast(f64, cast #bit(f32, aBits))
                        let b     = 2.0 * cast(f64, cast #bit(f32, bBits))
                        // A union below the first cutoff proves both magnitudes are zero.
                        if (aBits | bBits) < thresholds[1]
                        {
                            distortion += a * a + b * b
                            codedBits  += RateSpectralWidths[0, 0]
                            continue
                        }

                        let qa = rateMagnitude(aBits, thresholds)
                        let qb = rateMagnitude(bBits, thresholds)
                        let ea = a - cast(f64, reconstructed[qa])
                        let eb = b - cast(f64, reconstructed[qb])
                        distortion += ea * ea + eb * eb
                        codedBits  += RateSpectralWidths[qa, qb]
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
            let first    = g_FirstMagnitude[scale, magnitude]
            let inBand   = cast(f64, cast #bit(f32, first)) * 2.0
            let previous = cast(f64, cast #bit(f32, first - 1)) * 2.0
            Swag.require(Math.round(Math.pow(inBand / factor, 0.75)) == magnitude)
            Swag.require(Math.round(Math.pow(previous / factor, 0.75)) == magnitude - 1)
        }
    }
}

// A power-of-two change in the positive peak shifts the AAC gain by four.
#test
{
    Swag.require(gainForPeak(0.0) == 100)
    Swag.require(gainForPeak(cast #bit(f32, 1_u32)) == 0)
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
