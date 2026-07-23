#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    let path = audioGetTestDataPath("pcm16_stereo.wav")

    let bytes = catch File.readAllBytes(path)
    @assert(@err == null)
    @assert(bytes.count == 52)

    let file = catch SoundFile.load(path)
    @assert(@err == null)
    @assert(file.encoding == .Pcm16)
    @assert(file.frequency == 44100)
    @assert(file.channelCount == 2)
    @assert(file.bitsPerSample == 16)
    @assert(file.sampleCount == 2)
    @assert(file.dataSize == 8)
    @assert(file.dataSeek == 44)
    @assert(file.datas.count == 8)
    @assert(file.validity.has(.Format))
    @assert(file.validity.has(.Frequency))
    @assert(file.validity.has(.ChannelCount))
    @assert(file.validity.has(.BitsPerSample))
    @assert(file.validity.has(.Data))
    @assert(file.validity.has(.SampleCount))
    @assert(file.validity.has(.Duration))
    audioAssertFloat(file.duration, 2.0 / 44100.0, 0.000001)
    @assert(audioAssertBytes(file.datas.toSlice(), [0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0x7F]))
}

#test
{
    let path = audioGetTestDataPath("pcm16_stereo.wav")

    let file = catch SoundFile.load(path, loadDatas: false)
    @assert(@err == null)
    @assert(file.encoding == .Pcm16)
    @assert(file.dataSize == 8)
    @assert(file.dataSeek == 44)
    @assert(file.datas.count == 0)
    @assert(file.sampleCount == 2)
}

#test
{
    let path = audioGetTestDataPath("pcm16_stereo.wav")

    let file = catch SoundFile.load(path, loadDatas: false, loadMetaDatas: true)
    @assert(@err == null)
    @assert(file.encoding == .Pcm16)
    @assert(file.dataSize == 8)
    @assert(file.datas.count == 0)
    @assert(file.sampleCount == 2)
    @assert(file.validity.has(.Duration))
}

#test
{
    let path = audioGetTestDataPath("pcm8_mono_odd.wav")

    let file = catch SoundFile.load(path)
    @assert(@err == null)
    @assert(file.encoding == .Pcm8)
    @assert(file.frequency == 8000)
    @assert(file.channelCount == 1)
    @assert(file.bitsPerSample == 8)
    @assert(file.sampleCount == 3)
    @assert(file.dataSize == 3)
    @assert(file.dataSeek == 44)
    audioAssertFloat(file.duration, 3.0 / 8000.0, 0.000001)
    @assert(audioAssertBytes(file.datas.toSlice(), [0'u8, 128'u8, 255'u8]))
}

#test
{
    let path = audioGetTestDataPath("pcm24_extensible_stereo.wav")

    let file = catch SoundFile.load(path)
    @assert(@err == null)
    @assert(file.encoding == .Pcm24)
    @assert(file.frequency == 48000)
    @assert(file.channelCount == 2)
    @assert(file.bitsPerSample == 24)
    @assert(file.validBitsPerSample == 20)
    @assert(file.channelMask == 3)
    @assert(file.sampleCount == 2)
    @assert(file.dataSize == 12)
    @assert(file.validity.has(.ValidBitsPerSample))
    @assert(file.validity.has(.ChannelMask))
    @assert(audioAssertBytes(file.datas.toSlice(), [0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x7F, 0x34, 0x12, 0x00]))
}

#test
{
    let path = audioGetTestDataPath("float32_extensible_mono.wav")

    let file = catch SoundFile.load(path)
    @assert(@err == null)
    @assert(file.encoding == .Float32)
    @assert(file.frequency == 22050)
    @assert(file.channelCount == 1)
    @assert(file.bitsPerSample == 32)
    @assert(file.validBitsPerSample == 32)
    @assert(file.channelMask == 4)
    @assert(file.sampleCount == 2)
    @assert(file.dataSize == 8)
    @assert(file.validity.has(.ValidBitsPerSample))
    @assert(file.validity.has(.ChannelMask))
}

#test
{
    let path = audioGetTestDataPath("pcm16_with_unknown_chunk.wav")

    let file = catch SoundFile.load(path)
    @assert(@err == null)
    @assert(file.encoding == .Pcm16)
    @assert(file.frequency == 44100)
    @assert(file.channelCount == 1)
    @assert(file.bitsPerSample == 16)
    @assert(file.sampleCount == 2)
    @assert(file.dataSize == 4)
    @assert(file.dataSeek == 56)
    @assert(audioAssertBytes(file.datas.toSlice(), [0x34, 0x12, 0xFE, 0xFF]))
}

#test
{
    discard catch SoundFile.load("audio.unsupported")
    @assert(@err is Errors.UnsupportedFormatError)
}

#test
{
    discard catch SoundFile.load(audioGetTestDataPath("unsupported_adpcm.wav"))
    @assert(@err is Errors.UnsupportedFormatError)

    discard catch SoundFile.load(audioGetTestDataPath("not_wave.wav"))
    @assert(@err is Errors.InvalidFormatError)

    discard catch SoundFile.load(audioGetTestDataPath("truncated_fmt.wav"))
    @assert(@err is Errors.InvalidFormatError)
}
