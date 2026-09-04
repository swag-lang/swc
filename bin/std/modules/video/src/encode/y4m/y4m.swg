//! Format: YUV4MPEG2 (Y4M) encoder component.
//! Supported: Progressive 8-bit 4:4:4 limited-range planar output from 8-bit RGB/BGR images.
//! Not supported: Audio, alpha preservation, interlacing, alternative chroma modes, full-range output, and compression.
//! Role: This file owns stream headers, frame markers, RGB-to-planar conversion, and top-level encoding.
//
#global namespace Y4m

using Core, Core.Errors, Pixel

// Returns the red, green and blue channels of one pixel, whatever order its format stores them in.
private func readRgb(image: Image, source: const [*] u8)->{ r: s32, g: s32, b: s32 }
{
    switch image.pixelFormat
    {
    case .RGB8, .RGBA8: return {source[0], source[1], source[2]}
    case .BGR8, .BGRA8: return {source[2], source[1], source[0]}
    }
}

// Writes YUV4MPEG2 streams one frame at a time.
//
// The format carries no audio, and this encoder writes progressive 8-bit 4:4:4 limited-range
// BT.601 planes: chroma is not subsampled, so what a frame is written with is what reading it
// back returns, within the rounding of the color conversion itself.
struct Encoder
{
    internal
    {
        info:    StreamInfo     // Geometry and rate the stream was opened with.
        payload: Array'u8       // Scratch storage of one encoded frame.
    }
}

impl IEncoder for Encoder
{
    mtd impl format()->StreamFormat => {"Y4M - YUV4MPEG2 video", ".y4m"}

    mtd impl begin(sink: *Sink, info: StreamInfo, options: any?) fail
    {
        // The format has one plane layout here and one color range, so it has nothing to
        // configure and ignores what it is handed.
        discard options

        .info = info
        sink.writeText(Format.toString("% W% H% F%:% Ip A0:0 C444 XYSCSS=444 XCOLORRANGE=LIMITED\n", StreamSignature, info.width, info.height, info.frameRate.numerator(), info.frameRate.denominator()).toString())
    }

    mtd impl addFrame(sink: *Sink, image: Image) fail
    {
        let planeSize = cast(u64) .info.width * cast(u64) .info.height
        if .payload.count != planeSize * 3 do
            .payload.resize(planeSize * 3)

        let yPlane = .payload.buffer!
        let uPlane = yPlane + planeSize
        let vPlane = uPlane + planeSize
        for y in image.height
        {
            let sourceRow = cast(u64) (image.height - y - 1) * cast(u64) image.rowStride
            for x in image.width
            {
                let source    = image.pixels.buffer! + sourceRow + cast(u64) x * image.bytesPerPixel
                let {r, g, b} = readRgb(image, source)
                let target    = cast(u64) y * cast(u64) image.width + cast(u64) x
                yPlane[target] = clampByte(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16)
                uPlane[target] = clampByte(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128)
                vPlane[target] = clampByte(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128)
            }
        }

        sink.writeText(FrameMarker)
        sink.writeText("\n")
        sink.write(.payload.toSlice())
    }

    mtd impl end(sink: *Sink) fail
    {
        // The format has no trailer: a stream is complete as soon as its last frame is written.
        discard sink
    }
}
