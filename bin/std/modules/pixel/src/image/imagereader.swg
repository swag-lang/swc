using Swag, Core, Core.Errors

// Meaning of an image within its container.
public enum ImageFrameKind
{
    Still         // A representative still image.
    Animation     // A timed update to the animation canvas.
    Page          // An independent document page.
    Variant       // An alternative image, such as an icon size.
    Layer         // A document layer.
    Texture       // A texture level, array layer, cube face, or depth slice.
}

// Canvas operation performed after an animation frame's duration expires.
public enum ImageDisposal
{
    Keep           // Retain the displayed frame.
    Background     // Clear the frame rectangle to the animation background.
    Previous       // Restore the canvas from before the frame.
}

// How an animation frame updates its rectangle.
public enum ImageBlend
{
    Replace     // Replace every pixel, including transparent pixels.
    Over        // Composite straight alpha over the preceding canvas.
}

// Describes one image without allocating its pixels.
public struct ImageFrameInfo
{
    public
    {
        kind:            ImageFrameKind           // Role in the container; only Animation frames are timed.
        width:           s32                      // Width of the decoded frame rectangle in pixels.
        height:          s32                      // Height of the decoded frame rectangle in pixels.
        x:               s32                      // Left edge in canvas coordinates, measured from the top left.
        y:               s32                      // Top edge in canvas coordinates, measured from the top left.
        pixelFormat:     PixelFormat = .RGBA8     // Storage format returned by the frame decoder.
        durationSeconds: f64                      // Encoded display duration; zero means unspecified.
        disposal:        ImageDisposal            // Operation after displaying an animation frame.
        blend:           ImageBlend               // Operation when displaying an animation frame.
        level:           u32                      // Zero-based texture mip level.
        layer:           u32                      // Zero-based texture array layer or document layer.
        face:            u32                      // Cube face in +X, -X, +Y, -Y, +Z, -Z order.
        depthSlice:      u32                      // Zero-based slice at this mip level.
        name:            String                   // Optional owned page, layer, or part name.
    }
}

// Owns a container's image index and animation presentation rules.
public struct ImageSetInfo
{
    public
    {
        frames:              Array'ImageFrameInfo     // Images in encoded order, with texture indices identifying subresources.
        canvasWidth:         s32                      // Animation canvas width; zero for an independent image set.
        canvasHeight:        s32                      // Animation canvas height; zero for an independent image set.
        loopCount:           u32   = 1                // Total animation plays; zero means unlimited.
        background:          Color = {a: 0}           // Color used when clearing an animation canvas; transparent by default.
        representativeIndex: u32                      // Image selected by a still-image view of the container.
    }
}

// Optional decoder interface for containers with multiple images.
//
// Register the same type through [[Pixel.Image.registerDecoder]]. The reader owns the
// encoded storage and keeps this decoder at a stable address until it closes.
public interface IImageSetDecoder
{
    // Indexes all images without decoding their pixels, borrowing `buffer` until the next open or destruction.
    mtd open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail

    // Decodes an indexed image rectangle, without animation compositing; any valid index may be requested.
    mtd readFrame(index: u32, options: DecodeOptions)->Image fail
}

// Owns encoded input and decodes individual images through a format-neutral interface.
//
// Animation reads return complete composited canvases. Independent pages, variants,
// layers, and texture subresources retain their own dimensions and pixel format.
// Forward animation reads reuse the preceding canvas; seeking backwards replays from
// the beginning. Decoded frames are not cached. Returned images own their pixels and
// survive subsequent reads or closing the reader. A failed read resets animation state.
//
// ```swag
// var reader = try ImageReader.load("animation.webp")
// for index in reader.info.frames.count
// {
//     var image = try reader.read(cast(u32) index)
// }
// ```
public struct ImageReader
{
    public readonly info: ImageSetInfo     // Indexed images; valid until close or replacement of the reader.
    bytes:       Array'u8
    decoder:     *void?
    decoderType: const *TypeInfoStruct?
    options:     DecodeOptions
    canvas:      Image
    previous:    Image
    lastIndex:   s32 = -1
}

impl ImageReader
{
    mtd release()
    {
        if .decoder
        {
            let type = .decoderType!
            if type.opDrop do
                type.opDrop(.decoder)
            Memory.free(.decoder, cast(u64) type.sizeof)
            .decoder = null
        }
    }

    mtd clearRectangle(frame: ImageFrameInfo)
    {
        let value = colorPixelValue(.info.background)
        for y in frame.height
        {
            let row = .canvas.height - frame.y - y - 1
            for x in frame.width
            {
                let target = .canvas.pixels.buffer! + cast(u64) row * .canvas.rowStride + cast(u64) (frame.x + x) * .canvas.bytesPerPixel
                writePixelValue(target, .canvas.pixelFormat, value)
            }
        }
    }

    mtd composite(frame: ImageFrameInfo, image: Image) fail
    {
        if image.width != frame.width or image.height != frame.height or image.pixels.count != image.byteCount do
            fail InvalidFormatError{"decoded frame does not match its image index"}
        for y in frame.height
        {
            let sourceRow = image.height - y - 1
            let targetRow = .canvas.height - frame.y - y - 1
            for x in frame.width
            {
                let source = image.pixels.buffer! + cast(u64) sourceRow * image.rowStride + cast(u64) x * image.bytesPerPixel
                let target = .canvas.pixels.buffer! + cast(u64) targetRow * .canvas.rowStride + cast(u64) (frame.x + x) * .canvas.bytesPerPixel
                var value  = readLogicalPixelValue(source, image.pixelFormat, image.alphaMode)
                if frame.blend == .Over and value.a < 1
                {
                    let behind    = readPixelValue(target, .canvas.pixelFormat)
                    let remainder = behind.a * (1 - value.a)
                    let alpha     = value.a + remainder
                    if alpha > 0 do
                        value = {(value.r * value.a + behind.r * remainder) / alpha, (value.g * value.a + behind.g * remainder) / alpha, (value.b * value.a + behind.b * remainder) / alpha, alpha}
                    else do
                        value = {0, 0, 0, 0}
                }

                writePixelValue(target, .canvas.pixelFormat, value)
            }
        }
    }
}

public impl ImageReader
{
    // Releases the decoder and all owned storage automatically.
    mtd opDrop() { .release() }

    // Closes the reader; repeated calls are harmless.
    mtd close()
    {
        Swag.drop(me, 1)
        Swag.init(me, 1)
    }

    // Reports whether encoded input is open.
    mtd const isOpen()->bool => .decoder != null

    // Opens an owned copy of encoded bytes; unsupported or malformed input reports `fail`.
    //
    // Still-only registered decoders automatically appear as a one-image set. Limits
    // apply before frame decoding. The first frame represents animated containers;
    // icon containers retain their largest-entry representative selection.
    func decode(fileName: string, bytes: const [..] u8, options: DecodeOptions = {})->ImageReader fail
    {
        if options.maxInputBytes and bytes.count > options.maxInputBytes do
            fail UnsupportedFormatError{"image exceeds the encoded byte limit"}
        let found = Image.getDecoder(fileName)
        if not found do
            fail UnsupportedFormatError{"no matching image decoder"}
        var result: retval
        result.bytes.add(bytes)
        result.options     = options
        result.decoderType = found.type
        result.decoder     = Memory.new(found.type)
        let multiple = Swag.makeInterface(result.decoder, found.type, IImageSetDecoder)
        if multiple do
            result.info = multiple.open(result.bytes.toSlice(), options)
        else
        {
            let single       = Swag.makeInterface(result.decoder, found.type, IImageDecoder)!
            var probeOptions = options
            probeOptions.decodePixels = false
            let probe = single.decode(result.bytes.toSlice(), probeOptions)
            result.info.frames.add({width: probe.width, height: probe.height, pixelFormat: probe.pixelFormat})
        }

        if not result.info.frames.count or result.info.representativeIndex >= result.info.frames.count do
            fail InvalidFormatError{"image container has no representative image"}
        options.checkFrameCount(result.info.frames.count)
        for frame in result.info.frames
        {
            options.checkImage(frame.width, frame.height, frame.pixelFormat)
            if frame.kind == .Animation
            {
                options.checkImage(result.info.canvasWidth, result.info.canvasHeight, frame.pixelFormat.bitDepth() > 8 ? .RGBA16 : .RGBA8)
                if frame.x < 0 or frame.y < 0 or frame.x > result.info.canvasWidth - frame.width or frame.y > result.info.canvasHeight - frame.height do
                    fail InvalidFormatError{"animation frame lies outside its canvas"}
            }
        }

        return result
    }

    // Loads a file into owned storage and indexes its images.
    func load(fileName: string, options: DecodeOptions = {})->ImageReader fail
    {
        var file = File.MappedFile.open(fileName)
        if options.maxInputBytes and file.size() > options.maxInputBytes do
            fail UnsupportedFormatError{"image exceeds the encoded byte limit"}
        let region = file.mapAll()
        return decode(fileName, region.bytes(), options)
    }

    // Decodes a zero-based image index, failing for a closed reader or an out-of-range index.
    mtd read(index: u32)->Image fail
    {
        if not .decoder or index >= .info.frames.count do
            fail InvalidFormatError{"image index is outside the open container"}
        let multiple = Swag.makeInterface(.decoder, .decoderType!, IImageSetDecoder)
        if not multiple
        {
            let single = Swag.makeInterface(.decoder, .decoderType!, IImageDecoder)!
            return single.decode(.bytes.toSlice(), .options)
        }

        if .info.frames[index].kind != .Animation do
            return multiple.readFrame(index, .options)
        if not .options.decodePixels
        {
            let frame = multiple.readFrame(index, .options)
            var result: retval
            result.init(.info.canvasWidth, .info.canvasHeight, frame.pixelFormat)
            result.metadata = frame.metadata
            return result
        }

        var succeeded = false
        defer if not succeeded do
            .lastIndex = -1
        if .lastIndex < 0 or cast(s32) index < .lastIndex
        {
            let format: PixelFormat = .info.frames[0].pixelFormat.bitDepth() > 8 ? .RGBA16 : .RGBA8
            .canvas = Image.create(.info.canvasWidth, .info.canvasHeight, format)
            .canvas.fill(.info.background)
            .lastIndex = -1
        }

        while .lastIndex < cast(s32) index
        {
            if .lastIndex >= 0
            {
                let prior = &.info.frames[cast(u32) .lastIndex]
                switch prior.disposal
                {
                case .Background: .clearRectangle(prior[])
                case .Previous:   .canvas = .previous
                }
            }

            let current    = cast(u32) (.lastIndex + 1)
            let descriptor = &.info.frames[current]
            if descriptor.disposal == .Previous do
                .previous = .canvas
            let image = multiple!.readFrame(current, .options)
            .composite(descriptor[], image)
            .canvas.metadata = image.metadata
            .lastIndex       += 1
        }

        succeeded = true
        return .canvas
    }
}
