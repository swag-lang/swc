#global if #command == Swag.CompilerCommand.Test

using Core

private struct FlacWidthFixture
{
    name: string
    rate, channels: u32
}

#test
{
    const Frames = 69_u64
    const Cases  = [FlacWidthFixture{"flac-mono-4bit-11025", 11_025, 1},
                    FlacWidthFixture{"flac-stereo-8bit-12345", 12_345, 2},
                    FlacWidthFixture{"flac-3ch-12bit-192000", 192_000, 3},
                    FlacWidthFixture{"flac-quad-20bit-250000", 250_000, 4},
                    FlacWidthFixture{"flac-6.1-31bit-44100", 44_100, 7},
                    FlacWidthFixture{"flac-7.1-32bit-48000", 48_000, 8},
                    FlacWidthFixture{"flac-mid-side-32bit-48000", 48_000, 2}]
    for fixture in Cases
    {
        let path  = audioGetTestDataPath(Format.toString("%.flac", fixture.name).toString())
        let sound = expect SoundFile.load(path, preloadData: false)
        Swag.require(sound.sampleEncoding() == .Flac, fixture.name)
        Swag.require(sound.sampleFrameCount() == Frames, fixture.name)
        Swag.require(sound.sampleRateHz() == fixture.rate and sound.numChannels() == fixture.channels, fixture.name)

        let pcmPath = audioGetTestDataPath(Format.toString("%.pcm", fixture.name).toString())
        let pcm     = expect File.readAllBytes(pcmPath)
        Swag.require(pcm.count == Frames * fixture.channels * #sizeof(s16), fixture.name)
        let samples = Swag.makeSlice(cast(const [*] s16, pcm.storage()), pcm.count / #sizeof(s16))
        var decoded: Array!{s16}
        expect sound.decodePcm16(func|&decoded|(part)
        {
            decoded.add(part)
            return true
        })
        Swag.require(Slice.equals(decoded.toSlice(), samples), fixture.name)

        // Start just before a 32-sample FLAC frame boundary and finish in the short final frame.
        decoded.clear()
        expect sound.decodePcm16(31, 36, func|&decoded|(part)
        {
            decoded.add(part)
            return true
        })
        Swag.require(Slice.equals(decoded.toSlice(), samples[31 * fixture.channels until 67 * fixture.channels]), fixture.name)
    }
}
