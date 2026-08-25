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
