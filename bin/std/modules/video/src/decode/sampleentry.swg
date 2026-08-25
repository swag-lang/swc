//! Format: Format-neutral description of one coded access unit.
//! Supported: Where an access unit lives in its source, how long it is, when it is shown, and whether it starts a clean decode.
//! Not supported: This file does not decode or encode a concrete picture format.
//! Role: This file owns the container's view of one sample, which every coded picture format shares.
//
#global internal

// One length-prefixed access unit of a coded video track, in decode order.
//
// A container indexes its video samples this way whatever the codec inside them: the payload
// stays in the file, and the reader keeps only where it is and when it is shown.
struct SampleEntry
{
    offset:           u64     // Absolute byte offset of the access unit in the source file.
    size:             u64     // Access unit size in bytes.
    presentationTime: s64     // Presentation timestamp, in the container's own units.
    isSync:           bool    // Whether the unit starts a decode that needs nothing before it.
}

// Reads one stored frame, putting back whatever the container took off its front.
//
// A writer that knows every frame of a track begins with the same bytes may store them once and
// strip them, so what lies in the file is not the whole frame. A decoder is handed the frame.
func readStoredFrame(source: *Source, entry: SampleEntry, prefix: const [..] u8, payload: *Array'u8) fail
{
    let count = @countof(prefix)
    if payload.count != entry.size + count do
        payload.resize(entry.size + count)
    if count do
        Memory.copy(payload.buffer!, @dataof(prefix), count)
    try source.seek(entry.offset)
    try source.readExact(payload.toSlice()[count until payload.count])
}
