#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// RIFF numeric fields are little-endian independently of the host's native byte order.
#test
{
    const Header: [8] u8 = ['R'u8, 'I', 'F', 'F', 36, 0, 0, 0]
    let parsed = expect Wav.decodeChunkHeader(Swag.makeSlice(&Header[0], Header.count))
    Swag.require(parsed.chunkSize == 36)
    Swag.require(Memory.compare(&parsed.chunkID, "RIFF".buffer, 4) == 0)

    const Fact: [4] u8 = [0x78, 0x56, 0x34, 0x12]
    Swag.require(expect Wav.decodeFactFrameCount(Swag.makeSlice(&Fact[0], Fact.count)) == 0x12345678)
}

// A data chunk cannot extend beyond the declared RIFF container or the physical file.
#test
{
    let source    = expect File.readAllBytes(audioGetTestDataPath("pcm16_stereo.wav"))
    let temporary = Path.combine(Env.getSpecialDirectory(.Temp),
                                 Format.toString("audio-wav-bounds-%.wav", Guid128.random()))
    defer discard catch File.delete(temporary)

    for fieldOffset in [4'u64, 40]
    {
        var bytes  = source
        var writer = ByteStream.openWrite(&bytes)
        writer.setPosition(fieldOffset)
        writer.writeLittleEndian(fieldOffset == 4 ? 36'u32 : 100'u32)
        discard expect File.writeAllBytes(temporary, bytes.toSlice())

        var error: Swag.Error
        discard catch SoundFile.load(temporary) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }
}

// PCM audio data must contain a whole number of sample frames across all channels.
#test
{
    let source    = expect File.readAllBytes(audioGetTestDataPath("pcm16_stereo.wav"))
    let temporary = Path.combine(Env.getSpecialDirectory(.Temp),
                                 Format.toString("audio-wav-frame-alignment-%.wav", Guid128.random()))
    defer discard catch File.delete(temporary)

    var bytes  = source
    bytes.add([0x7F'u8, 0])
    var writer = ByteStream.openWrite(&bytes)
    writer.setPosition(4)
    writer.writeLittleEndian(46'u32)
    writer.setPosition(40)
    writer.writeLittleEndian(9'u32)
    discard expect File.writeAllBytes(temporary, bytes.toSlice())

    var error: Swag.Error
    discard catch SoundFile.load(temporary) as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

// PCM and float WAVE headers must describe the same frame layout as their sample format.
#test
{
    let temporary = Path.combine(Env.getSpecialDirectory(.Temp),
                                 Format.toString("audio-wav-format-%.wav", Guid128.random()))
    defer discard catch File.delete(temporary)

    for index in 2
    {
        let path = index == 0 ? audioGetTestDataPath("pcm16_stereo.wav") :
                   audioGetTestDataPath("float32_extensible_mono.wav")
        let source = expect File.readAllBytes(path)
        for fieldOffset in [28'u64, 32]
        {
            var bytes  = source
            var writer = ByteStream.openWrite(&bytes)
            writer.setPosition(fieldOffset)
            if fieldOffset == 28 do
                writer.writeLittleEndian(1'u32)
            else do
                writer.writeLittleEndian(1'u16)
            discard expect File.writeAllBytes(temporary, bytes.toSlice())

            var error: Swag.Error
            discard catch SoundFile.load(temporary) as error
            Swag.require(error.value() is Errors.InvalidFormatError)
        }
    }
}

#test
{
    let path = audioGetTestDataPath("pcm16_stereo.wav")

    let bytes = expect File.readAllBytes(path)
    Swag.require(bytes.count == 52)

    let file = expect SoundFile.load(path)
    Swag.require(file.encoding == .Pcm16)
    Swag.require(file.sampleEncoding() == .Pcm16)
    Swag.require(file.sampleRate == 44100)
    Swag.require(file.sampleRateHz() == 44100)
    Swag.require(file.channelCount == 2)
    Swag.require(file.numChannels() == 2)
    Swag.require(file.bitsPerSample == 16)
    Swag.require(file.frameCount == 2)
    Swag.require(file.sampleFrameCount() == 2)
    Swag.require(file.dataSize == 8)
    Swag.require(file.payloadSize() == 8)
    Swag.require(file.isDataPreloaded())
    Swag.require((file.preloadedData()).count == 8)
    Swag.require(file.dataOffset == 44)
    Swag.require(file.data.count == 8)
    Swag.require(file.availableFields.has(.Format))
    Swag.require(file.availableFields.has(.SampleRate))
    Swag.require(file.availableFields.has(.ChannelCount))
    Swag.require(file.availableFields.has(.BitsPerSample))
    Swag.require(file.availableFields.has(.Data))
    Swag.require(file.hasField(.Data))
    Swag.require(file.availableFields.has(.FrameCount))
    Swag.require(file.availableFields.has(.Duration))
    audioAssertFloat(file.durationSeconds, 2.0 / 44100.0, 0.000001)
    audioAssertFloat(file.durationInSeconds(), 2.0 / 44100.0, 0.000001)
    Swag.require(Slice.equals(file.data.toSlice(), [0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0x7F]))
}

#test
{
    let path = audioGetTestDataPath("pcm16_stereo.wav")

    let file = expect SoundFile.load(path, preloadData: false)
    Swag.require(file.encoding == .Pcm16)
    Swag.require(file.dataSize == 8)
    Swag.require(file.dataOffset == 44)
    Swag.require(file.data.isEmpty())
    Swag.require(not file.isDataPreloaded())
    Swag.require((file.preloadedData()).count == 0)
    Swag.require(file.frameCount == 2)

    var decoded: Array's16
    expect file.decodePcm16(func|decoded = &decoded|(samples: const [..] s16)->bool
    {
        decoded.add(samples)
        return true
    })
    Swag.require(decoded.count == 4)
    Swag.require(decoded[0] == Swag.S16.Min and
                 decoded[1] == -1 and
                 decoded[2] == 0 and
                 decoded[3] == Swag.S16.Max)

    let first = expect file.readPayload(0, 3)
    Swag.require(Slice.equals(first.toSlice(), [0x00, 0x80, 0xFF]))
    let tail = expect file.readPayload(6, 10)
    Swag.require(Slice.equals(tail.toSlice(), [0xFF, 0x7F]))
    Swag.require((expect file.readPayload(8, 1)).isEmpty())
}

#test
{
    let path = audioGetTestDataPath("pcm8_mono_odd.wav")

    let file = expect SoundFile.load(path)
    Swag.require(file.encoding == .Pcm8)
    Swag.require(file.sampleRate == 8000)
    Swag.require(file.channelCount == 1)
    Swag.require(file.bitsPerSample == 8)
    Swag.require(file.frameCount == 3)
    Swag.require(file.dataSize == 3)
    Swag.require(file.dataOffset == 44)
    audioAssertFloat(file.durationSeconds, 3.0 / 8000.0, 0.000001)
    Swag.require(Slice.equals(file.data.toSlice(), [0'u8, 128'u8, 255'u8]))
}

#test
{
    let path = audioGetTestDataPath("pcm24_extensible_stereo.wav")

    let file = expect SoundFile.load(path)
    Swag.require(file.encoding == .Pcm24)
    Swag.require(file.sampleRate == 48000)
    Swag.require(file.channelCount == 2)
    Swag.require(file.bitsPerSample == 24)
    Swag.require(file.validBitsPerSample == 20)
    Swag.require(file.waveSpeakerMask == 3)
    Swag.require(file.frameCount == 2)
    Swag.require(file.dataSize == 12)
    Swag.require(file.availableFields.has(.ValidBitsPerSample))
    Swag.require(file.availableFields.has(.SpeakerMask))
    Swag.require(Slice.equals(file.data.toSlice(), [0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x7F, 0x34, 0x12, 0x00]))
}

#test
{
    let path = audioGetTestDataPath("float32_extensible_mono.wav")

    let file = expect SoundFile.load(path)
    Swag.require(file.encoding == .Float32)
    Swag.require(file.sampleRate == 22050)
    Swag.require(file.channelCount == 1)
    Swag.require(file.bitsPerSample == 32)
    Swag.require(file.validBitsPerSample == 32)
    Swag.require(file.waveSpeakerMask == 4)
    Swag.require(file.frameCount == 2)
    Swag.require(file.dataSize == 8)
    Swag.require(file.availableFields.has(.ValidBitsPerSample))
    Swag.require(file.availableFields.has(.SpeakerMask))
}

#test
{
    let path = audioGetTestDataPath("pcm16_with_unknown_chunk.wav")

    let file = expect SoundFile.load(path)
    Swag.require(file.encoding == .Pcm16)
    Swag.require(file.sampleRate == 44100)
    Swag.require(file.channelCount == 1)
    Swag.require(file.bitsPerSample == 16)
    Swag.require(file.frameCount == 2)
    Swag.require(file.dataSize == 4)
    Swag.require(file.dataOffset == 56)
    Swag.require(Slice.equals(file.data.toSlice(), [0x34, 0x12, 0xFE, 0xFF]))
}

#test
{
    const Files: [11] string = ["clip.wav", "clip.flac", "clip.mp3", "clip.aac", "clip.ac3", "clip.eac3", "clip.ec3", "clip.dts", "clip.ogg", "clip.oga", "clip.opus"]

    let extensions = SoundFile.decodableExtensions()
    Swag.require(extensions.count == Files.count)
    for file, index in Files
    {
        Swag.require(SoundFile.canLoad(file))
        Swag.require(extensions[index] == Path.lowercaseExtension(file))
    }

    Swag.require(SoundFile.canLoad("CLIP.MP3"))
    Swag.require(not SoundFile.canLoad("clip.mid") and not SoundFile.canLoad("clip"))
}

#test
{
    var err9Outcome: Swag.Error
    discard catch SoundFile.load("audio.unsupported") as err9Outcome
    let err9 = err9Outcome.value()
    Swag.require((err9 is Errors.UnsupportedFormatError))
}

#test
{
    var err10Outcome: Swag.Error
    discard catch SoundFile.load(audioGetTestDataPath("malformed_adpcm.wav")) as err10Outcome
    let err10 = err10Outcome.value()
    Swag.require((err10 is Errors.InvalidFormatError))

    var err11Outcome: Swag.Error
    discard catch SoundFile.load(audioGetTestDataPath("not_wave.wav")) as err11Outcome
    let err11 = err11Outcome.value()
    Swag.require((err11 is Errors.InvalidFormatError))

    var err12Outcome: Swag.Error
    discard catch SoundFile.load(audioGetTestDataPath("truncated_fmt.wav")) as err12Outcome
    let err12 = err12Outcome.value()
    Swag.require((err12 is Errors.InvalidFormatError))
}
