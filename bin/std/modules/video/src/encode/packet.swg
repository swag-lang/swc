//! Format: Encoded media packet contract.
//! Supported: Borrowed packet payloads, decode and presentation times, duration, and sync points.
//! Role: This file carries encoded samples from a codec to a container writer.
//
#global public

// Describes one encoded access unit on the track's integer timescale.
//
// `bytes` is borrowed for the call that consumes the packet. `decodeTime` and `presentationTime`
// are ticks from the track's origin; `duration` is positive ticks. A key frame can start decoding
// without any preceding packet. Containers may restrict the supported range or packet layout.
struct EncodedPacket
{
    public
    {
        bytes:            const [..] u8     // Complete encoded access unit, borrowed during submission.
        decodeTime:       u64      // Decode timestamp in track ticks.
        presentationTime: u64      // Display timestamp in track ticks.
        duration:         u32      // Positive duration in track ticks.
        isKeyFrame:       bool     // Access unit can be decoded without preceding packets.
    }
}
