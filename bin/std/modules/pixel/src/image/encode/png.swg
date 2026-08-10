/*
    :LICENCE
    This code is based on the libspng library by Randy (https://libspng.org/)
    The original code has been modified for Swag
    See LICENCE.md for the corresponding licence.
*/

#global namespace Png

using Core, Core.Errors

private
{
    const Adam7StartX: [7] u32 = [0, 4, 0, 2, 0, 1, 0]
    const Adam7StartY: [7] u32 = [0, 0, 4, 0, 2, 0, 1]
    const Adam7DeltaX: [7] u32 = [8, 8, 4, 4, 2, 2, 1]
    const Adam7DeltaY: [7] u32 = [8, 8, 8, 4, 4, 2, 2]

    struct RowInfo
    {
        scanlineIdx: u32
        rowNum:      u32
        pass:        s32
        filter:      u8
    }

    #[Swag.EnumFlags]
    enum ColorType: u8
    {
        Paletted   = 1
        Color      = 2
        Alpha      = 4
        AlphaColor = Alpha | Color
    }

    struct EncodeFlags
    {
        filterChoice: FilterChoice
        interlace:    bool
        sameLayout:   bool
        toBigEndian:  bool
        progressive:  bool
        finalize:     bool
    }

    enum Filter
    {
        None
        Sub
        Up
        Average
        Paeth
    }

    #[Swag.EnumFlags]
    enum FilterChoice
    {
        Disabled = 0
        None     = 8
        Sub      = 16
        Up       = 32
        Average  = 64
        Paeth    = 128
        All      = (8 | 16 | 32 | 64 | 128)
    }

    const PngSignature: [8] u8 = [137, 80, 78, 71, 13, 10, 26, 10]
    const TypeIHdr:     [4] u8 = ['I', 'H', 'D', 'R']
    const TypeIDat:     [4] u8 = ['I', 'D', 'A', 'T']
    const TypeIEnd:     [4] u8 = ['I', 'E', 'N', 'D']
    const TypeTEXt:     [4] u8 = ['t', 'E', 'X', 't']

    struct SubImage
    {
        width:         u32
        height:        u32
        outWidth:      u32
        scanlineWidth: u32
    }

    struct Ihdr
    {
        width:             u32
        height:            u32
        bitDepth:          u8
        colorType:         ColorType = undefined
        compressionMethod: u8
        filterMethod:      u8
        interlaceMethod:   u8
    }

    struct ChunkBitfield
    {
        ihdr:    bool
        plte:    bool
        chrm:    bool
        iccp:    bool
        gama:    bool
        sbit:    bool
        srgb:    bool
        text:    bool
        bkgd:    bool
        hist:    bool
        trns:    bool
        phys:    bool
        splt:    bool
        time:    bool
        offs:    bool
        exif:    bool
        unknown: bool
    }

    struct Chunk
    {
        offset: u64
        length: u32
        type:   [4] u8
        crc:    u32
    }
}

// Encodes PNG images with configurable filtering, compression, and interlacing.
//
// The encoder is opaque; use [[Png.EncodeOptions]] to configure output.
#[Swag.Opaque]
internal struct Encoder
{
    // Encoding state: the chunk being written, the scanline filter windows, and the
    // interlacing passes. Encode through the module entry points; none of this is a knob.
    private
    {
        stream:              #null *ConcatBuffer     // Output buffer chunks are appended to.
        stored:              ChunkBitfield           // Chunks already written, to keep their order legal.
        ihdr:                Ihdr                    // Image header being written.
        currentChunk:        Chunk                   // Chunk currently open.
        tmpBuf:              [256] u8                // Scratch for small chunk payloads.
        writePtr:            #null [*] u8            // Write cursor inside 'tmpBuf'.
        crc:                 Hash.Crc32              // Running CRC of the chunk being written.
        subimage:            [7] SubImage            // Geometry of the seven Adam7 passes.
        widestPass:          s32                     // Widest pass, sizing the scanline buffers.
        lastPass:            s32                     // Index of the last pass to write.
        bytesPerPixel:       u32                     // Bytes per pixel of the output format.
        scanlineBuf:         #null [*] u8            // Storage for the current scanline.
        prevScanlineBuf:     #null [*] u8            // Storage for the previous scanline.
        row_buf:             #null [*] u8            // Source row converted to the output format.
        filteredScanlineBuf: #null [*] u8            // Storage for the filtered scanline.
        filteredScanline:    #null [*] u8            // Filtered scanline being emitted.
        scanline:            #null [*] u8            // Current scanline, aliasing 'scanlineBuf'.
        prevScanline:        #null [*] u8            // Previous scanline, for the filter predictors.
        encodeFlags:         EncodeFlags             // Flags derived from the requested options.
        rowInfo:             RowInfo                 // Geometry of the row being filtered.
        pixelSize:           u32                     // Size of one source pixel, in bytes.
        bufferToCompress:    Array'u8                // Filtered image data handed to Deflate.
        swapRB:              bool                    // Whether the source needs its red and blue swapped.
        userOptions:         EncodeOptions           // Options the caller asked for.
    }
}

impl Encoder
{
    func writeU32(dst: [*] u8, val: u32)
    {
        let v = Math.nativeToBigEndian(val)
        dref cast(*u32) dst = v
    }

    mtd writeData(buf: const [*] u8, bytes: u32)
    {
        let stream = .stream!
        stream.addBytes(@mkslice(buf, bytes))
    }

    mtd writeU32(val: u32)
    {
        var v      = Math.nativeToBigEndian(val)
        let stream = .stream!
        stream.addBytes(@mkslice(cast(const [*] u8) &v, 4))
    }

    mtd writeHeader(chunkType: const [4] u8, chunkLength: u64)->[*] u8
    {
        let total  = chunkLength + 8 + 4
        let stream = .stream!
        stream.grow(total)

        .currentChunk.length = cast(u32) chunkLength
        .writeU32(.currentChunk.length)

        Memory.copy(&.currentChunk.type, chunkType, 4)
        .writeData(.currentChunk.type, 4)

        .crc.reset()
        .crc.update(null)
        .crc.update(chunkType)
        .currentChunk.crc = .crc.value()

        return stream.reserveInPlace(chunkLength)
    }

    mtd finishChunk()
    {
        .crc.update(@mkslice(.writePtr, .currentChunk.length))
        .currentChunk.crc = .crc.value()
        .writeU32(.currentChunk.crc)
    }

    mtd writeChunk(chunkType: const [4] u8, buf: const *u8, length: u64)
    {
        .writePtr = .writeHeader(chunkType, length)
        if length do
            Memory.copy(.writePtr, buf, length)
        .finishChunk()
    }

    mtd writeChunksBeforeIDat() fail
    {
        .writeData(PngSignature, 8)

        var dst = cast([*] u8) &.tmpBuf[0]
        writeU32(dst, .ihdr.width)
        writeU32(dst + 4, .ihdr.height)
        dst[8]  = .ihdr.bitDepth
        dst[9]  = cast(u8) .ihdr.colorType
        dst[10] = .ihdr.compressionMethod
        dst[11] = .ihdr.filterMethod
        dst[12] = .ihdr.interlaceMethod
        .writeChunk(TypeIHdr, dst, 13)
    }

    mtd writeMetadata(image: Image) fail
    {
        for md in image.metadata
        {
            if !md.tag.count or !md.value.count do
                continue
            .writePtr = .writeHeader(TypeTEXt, md.tag.count + 1 + md.value.count)
            Memory.copy(.writePtr, md.tag.buffer, md.tag.count)
            .writePtr[md.tag.count] = 0
            Memory.copy(.writePtr + md.tag.count + 1, md.value.buffer, md.value.count)
            .finishChunk()
        }
    }
}

// Configures PNG filtering, Deflate behavior, and Adam7 interlacing.
public struct EncodeOptions
{
    public
    {
        compressionLevel = Compress.Deflate.CompressionLevel.Default     // Deflate compression level.
        filtering        = true                                          // Select adaptive PNG scanline filters.
        interlace        = false                                         // Encode seven-pass Adam7 interlacing.
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"PNG - Portable Network Graphics", ".png"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: #null any) fail
    {
        var defaultOptions: EncodeOptions
        .userOptions = defaultOptions
        if @dataof(options) != null
        {
            Debug.assert(@kindof(options) == EncodeOptions)
            .userOptions = dref cast(*EncodeOptions) @dataof(options)!
        }

        // unsupported pixel format
        if image.pixelFormat.channels() < 3 or image.pixelFormat.bitDepth() != 8 do
            fail UnsupportedFormatError{"unsupported pixel format"}
        if image.width == 0 or image.height == 0 do
            fail UnsupportedFormatError{"unsupported size"}

        .swapRB = image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8

        .stream = result

        .stored.ihdr          = true
        .ihdr.width           = image.width
        .ihdr.height          = image.height
        .ihdr.bitDepth        = 8
        .ihdr.colorType       = .Color
        .ihdr.interlaceMethod = .userOptions.interlace ? 1 : 0
        if image.bitsPerPixel == 32 do
            .ihdr.colorType |= .Alpha

        .writeChunksBeforeIDat()
        .writeMetadata(image)
        .calculateSubImages()

        .bytesPerPixel = .numChannels() * (.ihdr.bitDepth / 8)
        var scanlineBufSize = .subimage[.widestPass].scanlineWidth
        scanlineBufSize += 32

        .scanlineBuf         = Memory.alloc(cast(u64) scanlineBufSize)
        .prevScanlineBuf     = Memory.alloc(cast(u64) scanlineBufSize)
        .filteredScanlineBuf = Memory.alloc(cast(u64) scanlineBufSize)
        defer Memory.free(.scanlineBuf, cast(u64) scanlineBufSize)
        defer Memory.free(.prevScanlineBuf, cast(u64) scanlineBufSize)
        defer Memory.free(.filteredScanlineBuf, cast(u64) scanlineBufSize)

        .scanline         = .scanlineBuf + 16
        .prevScanline     = .prevScanlineBuf + 16
        .filteredScanline = .filteredScanlineBuf + 16

        .pixelSize                = image.bytesPerPixel
        .encodeFlags.filterChoice = .Disabled
        if .userOptions.filtering and .userOptions.compressionLevel != .NoCompression do
            .encodeFlags.filterChoice = .All

        let srcPixels = cast([*] u8) image.pixels.buffer!
        for
        {
            let ioffset = (image.height - .rowInfo.rowNum - 1) * image.width * image.bytesPerPixel
            if .encodeRow(srcPixels + ioffset) do
                break
        }

        discard .writeHeader(TypeIEnd, 0)
        .finishChunk()
    }
}
