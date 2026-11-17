//! Format: YUV4MPEG2 (Y4M) encoder options.
//! Supported: Progressive 8-bit limited-range 4:1:1, 4:2:0, 4:2:2, and 4:4:4 chroma output.
//! Not supported: Monochrome, interlaced, or full-range output.
//! Role: This file owns the public chroma-sampling options for Y4M streams.
//
#global namespace Y4m
#global export

// Chroma sampling used for YUV4MPEG2 output.
enum EncodeChromaMode
{
    Yuv411     // Average each horizontal group of four for each chroma plane.
    Yuv420     // Average each aligned 2x2 group for each chroma plane.
    Yuv422     // Average each aligned horizontal pair for each chroma plane.
    Yuv444     // Preserve one chroma sample per pixel; this is the default.
}

// Configures the planar chroma layout written by the Y4M encoder.
struct EncodeOptions
{
    public chroma = EncodeChromaMode.Yuv444    // Output chroma sampling; 4:4:4 preserves one value per pixel.
}
