#global if #command == Swag.CompilerCommand.Test

using Core, Core.Errors

// Decodes every packet of a loaded sound through the codec and returns interleaved PCM16.
//
// The packet table comes from the file reader, so this proves the two halves agree: a frame the
// index closed at the wrong byte does not decode.
private func mp3DecodeAll(sound: const *SoundFile)->Array's16 fail
{
    let file  = try File.readAllBytes(sound.sourcePath())
    let bytes = file.toSlice()

    var codec: Mp3.Codec
    let itf:   IPacketCodec = &codec
    try itf.initialize(sound.decoderConfig.toSlice(), sound.sampleRateHz(), sound.numChannels())

    var block: Array'u8
    block.resize(1152 * cast(u64, sound.numChannels()) * #sizeof(s16))

    var result: #returntype
    for index in sound.packetCount()
    {
        let packet  = try sound.packet(index)
        let written = try itf.decodePacket(block.storage(),
                                           block.count,
                                           bytes[packet.sourceOffset until packet.sourceOffset + packet.byteSize])
        let samples = cast(const [*] s16, block.storage())
        for sample in written / #sizeof(s16) do
            result.add(samples[sample])
    }

    return result
}

// A frame header needs all four bytes before the reader can classify it.
#test
{
    const Truncated: [3] u8 = [0xFF, 0xFB, 0x90]
    var error: Swag.Error
    discard catch Mp3.readHeader(Swag.makeSlice(&Truncated[0], Truncated.count)) as error
    Swag.require(error.value() is InvalidFormatError)
}

// A too-small output buffer must not consume the packet or disturb decoder history.
#test
{
    let path                        = audioGetTestDataPath("mp3-stereo-44100.mp3")
    var sound                       = expect SoundFile.load(path.toString())
    let file                        = expect File.readAllBytes(path.toString())
    let packet                      = expect sound.packet(0)
    let encoded                     = file.toSlice()[packet.sourceOffset until packet.sourceOffset + packet.byteSize]
    var actual:        Mp3.Codec
    var fresh:         Mp3.Codec
    let actualDecoder: IPacketCodec = &actual
    let freshDecoder:  IPacketCodec = &fresh
    expect actualDecoder.initialize(sound.decoderConfig.toSlice(), sound.sampleRateHz(), sound.numChannels())
    expect freshDecoder.initialize(sound.decoderConfig.toSlice(), sound.sampleRateHz(), sound.numChannels())

    var undersized: [2_303] s16
    var error:      Swag.Error
    discard catch actualDecoder.decodePacket(cast([*] void, &undersized[0]),
                                             undersized.count * #sizeof(s16),
                                             encoded) as error
    Swag.require(error.value() is BadParameterError)

    var actualPcm: [2_304] s16
    var freshPcm:  [2_304] s16
    let actualSize = expect actualDecoder.decodePacket(cast([*] void, &actualPcm[0]),
                                                       actualPcm.count * #sizeof(s16),
                                                       encoded)
    let freshSize = expect freshDecoder.decodePacket(cast([*] void, &freshPcm[0]),
                                                     freshPcm.count * #sizeof(s16),
                                                     encoded)
    Swag.require(actualSize == freshSize and
                 Slice.equals(Swag.makeSlice(&actualPcm[0], actualPcm.count),
                              Swag.makeSlice(&freshPcm[0], freshPcm.count)))
}

// MPEG-1 side information cannot claim more than 288 spectral value pairs per granule.
#test
{
    let sourcePath = audioGetTestDataPath("mp3-stereo-44100.mp3")
    var bytes      = expect File.readAllBytes(sourcePath.toString())
    var sound      = expect SoundFile.load(sourcePath.toString())
    let packet     = expect sound.packet(0)
    let offset     = packet.sourceOffset
    let header     = expect Mp3.readHeader(bytes.toSlice()[offset to])
    Swag.require(header.isMpeg1 and header.channels == 2)

    // MPEG-1 stereo side information starts with 20 bits before the first part2_3_length;
    // big_values follows its 12 bits, so its nine bits begin at side-information bit 32.
    let bigValuesOffset = offset + 4 + (header.hasCrc ? 2 : 0) + 4
    bytes[bigValuesOffset]     = 0xFF
    bytes[bigValuesOffset + 1] |= 0x80

    let temporary = Path.combine(Env.getSpecialDirectory(.Temp),
                                 Format.toString("audio-mp3-big-values-%.mp3", Guid64.random()).toString())
    defer discard catch File.delete(temporary)
    discard expect File.writeAllBytes(temporary, bytes.toSlice())

    var broken = expect SoundFile.load(temporary.toString())
    var error: Swag.Error
    discard catch mp3DecodeAll(&broken) as error
    Swag.require(error.value() is InvalidFormatError)
}

// Device-independent decoding follows the same audible timeline as playback, including the MP3
// encoder delay that must be removed before frame zero reaches analysis consumers.
#test
{
    var sound = expect SoundFile.load(audioGetTestDataPath("mp3-stereo-44100.mp3").toString())
    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(samples: const [..] s16)->bool
    {
        decoded.add(samples)
        return true
    })

    Swag.require(decoded.count == sound.sampleFrameCount() * sound.numChannels())
    var visible: bool
    for sample in decoded where Math.abs(cast(s32, sample)) > 256
    {
        visible = true
        break
    }

    Swag.require(visible)
}

// Packetized MP3 playback advances the same public cursor the player polls for its timeline.
#test
{
    destroyEngine()
    discard expect createNoSoundEngine()
    defer destroyEngine()

    var sound = expect SoundFile.load(audioGetTestDataPath("mp3-stereo-44100.mp3").toString())
    let voice = expect Voice.create(&sound)
    defer voice.destroy()
    discard expect voice.play(.Loop)
    discard expect voice.updateNoSound()
    Swag.require(voice.playbackSampleFrame() > 0 and voice.playbackSampleFrame() < sound.sampleFrameCount())
}

// Compares a decode against FFmpeg's, the way the standard's own compliance criterion does.
//
// Layer III is lossy, so two correct decoders differ in the last bits; what a defect produces is
// not a rounding difference but a burst. The measure is therefore the root mean square of the
// difference across the whole stream, against the full scale of the format. The threshold is far
// tighter than the standard's, because two decoders of the same stream really do agree that well.
private func mp3AssertCloseTo(name: string, sampleRate, channels: u32)
{
    var sound = expect SoundFile.load(audioGetTestDataPath(Format.toString("%.mp3", name).toString()).toString())
    Swag.require(sound.sampleEncoding() == .Mp3)
    Swag.require(sound.sampleRateHz() == sampleRate and sound.numChannels() == channels)

    let decoded = expect mp3DecodeAll(&sound)
    let wanted  = expect File.readAllBytes(audioGetTestDataPath(Format.toString("%.pcm", name).toString()).toString())

    // The reader states the priming the encoder added; what a player hears starts after it.
    let skip     = sound.leadingTrim * cast(u64, channels)
    let wantedAt = cast(const [*] s16, wanted.storage())
    Swag.require(decoded.count > skip)
    let count = wanted.count / #sizeof(s16)
    Swag.require(decoded.count - skip >= count)
    Swag.require(count > cast(u64, sampleRate) / 8)

    var energy = 0.0'f64
    var worst  = 0.0'f64
    for index in count
    {
        let difference = cast(f64, decoded[skip + index]) - cast(f64, wantedAt[index])
        energy += difference * difference
        worst  = Math.max(worst, Math.abs(difference))
    }

    let rms = Math.sqrt(energy / cast(f64, count)) / 32768.0'f64
    if rms > 0.001'f64 do
        Swag.print("mp3 ", name, ": rms ", rms, " over ", count, " samples, worst ", worst, "\n")
    Swag.require(rms <= 0.001'f64)
}

// MPEG-1 Layer III, joint stereo, 44.1 kHz: the shape almost every music file has, with an ID3v2
// prologue, an encoder information frame, and a stated encoder delay.
#test
{
    mp3AssertCloseTo("mp3-stereo-44100", 44_100, 2)
}

// MPEG-2 Layer III at a low sampling frequency, mono, with no tag of any kind: 576 samples a
// frame, nine-bit scalefactor selection, and its own scalefactor band table.
#test
{
    mp3AssertCloseTo("mp3-mono-22050", 22_050, 1)
}

// Every sampling frequency of the three versions, because each one selects its own scalefactor
// band table and a wrong row is silent about itself.
#test
{
    mp3AssertCloseTo("mp3-mono-48000", 48_000, 1)
    mp3AssertCloseTo("mp3-mono-32000", 32_000, 1)
}

#test
{
    mp3AssertCloseTo("mp3-mono-24000", 24_000, 1)
    mp3AssertCloseTo("mp3-mono-16000", 16_000, 1)
}

// MPEG-2.5, which halves MPEG-2 again. Eight kilohertz has a band table of its own.
#test
{
    mp3AssertCloseTo("mp3-mono-12000", 12_000, 1)
    mp3AssertCloseTo("mp3-mono-11025", 11_025, 1)
    mp3AssertCloseTo("mp3-mono-8000", 8_000, 1)
}

// Clicks over noise at the highest bit rate: this is what makes an encoder switch to short and
// mixed blocks, and what fills the escape-coded Huffman tables with values above fifteen.
#test
{
    mp3AssertCloseTo("mp3-transient-44100", 44_100, 2)
}

// The reader states what the file says about itself rather than decoding to find out.
#test
{
    var tagged = expect SoundFile.load(audioGetTestDataPath("mp3-stereo-44100.mp3").toString())
    Swag.require(tagged.isPacketStream() and not tagged.isDataPreloaded())
    Swag.require((expect tagged.packet(0)).sampleFrameCount == 1152)
    Swag.require(tagged.leadingTrim == 1105)
    Swag.require(tagged.speakerChannelMask() == 0x0003)

    var bare = expect SoundFile.load(audioGetTestDataPath("mp3-mono-22050.mp3").toString())
    Swag.require((expect bare.packet(0)).sampleFrameCount == 576)
    Swag.require(bare.leadingTrim == 0)
}

// A CRC-protected Xing frame includes the CRC word before its side information.
#test
{
    let sourcePath = audioGetTestDataPath("mp3-stereo-44100.mp3")
    let source     = expect File.readAllBytes(sourcePath)
    Swag.require(source[0] == 'I' and source[1] == 'D' and source[2] == '3')
    let audioOffset = 10'u64 +
                      (cast(u64, (source[6] & 0x7F)) << 21) +
                      (cast(u64, (source[7] & 0x7F)) << 14) +
                      (cast(u64, (source[8] & 0x7F)) << 7) +
                      cast(u64, (source[9] & 0x7F))
    let header = expect Mp3.readHeader(source[audioOffset to])
    Swag.require(not header.hasCrc and header.frameBytes > 6)

    var protected: Array'u8
    protected.add(source[until audioOffset + 4])

    // CRC validation is unsupported; the two-byte word exercises the protected-frame layout.
    protected.add([0'u8, 0])
    protected.add(source[audioOffset + 4 until audioOffset + header.frameBytes - 2])
    protected.add(source[audioOffset + header.frameBytes to])
    protected[audioOffset + 1] &= 0xFE

    let temporary = Path.combine(Env.getSpecialDirectory(.Temp),
                                 Format.toString("audio-mp3-crc-%.mp3", Guid64.random()))
    defer discard catch File.delete(temporary)
    discard expect File.writeAllBytes(temporary, protected.toSlice())

    let original = expect SoundFile.load(sourcePath)
    let decoded  = expect SoundFile.load(temporary)
    Swag.require(decoded.leadingTrim == 1105)
    Swag.require(decoded.packetCount() == original.packetCount())
    Swag.require((expect decoded.packet(0)).sourceOffset == audioOffset + header.frameBytes)
}

// A file that is not one fails on its own terms rather than being decoded into noise.
#test
{
    let directory = Env.getSpecialDirectory(.Temp)
    let path      = Path.combine(directory.toString(),
                                 Format.toString("audio-mp3-%.mp3", Guid64.random()).toString())
    defer discard catch File.delete(path.toString())

    var bytes: Array'u8
    bytes.add("not an elementary stream")
    expect File.writeAllBytes(path.toString(), bytes.toSlice())
    var errOutcome: Swag.Error
    discard catch SoundFile.load(path.toString()) as errOutcome
    let err = errOutcome.value()
    Swag.require(err != null)
}

// A frame header whose final frame is cut short must not silently shorten the sound.
#test
{
    let sourcePath = audioGetTestDataPath("mp3-mono-22050.mp3")
    var bytes      = expect File.readAllBytes(sourcePath.toString())
    let original   = expect SoundFile.load(sourcePath.toString())
    let lastPacket = expect original.packet(original.packetCount() - 1)
    bytes.resize(lastPacket.sourceOffset + lastPacket.byteSize - 1)

    let temporary = Path.combine(Env.getSpecialDirectory(.Temp),
                                 Format.toString("audio-mp3-truncated-%.mp3", Guid64.random()))
    defer discard catch File.delete(temporary)
    discard expect File.writeAllBytes(temporary, bytes.toSlice())

    var error: Swag.Error
    discard catch SoundFile.load(temporary) as error
    Swag.require(error.value() is InvalidFormatError)
}

// A valid later frame cannot silently change the sample rate and truncate the indexed stream.
#test
{
    let sourcePath = audioGetTestDataPath("mp3-stereo-44100.mp3")
    let original   = expect SoundFile.load(sourcePath.toString())
    let packet     = expect original.packet(1)
    var bytes      = expect File.readAllBytes(sourcePath.toString())
    let header     = expect Mp3.readHeader(bytes.toSlice()[packet.sourceOffset to])
    Swag.require(header.sampleRate == 44_100 and header.channels == 2)

    bytes[packet.sourceOffset + 2] = (bytes[packet.sourceOffset + 2] & 0xF3) | 0x04
    let changed = expect Mp3.readHeader(bytes.toSlice()[packet.sourceOffset to])
    Swag.require(changed.sampleRate == 48_000 and changed.channels == header.channels)

    let temporary = Path.combine(Env.getSpecialDirectory(.Temp),
                                 Format.toString("audio-mp3-rate-change-%.mp3", Guid64.random()))
    defer discard catch File.delete(temporary)
    discard expect File.writeAllBytes(temporary, bytes.toSlice())

    var error: Swag.Error
    discard catch SoundFile.load(temporary.toString()) as error
    Swag.require(error.value() is InvalidFormatError)
}

// A valid later frame cannot silently change the channel count and truncate the indexed stream.
#test
{
    let sourcePath = audioGetTestDataPath("mp3-stereo-44100.mp3")
    let original   = expect SoundFile.load(sourcePath.toString())
    let packet     = expect original.packet(1)
    var bytes      = expect File.readAllBytes(sourcePath.toString())
    let header     = expect Mp3.readHeader(bytes.toSlice()[packet.sourceOffset to])
    Swag.require(header.sampleRate == 44_100 and header.channels == 2)

    bytes[packet.sourceOffset + 3] = (bytes[packet.sourceOffset + 3] & 0x3F) | 0xC0
    let changed = expect Mp3.readHeader(bytes.toSlice()[packet.sourceOffset to])
    Swag.require(changed.sampleRate == header.sampleRate and changed.channels == 1)

    let temporary = Path.combine(Env.getSpecialDirectory(.Temp),
                                 Format.toString("audio-mp3-channel-change-%.mp3", Guid64.random()))
    defer discard catch File.delete(temporary)
    discard expect File.writeAllBytes(temporary, bytes.toSlice())

    var error: Swag.Error
    discard catch SoundFile.load(temporary.toString()) as error
    Swag.require(error.value() is InvalidFormatError)
}

// Lookahead must keep the consumed position while seeking and zero-padding truncated input.
#test
{
    const Bytes: [7] u8 = [0xB4, 0x39, 0xC2, 0x67, 0x85, 0xFA, 0x01]
    let payload = Swag.makeSlice(&Bytes[0], Bytes.count)
    var reader  = Mp3.BitReader.create(payload)
    for start in [3'u64, 31, 5, 53, 57, 16]
    {
        reader.seek(start)
        var position = start
        for width in [0'u32, 9, 24, 7, 1]
        {
            var expected = 0'u32
            for width
            {
                expected <<= 1
                if position < payload.count * 8 do
                    expected |= cast(u32, payload[position >> 3] >> cast(u32, (7 - (position & 7)))) & 1
                position += 1
            }

            let read = reader.read(width)
            Swag.require(read == expected)
            Swag.require(reader.overran() == (position > payload.count * 8))
        }
    }
}
