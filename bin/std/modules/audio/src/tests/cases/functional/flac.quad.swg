#global if #command == Swag.CompilerCommand.Test

using Core

// Both transports share the standard FLAC quad layout. The explicit 4.0 comment
// in the Ogg fixture continues on another page.
#test
{
    let pcm     = expect File.readAllBytes(audioGetTestDataPath("flac-quad-20bit-250000.pcm"))
    let samples = Swag.makeSlice(cast(const [*] s16, pcm.storage()), pcm.count / #sizeof(s16))
    for extension in [".flac", ".oga"]
    {
        let untagged = Format.toString("flac-quad-20bit-250000%", extension)
        let tagged   = Format.toString("flac-4.0-20bit-250000%", extension)
        for index in 2
        {
            let name  = index ? tagged.toString() : untagged.toString()
            let sound = expect SoundFile.load(audioGetTestDataPath(name), preloadData: false)
            let mask  = index ? 0x0107_u32 : 0x0033_u32
            Swag.require(sound.numChannels() == 4 and sound.speakerChannelMask() == mask, name)
            var decoded: Array!{s16}
            expect sound.decodePcm16(func|&decoded|(part)
            {
                decoded.add(part)
                return true
            })
            Swag.require(Slice.equals(decoded.toSlice(), samples), name)
        }
    }
}
