#global if #command == Swag.CompilerCommand.Test
#global private

using Core

private func assertInvalidFrameNumberSize(payload: const [..] u8)
{
    var sps: H264.Sps
    var rejected: Swag.Error
    discard catch sps.parse(payload) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}

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
    Swag.require(subsampled.chromaShift() == 1 and not subsampled.is444())
    Swag.require(subsampled.mbWidth == 6 and subsampled.mbHeight == 4)
    Swag.require(subsampled.cropBottom == 6)
    Swag.require(subsampled.width() == 96 and subsampled.height() == 58)

    var full: H264.Sps
    expect full.parse(Sps444)
    Swag.require(full.chromaShift() == 0 and full.is444())
    Swag.require(full.mbWidth == 6 and full.mbHeight == 4)
    Swag.require(full.cropBottom == 6)
    Swag.require(full.width() == 96 and full.height() == 58)
}

// The SPS frame-number width is log2_max_frame_num_minus4 + 4 and the syntax value is limited
// to 12. These are Sps420 with only that Exp-Golomb field replaced: once by 13 and once by the
// largest value the bit reader can return, which used to wrap when four was added.
#test
{
    const FrameNumTooWide: [20] u8 = [0x42, 0xC0, 0x0A, 0x8E, 0x71, 0x89, 0xF9, 0x21, 0x00, 0x00,
                                     0x00, 0x01, 0x00, 0x00, 0x00, 0x32, 0x0F, 0x12, 0x27, 0x80]
    const FrameNumOverflow: [27] u8 = [0x42, 0xC0, 0x0A, 0x80, 0x00, 0x00, 0x00, 0xFF, 0xFF,
                                       0xFF, 0xFF, 0x71, 0x89, 0xF9, 0x21, 0x00, 0x00, 0x00,
                                       0x01, 0x00, 0x00, 0x00, 0x32, 0x0F, 0x12, 0x27, 0x80]

    assertInvalidFrameNumberSize(FrameNumTooWide)
    assertInvalidFrameNumberSize(FrameNumOverflow)
}

// Extreme 4:4:4 crop offsets must not wrap through signed dimensions and reach frame export.
#test
{
    const OverflowCrop = [0xF4'u8, 0x00, 0x0A, 0x91, 0x97, 0x7C, 0x00, 0x00,
                          0x00, 0x04, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00,
                          0x00, 0x08, 0x00, 0x00, 0x00, 0x1D]
    var sps: H264.Sps
    var rejected: Swag.Error
    discard catch sps.parse(OverflowCrop) as rejected
    Swag.require(rejected.value() is InvalidFormatError)
}
