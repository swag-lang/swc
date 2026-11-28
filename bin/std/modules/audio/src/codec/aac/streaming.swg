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
// again. `finish` emits any queued input, zero-pads the last partial block and drains the
// transform overlap. `lastPacketStartSample` and `lastPacketValidFrames` describe the input assigned to
// each packet. AAC decoding has a 1024-frame priming delay; the container must compensate it
// for sample-accurate sync. The caller owns and may reuse each output packet array.
#[Swag.NoCopy]
struct StreamEncoder
{
    private
    {
        encoder:        Encoder
        pending:        [2 * 1_024] s16
        buffered:       Array!{s16}
        bufferedFrames: u32
        window:         EncodeWindow
        nextShort:      bool
        channels:       u16
        packetBudget:   u64
        packetCredit:   u64
        pendingFrames:  u32
        inputFrames:    u64
        emittedPackets: u64
        lastStart:      u64
        lastValid:      u32
        drained:        bool
        finalizing:     bool
        ended:          bool
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

    // Creates an AAC stream that switches to short windows around detected attacks.
    //
    // One block of 1024 input frames is retained for lookahead. The first complete input
    // block produces no packet. Subsequent packets describe the oldest buffered input.
    // Call [[Audio.Aac.StreamEncoder.finish]] until it returns false to drain the stream.
    // The coded priming delay remains 1024 frames.
    func createAdaptive(sampleRate: u32, channels: u16, bandwidth: Bandwidth = .Full)->StreamEncoder fail
    {
        var result = try StreamEncoder.create(sampleRate, channels, bandwidth)
        result.buffered.resize(1_024_u64 * channels)
        result.encoder.prepareShortWindows()
        return result
    }

    // Creates an AAC encoder with a bounded payload rate across coded audio.
    //
    // The ceiling is rounded down to whole payload bytes per 1024 coded frames.
    // Unused bytes carry forward up to three access units' worth. The budget includes
    // packets used for priming and draining. The caller accounts for container headers.
    // A ceiling below the minimum access unit size fails with [[Core.Errors.BadParameterError]].
    func createRateLimited(sampleRate: u32, channels: u16, bitsPerSecond: u32, bandwidth: Bandwidth = .Full)->StreamEncoder fail
    {
        var result = try StreamEncoder.create(sampleRate, channels, bandwidth)
        result.packetBudget = cast(u64, bitsPerSecond) * 1_024 / (8 * sampleRate)
        let minimum = channels == 1 ? 6 : bandwidth == .Voice ? 10 : 11
        if result.packetBudget < minimum
        {
            fail BadParameterError{"AAC payload limit is too small for its channel configuration"}
        }

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
    // input is accepted. No input is accepted after [[Audio.Aac.StreamEncoder.finish]] begins.
    // Invalid input leaves the stream and the caller's packet unchanged.
    mtd push(samples: const [..] s16, packet: *Array!{u8})->u64 fail
    {
        if .finalizing
        {
            fail BadParameterError{"cannot append to an AAC stream after finish has begun"}
        }

        if samples.count % .channels
        {
            fail BadParameterError{"AAC stream input must contain complete frames"}
        }

        let frames = Math.min(samples.count / .channels, 1_024_u64 - .pendingFrames)
        if frames > Swag.U64.Max - .inputFrames
        {
            fail OverflowError{"AAC stream input frame count overflows"}
        }

        packet.clear()
        if not frames
        {
            return 0
        }

        Memory.copy(&.pending[cast(u64, .pendingFrames) * .channels], samples.buffer, frames * .channels * #sizeof(s16))
        .pendingFrames += cast(u32, frames)
        .inputFrames   += frames
        if .pendingFrames == 1_024
        {
            if .buffered.count
            {
                try .bufferPacket(packet)
            }
            else
            {
                try .emit(packet, 1_024)
            }
        }

        return frames
    }

    // Emits any padded final packet and one transform drain packet, one packet per call.
    //
    // Returns true while a packet was produced. Call until false before closing the recording;
    // repeated calls after completion return false and clear `packet`. An empty stream emits none.
    mtd finish(packet: *Array!{u8})->bool fail
    {
        packet.clear()
        if .ended
        {
            return false
        }

        .finalizing = true
        if .buffered.count
        {
            return try .finishWindowed(packet)
        }

        if .pendingFrames
        {
            let valid = .pendingFrames
            for index in cast(u64, .pendingFrames) * .channels until 1_024_u64 * .channels
            {
                .pending[index] = 0
            }

            try .emit(packet, valid)
            return true
        }

        if .emittedPackets and not .drained
        {
            for index in 1_024_u64 * .channels
            {
                .pending[index] = 0
            }

            try .emit(packet, 0)
            .drained = true
            .ended   = true
            return true
        }

        .ended = true
        return false
    }
}

private impl StreamEncoder
{
    mtd bufferPacket(packet: *Array!{u8}) fail
    {
        let pending = Swag.makeSlice(&.pending[0], 1_024_u64 * .channels)
        if .bufferedFrames
        {
            try .emitWindowed(.buffered.toSlice(), pending, packet, .bufferedFrames)
        }

        Memory.copy(.buffered.storage(), pending.buffer, pending.count * #sizeof(s16))
        .bufferedFrames = .pendingFrames
        .pendingFrames  = 0
    }

    mtd finishWindowed(packet: *Array!{u8})->bool fail
    {
        let samples = 1_024_u64 * .channels
        if .pendingFrames
        {
            for index in cast(u64, .pendingFrames) * .channels until samples
            {
                .pending[index] = 0
            }

            try .bufferPacket(packet)
            if packet.count
            {
                return true
            }
        }

        Memory.clear(&.pending, #sizeof(.pending))
        let silence = Swag.makeSlice(&.pending[0], samples)
        if .bufferedFrames
        {
            try .emitWindowed(.buffered.toSlice(), silence, packet, .bufferedFrames)
            .bufferedFrames = 0
            return true
        }

        if .emittedPackets and not .drained
        {
            try .emitWindowed(silence, silence, packet, 0)
            .drained = true
            .ended   = true
            return true
        }

        .ended = true
        return false
    }

    mtd const hasAttack(samples: const [..] s16, begin, end: u64)->bool
    {
        for channel in .channels
        {
            var previousEnergy = 0_f64
            var previous       = cast(s32, samples[(begin ? begin - 1 : 0) * .channels + channel])
            var lower          = begin
            while lower < end
            {
                var peak   = 0_f64
                var energy = 0_f64
                let upper  = Math.min(end, lower + 128_u64)
                for index in lower until upper
                {
                    let value = cast(s32, samples[index * .channels + channel])
                    let delta = cast(f64, value - previous)
                    let power = delta * delta
                    peak     = Math.max(peak, power)
                    energy   += power
                    previous = value
                }

                if peak >= 36_000_000 and
                   (8.0 * peak >= energy or
                    (previousEnergy > 0.0 and energy > 8.0 * previousEnergy))
                {
                    return true
                }

                previousEnergy = energy
                lower = upper
            }
        }

        return false
    }

    mtd emitWindowed(input, lookahead: const [..] s16, packet: *Array!{u8}, valid: u32) fail
    {
        // The next short transform covers the late part of this block and the early part
        // of lookahead. Detect at both edges of the long-to-short overlap.
        let following = .hasAttack(input, 448, 1_024) or .hasAttack(lookahead, 0, 576)
        var sequence  = EncodeWindow.Long
        switch .window
        {
        case .Long, .Stop: sequence = following ? .Start : .Long
        case .Start:       sequence = .Short
        case .Short:       sequence = .nextShort or following ? .Short : .Stop
        }

        try .encoder.encodeWindowed!{true, false}(input, packet, sequence)
        .window         = sequence
        .nextShort      = following
        .lastStart      = .emittedPackets * 1_024
        .lastValid      = valid
        .emittedPackets += 1
    }

    mtd emit(packet: *Array!{u8}, validFrames: u32) fail
    {
        let samples = Swag.makeSlice(&.pending[0], 1_024_u64 * .channels)
        if .packetBudget
        {
            let available = .packetBudget + .packetCredit
            try .encoder.encodeLimited(samples, packet, available)
            .packetCredit = Math.min(3 * .packetBudget, available - packet.count)
        }
        else
        {
            try .encoder.encode(samples, packet)
        }

        .lastStart      = .emittedPackets * 1_024
        .lastValid      = validFrames
        .emittedPackets += 1
        .pendingFrames  = 0
    }
}
