#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Builds a two-chunk PCM stream whose playback order differs from its file layout.
func audioPcmPacketSound()->SoundFile fail
{
    let path   = audioGetTestDataPath("pcm16_stereo.wav")
    let source = try SoundFile.load(path, preloadData: false)
    let packets: [2] SoundPacket = [{source.dataOffset + 4, 4, 1},
                                    {source.dataOffset, 4, 1}]
    return SoundFile.openPcmPacketStream(path, .Pcm16, 44_100, 2, packets)
}

#test
{
    var file = expect audioPcmPacketSound()
    @assert(file.sampleEncoding() == .Pcm16 and file.sampleFrameCount() == 2 and file.payloadSize() == 8)
    @assert(file.isPacketStream() and file.packetCount() == 2 and !file.isDataPreloaded())

    let payload = expect file.readPayload(0, 8)
    @assert(audioAssertBytes(payload.toSlice(), [0x00'u8, 0x00, 0xFF, 0x7F, 0x00, 0x80, 0xFF, 0xFF]))

    var voice: Voice
    voice.file              = &file
    voice.requestedEncoding = .Pcm16
    let decoded = expect voice.readBuffer()
    audioAssertBufferBytes(decoded.buffer, decoded.size, payload.toSlice())
    @assert(voice.streamCurSeek == file.payloadSize())

    let first = expect file.packet(0)
    let malformed: [1] SoundPacket = [{first.sourceOffset, 3, 1}]
    discard catch SoundFile.openPcmPacketStream(file.sourcePath(), .Pcm16, 44_100, 2, malformed) as chunkSize
    @assert(chunkSize is Errors.InvalidFormatError)
}

#test
{
    var file = expect audioPcmPacketSound()
    discard expect createNoSoundEngine()
    defer destroyEngine()
    let voice = (expect Voice.create(&file))!
    defer voice.destroy()

    discard expect voice.seekSampleFrame(1)
    let decoded = expect voice.readBuffer()
    audioAssertBufferBytes(decoded.buffer, decoded.size, [0x00'u8, 0x80, 0xFF, 0xFF])
    @assert(voice.streamCurSeek == file.payloadSize())
}

#test
{
    var file = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"))
    var voice: Voice
    voice.file              = &file
    voice.requestedEncoding = .Pcm16

    let {buffer0, size0} = expect voice.readBuffer()
    audioAssertBufferBytes(buffer0, size0, [0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0x7F])
    @assert(voice.streamCurSeek == file.dataSize)

    let {_, size1} = expect voice.readBuffer()
    @assert(size1 == 0)

    voice.playFlags = .Loop
    let {buffer2, size2} = expect voice.readBuffer()
    audioAssertBufferBytes(buffer2, size2, [0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0x7F])
    @assert(voice.streamCurSeek == file.dataSize)
}

#test
{
    var file = expect SoundFile.load(audioGetTestDataPath("pcm8_mono_odd.wav"))
    var voice: Voice
    voice.file              = &file
    voice.requestedEncoding = .Pcm16

    var decoded: [6] u8
    let size = expect voice.decodeData(&decoded[0], @countof(decoded))
    @assert(size == @countof(decoded))
    @assert(voice.streamCurSeek == file.dataSize)
    audioAssertSamples(decoded, [-32768's16, 0's16, 32512's16])

    let empty = expect voice.decodeData(&decoded[0], @countof(decoded))
    @assert(empty == 0)
}

#test
{
    var file = expect SoundFile.load(audioGetTestDataPath("pcm16_stereo.wav"), preloadData: false)
    var voice: Voice
    voice.file              = &file
    voice.requestedEncoding = .Pcm16

    var buffer: [4] u8
    let size0 = expect voice.decodeData(&buffer[0], @countof(buffer))
    @assert(size0 == 4)
    @assert(audioAssertBytes(buffer, [0x00, 0x80, 0xFF, 0xFF]))
    @assert(voice.streamCurSeek == 4)

    let size1 = expect voice.decodeData(&buffer[0], @countof(buffer))
    @assert(size1 == 4)
    @assert(audioAssertBytes(buffer, [0x00, 0x00, 0xFF, 0x7F]))
    @assert(voice.streamCurSeek == 8)

    let size2 = expect voice.decodeData(&buffer[0], @countof(buffer))
    @assert(size2 == 0)

    voice.closeBuffer()
    @assert(voice.streamCurSeek == 0)
    @assert(!voice.stream.isOpen())
}
