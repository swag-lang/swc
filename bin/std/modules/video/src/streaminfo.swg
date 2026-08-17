#global public

using Core

// Describes the video stream a codec opened or is about to write.
//
// It is what a decoder reports from the header of a stream, and what an encoder is handed
// before its first frame, so the two sides of a format describe a stream the same way.
struct StreamInfo
{
    public
    {
        width:  s32     // Frame width, in pixels.
        height: s32     // Frame height, in pixels.

        frameRate: FrameRate     // Exact playback rate.

        // Number of frames in the stream, or zero when the format cannot report it without
        // decoding the whole stream.
        //
        // Zero is not an error and not an empty stream: it means the count is unknown, so a
        // caller reads frames in order until decoding fails at the end of the stream instead
        // of driving a bounded loop. It is always zero when an encoder is handed one, since a
        // writer accepts frames until it is ended.
        frameCount: u64
    }
}
