#global public
#global namespace Jpg

// Configures JPEG lossy compression.
struct EncodeOptions
{
    quality = 95'u8 // Quality in `[1, 100]`; higher values preserve more detail and produce larger files.
}
