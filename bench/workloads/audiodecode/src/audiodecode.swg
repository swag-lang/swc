using Core, Audio

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 2 or args.count == 3)
    for sample in 8
    {
        var pcm: Array's16
        var watch: Time.Stopwatch
        watch.start()
        let sound  = expect SoundFile.load(args[1], preloadData: false)
        let opened = watch.elapsedMicroseconds()
        let rate   = sound.sampleRateHz()
        let frames = Math.min(sound.sampleFrameCount(), 10'u64 * rate)
        let count  = frames * sound.numChannels()
        pcm.reserve(count)
        expect sound.decodePcm16(0, frames, func|&pcm|(part)
        {
            pcm.add(part)
            return true
        })
        watch.stop()
        let total = watch.elapsedMicroseconds()
        Swag.require(pcm.count == count)
        if sample
        {
            let bytes = Swag.makeSlice(cast(const [*] u8, pcm.storage()), pcm.count * #sizeof(s16))
            Console.println(opened, " ", total - opened, " ", total, " ", frames, " ", sound.numChannels(), " ", rate, " ", Hash.Crc64.compute(bytes))
            if args.count == 3 and sample == 7 do
                discard expect File.writeAllBytes(args[2], bytes)
        }
    }
}
