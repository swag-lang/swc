#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Both channels contain all 256 G.711 codes in opposite orders. The PCM16 references were
// decoded by FFmpeg 9.1 from the same classic and extensible WAVE payloads.
#test
{
    discard expect createNoSoundEngine()
    defer destroyEngine()

    for name in ["alaw", "mulaw"]
    {
        let encoding = name == "alaw" ? SoundFileEncoding.ALaw : SoundFileEncoding.MuLaw
        let wanted = expect File.readAllBytes(audioGetTestDataPath(Format.toString("wav-g711-%.pcm", name)))
        for extensible in [false, true]
        {
            let pattern = extensible ? "wav-g711-%-extensible.wav" : "wav-g711-%.wav"
            let path = audioGetTestDataPath(Format.toString(pattern, name))
            for preload in [false, true]
            {
                let sound = expect SoundFile.load(path, preloadData: preload)
                Swag.require(sound.sampleEncoding() == encoding and sound.isDataPreloaded() == preload)
                Swag.require(sound.sampleFrameCount() == 256 and sound.numChannels() == 2 and sound.sampleRateHz() == 8000)
                var decoded: Array!{s16}
                expect sound.decodePcm16(func|&decoded|(part)
                {
                    decoded.add(part)
                    return true
                })
                audioAssertBufferBytes(decoded.storage(), decoded.count * #sizeof(s16), wanted.toSlice())

                let voice = expect Voice.create(&sound)
                defer voice.destroy()
                discard expect voice.seekSampleFrame(73)
                let block = expect voice.readBuffer()
                audioAssertBufferBytes(block.buffer, block.size, wanted.toSlice()[73 * 4 to])
            }
        }
    }
}

// A G.711 range starts on its exact interleaved frame and continues across input windows.
#test
{
    const Repeats = 520
    const First = 211_u64
    const Frames = 132_000_u64
    let fixture = audioGetTestDataPath("wav-g711-alaw.wav")
    let metadata = expect SoundFile.load(fixture, preloadData: false)
    let original = expect File.readAllBytes(fixture)
    let reference = expect File.readAllBytes(audioGetTestDataPath("wav-g711-alaw.pcm"))
    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("g711-range-%.wav", Guid128.random()))
    defer discard catch File.delete(path)

    var bytes: Array!{u8}
    bytes.reserve(metadata.dataOffset + metadata.payloadSize() * Repeats)
    bytes.add(original.toSlice()[until metadata.dataOffset])
    for Repeats
    {
        bytes.add(original.toSlice()[metadata.dataOffset to])
    }

    var writer = ByteStream.openWrite(&bytes)
    writer.setPosition(4)
    writer.writeLittleEndian(cast(u32, bytes.count - 8))
    writer.setPosition(metadata.dataOffset - 12)
    writer.writeLittleEndian(cast(u32, metadata.sampleFrameCount() * Repeats))
    writer.setPosition(metadata.dataOffset - 4)
    writer.writeLittleEndian(cast(u32, metadata.payloadSize() * Repeats))
    discard expect File.writeAllBytes(path, bytes.toSlice())

    let sound = expect SoundFile.load(path, preloadData: false)
    let expected = reference.toSlice()
    var next = First * 4
    var calls: u64
    expect sound.decodePcm16(First, Frames, func|&next, &calls, expected|(part)
    {
        Swag.require(part.count and part.count % 2 == 0)
        let pcm = Swag.makeSlice(cast(const [*] u8, part.buffer), part.count * #sizeof(s16))
        for sample in pcm
        {
            Swag.require(sample == expected[next % expected.count])
            next += 1
        }
        calls += 1
        return true
    })
    Swag.require(next == (First + Frames) * 4 and calls == 2)
}

// A companded byte is one source sample, so its WAVE block alignment must match the channels.
#test
{
    let bytes = expect File.readAllBytes(audioGetTestDataPath("wav-g711-mulaw.wav"))
    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("g711-alignment-%.wav", Guid128.random()))
    defer discard catch File.delete(path)

    var invalid = bytes
    var writer = ByteStream.openWrite(&invalid)
    writer.setPosition(32)
    writer.writeLittleEndian(1_u16)
    discard expect File.writeAllBytes(path, invalid.toSlice())
    var error: Swag.Error
    discard catch SoundFile.load(path) as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}
