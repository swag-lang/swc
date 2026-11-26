//! Format: YUV4MPEG2 (Y4M) encoder component.
//! Supported: Progressive 8-bit 4:4:4, 4:2:2, 4:2:0, and 4:1:1 limited-range planar output from 8-bit RGB/BGR images.
//! Not supported: Audio, alpha preservation, interlacing, monochrome output, full-range output, and compression.
//! Role: This file owns stream headers, frame markers, RGB-to-planar conversion, and top-level encoding.
//
#global namespace Y4m

using Core, Core.Errors, Pixel

private func(StepX: u64, StepY: u64) convertPlanes(image: const *Image, width, height, chromaWidth, chromaHeight: u64, luma, cb, cr: [*] u8)
{
    let red       = image.pixelFormat == .RGB8 or image.pixelFormat == .RGBA8 ? 0'u64 : 2'u64
    let blue      = 2 - red
    let pixelSize = image.bytesPerPixel
    let stride    = cast(u64, image.rowStride)
    const Samples = StepX * StepY
    for cy in chromaHeight
    {
        let y      = cy * StepY
        let input  = image.pixels.storage() + (height - 1 - y) * stride
        let output = luma + y * width
        for cx in chromaWidth
        {
            let x = cx * StepX
            var sumCb, sumCr: s32
            for dy in StepY
            {
                let source = input - dy * stride + x * pixelSize
                let yRow   = output + dy * width + x
                for dx in StepX
                {
                    let pixel = source + dx * pixelSize
                    let r     = cast(s32, pixel[red])
                    let g     = cast(s32, pixel[1])
                    let b     = cast(s32, pixel[blue])

                    // The BT.601 coefficients already keep Y in 16–235 and Cb/Cr in 16–240.
                    yRow[dx] = cast(u8, (((66 * r + 129 * g + 25 * b + 128) >> 8) + 16))
                    sumCb    += ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128
                    sumCr    += ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128
                }
            }

            let at = cy * chromaWidth + cx
            cb[at] = cast(u8, ((sumCb + cast(s32, Samples / 2)) / cast(s32, Samples)))
            cr[at] = cast(u8, ((sumCr + cast(s32, Samples / 2)) / cast(s32, Samples)))
        }
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
        info:     StreamInfo        // Geometry and rate the stream was opened with.
        payload:  Array'u8          // Scratch storage of one encoded frame.
        options:  EncodeOptions     // Chroma layout applied to every frame.
        hasFrame: bool              // Whether at least one complete frame was written.
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
        switch .options.chroma
        {
        case .Yuv411: convertPlanes'(4, 1)(&image, width, height, chromaWidth, chromaHeight, yPlane, uPlane, vPlane)
        case .Yuv420: convertPlanes'(2, 2)(&image, width, height, chromaWidth, chromaHeight, yPlane, uPlane, vPlane)
        case .Yuv422: convertPlanes'(2, 1)(&image, width, height, chromaWidth, chromaHeight, yPlane, uPlane, vPlane)
        case .Yuv444: convertPlanes'(1, 1)(&image, width, height, chromaWidth, chromaHeight, yPlane, uPlane, vPlane)
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
