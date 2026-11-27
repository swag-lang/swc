#global if #command == Swag.CompilerCommand.Test

using Core

private func aacCheckExternalReference(name: string, channels: u32, frames: u64)
{
    let audioPath = audioGetTestDataPath(Format.toString("%.aac", name).toString())
    let pcmPath   = audioGetTestDataPath(Format.toString("%.pcm", name).toString())
    let sound     = expect SoundFile.load(audioPath, preloadData: false)
    let reference = expect File.readAllBytes(pcmPath)
    Swag.require(sound.sampleEncoding() == .AacLc)
    Swag.require(sound.sampleRateHz() == 44_100 and sound.numChannels() == channels)
    Swag.require(sound.sampleFrameCount() == frames)
    Swag.require(reference.count == frames * channels * #sizeof(s16))

    var decoded: Array!{s16}
    expect sound.decodePcm16(func|&decoded|(part: const [..] s16)->bool
    {
        decoded.add(part)
        return true
    })
    Swag.require(decoded.count == frames * channels)

    let expected = cast(const [*] s16, reference.storage())
    for sample, index in decoded
    {
        Swag.require(Math.abs(cast(s32, sample) - cast(s32, expected[index])) <= 1)
    }
}

// FDK AAC 2.0.3 encodes a swept mono tone at 64 kb/s. The PCM reference is from FFmpeg 9.1.
#test
{
    aacCheckExternalReference("aac-lc-mono-44100-fdk", 1, 28_672)
}

// FFmpeg 9.1 encodes staggered stereo attacks at 128 kb/s using all four window sequences.
// Noise substitution and intensity stereo are disabled to isolate the transform transitions.
#test
{
    aacCheckExternalReference("aac-lc-stereo-44100-transients", 2, 27_648)
}
