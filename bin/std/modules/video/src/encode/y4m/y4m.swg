//! Format: YUV4MPEG2 (Y4M) encoder component.
//! Supported: Progressive 8-bit 4:4:4, 4:2:2, 4:2:0, and 4:1:1 limited-range planar output from 8-bit RGB/BGR images.
//! Not supported: Audio, alpha preservation, interlacing, monochrome output, full-range output, and compression.
//! Role: This file owns stream headers, frame markers, RGB-to-planar conversion, and top-level encoding.
//
#global namespace Y4m

using Core, Core.Errors, Pixel

private func luma(r, g, b: s32)->u8 => clampByte(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16)
private func cb(r, g, b: s32)->u8   => clampByte(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128)
private func cr(r, g, b: s32)->u8   => clampByte(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128)

// Returns the red, green and blue channels of one pixel, whatever order its format stores them in.
//
// Only the four interleaved 8-bit layouts are read here; 'addFrame' rejects every other format
// before a pixel is touched, so the default arm exists to give the switch a value and is never
// the one that runs.
private func readRgb(image: Image, source: const [*] u8)->{ r: s32, g: s32, b: s32 }
{
    switch image.pixelFormat
    {
    case .RGB8, .RGBA8: return {r: source[0], g: source[1], b: source[2]}
    case .BGR8, .BGRA8: return {r: source[2], g: source[1], b: source[0]}
    default: return {r: 0, g: 0, b: 0}
    }
}

// Writes YUV4MPEG2 streams one frame at a time.
//
// The format carries no audio. This encoder writes progressive 8-bit limited-range BT.601 planes;
// the selected 4:2:0 or 4:2:2 layout averages chroma over its sampling footprint.
struct Encoder
{
    internal
    {
        info:    StreamInfo        // Geometry and rate the stream was opened with.
        payload: Array'u8          // Scratch storage of one encoded frame.
        options: EncodeOptions     // Chroma layout applied to every frame.
        hasFrame: bool             // Whether at least one complete frame was written.
    }
}

impl IEncoder for Encoder
{
    mtd impl format()->StreamFormat => {"Y4M - YUV4MPEG2 video", ".y4m"}

    mtd impl begin(sink: *ByteSink, info: StreamInfo, options: any?) fail
    {
        .info = info
        if options.buffer != null
        {
            Swag.assert(Swag.kindOf(options) == EncodeOptions)
            .options = cast(const *EncodeOptions, unwrap options.buffer)[]
        }

        if (.options.chroma == .Yuv420 or .options.chroma == .Yuv422) and info.width & 1 do
            fail BadParameterError{"Y4M 4:2:2 and 4:2:0 output needs an even frame width"}
        if .options.chroma == .Yuv420 and info.height & 1 do
            fail BadParameterError{"Y4M 4:2:0 output needs an even frame height"}
        if .options.chroma == .Yuv411 and info.width & 3 do
            fail BadParameterError{"Y4M 4:1:1 output needs a frame width divisible by four"}

        var chromaTag = "C444 XYSCSS=444"
        switch .options.chroma
        {
        case .Yuv411: chromaTag = "C411 XYSCSS=411"
        case .Yuv420: chromaTag = "C420jpeg XYSCSS=420JPEG"
        case .Yuv422: chromaTag = "C422 XYSCSS=422"
        case .Yuv444: chromaTag = "C444 XYSCSS=444"
        }

        let header = Format.toString("% W% H% F%:% Ip A0:0 % XCOLORRANGE=LIMITED\n",
                                     StreamSignature,
                                     info.width,
                                     info.height,
                                     info.frameRate.numerator(),
                                     info.frameRate.denominator(),
                                     chromaTag)
        try sink.writeText(header.toString())
    }

    mtd impl addFrame(sink: *ByteSink, image: Image) fail
    {
        // The frame is read pixel by pixel as interleaved 8-bit colour: any other layout would
        // be read at the wrong stride and with the wrong channel meaning.
        switch image.pixelFormat
        {
        case .RGB8, .RGBA8, .BGR8, .BGRA8: break
        default: fail UnsupportedFormatError{"Y4M frames need an interleaved 8-bit RGB or BGR image"}
        }

        let width       = cast(u64, .info.width)
        let height      = cast(u64, .info.height)
        let lumaSize    = width * height
        let chromaWidth = .options.chroma == .Yuv444 ? width :
                          (.options.chroma == .Yuv411 ? width / 4 : width / 2)
        let chromaHeight = .options.chroma == .Yuv420 ? height / 2 : height
        let chromaSize   = chromaWidth * chromaHeight
        if .payload.count != lumaSize + chromaSize * 2 do
            .payload.resize(lumaSize + chromaSize * 2)

        let yPlane = .payload.storage()
        let uPlane = yPlane + lumaSize
        let vPlane = uPlane + chromaSize
        for y in image.height
        {
            let sourceRow = cast(u64, (image.height - y - 1)) * cast(u64, image.rowStride)
            for x in image.width
            {
                let source    = image.pixels.storage() + sourceRow + cast(u64, x) * image.bytesPerPixel
                let {r, g, b} = readRgb(image, source)
                yPlane[cast(u64, y) * width + cast(u64, x)] = luma(r, g, b)
            }
        }

        let stepX = .options.chroma == .Yuv444 ? 1'u64 :
                    (.options.chroma == .Yuv411 ? 4'u64 : 2'u64)
        let stepY = .options.chroma == .Yuv420 ? 2'u64 : 1'u64
        for cy in chromaHeight
        {
            for cx in chromaWidth
            {
                var sumU, sumV: u32
                for dy in stepY
                {
                    for dx in stepX
                    {
                        let x         = cx * stepX + dx
                        let y         = cy * stepY + dy
                        let sourceRow = (height - y - 1) * cast(u64, image.rowStride)
                        let source    = image.pixels.storage() + sourceRow + x * image.bytesPerPixel
                        let {r, g, b} = readRgb(image, source)
                        sumU += cast(u32, cb(r, g, b))
                        sumV += cast(u32, cr(r, g, b))
                    }
                }

                let samples = stepX * stepY
                let target  = cy * chromaWidth + cx
                uPlane[target] = cast(u8, (sumU + cast(u32, samples / 2)) / cast(u32, samples))
                vPlane[target] = cast(u8, (sumV + cast(u32, samples / 2)) / cast(u32, samples))
            }
        }

        try sink.writeText(FrameMarker)
        try sink.writeText("\n")
        try sink.write(.payload.toSlice())
        .hasFrame = true
    }

    mtd impl end(_: *ByteSink) fail
    {
        if not .hasFrame do
            fail BadParameterError{"Y4M stream needs at least one frame"}
    }
}
