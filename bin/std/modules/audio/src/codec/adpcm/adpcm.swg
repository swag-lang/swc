//! Format: WAVE ADPCM block decoder component.
//! Supported: Microsoft ADPCM and IMA ADPCM blocks of one or two channels at four bits a sample, the coefficient table a Microsoft `fmt ` chunk carries, and a shortened final block.
//! Not supported: IMA ADPCM at two, three, or five bits a sample, more than two channels, and other WAVE compression tags.
//! Role: This file owns ADPCM block syntax, predictor adaptation, and PCM output.
//
#global namespace Adpcm

using Core, Core.Errors

private const MaxChannels = 2'u32

// Bytes every Microsoft ADPCM block spends on one channel: the predictor choice, the initial
// step, and the two seed samples.
private const MsHeaderBytes = 7'u64

// Bytes every IMA ADPCM block spends on one channel: the seed sample and the step index.
private const ImaHeaderBytes = 4'u64

// IMA nibbles are grouped four bytes a channel, eight samples a group.
private const ImaGroupBytes = 4'u64
private const ImaGroupSamples = 8'u64

// The step scaling every Microsoft ADPCM nibble applies, indexed by the nibble itself.
private const MsAdaptation: [16] s32 = [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230]

// The seven predictor pairs the Microsoft format defines, in the 8.8 fixed point the `fmt `
// chunk carries them in. A file may state its own table; this is what it states by default.
private const MsCoefficients: [14] s32 = [256, 0, 512, -256, 0, 0, 192, 64, 240, 0, 460, -208, 392, -232]

// The IMA step table and the index adjustment every nibble applies, indexed by the nibble.
private const ImaSteps: [89] s32 = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1_060, 1_166, 1_282, 1_411, 1_552, 1_707, 1_878, 2_066,
    2_272, 2_499, 2_749, 3_024, 3_327, 3_660, 4_026, 4_428, 4_871, 5_358, 5_894, 6_484, 7_132, 7_845, 8_630, 9_493, 10_442, 11_487, 12_635, 13_899, 15_289, 16_818, 18_500, 20_350, 22_385, 24_623, 27_086, 29_794, 32_767]
private const ImaIndexSteps: [16] s32 = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

// Returns the number of sample frames a block of `blockBytes` decodes to, or zero for a block
// too short to hold its header.
//
// The count follows from the block's size alone, as FFmpeg computes it, so a file whose `fmt `
// chunk states a different samples-per-block value still decodes every nibble it carries, and a
// final block cut short by the writer decodes to what it holds.
internal func blockFrameCount(encoding: SoundFileEncoding, channels: u32, blockBytes: u64)->u64
{
    let width = cast(u64) channels
    switch encoding
    {
    case .AdpcmMs:
        if blockBytes < MsHeaderBytes * width do
            return 0
        return 2 + (blockBytes - MsHeaderBytes * width) * 2 / width

    case .AdpcmIma:
        if blockBytes < ImaHeaderBytes * width do
            return 0
        return 1 + (blockBytes - ImaHeaderBytes * width) / (ImaGroupBytes * width) * ImaGroupSamples

    default:
        return 0
    }
}

private func readS16(bytes: const [..] u8, offset: u64)->s32
{
    let raw = cast(u32) bytes[offset] | (cast(u32) bytes[offset + 1] << 8)
    return cast(s32) (cast #bit (s16) cast(u16) raw)
}

// The adaptive state of one Microsoft ADPCM channel inside a block.
private struct MsChannel
{
    coefficient1: s32
    coefficient2: s32
    delta:        s32
    sample1:      s32
    sample2:      s32
}

private impl MsChannel
{
    // Reconstructs one sample from its nibble and adapts the step for the next one.
    //
    // The predictor divides toward zero, as the reference decoders do; a floor would differ by
    // one on negative products and the error would then feed every following sample.
    mtd expand(nibble: u32)->s16
    {
        let signed    = nibble & 8 ? cast(s32) nibble - 16 : cast(s32) nibble
        var predicted = (.sample1 * .coefficient1 + .sample2 * .coefficient2) / 256
        predicted += signed * .delta
        .sample2 = .sample1
        .sample1 = Math.clamp(predicted, -32_768, 32_767)
        .delta   = (MsAdaptation[nibble] * .delta) >> 8
        if .delta < 16 do
            .delta = 16
        elif .delta > Swag.S32.Max / 768 do
            .delta = Swag.S32.Max / 768
        return cast(s16) .sample1
    }
}

// The adaptive state of one IMA ADPCM channel inside a block.
private struct ImaChannel
{
    predictor: s32
    stepIndex: s32
}

private impl ImaChannel
{
    // Reconstructs one sample from its nibble and adapts the step for the next one.
    //
    // The difference is the reference implementation's sum of shifted step terms, not the
    // product `(2n + 1) * step / 8` some decoders use: the two round differently in the last
    // bit, and the sum is what the format's reference decoder and FFmpeg produce for WAVE.
    mtd expand(nibble: u32)->s16
    {
        let step       = ImaSteps[.stepIndex]
        var difference = step >> 3
        if nibble & 4 do
            difference += step
        if nibble & 2 do
            difference += step >> 1
        if nibble & 1 do
            difference += step >> 2
        .predictor = Math.clamp(nibble & 8 ? .predictor - difference : .predictor + difference, -32_768, 32_767)
        .stepIndex = Math.clamp(.stepIndex + ImaIndexSteps[nibble], 0, 88)
        return cast(s16) .predictor
    }
}

// Decodes the ADPCM blocks a WAVE file indexes, one complete block per call.
//
// Every block restarts its predictors from the header it carries, so the codec keeps no state
// between calls beyond the coefficient table the container declared.
private struct Codec
{
    // Every registered codec starts with the registry's own header: a voice destroys one through
    // this, reading back the concrete type and the allocator the instance was made with.
    using base: Audio.Codec

    channels:     u32
    coefficients: Array's32     // Microsoft predictor pairs, first then second coefficient of each.
}

private impl Codec
{
    // Reads the predictor table a Microsoft `fmt ` chunk carries after its samples-per-block
    // field, or installs the format's own seven pairs when the chunk carries none.
    mtd readCoefficients(config: const [..] u8)
    {
        .coefficients.clear()
        if @countof(config) >= 4
        {
            let count = cast(u64) config[2] | (cast(u64) config[3] << 8)
            if count and @countof(config) >= 4 + count * 4
            {
                for index in count * 2 do
                    .coefficients.add(readS16(config, 4 + index * 2))
                return
            }
        }

        .coefficients.add(MsCoefficients)
    }

    mtd decodeMs(destination: [*] s16, packet: const [..] u8, frames: u64) fail
    {
        let width = cast(u64) .channels
        var states: [MaxChannels] MsChannel
        for channel in width
        {
            let choice = cast(u64) packet[channel]
            if choice * 2 + 1 >= .coefficients.count do
                fail InvalidFormatError{"Microsoft ADPCM block selects a predictor outside its table"}
            states[channel].coefficient1 = .coefficients[choice * 2]
            states[channel].coefficient2 = .coefficients[choice * 2 + 1]
            states[channel].delta        = readS16(packet, width + channel * 2)
            states[channel].sample1      = readS16(packet, width * 3 + channel * 2)
            states[channel].sample2      = readS16(packet, width * 5 + channel * 2)
        }

        // The seed samples are output oldest first, then every byte carries one nibble for the
        // first channel and one for the last, which are the same channel in mono.
        for channel in width
        {
            destination[channel]         = cast(s16) states[channel].sample2
            destination[width + channel] = cast(s16) states[channel].sample1
        }

        var written = 2 * width
        var offset  = MsHeaderBytes * width
        let total   = frames * width
        while written < total
        {
            let byte = cast(u32) packet[offset]
            destination[written]     = states[0].expand(byte >> 4)
            destination[written + 1] = states[width - 1].expand(byte & 15)
            written += 2
            offset  += 1
        }
    }

    mtd decodeIma(destination: [*] s16, packet: const [..] u8, frames: u64) fail
    {
        let width = cast(u64) .channels
        var states: [MaxChannels] ImaChannel
        for channel in width
        {
            let at = channel * ImaHeaderBytes
            states[channel].predictor = readS16(packet, at)
            states[channel].stepIndex = cast(s32) packet[at + 2]
            if states[channel].stepIndex > 88 do
                fail InvalidFormatError{"IMA ADPCM block states a step index outside its table"}
            destination[channel] = cast(s16) states[channel].predictor
        }

        // After the seed sample, nibbles come in four-byte groups per channel, low nibble first.
        var offset = ImaHeaderBytes * width
        var frame  = 1'u64
        while frame < frames
        {
            for channel in width
            {
                for index in ImaGroupBytes
                {
                    let byte = cast(u32) packet[offset]
                    destination[(frame + index * 2) * width + channel]     = states[channel].expand(byte & 15)
                    destination[(frame + index * 2 + 1) * width + channel] = states[channel].expand(byte >> 4)
                    offset += 1
                }
            }

            frame += ImaGroupSamples
        }
    }
}

impl IPacketCodec for Codec
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .AdpcmMs or encoding == .AdpcmIma

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        if !sampleRateHz or !channels or channels > MaxChannels do
            fail BadParameterError{"ADPCM audio needs one or two channels and a non-zero sample rate"}
        .channels = channels
        if .sourceEncoding == .AdpcmMs do
            .readCoefficients(config)
    }

    mtd impl reset() {}

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        let frames = blockFrameCount(.sourceEncoding, .channels, @countof(packet))
        if !frames do
            fail InvalidFormatError{"ADPCM block is shorter than its header"}
        let produced = frames * .channels * #sizeof(s16)
        if destinationSize < produced do
            fail BadParameterError{"ADPCM destination buffer is too small"}

        let samples = cast([*] s16) destination
        if .sourceEncoding == .AdpcmMs do
            try .decodeMs(samples, packet, frames)
        else do
            try .decodeIma(samples, packet, frames)
        return produced
    }
}

#init
{
    registerPacketCodec'Codec()
}
