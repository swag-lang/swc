//! Format: streaming MPEG-4 AAC Low Complexity encoder.
//! Supported: arbitrarily chunked interleaved PCM16 at 44.1 or 48 kHz, mono or stereo.
//! Role: This file buffers capture input into AAC access units with sample-clock metadata.
//
#global namespace Aac
#global export

using Core, Core.Errors

// Buffers live PCM16 input into 1024-frame AAC-LC access units in bounded memory.
//
// `push` consumes at most the samples needed for one packet, and returns the number of input
// frames consumed. A nonempty `packet` is ready for the caller to write before calling `push`
// again. `finish` emits a zero-padded partial packet, then a drain packet for the transform
// overlap. `lastPacketStartSample` and `lastPacketValidFrames` describe the input assigned to
// each packet. AAC decoding has a 1024-frame priming delay; the container must compensate it
// for sample-accurate sync. The caller owns and may reuse each output packet array.
#[Swag.NoCopy]
struct StreamEncoder
{
    private
    {
        encoder:               Encoder
        pending:               [2 * 1_024] s16
        channels:              u16
        pendingFrames:         u32
        inputFrames:           u64
        emittedPackets:        u64
        lastStart:             u64
        lastValid:             u32
        drained:               bool
        ended:                 bool
    }
}

impl StreamEncoder
{
    // Creates a bounded AAC stream encoder with the selected spectral bandwidth.
    func create(sampleRate: u32, channels: u16, bandwidth: Bandwidth = .Full)->StreamEncoder fail
    {
        var result: #returntype
        result.encoder  = try Encoder.create(sampleRate, channels, bandwidth)
        result.channels = channels
        return result
    }

    // Returns the AAC-LC AudioSpecificConfig to place in a container track.
    mtd const decoderConfig()->const [..] u8 => .encoder.decoderConfig()

    // Returns the number of PCM channels accepted by `push`.
    mtd const channelCount()->u16 => .channels

    // Returns the configured sample rate in frames per second.
    mtd const sampleRateHz()->u32 => .encoder.sampleRateHz()

    // Returns the upper frequency retained by the selected bandwidth profile.
    mtd const upperFrequencyHz()->u32 => .encoder.upperFrequencyHz()

    // Returns the AAC priming delay, which a container or playback timeline must remove.
    mtd const encoderDelayFrames()->u32 => 1_024

    // Returns the number of complete input frames consumed so far.
    mtd const inputFrameCount()->u64 => .inputFrames

    // Returns the number of AAC access units produced so far, including the drain packet.
    mtd const packetCount()->u64 => .emittedPackets

    // Returns the sample-clock start of the most recently produced access unit.
    mtd const lastPacketStartSample()->u64 => .lastStart

    // Returns the number of non-padding input frames in the last access unit.
    //
    // A drain packet has zero valid input frames; a partial final packet has fewer than 1024.
    mtd const lastPacketValidFrames()->u32 => .lastValid

    // Consumes up to one AAC packet's worth of complete interleaved PCM16 frames.
    //
    // Returns input frames consumed, which can be less than the supplied count. A nonempty
    // `packet` contains one access unit. Keep calling with the unconsumed suffix until all
    // input is accepted. Invalid input leaves the stream and the caller's packet unchanged.
    mtd push(samples: const [..] s16, packet: *Array'u8)->u64 fail
    {
        if .ended do
            fail BadParameterError{"cannot append to a finished AAC stream"}
        if samples.count % .channels do
            fail BadParameterError{"AAC stream input must contain complete frames"}
        let frames = Math.min(samples.count / .channels, 1_024'u64 - .pendingFrames)
        if frames > Swag.U64.Max - .inputFrames do
            fail OverflowError{"AAC stream input frame count overflows"}
        packet.clear()
        if not frames do
            return 0
        Memory.copy(&.pending[cast(u64, .pendingFrames) * .channels], samples.buffer,
                    frames * .channels * #sizeof(s16))
        .pendingFrames += cast(u32, frames)
        .inputFrames += frames
        if .pendingFrames == 1_024 do
            try .emit(packet, 1_024)
        return frames
    }

    // Emits any padded final packet and one transform drain packet, one packet per call.
    //
    // Returns true while a packet was produced. Call until false before closing the recording;
    // repeated calls after completion return false and clear `packet`. An empty stream emits none.
    mtd finish(packet: *Array'u8)->bool fail
    {
        packet.clear()
        if .ended do
            return false
        if .pendingFrames
        {
            let valid = .pendingFrames
            for index in cast(u64, .pendingFrames) * .channels until 1_024'u64 * .channels do
                .pending[index] = 0
            try .emit(packet, valid)
            return true
        }
        if .emittedPackets and not .drained
        {
            for index in 1_024'u64 * .channels do
                .pending[index] = 0
            try .emit(packet, 0)
            .drained = true
            .ended = true
            return true
        }
        .ended = true
        return false
    }
}

private impl StreamEncoder
{
    mtd emit(packet: *Array'u8, validFrames: u32) fail
    {
        try .encoder.encode(Swag.makeSlice(&.pending[0], 1_024'u64 * .channels), packet)
        .lastStart      = .emittedPackets * 1_024
        .lastValid      = validFrames
        .emittedPackets += 1
        .pendingFrames = 0
    }
}
