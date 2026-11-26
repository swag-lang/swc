using Core, Audio

private struct Timing
{
    opened: u64
    fed:    u64
    total:  u64
    delay:  u32
}

private func(Writer) encodeLossless(path: string, pcm: const [..] s16, rate: u32, channels: u16)->Timing fail
{
    var watch: Time.Stopwatch
    watch.start()
    var writer = try Writer.create(path, channels, rate)
    let opened = watch.elapsedMicroseconds()
    let block  = 4096'u64 * channels
    var offset = 0'u64
    while offset < pcm.count
    {
        let end = Math.min(offset + block, pcm.count)
        try writer.addFrames(pcm[offset until end])
        offset = end
    }

    let fed = watch.elapsedMicroseconds()
    try writer.end()
    return Timing{opened, fed, watch.elapsedMicroseconds(), 0}
}

private func writeAdts(sink: *ByteSink, packet: const [..] u8, rateIndex: u8, channels: u16) fail
{
    let size = packet.count + 7
    Swag.require(size <= 8191)
    let header: [7] u8 = [0xFF'u8, 0xF1, 0x40 | (rateIndex << 2),
                          cast(u8, channels << 6) | cast(u8, size >> 11),
                          cast(u8, (size >> 3) & 255),
                          cast(u8, ((size & 7) << 5) | 31), 0xFC]
    try sink.write(header)
    try sink.write(packet)
}

private func encodeAac(path: string, pcm: const [..] s16, rate: u32, channels: u16, bandwidth: Aac.Bandwidth)->Timing fail
{
    let rateIndex = rate == 48000 ? 3'u8 : 4'u8
    var watch: Time.Stopwatch
    watch.start()
    var encoder = try Aac.StreamEncoder.create(rate, channels, bandwidth)
    var sink    = try ByteSink.createFile(path)
    var packet: Array'u8
    let opened  = watch.elapsedMicroseconds()
    var offset  = 0'u64
    while offset < pcm.count
    {
        let frames = try encoder.push(pcm[offset until], &packet)
        Swag.require(frames)
        offset += frames * channels
        if not packet.isEmpty() do
            try writeAdts(&sink, packet.toSlice(), rateIndex, channels)
    }

    let fed = watch.elapsedMicroseconds()
    while try encoder.finish(&packet) do
        try writeAdts(&sink, packet.toSlice(), rateIndex, channels)
    try sink.close()
    return Timing{opened, fed, watch.elapsedMicroseconds(), encoder.encoderDelayFrames()}
}

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 8)
    let codec       = args[1]
    let rate        = expect StrConv.toU32(args[3])
    let channels    = cast(u16, expect StrConv.toU32(args[4]))
    let bandwidth   = args[5] == "voice" ? Aac.Bandwidth.Voice : Aac.Bandwidth.Full
    let repetitions = expect StrConv.toU32(args[7])
    let input       = expect File.readAllBytes(args[2])
    Swag.require(channels and repetitions and input.count and input.count % (2 * channels) == 0)
    let pcm = Swag.makeSlice(cast(const [*] s16, input.storage()), input.count / 2)

    for repeat in cast(u64, repetitions) + 1
    {
        var timing: Timing
        switch codec
        {
        case "wav":  timing = expect encodeLossless'Wav.Writer(args[6], pcm, rate, channels)
        case "flac": timing = expect encodeLossless'Flac.Writer(args[6], pcm, rate, channels)
        case "aac":  timing = expect encodeAac(args[6], pcm, rate, channels, bandwidth)
        default:     unreachable
        }

        if repeat
        {
            Console.println(timing.opened, " ", timing.fed - timing.opened, " ", timing.total - timing.fed, " ", timing.total, " ", pcm.count / channels, " ", timing.delay)
        }
    }
}
