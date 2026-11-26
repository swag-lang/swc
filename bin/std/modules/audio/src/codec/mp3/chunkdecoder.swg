//! MPEG Layer III audio ranges with independent, reservoir-seeded decode lanes.

#global namespace Mp3
#global internal

using Core, Core.Errors

// At most 32 packets of PCM per lane are staged before delivering the next callback.
private const ChunkPackets = 32'u64
private const MaxLanes     = 4'u64

// MPEG-1 at 320 kb/s and 32 kHz reaches this bound with padding.
private const MaxFrameBytes   = 1441'u64
private const MaxFrameSamples = 1152'u64

private struct Reservoir
{
    size:  u64
    bytes: [ReservoirBytes] u8
}

// A delayed frame carries the unused reservoir that existed immediately before it.
private struct PrerollFrame
{
    preceding: Reservoir
    frame:     PreparedFrame
    size:      u64
    payload:   [MaxFrameBytes] u8
}

private struct ChunkEntry
{
    frame:  PreparedFrame
    offset: u64
    size:   u64
    frames: u32
}

private struct ChunkDecoder
{
    codec:      Codec
    entries:    Array'ChunkEntry
    mainData:   Array'u8
    samples:    Array's16
    warmCount:  u64
    outputSize: u64
}

private impl ChunkDecoder
{
    mtd reset(channels: u32)
    {
        .codec.resetState()
        .codec.channels = channels
        .codec.mainData.reserve(MaxFrameBytes + ReservoirBytes)
        .entries.clear()
        .entries.reserve(ChunkPackets + 2)
        .mainData.clear()
        .mainData.reserve((ChunkPackets + 2) * MaxFrameBytes)
        .samples.reserve(ChunkPackets * MaxFrameSamples * channels)
        .warmCount  = 0
        .outputSize = 0
    }

    mtd append(frame: const *PreparedFrame, payload: const [..] u8)
    {
        .entries.add(ChunkEntry{frame[], .mainData.count, payload.count, frame.header.frameSamples})
        .mainData.add(payload)
    }

    mtd decode()
    {
        var at = 0'u64
        for index in .entries.count
        {
            let entry = &.entries[index]
            if not entry.frame.header.frameSamples do
                continue

            let payload = .mainData.toSlice()[entry.offset until entry.offset + entry.size]
            .codec.decodeFrame(&entry.frame, payload)
            if index >= .warmCount
            {
                .codec.writePcm16(.samples.storage() + at, entry.frames)
                at += cast(u64, entry.frames) * .codec.channels
            }
        }
    }

    // Only the caller delivers PCM, in packet order and with the serial callback boundaries.
    mtd const deliver(discardFrames, remaining: *u64, gap: *Array's16, consumer: SoundPcm16Consumer)->bool
    {
        let channels = cast(u64, .codec.channels)
        var at       = 0'u64
        for index in .warmCount until .entries.count
        {
            let entry  = &.entries[index]
            let frames = cast(u64, entry.frames)
            let skip   = Math.min(discardFrames[], frames)
            discardFrames[] -= skip
            let count = Math.min(remaining[], frames - skip)
            if count
            {
                var pcm: const [..] s16
                if entry.frame.header.frameSamples
                {
                    let from = at + skip * channels
                    pcm = .samples.toSlice()[from until from + count * channels]
                }
                else
                {
                    // There is no codec frame or history update for a timestamp gap.
                    gap.resize(count * channels)
                    pcm = gap.toSlice()
                }

                remaining[] -= count
                if not consumer(pcm) or not remaining[] do
                    return false
            }

            if entry.frame.header.frameSamples do
                at += frames * channels
        }

        return true
    }
}

private struct ChunkPlanner
{
    source:    ByteSource
    reservoir: Reservoir
    history:   [2] PrerollFrame
    next:      u64
    saved:     u64
}

private impl ChunkPlanner
{
    mtd const startChunk(chunk: *ChunkDecoder, sampleRate, channels: u32)
    {
        chunk.reset(channels)

        // One granule restores MDCT overlap. The following granule replaces all sixteen
        // synthesis slots. MPEG-1 carries both granules in one packet, LSF needs two.
        let wanted = sampleRate >= 32_000 ? 1'u64 : 2
        let count  = Math.min(wanted, .saved)
        if not count do
            return
        let first = (.next + 2 - count) & 1
        let seed  = &.history[first].preceding
        chunk.codec.mainData.add(seed.bytes[until seed.size])
        chunk.codec.reservoirSize = seed.size

        for i in count
        {
            let entry = &.history[(first + i) & 1]
            chunk.append(&entry.frame, entry.payload[until entry.size])
        }

        chunk.warmCount = count
    }

    mtd read(packet: SoundPacket, sampleRate, channels: u32, chunk: *ChunkDecoder?) fail
    {
        if not packet.byteSize
        {
            if chunk
            {
                var gap: ChunkEntry
                gap.frames = packet.sampleFrameCount
                chunk.entries.add(gap)
            }

            return
        }

        try .source.seek(packet.sourceOffset)
        let window = try .source.peek(packet.byteSize)
        let bytes  = window[until packet.byteSize]

        let samples = cast(u64, packet.sampleFrameCount) * channels
        let frame   = try prepareFrame(bytes, samples * #sizeof(s16), sampleRate, channels)
        if frame.header.frameSamples != packet.sampleFrameCount do
            fail InvalidFormatError{"compressed sound packet decoded to an unexpected size"}
        let payload = bytes[frame.payloadOffset until frame.header.frameBytes]
        if chunk
        {
            chunk.append(&frame, payload)
            chunk.outputSize += samples
        }

        let history = &.history[.next]
        history.preceding = .reservoir
        history.frame     = frame
        history.size      = payload.count
        if payload.count do
            Memory.copy(&history.payload[0], payload.buffer, payload.count)
        .next  = (.next + 1) & 1
        .saved = Math.min(.saved + 1, 2)

        // The decoder always seeks to the declared end of each granule's main data.
        // Its next reservoir is therefore the unconsumed suffix, even for a malformed
        // spectral code. When history is missing it consumes no bits and resets synthesis.
        let available = Math.min(frame.mainDataBegin, .reservoir.size)
        var bits      = 0'u64
        if available == frame.mainDataBegin
        {
            for granule in frame.header.granules
            {
                for channel in channels do
                    bits += frame.granules[granule, channel].part23Length
            }
        }

        let total       = available + payload.count
        let consumed    = Math.min(total, (bits + 7) / 8)
        let kept        = Math.min(total - consumed, ReservoirBytes)
        let fromPayload = Math.min(kept, payload.count)
        let fromHistory = kept - fromPayload
        if fromHistory do
            Memory.copyOverlapping(&.reservoir.bytes[0], &.reservoir.bytes[.reservoir.size - fromHistory], fromHistory)
        if fromPayload do
            Memory.copy(&.reservoir.bytes[fromHistory], payload.buffer + payload.count - fromPayload, fromPayload)
        .reservoir.size = kept
    }
}

// Handles a large audible range with independent decoder states. False leaves the
// range untouched for the sequential path.
func decodeParallel(sound: const *SoundFile, firstFrame, frameCount: u64, consumer: SoundPcm16Consumer)->bool fail
{
    if not frameCount do
        return false
    let decodedTarget = sound.leadingTrim + firstFrame
    let firstPacket   = sound.packetAtDecodedFrame(decodedTarget)
    let endPacket     = sound.packetAtDecodedFrame(decodedTarget + frameCount - 1) + 1
    if endPacket - firstPacket < 2 * ChunkPackets do
        return false

    let lanes = Math.min(cast(u64, Swag.workerCount()), MaxLanes)
    if lanes < 2 do
        return false

    // Arbitrary packet streams may include padding or long timestamp gaps. Leave those
    // to the serial path so every parallel lane stays within the MPEG frame bounds.
    for i in endPacket
    {
        let packet = sound.packets[i]
        if packet.byteSize > MaxFrameBytes or packet.sampleFrameCount > MaxFrameSamples do
            return false
    }

    try decodeChunks(sound, firstFrame, frameCount, lanes, consumer)
    return true
}

// Decodes a validated range of bounded packets. Each lane owns all state it mutates.
func decodeChunks(sound: const *SoundFile, firstFrame, frameCount, lanes: u64, consumer: SoundPcm16Consumer) fail
{
    let decodedTarget = sound.leadingTrim + firstFrame
    let firstPacket   = sound.packetAtDecodedFrame(decodedTarget)
    let endPacket     = sound.packetAtDecodedFrame(decodedTarget + frameCount - 1) + 1
    var planner: ChunkPlanner
    planner.source = try ByteSource.openFile(sound.path.toString(), .ReadWrite)
    let sampleRate = sound.sampleRate
    let channels   = sound.channelCount
    for index in firstPacket do
        try planner.read(sound.packets[index], sampleRate, channels, null)

    var chunks: [MaxLanes] ChunkDecoder
    var gap:    Array's16
    var index         = firstPacket
    var discardFrames = decodedTarget - sound.packetStarts[firstPacket]
    var remaining     = frameCount
    while index < endPacket
    {
        var group:   Swag.TaskGroup
        var count = 0'u64
        var pending: Swag.Error
        for lane in lanes
        {
            if index == endPacket or not pending.isEmpty() do
                break
            let chunk = &chunks[lane]
            planner.startChunk(chunk, sampleRate, channels)
            for Math.min(ChunkPackets, endPacket - index)
            {
                // Keep a later packet's error until all earlier available PCM has been
                // delivered. Cancellation can leave that error unobservable, as in serial.
                catch planner.read(sound.packets[index], sampleRate, channels, chunk)
                {
                    pending.capture(Swag.err)
                    break
                }

                index += 1
            }

            if chunk.entries.count > chunk.warmCount
            {
                chunk.samples.resize(chunk.outputSize)
                count += 1
                if lane + 1 < lanes and index < endPacket and pending.isEmpty() do
                    group.spawn(func|chunk|() => chunk.decode())
                else do
                    chunk.decode()
            }
        }

        group.wait()
        for lane in count
        {
            if not chunks[lane].deliver(&discardFrames, &remaining, &gap, consumer) do
                return
        }

        try pending.raise()
    }
}
