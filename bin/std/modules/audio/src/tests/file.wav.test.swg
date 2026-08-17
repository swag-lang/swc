#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let path = audioGetTestDataPath("pcm16_stereo.wav")

    let bytes = expect File.readAllBytes(path)
    @assert(bytes.count == 52)

    let file = expect SoundFile.load(path)
    @assert(file.encoding == .Pcm16)
    @assert(file.sampleEncoding() == .Pcm16)
    @assert(file.sampleRate == 44100)
    @assert(file.sampleRateHz() == 44100)
    @assert(file.channelCount == 2)
    @assert(file.numChannels() == 2)
    @assert(file.bitsPerSample == 16)
    @assert(file.frameCount == 2)
    @assert(file.sampleFrameCount() == 2)
    @assert(file.dataSize == 8)
    @assert(file.payloadSize() == 8)
    @assert(file.isDataPreloaded())
    @assert(@countof(file.preloadedData()) == 8)
    @assert(file.dataOffset == 44)
    @assert(file.data.count == 8)
    @assert(file.availableFields.has(.Format))
    @assert(file.availableFields.has(.SampleRate))
    @assert(file.availableFields.has(.ChannelCount))
    @assert(file.availableFields.has(.BitsPerSample))
    @assert(file.availableFields.has(.Data))
    @assert(file.hasField(.Data))
    @assert(file.availableFields.has(.FrameCount))
    @assert(file.availableFields.has(.Duration))
    audioAssertFloat(file.durationSeconds, 2.0 / 44100.0, 0.000001)
    audioAssertFloat(file.durationInSeconds(), 2.0 / 44100.0, 0.000001)
    @assert(audioAssertBytes(file.data.toSlice(), [0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0x7F]))
}

#test
{
    let path = audioGetTestDataPath("pcm16_stereo.wav")

    let file = expect SoundFile.load(path, preloadData: false)
    @assert(file.encoding == .Pcm16)
    @assert(file.dataSize == 8)
    @assert(file.dataOffset == 44)
    @assert(file.data.count == 0)
    @assert(!file.isDataPreloaded())
    @assert(@countof(file.preloadedData()) == 0)
    @assert(file.frameCount == 2)

    let first = expect file.readPayload(0, 3)
    @assert(audioAssertBytes(first.toSlice(), [0x00, 0x80, 0xFF]))
    let tail = expect file.readPayload(6, 10)
    @assert(audioAssertBytes(tail.toSlice(), [0xFF, 0x7F]))
    @assert((expect file.readPayload(8, 1)).isEmpty())
}

#test
{
    let path = audioGetTestDataPath("pcm8_mono_odd.wav")

    let file = expect SoundFile.load(path)
    @assert(file.encoding == .Pcm8)
    @assert(file.sampleRate == 8000)
    @assert(file.channelCount == 1)
    @assert(file.bitsPerSample == 8)
    @assert(file.frameCount == 3)
    @assert(file.dataSize == 3)
    @assert(file.dataOffset == 44)
    audioAssertFloat(file.durationSeconds, 3.0 / 8000.0, 0.000001)
    @assert(audioAssertBytes(file.data.toSlice(), [0'u8, 128'u8, 255'u8]))
}

#test
{
    let path = audioGetTestDataPath("pcm24_extensible_stereo.wav")

    let file = expect SoundFile.load(path)
    @assert(file.encoding == .Pcm24)
    @assert(file.sampleRate == 48000)
    @assert(file.channelCount == 2)
    @assert(file.bitsPerSample == 24)
    @assert(file.validBitsPerSample == 20)
    @assert(file.waveSpeakerMask == 3)
    @assert(file.frameCount == 2)
    @assert(file.dataSize == 12)
    @assert(file.availableFields.has(.ValidBitsPerSample))
    @assert(file.availableFields.has(.SpeakerMask))
    @assert(audioAssertBytes(file.data.toSlice(), [0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x7F, 0x34, 0x12, 0x00]))
}

#test
{
    let path = audioGetTestDataPath("float32_extensible_mono.wav")

    let file = expect SoundFile.load(path)
    @assert(file.encoding == .Float32)
    @assert(file.sampleRate == 22050)
    @assert(file.channelCount == 1)
    @assert(file.bitsPerSample == 32)
    @assert(file.validBitsPerSample == 32)
    @assert(file.waveSpeakerMask == 4)
    @assert(file.frameCount == 2)
    @assert(file.dataSize == 8)
    @assert(file.availableFields.has(.ValidBitsPerSample))
    @assert(file.availableFields.has(.SpeakerMask))
}

#test
{
    let path = audioGetTestDataPath("pcm16_with_unknown_chunk.wav")

    let file = expect SoundFile.load(path)
    @assert(file.encoding == .Pcm16)
    @assert(file.sampleRate == 44100)
    @assert(file.channelCount == 1)
    @assert(file.bitsPerSample == 16)
    @assert(file.frameCount == 2)
    @assert(file.dataSize == 4)
    @assert(file.dataOffset == 56)
    @assert(audioAssertBytes(file.data.toSlice(), [0x34, 0x12, 0xFE, 0xFF]))
}

#test
{
    discard catch SoundFile.load("audio.unsupported") as err9
    @assert(err9 is Errors.UnsupportedFormatError)
}

#test
{
    discard catch SoundFile.load(audioGetTestDataPath("unsupported_adpcm.wav")) as err10
    @assert(err10 is Errors.UnsupportedFormatError)

    discard catch SoundFile.load(audioGetTestDataPath("not_wave.wav")) as err11
    @assert(err11 is Errors.InvalidFormatError)

    discard catch SoundFile.load(audioGetTestDataPath("truncated_fmt.wav")) as err12
    @assert(err12 is Errors.InvalidFormatError)
}
