//! Format: Joint Photographic Experts Group (JPEG) encoder component.
//! Supported: Baseline Huffman-coded lossy output from 8-bit RGB/BGR images with configurable quality.
//! Not supported: Progressive, arithmetic, lossless, CMYK/YCCK, and alpha output.
//! Role: This file owns public encoder options.
//
#global public
#global namespace Jpg

// Configures JPEG lossy compression.
struct EncodeOptions
{
    public quality = 95'u8     // Quality in `[1, 100]`; higher values preserve more detail and produce larger files.
}
