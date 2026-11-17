//! Format: ISO Base Media File Format (MP4/M4V/MOV) encoder component.
//! Supported: Motion JPEG video with 64-bit media data and classic sample tables.
//! Not supported: H.264 encoding, audio tracks, fragmented/encrypted media, edit lists, and metadata beyond the emitted core boxes.
//! Role: This file owns public MP4 Motion JPEG encoder options.
//
#global export
#global namespace Mp4

// Configures the Motion JPEG samples of an encoded MP4 stream.
struct EncodeOptions
{
    // Quality of every frame, in `[1, 100]`; higher values preserve more detail and produce larger files.
    public quality = 90'u8

    // Optional pixel aspect ratio numerator. Zero and `pixelAspectHeight` zero omit the `pasp` box.
    public pixelAspectWidth = 0'u32

    // Optional pixel aspect ratio denominator; this is not the displayed frame width.
    public pixelAspectHeight = 0'u32
}
