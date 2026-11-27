#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Classic and extensible Float64 WAVE files preserve channel order and clipped PCM16 values.
#test
{
    let wanted = expect File.readAllBytes(audioGetTestDataPath("wav-float64.pcm"))
    discard expect createNoSoundEngine()
    defer destroyEngine()

    for name in ["wav-float64.wav", "wav-float64-extensible.wav"]
    {
        for preload in [false, true]
        {
            let sound = expect SoundFile.load(audioGetTestDataPath(name), preloadData: preload)
            Swag.require(sound.sampleEncoding() == .Float64 and sound.isDataPreloaded() == preload)
            Swag.require(sound.sampleFrameCount() == 8 and sound.numChannels() == 2 and sound.sampleRateHz() == 48_000)

            var decoded: [16] s16
            expect sound.decodePcm16(0, decoded)
            audioAssertBufferBytes(&decoded[0], #sizeof(decoded), wanted.toSlice())

            let voice = expect Voice.create(&sound)
            defer voice.destroy()
            discard expect voice.seekSampleFrame(3)
            let block = expect voice.readBuffer()
            audioAssertBufferBytes(block.buffer, block.size, wanted.toSlice()[3 * 4 to])
        }
    }
}

// PCM16 truncates finite fractions at double precision, saturates infinities, and silences NaN.
#test
{
    const Expected: [22] s16 = [
        0, Swag.S16.Max, Swag.S16.Min, 0, 0, 1, -1, 0, 0, 1, -1, 0,
        Swag.S16.Max, Swag.S16.Min, 0, 0, Swag.S16.Max, Swag.S16.Min, 0, 0, 0, 0]
    let sound = expect SoundFile.load(audioGetTestDataPath("wav-float64-edge-values.wav"), preloadData: false)
    var decoded: [Expected.count] s16
    expect sound.decodePcm16(0, decoded)
    Swag.require(Slice.equals(decoded, Expected))
}
