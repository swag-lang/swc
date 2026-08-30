#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let path = audioGetTestDataPath("pcm16_stereo.wav")

    let bytes = expect File.readAllBytes(path)
    Swag.assert(bytes.count == 52)

    let file = expect SoundFile.load(path)
    Swag.assert(file.encoding == .Pcm16)
    Swag.assert(file.sampleEncoding() == .Pcm16)
    Swag.assert(file.sampleRate == 44100)
    Swag.assert(file.sampleRateHz() == 44100)
    Swag.assert(file.channelCount == 2)
    Swag.assert(file.numChannels() == 2)
    Swag.assert(file.bitsPerSample == 16)
    Swag.assert(file.frameCount == 2)
    Swag.assert(file.sampleFrameCount() == 2)
    Swag.assert(file.dataSize == 8)
    Swag.assert(file.payloadSize() == 8)
    Swag.assert(file.isDataPreloaded())
    Swag.assert((file.preloadedData()).count == 8)
    Swag.assert(file.dataOffset == 44)
    Swag.assert(file.data.count == 8)
    Swag.assert(file.availableFields.has(.Format))
    Swag.assert(file.availableFields.has(.SampleRate))
    Swag.assert(file.availableFields.has(.ChannelCount))
    Swag.assert(file.availableFields.has(.BitsPerSample))
    Swag.assert(file.availableFields.has(.Data))
    Swag.assert(file.hasField(.Data))
    Swag.assert(file.availableFields.has(.FrameCount))
    Swag.assert(file.availableFields.has(.Duration))
    audioAssertFloat(file.durationSeconds, 2.0 / 44100.0, 0.000001)
    audioAssertFloat(file.durationInSeconds(), 2.0 / 44100.0, 0.000001)
    Swag.assert(audioAssertBytes(file.data.toSlice(), [0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0x7F]))
}

#test
{
    let path = audioGetTestDataPath("pcm16_stereo.wav")

    let file = expect SoundFile.load(path, preloadData: false)
    Swag.assert(file.encoding == .Pcm16)
    Swag.assert(file.dataSize == 8)
    Swag.assert(file.dataOffset == 44)
    Swag.assert(file.data.count == 0)
    Swag.assert(!file.isDataPreloaded())
    Swag.assert((file.preloadedData()).count == 0)
    Swag.assert(file.frameCount == 2)

    var decoded: Array's16
    expect file.decodePcm16(func|decoded = &decoded|(samples: const [..] s16)->bool
    {
        decoded.add(samples)
        return true
    })
    Swag.assert(decoded.count == 4)
    Swag.assert(decoded[0] == Swag.S16.Min and decoded[1] == -1 and decoded[2] == 0 and decoded[3] == Swag.S16.Max)

    let first = expect file.readPayload(0, 3)
    Swag.assert(audioAssertBytes(first.toSlice(), [0x00, 0x80, 0xFF]))
    let tail = expect file.readPayload(6, 10)
    Swag.assert(audioAssertBytes(tail.toSlice(), [0xFF, 0x7F]))
    Swag.assert((expect file.readPayload(8, 1)).isEmpty())
}

#test
{
    let path = audioGetTestDataPath("pcm8_mono_odd.wav")

    let file = expect SoundFile.load(path)
    Swag.assert(file.encoding == .Pcm8)
    Swag.assert(file.sampleRate == 8000)
    Swag.assert(file.channelCount == 1)
    Swag.assert(file.bitsPerSample == 8)
    Swag.assert(file.frameCount == 3)
    Swag.assert(file.dataSize == 3)
    Swag.assert(file.dataOffset == 44)
    audioAssertFloat(file.durationSeconds, 3.0 / 8000.0, 0.000001)
    Swag.assert(audioAssertBytes(file.data.toSlice(), [0'u8, 128'u8, 255'u8]))
}

#test
{
    let path = audioGetTestDataPath("pcm24_extensible_stereo.wav")

    let file = expect SoundFile.load(path)
    Swag.assert(file.encoding == .Pcm24)
    Swag.assert(file.sampleRate == 48000)
    Swag.assert(file.channelCount == 2)
    Swag.assert(file.bitsPerSample == 24)
    Swag.assert(file.validBitsPerSample == 20)
    Swag.assert(file.waveSpeakerMask == 3)
    Swag.assert(file.frameCount == 2)
    Swag.assert(file.dataSize == 12)
    Swag.assert(file.availableFields.has(.ValidBitsPerSample))
    Swag.assert(file.availableFields.has(.SpeakerMask))
    Swag.assert(audioAssertBytes(file.data.toSlice(), [0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x7F, 0x34, 0x12, 0x00]))
}

#test
{
    let path = audioGetTestDataPath("float32_extensible_mono.wav")

    let file = expect SoundFile.load(path)
    Swag.assert(file.encoding == .Float32)
    Swag.assert(file.sampleRate == 22050)
    Swag.assert(file.channelCount == 1)
    Swag.assert(file.bitsPerSample == 32)
    Swag.assert(file.validBitsPerSample == 32)
    Swag.assert(file.waveSpeakerMask == 4)
    Swag.assert(file.frameCount == 2)
    Swag.assert(file.dataSize == 8)
    Swag.assert(file.availableFields.has(.ValidBitsPerSample))
    Swag.assert(file.availableFields.has(.SpeakerMask))
}

#test
{
    let path = audioGetTestDataPath("pcm16_with_unknown_chunk.wav")

    let file = expect SoundFile.load(path)
    Swag.assert(file.encoding == .Pcm16)
    Swag.assert(file.sampleRate == 44100)
    Swag.assert(file.channelCount == 1)
    Swag.assert(file.bitsPerSample == 16)
    Swag.assert(file.frameCount == 2)
    Swag.assert(file.dataSize == 4)
    Swag.assert(file.dataOffset == 56)
    Swag.assert(audioAssertBytes(file.data.toSlice(), [0x34, 0x12, 0xFE, 0xFF]))
}

#test
{
    const Files: [11] string = ["clip.wav", "clip.flac", "clip.mp3", "clip.aac", "clip.ac3", "clip.eac3", "clip.ec3", "clip.dts", "clip.ogg", "clip.oga", "clip.opus"]

    let extensions = SoundFile.decodableExtensions()
    Swag.assert(extensions.count == Files.count)
    for file, index in Files
    {
        Swag.assert(SoundFile.canLoad(file))
        Swag.assert(extensions[index] == Path.lowercaseExtension(file))
    }

    Swag.assert(SoundFile.canLoad("CLIP.MP3"))
    Swag.assert(!SoundFile.canLoad("clip.mid") and !SoundFile.canLoad("clip"))
}

#test
{
    discard catch SoundFile.load("audio.unsupported") as err9
    Swag.assert(err9 is Errors.UnsupportedFormatError)
}

#test
{
    discard catch SoundFile.load(audioGetTestDataPath("malformed_adpcm.wav")) as err10
    Swag.assert(err10 is Errors.InvalidFormatError)

    discard catch SoundFile.load(audioGetTestDataPath("not_wave.wav")) as err11
    Swag.assert(err11 is Errors.InvalidFormatError)

    discard catch SoundFile.load(audioGetTestDataPath("truncated_fmt.wav")) as err12
    Swag.assert(err12 is Errors.InvalidFormatError)
}
