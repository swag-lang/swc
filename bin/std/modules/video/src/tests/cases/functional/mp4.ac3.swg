#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Audio

// Classic MP4 AC-3 sync samples expose their native packet durations, speaker layout, and decoded PCM.
#test
{
    var reader = expect Reader.open(videoFixturePath("ffmpeg-h264-ac3.mp4"))
    Swag.require(reader.frameCount() == 12)
    Swag.require(reader.audioTrackCount() == 1)

    let sound = unwrap reader.audioTrack(0)
    Swag.require(sound.sampleEncoding() == Audio.SoundFileEncoding.Ac3)
    Swag.require(sound.sampleRateHz() == 48_000 and sound.numChannels() == 6)
    Swag.require(sound.speakerChannelMask() == 0x003F)
    Swag.require(sound.packetCount() == 16 and sound.sampleFrameCount() == 16 * 1_536)
    for index in [0'u64, 7, 15] do
        Swag.require((expect sound.packet(index)).sampleFrameCount == 1_536)

    var decoded: Array's16
    expect sound.decodePcm16(func|decoded = &decoded|(samples: const [..] s16)->bool
    {
        decoded.add(samples)
        return true
    })

    let reference = expect File.readAllBytes(videoFixturePath("ffmpeg-h264-ac3.pcm"))
    let wanted = cast(const [*] s16, reference.storage())
    Swag.require(decoded.count == sound.sampleFrameCount() * sound.numChannels())
    Swag.require(reference.count / #sizeof(s16) == decoded.count)

    var energy = 0.0'f64
    for index in decoded.count
    {
        let difference = cast(f64, decoded[index]) - cast(f64, wanted[index])
        energy += difference * difference
    }
    let rms = Math.sqrt(energy / cast(f64, decoded.count)) / 32768.0'f64
    Swag.require(rms <= 0.012'f64)
}
