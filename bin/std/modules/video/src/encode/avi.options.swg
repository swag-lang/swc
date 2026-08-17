#global public
#global namespace Avi

// Configures the Motion JPEG frames of an encoded AVI stream.
struct EncodeOptions
{
    // Quality of every frame, in `[1, 100]`; higher values preserve more detail and produce
    // larger files.
    //
    // The default sits below the one a single photograph deserves: a video is a long sequence of
    // similar pictures, so the last few percent of detail costs proportionally far more here.
    public quality = 90'u8
}
