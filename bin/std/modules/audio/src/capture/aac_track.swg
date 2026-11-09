//! Format: timestamped AAC-LC capture track.
//! Supported: mono/stereo PCM16 at 44.1 or 48 kHz, bounded gap filling, and encoder priming.
//! Role: This file turns capture-queue blocks into mux-ready audio packets without storing a recording.
//
#global public

using Core, Core.Errors

// Describes one AAC-LC access unit from [[Audio.CaptureAacTrack]].
struct CaptureAacPacket
{
    public
    {
        startSample:       u64  // Encoded packet start on the output sample clock.
        validFrames:       u32  // Input frames represented by this packet, excluding final padding.
        syntheticFrames:   u32  // Frames inserted for a missing capture block or lost source.
        sourceInterrupted: bool // A device restoration contributed PCM to this packet.
    }
}

// Converts a timestamped PCM16 queue into a continuous AAC-LC track in bounded memory.
//
// Each `nextPacket` emits at most one access unit, so even a multi-hour source outage uses one
// fixed zero block and one packet buffer. Queued timing gaps and queue overflows become encoded
// silence. While the source is marked lost, the track can fill through the queue's committed
// sample end without waiting for a new capture block. `finish` drains the encoder after the
// producer has stopped. The caller writes packet bytes and timestamps to its container and
// compensates [[Audio.CaptureAacTrack.encoderDelayFrames]] in playback or export.
// Input and output sample rates are equal in this first bridge; drift resampling is a separate
// clock-control step. Keep the queue alive until this track is finished.
#[Swag.NoCopy]
struct CaptureAacTrack
{
    private
    {
        late queue:         *CaptureQueue
        encoder:            Aac.StreamEncoder
        captured:           Array's16
        current:            CaptureBlock
        zeros:              [2 * 1_024] s16
        channels:           u16
        capturedOffset:     u64
        nextInputSample:    u64
        gapFrames:          u64
        syntheticInPacket:  u32
        pendingInterrupted: bool
        packetInterrupted:  bool
        finishing:          bool
        finished:           bool
    }
}

impl CaptureAacTrack
{
    // Creates a track at its queue's PCM rate and channel count.
    //
    // The queue must use one or two channels at 44.1 or 48 kHz. The AAC encoder accepts 1024
    // frames per packet; an arbitrary queue block may be smaller or larger than that.
    func create(queue: *CaptureQueue, bandwidth: Aac.Bandwidth = .Full)->CaptureAacTrack fail
    {
        with var result: #returntype
        {
            .queue = queue
            .channels = queue.channelCount()
            .encoder = try Aac.StreamEncoder.create(queue.sampleRateHz(), .channels, bandwidth)
        }
        return result
    }

    // Returns the two-byte AAC-LC AudioSpecificConfig for a container track.
    mtd const decoderConfig()->const [..] u8 => .encoder.decoderConfig()

    // Returns the packet sample rate in frames per second.
    mtd const sampleRateHz()->u32 => .encoder.sampleRateHz()

    // Returns the AAC priming delay that a container timeline must compensate.
    mtd const encoderDelayFrames()->u32 => .encoder.encoderDelayFrames()

    // Returns the number of timeline frames submitted to the AAC encoder so far.
    mtd const inputFrameCount()->u64 => .nextInputSample

    // Produces one AAC access unit from currently available capture blocks or source-loss time.
    //
    // Returns false with an empty `packet` when no complete unit is ready. A later call may
    // succeed after the producer submits another block or advances the lost-source timeline.
    mtd nextPacket(packet: *Array'u8, info: *CaptureAacPacket)->bool fail
    {
        if .finishing do
            fail BadParameterError{"capture AAC track has begun finalization"}
        return try .pull(packet, info)
    }

    // Completes queued input, padding the final packet and draining AAC's transform overlap.
    //
    // Stop the capture producer first. Call repeatedly until false; each successful call returns
    // one packet. Repeated calls after completion return false with an empty output array.
    mtd finish(packet: *Array'u8, info: *CaptureAacPacket)->bool fail
    {
        packet.clear()
        if .finished do
            return false
        .finishing = true
        if try .pull(packet, info) do
            return true
        if try .encoder.finish(packet)
        {
            .describePacket(info)
            return true
        }
        .finished = true
        return false
    }
}

private impl CaptureAacTrack
{
    mtd pull(packet: *Array'u8, info: *CaptureAacPacket)->bool fail
    {
        packet.clear()
        for
        {
            if .gapFrames
            {
                let frames = Math.min(.gapFrames, 1_024'u64)
                let consumed = try .encoder.push(Swag.makeSlice(&.zeros[0], frames * .channels), packet)
                .gapFrames -= consumed
                .nextInputSample += consumed
                .syntheticInPacket += cast(u32, consumed)
                if packet.count
                {
                    .describePacket(info)
                    return true
                }
                continue
            }

            if .capturedOffset < .current.frameCount
            {
                .packetInterrupted = .packetInterrupted or .pendingInterrupted
                .pendingInterrupted = false
                let start = .capturedOffset * .channels
                let consumed = try .encoder.push(.captured.toSlice()[start until .current.frameCount * .channels], packet)
                .capturedOffset += consumed
                .nextInputSample += consumed
                if packet.count
                {
                    .describePacket(info)
                    return true
                }
                continue
            }

            if .queue.pop(&.captured, &.current)
            {
                .capturedOffset = .nextInputSample > .current.startSample ?
                                  Math.min(.nextInputSample - .current.startSample, .current.frameCount) : 0
                .pendingInterrupted = .current.sourceInterrupted
                if .current.startSample > .nextInputSample do
                    .gapFrames = .current.startSample - .nextInputSample
                continue
            }

            let lostEnd = .queue.silentGapEnd()
            if lostEnd > .nextInputSample
            {
                .gapFrames = lostEnd - .nextInputSample
                continue
            }
            return false
        }
    }

    mtd describePacket(info: *CaptureAacPacket)
    {
        info.startSample = .encoder.lastPacketStartSample()
        info.validFrames = .encoder.lastPacketValidFrames()
        info.syntheticFrames = .syntheticInPacket
        info.sourceInterrupted = .packetInterrupted
        .syntheticInPacket = 0
        .packetInterrupted = false
    }
}
