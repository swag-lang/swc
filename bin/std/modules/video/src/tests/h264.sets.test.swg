#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Cropping is stated in chroma samples, so the same visible picture is written with a different
// syntax value in each chroma format, and a decoder that assumes one of them silently returns a
// picture of the wrong size. Both payloads below are the sequence sets libx264 wrote for the same
// 96 by 58 picture, which is six luma rows short of four whole macroblock rows.
#test
{
    // High profile, 4:2:0: bottom crop 3, one chroma sample per two luma rows.
    const Sps420 = [0x42'u8, 0xC0, 0x0A, 0xDC, 0x62, 0x7E, 0x48, 0x40, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x0C, 0x83, 0xC4, 0x89, 0xE0]

    // High 4:4:4 Predictive: bottom crop 6, one chroma sample per luma row.
    const Sps444 = [0xF4'u8, 0x10, 0x0A, 0x91, 0x97, 0x18, 0x9F, 0x9E, 0x10, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x03, 0x20, 0x40]

    var subsampled: H264.Sps
    expect subsampled.parse(Sps420)
    Swag.assert(subsampled.chromaShift() == 1 and !subsampled.is444())
    Swag.assert(subsampled.mbWidth == 6 and subsampled.mbHeight == 4)
    Swag.assert(subsampled.cropBottom == 6)
    Swag.assert(subsampled.width() == 96 and subsampled.height() == 58)

    var full: H264.Sps
    expect full.parse(Sps444)
    Swag.assert(full.chromaShift() == 0 and full.is444())
    Swag.assert(full.mbWidth == 6 and full.mbHeight == 4)
    Swag.assert(full.cropBottom == 6)
    Swag.assert(full.width() == 96 and full.height() == 58)
}
