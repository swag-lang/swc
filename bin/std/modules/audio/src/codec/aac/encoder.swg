//! Format: MPEG-4 AAC Low Complexity software encoder.
//! Supported: 1024-sample long-window mono/stereo PCM16 at 44.1 or 48 kHz, in full or voice band.
//! Role: This file turns non-silent capture PCM into AAC access units without a runtime codec dependency.
//
#global namespace Aac
#global export

using Core, Core.Errors

private const EncoderFrames = 1_024'u64
private const VoiceLines    = 176'u64
private const VoiceBands    = 23'u64
private const FullLines     = 1_024'u64
private const FullBands     = 49'u64
private const MaximumBandBoost = 48's32

internal struct EncoderSectionCode
{
    value: u32
    width: u32
}

// Plans AAC long-window section codewords, including the 31-band escape.
internal func planEncoderSections(active: const [..] bool,
                                  codes: [..] EncoderSectionCode)->u32
{
    Swag.assert(codes.count >= active.count * 2)
    var count = 0'u32
    var band = 0'u64
    while band < active.count
    {
        let book = active[band] ? 11'u32 : 0'u32
        var next = band + 1
        while next < active.count and active[next] == active[band] do
            next += 1
        codes[count] = {book, 4}
        count += 1
        var length = next - band
        while length >= 31
        {
            codes[count] = {31, 5}
            count += 1
            length -= 31
        }
        codes[count] = {cast(u32, length), 5}
        count += 1
        band = next
    }
    return count
}

// Selects the MDCT bandwidth of the software AAC encoder.
enum Bandwidth
{
    // Encodes all 1024 spectral lines up to the Nyquist frequency.
    Full,

    // Keeps 176 lines for speech and smaller packets, ending near 4 kHz.
    Voice,
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
        basis:      Array'f32
        previous:   [2, 1_024] s16
        silent:     SilenceEncoder
        config:     [2] u8
        channels:   u16
        sampleRate: u32
        lineCount:  u64
        bandCount:  u64
        bitCount:   u64
        output:     Array'u8
    }
}

impl Encoder
{
    // Creates a full-band or voice-band software encoder for mono or stereo PCM16.
    func create(sampleRate: u32, channels: u16, bandwidth: Bandwidth = .Full)->Encoder fail
    {
        let silence = try SilenceEncoder.create(sampleRate, channels)
        if sampleRate != 44_100 and sampleRate != 48_000 do
            fail BadParameterError{"AAC software encoder supports 44.1 and 48 kHz"}
        var result: #returntype
        result.channels = channels
        result.sampleRate = sampleRate
        result.lineCount = bandwidth == .Voice ? VoiceLines : FullLines
        result.bandCount = bandwidth == .Voice ? VoiceBands : FullBands
        result.silent = silence
        Memory.copy(&result.config[0], silence.decoderConfig().buffer, 2)
        result.basis.resize(result.lineCount * 2 * EncoderFrames)
        var window: [2 * EncoderFrames] f64
        for sample in 2 * EncoderFrames do
            window[sample] = Math.sin(Math.ConstF64.Pi / (2 * EncoderFrames) * (cast(f64, sample) + 0.5))
        for line in result.lineCount
        {
            let delta = Math.ConstF64.Pi / EncoderFrames * (cast(f64, line) + 0.5)
            let stepCos = Math.cos(delta)
            let stepSin = Math.sin(delta)
            let start = delta * (0.5 + EncoderFrames / 2)
            var cosine = Math.cos(start)
            var sine = Math.sin(start)
            for sample in 2 * EncoderFrames
            {
                result.basis[line * 2 * EncoderFrames + sample] = cast(f32, cosine * window[sample])
                let nextCosine = cosine * stepCos - sine * stepSin
                sine = sine * stepCos + cosine * stepSin
                cosine = nextCosine
            }
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
    mtd encode(samples: const [..] s16, packet: *Array'u8) fail
    {
        if samples.count != EncoderFrames * .channels do
            fail BadParameterError{"AAC software encoder needs exactly 1024 complete sample frames"}
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
                if not allZero do
                    break
            }
        }
        if allZero
        {
            packet.add(.silent.packet())
            return
        }
        .output.clear()
        .bitCount = 0
        if .channels == 2
        {
            .writeBits(1, 3) // Channel pair element.
            .writeBits(0, 4) // Element tag.
            .writeBits(0, 1) // Independent channel windows.
        }
        else
        {
            .writeBits(0, 3) // Single channel element.
            .writeBits(0, 4)
        }

        for channel in .channels
        {
            var spectrum: [FullLines] f64
            var largest = 0.0'f64
            for line in .lineCount
            {
                var value = 0.0'f64
                let row = line * 2 * EncoderFrames
                for sample in EncoderFrames do
                    value += .previous[channel, sample] * .basis[row + sample]
                for sample in EncoderFrames do
                    value += samples[sample * .channels + channel] * .basis[row + EncoderFrames + sample]
                spectrum[line] = value * 2.0
                largest = Math.max(largest, Math.abs(spectrum[line]))
            }

            var gain = 100's32
            if largest > 0 do
                gain = Math.clamp(cast(s32, Math.ceil(100.0 + 4.0 *
                                 Math.log2(largest / Math.pow(15.0'f64, 4.0'f64 / 3.0)))), 0, 255)
            var quantized: [FullLines] s32
            var active: [FullBands] bool
            var bandGain: [FullBands] s32
            let rateIndex = .sampleRate == 48_000 ? 3'u32 : 4'u32
            let offsets = swbLong(rateIndex)
            // Keep each band's quiet components above the global quantization floor. AAC
            // codes scalefactor differences in [-60, 60]; limiting the boost to 48 steps
            // also bounds every jump between active bands without extra side information.
            let minimumGain = Math.max(0's32, gain - MaximumBandBoost)
            for band in .bandCount
            {
                var bandPeak = 0.0'f64
                for line in offsets[band] until offsets[band + 1] do
                    bandPeak = Math.max(bandPeak, Math.abs(spectrum[line]))
                var selected = gain
                // Ignore far-off leakage and numerical residue around a strong tone.
                // A component 150x below the strongest band remains eligible.
                if bandPeak >= largest / 512.0 and bandPeak > 0 do
                    selected = Math.clamp(cast(s32, Math.ceil(100.0 + 4.0 *
                               Math.log2(bandPeak / Math.pow(15.0'f64, 4.0'f64 / 3.0)))),
                                          minimumGain, gain)
                bandGain[band] = selected
                let factor = Math.pow(2.0, 0.25 * cast(f64, selected - 100))
                for line in offsets[band] until offsets[band + 1]
                {
                    let value = spectrum[line]
                    let magnitude = Math.min(15's32, cast(s32, Math.round(Math.pow(Math.abs(value) / factor, 0.75))))
                    quantized[line] = value < 0 ? -magnitude : magnitude
                    if magnitude do
                        active[band] = true
                }
            }

            .writeBits(cast(u32, gain), 8)
            .writeBits(0, 1) // Reserved ICS bit.
            .writeBits(0, 2) // ONLY_LONG_SEQUENCE.
            .writeBits(0, 1) // Sine window.
            .writeBits(cast(u32, .bandCount), 6)
            .writeBits(0, 1) // No predictor.
            var sectionCodes: [2 * FullBands] EncoderSectionCode
            let sectionCount = planEncoderSections(Swag.makeSlice(&active[0], .bandCount),
                                                   Swag.makeSlice(&sectionCodes[0], sectionCodes.count))
            for index in sectionCount do
                .writeBits(sectionCodes[index].value, sectionCodes[index].width)
            var previousGain = gain
            for band in .bandCount where active[band]
            {
                let difference = cast(u64, 60 + bandGain[band] - previousGain)
                .writeBits(ScfCodes[difference], ScfBits[difference])
                previousGain = bandGain[band]
            }
            .writeBits(0, 1) // No pulse data.
            .writeBits(0, 1) // No TNS.
            .writeBits(0, 1) // No gain control.
            let bits = specBits(10)
            let codes = specCodes(10)
            for band in .bandCount where active[band]
            {
                var line = cast(u64, offsets[band])
                while line < offsets[band + 1]
                {
                    let first  = quantized[line]
                    let second = quantized[line + 1]
                    let symbol = cast(u64, Math.abs(first) * 17 + Math.abs(second))
                    .writeBits(codes[symbol], bits[symbol])
                    if first do .writeBits(first < 0 ? 1 : 0, 1)
                    if second do .writeBits(second < 0 ? 1 : 0, 1)
                    line += 2
                }
            }
            for sample in EncoderFrames do
                .previous[channel, sample] = samples[sample * .channels + channel]
        }
        .writeBits(7, 3) // End element.
        packet.add(.output.toSlice())
    }
}

private impl Encoder
{
    mtd writeBits(value: u32, count: u32)
    {
        for index in count
        {
            if .bitCount == .output.count * 8 do
                .output.add(0'u8)
            .output[.bitCount >> 3] |= cast(u8, ((value >> (count - index - 1)) & 1) <<
                                                  (7 - cast(u32, .bitCount & 7)))
            .bitCount += 1
        }
    }
}
