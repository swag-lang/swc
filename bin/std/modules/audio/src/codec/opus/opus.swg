//! Format: Opus audio decoder.
//! Supported: RFC 6716 packets with every frame-packing code, the SILK, CELT, and hybrid modes at every bandwidth and frame size, mono and stereo streams on mono or stereo output, redundant transition frames, the output gain of the Ogg header, packets handed over raw or inside runs of Ogg pages, and the trimming the Ogg granule positions ask for.
//! Not supported: Packet-loss concealment, so an empty frame plays as silence and a mode switch coded without redundancy joins its neighbours without a concealed crossfade; and multistream channel mappings.
//! Role: This file owns Opus packet syntax, mode dispatch and mixing, and PCM output.
//
#global namespace Opus

using Core, Core.Errors, Core.Math

// Every Opus decoder produces 48 kHz output, whatever rate the stream was encoded from.
internal const OutputRate = 48_000'u32

// The most a packet may play, RFC 6716 clause 3.2.
private const MaxPacketFrames    = 5_760'u64
private const MaxFrameBytes      = 1275'u32
private const MaxFramesPerPacket = 48'u32

private const ModeSilk             = 1'u32
private const ModeHybrid           = 2'u32
private const ModeCelt             = 3'u32
private const BandwidthNarrow      = 1'u32
private const BandwidthMedium      = 2'u32
private const BandwidthWide        = 3'u32
private const BandwidthSuperWide   = 4'u32
private const BandwidthFull        = 5'u32
private const Frame20Ms            = 960'u32
private const Frame10Ms            = 480'u32
private const Frame5Ms             = 240'u32
private const Frame2Ms5            = 120'u32
private const SilenceFrame: [2] u8 = [0xFF, 0xFF]

// Returns the number of 48 kHz sample frames a packet plays, or zero for an invalid packet.
//
// The count follows from the table of contents alone, so an index can be built without decoding.
internal func packetFrames(packet: const [..] u8)->u64
{
    if !packet.count do
        return 0
    let toc    = cast(u32) packet[0]
    let config = toc >> 3
    let code   = toc & 3

    // Frame sizes in 48 kHz samples: 2.5, 5, 10, 20, 40, and 60 ms.
    var frameSize: u64
    if config < 12 do
        frameSize = 480'u64 << (config & 3)
    elif config < 16 do
        frameSize = 480'u64 << (config & 1)
    else do
        frameSize = 120'u64 << (config & 3)

    var frames = 1'u64
    if code == 1 or code == 2 do
        frames = 2
    elif code == 3
    {
        if packet.count < 2 do
            return 0
        frames = cast(u64) packet[1] & 63
        if !frames do
            return 0
    }

    let total = frames * frameSize
    return total <= MaxPacketFrames ? total : 0
}

// What the table of contents byte says about every frame of a packet.
private struct FrameInfo
{
    mode:           u32
    bandwidth:      u32
    frameSize:      u32
    streamChannels: u32
}

private func frameInfo(toc: u8)->FrameInfo
{
    var result: retval
    let value  = cast(u32) toc
    let config = value >> 3
    if value & 0x80
    {
        result.mode      = ModeCelt
        result.bandwidth = BandwidthMedium + ((value >> 5) & 3)
        if result.bandwidth == BandwidthMedium do
            result.bandwidth = BandwidthNarrow
        result.frameSize = 120'u32 << (config & 3)
    }
    elif (value & 0x60) == 0x60
    {
        result.mode      = ModeHybrid
        result.bandwidth = value & 0x10 ? BandwidthFull : BandwidthSuperWide
        result.frameSize = value & 0x08 ? Frame20Ms : Frame10Ms
    }
    else
    {
        result.mode      = ModeSilk
        result.bandwidth = BandwidthNarrow + ((value >> 5) & 3)
        result.frameSize = 480'u32 << (config & 3)
    }

    result.streamChannels = value & 0x04 ? 2'u32 : 1
    return result
}

private func smoothFade(first, second: const [*] f32, out: [*] f32, channels: u32)
{
    for i in Frame2Ms5
    {
        let w = CeltWindow[i] * CeltWindow[i]
        for c in channels do
            out[i * channels + c] = w * second[i * channels + c] + (1.0 - w) * first[i * channels + c]
    }
}

// Decodes Opus packets, one run of Ogg pages or one raw packet per call.
//
// The codec keeps the SILK and CELT states across frames and, when it decodes page runs, the
// granule position the last run ended on, which is what trims the first and last runs exactly as
// the container promised.
private struct Decoder
{
    // Every registered codec starts with the registry's own header: a voice destroys one through
    // this, reading back the concrete type and the allocator the instance was made with.
    using base: Audio.Codec

    channels:       u32
    gainQ8:         s32
    silk:           SilkDecoder
    celt:           CeltDecoder
    prevMode:       u32
    prevRedundancy: bool
    pcm:            Array'f32     // One frame of mixed output, interleaved.
    silkPcm:        Array's16     // One frame of SILK output at 48 kHz, interleaved.
    redundant:      Array'f32     // The 5 ms redundant CELT frame of a transition.
    output:         Array's16     // Interleaved samples of the run being decoded.
    packet:         Array'u8      // Packet being assembled across pages.

    serial:             u32
    firstAudioSequence: u32
    granule:            u64
    granuleKnown:       bool
}

private impl Decoder
{
    mtd resetState()
    {
        .silk.reset()
        .celt.reset()
        .prevMode       = 0
        .prevRedundancy = false
        .granuleKnown   = false
        .packet.clear()
    }

    // Reads the identification header, from the Ogg header pages or from the bare header a
    // Matroska track carries.
    mtd readConfig(config: const [..] u8) fail
    {
        var head: Array'u8
        if config.count >= 4 and config[0] == 'O' and config[1] == 'g' and config[2] == 'g' and config[3] == 'S'
        {
            var hasSerial = false
            var completed = 0'u32
            var offset    = 0'u64
            while offset < config.count and completed < 2
            {
                let page = try Ogg.readPageHeader(config, offset)
                if offset + page.totalBytes() > config.count do
                    fail InvalidFormatError{"Opus header pages are truncated"}
                let body = config[offset + page.headerBytes until offset + page.totalBytes()]
                if !hasSerial and (page.flags & Ogg.FirstPage) and body.count >= 8 and body[0] == 'O' and body[1] == 'p' and body[2] == 'u' and body[3] == 's' and body[4] == 'H' and body[5] == 'e' and body[6] == 'a' and body[7] == 'd'
                {
                    .serial   = page.serial
                    hasSerial = true
                }

                if hasSerial and page.serial == .serial
                {
                    var at = 0'u64
                    for index in page.segments
                    {
                        let size = cast(u64) page.lacing[index]
                        if completed == 0 do
                            head.add(body[at until at + size])
                        at += size
                        if size < 255
                        {
                            completed += 1
                            if completed == 2
                            {
                                .firstAudioSequence = page.sequence + 1
                                break
                            }
                        }
                    }
                }

                offset += page.totalBytes()
            }

            if completed < 2 do
                fail InvalidFormatError{"Opus stream ends inside its header packets"}
        }
        else do
            head.add(config)

        if head.count < 19 or head[0] != 'O' or head[1] != 'p' or head[2] != 'u' or head[3] != 's' or head[4] != 'H' or head[5] != 'e' or head[6] != 'a' or head[7] != 'd' do
            fail InvalidFormatError{"Opus identification header is missing"}
        if (head[8] >> 4) != 0 do
            fail UnsupportedFormatError{"Opus stream uses an unknown version"}
        .channels = cast(u32) head[9]
        if !.channels or .channels > 2 do
            fail UnsupportedFormatError{"Opus stream needs one or two channels"}
        .gainQ8 = cast(s32) cast #bit (s16) (cast(u16) head[16] | (cast(u16) head[17] << 8))
        if head[18] != 0 do
            fail UnsupportedFormatError{"Opus stream uses a multistream channel mapping"}
    }

    // Decodes one frame of a packet and appends its samples to `.output`.
    mtd decodeFrame(data: const [..] u8, info: FrameInfo) fail
    {
        let CC        = .channels
        let frameSize = info.frameSize
        let mode      = info.mode
        let base      = .output.count
        .output.resize(base + cast(u64) frameSize * CC)
        let pcm = .pcm.buffer!
        for i in frameSize * CC do
            pcm[i] = 0

        // A frame of one byte or none is a request for concealment; a file plays it as silence.
        if data.count <= 1
        {
            for i in frameSize * CC do
                .output[base + i] = 0
            .prevMode = mode
            return
        }

        var dec = RangeDecoder.create(data)
        var len = cast(s32) data.count

        if mode != ModeCelt
        {
            if .prevMode == ModeCelt do
                .silk.reset()
            let payloadMs    = Math.max(10'u32, 1000 * frameSize / OutputRate)
            var internalRate = 16_000'u32
            if mode == ModeSilk
            {
                if info.bandwidth == BandwidthNarrow do
                    internalRate = 8_000
                elif info.bandwidth == BandwidthMedium do
                    internalRate = 12_000
            }

            var decoded = 0'u32
            let silkOut = .silkPcm.buffer!
            while decoded < frameSize
            {
                let produced = try .silk.decode(&dec, decoded == 0, payloadMs, internalRate, info.streamChannels, silkOut + decoded * CC)
                if !produced do
                    fail InvalidFormatError{"Opus SILK frame decoded to nothing"}
                decoded += produced
            }
        }

        var startBand       = 0'u32
        var redundancy      = false
        var celtToSilk      = false
        var redundancyBytes = 0's32
        if mode != ModeCelt and dec.tell() + 17 + (mode == ModeHybrid ? 20 : 0) <= 8 * len
        {
            redundancy = mode == ModeHybrid ? dec.decodeBit(12) : true
            if redundancy
            {
                celtToSilk      = dec.decodeBit(1)
                redundancyBytes = mode == ModeHybrid ? cast(s32) dec.decodeUint(256) + 2 : len - ((dec.tell() + 7) >> 3)
                len             -= redundancyBytes
                if len * 8 < dec.tell()
                {
                    len             = 0
                    redundancyBytes = 0
                    redundancy      = false
                }

                dec.storage -= cast(u32) redundancyBytes
            }
        }

        if mode != ModeCelt do
            startBand = 17
        var endBand = CeltBandCount
        switch info.bandwidth
        {
        case BandwidthNarrow:                endBand = 13
        case BandwidthMedium, BandwidthWide: endBand = 17
        case BandwidthSuperWide:             endBand = 19
        default:                             endBand = 21
        }

        .celt.streamChannels = info.streamChannels
        .celt.endBand        = endBand
        let usable    = cast(u64) len
        let redundant = .redundant.buffer!
        if redundancy and celtToSilk
        {
            .celt.startBand = 0
            let bytes = data[usable until usable + cast(u64) redundancyBytes]
            var rdec  = RangeDecoder.create(bytes)
            try .celt.decodeFrame(bytes, &rdec, Frame5Ms, redundant)
        }

        .celt.startBand = startBand
        if mode != ModeSilk
        {
            let celtFrameSize = Math.min(Frame20Ms, frameSize)
            if mode != .prevMode and .prevMode > 0 and !.prevRedundancy do
                .celt.reset()
            try .celt.decodeFrame(data[0 until usable], &dec, celtFrameSize, pcm)
        }
        elif .prevMode == ModeHybrid and !(redundancy and celtToSilk and .prevRedundancy)
        {
            // Let the CELT overlap fade out through a frame of silence.
            .celt.startBand = 0
            var sdec = RangeDecoder.create(SilenceFrame)
            try .celt.decodeFrame(SilenceFrame, &sdec, Frame2Ms5, pcm)
        }

        if mode != ModeCelt
        {
            let silkOut = .silkPcm.buffer!
            for i in frameSize * CC do
                pcm[i] += cast(f32) silkOut[i] * (1.0 / 32768.0)
        }

        if redundancy and !celtToSilk
        {
            .celt.reset()
            .celt.startBand = 0
            let bytes = data[usable until usable + cast(u64) redundancyBytes]
            var rdec  = RangeDecoder.create(bytes)
            try .celt.decodeFrame(bytes, &rdec, Frame5Ms, redundant)
            let tail = pcm + (frameSize - Frame2Ms5) * CC
            smoothFade(tail, redundant + Frame2Ms5 * CC, tail, CC)
        }

        if redundancy and celtToSilk and (.prevMode != ModeSilk or .prevRedundancy)
        {
            for i in Frame2Ms5 * CC do
                pcm[i] = redundant[i]
            smoothFade(redundant + Frame2Ms5 * CC, pcm + Frame2Ms5 * CC, pcm + Frame2Ms5 * CC, CC)
        }

        if .gainQ8
        {
            let gain = cast(f32) Math.exp(0.6931471805599453 * 6.48814081e-4 * cast(f64) .gainQ8)
            for i in frameSize * CC do
                pcm[i] *= gain
        }

        .prevMode       = mode
        .prevRedundancy = redundancy and !celtToSilk
        for i in frameSize * CC do
            .output[base + i] = cast(s16) Math.clamp(Math.round(cast(f64) pcm[i] * 32768.0), -32768.0, 32767.0)
    }

    // Splits a packet into its frames, RFC 6716 clause 3.2, and decodes each of them.
    mtd decodePacketFrames(packet: const [..] u8)->u64 fail
    {
        if !packet.count do
            fail InvalidFormatError{"Opus packet is empty"}
        let info  = frameInfo(packet[0])
        var sizes: [MaxFramesPerPacket] u32
        var count = 1'u32
        var pos   = 1'u64
        var len   = cast(s64) packet.count - 1
        switch cast(u32) packet[0] & 3
        {
        case 0:
            sizes[0] = cast(u32) len

        case 1:
            if len & 1 do
                fail InvalidFormatError{"Opus packet splits an odd length into two equal frames"}
            count    = 2
            sizes[0] = cast(u32) (len / 2)
            sizes[1] = sizes[0]

        case 2:
            count = 2
            let first = try parseFrameSize(packet, &pos, &len)
            sizes[0] = first
            sizes[1] = cast(u32) len - first

        default:
            if len < 1 do
                fail InvalidFormatError{"Opus packet is truncated"}
            let flags = cast(u32) packet[pos]
            pos   += 1
            len   -= 1
            count = flags & 63
            if !count or cast(u64) info.frameSize * count > MaxPacketFrames do
                fail InvalidFormatError{"Opus packet states an invalid frame count"}
            if flags & 0x40
            {
                while true
                {
                    if len <= 0 do
                        fail InvalidFormatError{"Opus packet padding is truncated"}
                    let p = cast(s64) packet[pos]
                    pos += 1
                    len -= 1
                    len -= p == 255 ? 254 : p
                    if p != 255 do
                        break
                }

                if len < 0 do
                    fail InvalidFormatError{"Opus packet padding exceeds the packet"}
            }

            if flags & 0x80
            {
                var last = len
                for i in count - 1
                {
                    let before = len
                    sizes[i] = try parseFrameSize(packet, &pos, &len)
                    last     -= (before - len) + cast(s64) sizes[i]
                }

                if last < 0 do
                    fail InvalidFormatError{"Opus packet frame sizes exceed the packet"}
                sizes[count - 1] = cast(u32) last
            }
            else
            {
                let each = len / count
                if each * count != len do
                    fail InvalidFormatError{"Opus packet length is not a multiple of its frame count"}
                for i in count do
                    sizes[i] = cast(u32) each
            }
        }

        if sizes[count - 1] > MaxFrameBytes do
            fail InvalidFormatError{"Opus frame is larger than the format allows"}
        for i in count
        {
            if pos + sizes[i] > packet.count do
                fail InvalidFormatError{"Opus frame runs past its packet"}
            try .decodeFrame(packet[pos until pos + sizes[i]], info)
            pos += sizes[i]
        }

        return cast(u64) info.frameSize * count
    }

    // Decodes every packet of one run of pages and returns the frames the run completes, after
    // the trimming its granule positions ask for.
    mtd decodeRun(run: const [..] u8)->u64 fail
    {
        var produced      = 0'u64
        var lastGranule   = Ogg.NoGranule
        var firstSequence = Swag.U32.Max
        var offset        = 0'u64
        .packet.clear()
        while offset < run.count
        {
            let page = try Ogg.readPageHeader(run, offset)
            if offset + page.totalBytes() > run.count do
                fail InvalidFormatError{"Ogg page run is truncated"}
            if page.serial == .serial
            {
                if firstSequence == Swag.U32.Max do
                    firstSequence = page.sequence
                if page.granule != Ogg.NoGranule do
                    lastGranule = page.granule
                let body = run[offset + page.headerBytes until offset + page.totalBytes()]
                var at   = 0'u64
                for index in page.segments
                {
                    let size = cast(u64) page.lacing[index]
                    .packet.add(body[at until at + size])
                    at += size
                    if size < 255
                    {
                        if .packet.count do
                            produced += try .decodePacketFrames(.packet.toSlice())
                        .packet.clear()
                    }
                }
            }

            offset += page.totalBytes()
        }

        if lastGranule == Ogg.NoGranule do
            return produced

        // The first run starts at position zero and the later ones where the previous one ended;
        // a run decoded fresh after a seek knows neither, and keeps what it produced.
        var expected = produced
        if firstSequence == .firstAudioSequence do
            expected = Math.min(produced, lastGranule)
        elif .granuleKnown
        {
            if lastGranule < .granule do
                fail InvalidFormatError{"Ogg granule position runs backwards"}
            expected = lastGranule - .granule
        }

        if produced > expected do
            .output.resize(expected * .channels)
        elif produced < expected
        {
            .output.resize(expected * .channels)
            for index in produced * .channels until expected * .channels do
                .output[index] = 0
        }

        .granule      = lastGranule
        .granuleKnown = true
        return expected
    }
}

impl IPacketCodec for Decoder
{
    mtd impl canDecode(encoding: SoundFileEncoding)->bool => encoding == .Opus

    mtd impl initialize(config: const [..] u8, sampleRateHz, channels: u32) fail
    {
        try .readConfig(config)
        if sampleRateHz != OutputRate or .channels != channels do
            fail InvalidFormatError{"Opus stream shape differs from its container track"}
        .silk = SilkDecoder.create(.channels)
        .celt = CeltDecoder.create(.channels)
        .pcm.resize(cast(u64) Frame20Ms * 3 * .channels)
        .silkPcm.resize(cast(u64) Frame20Ms * 3 * .channels)
        .redundant.resize(cast(u64) Frame5Ms * .channels)
        .resetState()
    }

    mtd impl reset() => .resetState()

    mtd impl decodePacket(destination: [*] void, destinationSize: u64, packet: const [..] u8)->u64 fail
    {
        .output.clear()
        var frames: u64
        if packet.count >= 4 and packet[0] == 'O' and packet[1] == 'g' and packet[2] == 'g' and packet[3] == 'S' do
            frames = try .decodeRun(packet)
        else do
            frames = try .decodePacketFrames(packet)

        // A container's index is the authority on what a packet contributes: the discard padding
        // a Matroska block declares shortens the last packet below what its table of contents says.
        let produced = Math.min(frames * .channels * #sizeof(s16), destinationSize)
        if produced do
            Memory.copy(destination, .output.buffer!, produced)
        return produced
    }
}

// Reads one frame size of a code-3 packet: one byte below 252, two bytes otherwise.
private func parseFrameSize(packet: const [..] u8, pos: *u64, len: *s64)->u32 fail
{
    if len[] < 1 do
        fail InvalidFormatError{"Opus packet frame size is truncated"}
    let first = cast(u32) packet[pos[]]
    if first < 252
    {
        pos[] += 1
        len[] -= 1
        if cast(s64) first > len[] do
            fail InvalidFormatError{"Opus frame size exceeds the packet"}
        return first
    }

    if len[] < 2 do
        fail InvalidFormatError{"Opus packet frame size is truncated"}
    let size = 4 * cast(u32) packet[pos[] + 1] + first
    pos[] += 2
    len[] -= 2
    if cast(s64) size > len[] do
        fail InvalidFormatError{"Opus frame size exceeds the packet"}
    return size
}

#init
{
    registerPacketCodec'Decoder()
}
