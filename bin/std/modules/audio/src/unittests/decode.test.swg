#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

#test
{
    var file = catch SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    @assert(@err == null)

    var voice: Voice
    voice.file = &file
    voice.requestedEncoding = .Pcm16

    let (buffer0, size0) = catch voice.readBuffer()
    @assert(@err == null)
    audioAssertBufferBytes(buffer0, size0, [0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0x7F])
    @assert(voice.streamCurSeek == file.dataSize)

    let (_, size1) = catch voice.readBuffer()
    @assert(@err == null)
    @assert(size1 == 0)

    voice.playFlags = .Loop
    let (buffer2, size2) = catch voice.readBuffer()
    @assert(@err == null)
    audioAssertBufferBytes(buffer2, size2, [0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0x7F])
    @assert(voice.streamCurSeek == file.dataSize)
}

#test
{
    var file = catch SoundFile.load(audioGetTestDataPath("pcm8_mono_odd.wav"))
    @assert(@err == null)

    var voice: Voice
    voice.file = &file
    voice.requestedEncoding = .Pcm16

    var decoded: [6] u8
    let size = catch voice.decodeData(&decoded[0], @countof(decoded))
    @assert(@err == null)
    @assert(size == @countof(decoded))
    @assert(voice.streamCurSeek == file.dataSize)
    audioAssertSamples(decoded, [-32768's16, 0's16, 32512's16])

    let empty = catch voice.decodeData(&decoded[0], @countof(decoded))
    @assert(@err == null)
    @assert(empty == 0)
}

#test
{
    var file = catch SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"), loadDatas: false)
    @assert(@err == null)

    var voice: Voice
    voice.file = &file
    voice.requestedEncoding = .Pcm16

    var buffer: [4] u8
    let size0 = catch voice.decodeData(&buffer[0], @countof(buffer))
    @assert(@err == null)
    @assert(size0 == 4)
    @assert(audioAssertBytes(buffer, [0x00, 0x80, 0xFF, 0xFF]))
    @assert(voice.streamCurSeek == 4)

    let size1 = catch voice.decodeData(&buffer[0], @countof(buffer))
    @assert(@err == null)
    @assert(size1 == 4)
    @assert(audioAssertBytes(buffer, [0x00, 0x00, 0xFF, 0x7F]))
    @assert(voice.streamCurSeek == 8)

    let size2 = catch voice.decodeData(&buffer[0], @countof(buffer))
    @assert(@err == null)
    @assert(size2 == 0)

    voice.closeBuffer()
    @assert(voice.streamCurSeek == 0)
    @assert(!voice.stream.isOpen())
}
