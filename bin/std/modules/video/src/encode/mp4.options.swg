#global export
#global namespace Mp4

// Configures the Motion JPEG samples of an encoded MP4 stream.
struct EncodeOptions
{
    // Quality of every frame, in `[1, 100]`; higher values preserve more detail and produce
    // larger files.
    public quality = 90'u8
}
