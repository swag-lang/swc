//! Format: Joint Photographic Experts Group (JPEG) encoder component.
//! Supported: Baseline Huffman-coded lossy output from 8-bit RGB/BGR images with configurable quality.
//! Not supported: Progressive, arithmetic, lossless, CMYK/YCCK, and alpha output.
//! Role: This file owns marker emission, component metadata, and top-level encoding.
//
#global namespace Jpg

using Core

private
{
    struct SOF0InfoType
    {
        marker:        u16
        length:        u16
        precision:     u8
        height:        u16
        width:         u16
        numComponents: u8

        idy:  u8
        hvy:  u8
        qty:  u8
        idcb: u8
        hvcb: u8
        qtcb: u8
        idcr: u8
        hvcr: u8
        qtcr: u8
    }

    struct SOSInfoType
    {
        marker:        u16
        length:        u16
        numComponents: u8

        idy:  u8
        hty:  u8
        idcb: u8
        htcb: u8
        idcr: u8
        htcr: u8
        ss:   u8
        se:   u8
        bf:   u8
    }

    struct ColorRGB
    {
        b, g, r: u8
    }

    struct BitString
    {
        length: u8
        value:  u16
    }

    struct DQTInfoType
    {
        marker:   u16
        length:   u16
        infoQty:  u8
        tableY:   [64] u8
        infoQtcb: u8
        tableCb:  [64] u8
    }

    struct DHTInfoType
    {
        marker:      u16
        length:      u16
        infoHTYDC:   u8
        nrcodesYDC:  [16] u8
        valuesYDC:   [12] u8
        infoHTYAC:   u8
        nrcodesYAC:  [16] u8
        valuesYAC:   [162] u8
        infoHTCbDC:  u8
        nrcodesCbDC: [16] u8
        valuesCbDC:  [12] u8
        infoHTCbAC:  u8
        nrcodesCbAC: [16] u8
        valuesCbAC:  [162] u8
    }

    const SOF0info = SOF0InfoType{0xFFC0, 17, 8, 0, 0, 3, 1, 0x11, 0, 2, 0x11, 1, 3, 0x11, 1}
    const SOSinfo  = SOSInfoType{0xFFDA, 12, 3, 1, 0, 2, 0x11, 3, 0x11, 0, 0x3F, 0}

    // Bytes the encoder stages before handing them to the output buffer.
    //
    // The entropy coder produces one byte at a time, and appending each of them to a
    // `ConcatBuffer` costs more than the coding itself; staging turns that into one append
    // per full buffer.
    const OutBufSize = 4096

    const ZigZag: [?] u8 = [
        0, 1, 5, 6, 14, 15, 27, 28, 2, 4, 7, 13, 16, 26, 29, 42, 3, 8, 12, 17, 25, 30,
        41, 43, 9, 11, 18, 24, 31, 40, 44, 53, 10, 19, 23, 32, 39, 45, 52, 54, 20, 22, 33, 38,
        46, 51, 55, 60, 21, 34, 37, 47, 50, 56, 59, 61, 35, 36, 48, 49, 57, 58, 62, 63]

    const LuminanceQt: [?] u8 = [
        16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62,
        18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99]

    const ChrominanceQt: [?] u8 = [
        17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99, 99, 99, 99, 99,
        99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99]

    // Fixed-point coefficients of the colour conversion, in 16.16. The rounding of each one is
    // part of the sample the transform receives.
    const CoeffYR  = cast(s32) (65536.0 * 0.299 + 0.5)
    const CoeffYG  = cast(s32) (65536.0 * 0.587 + 0.5)
    const CoeffYB  = cast(s32) (65536.0 * 0.114 + 0.5)
    const CoeffCbR = cast(s32) (65536.0 * -0.16874 + 0.5)
    const CoeffCbG = cast(s32) (65536.0 * -0.33126 + 0.5)
    const CoeffCbB = 32768
    const CoeffCrR = 32768
    const CoeffCrG = cast(s32) (65536.0 * -0.41869 + 0.5)
    const CoeffCrB = cast(s32) (65536.0 * -0.08131 + 0.5)

    // Byte permutations that lift one colour channel of four pixels into four 32-bit lanes.
    const RedLanes   = cast(Math.Simd.U8x16) [2'u8, 0x80, 0x80, 0x80, 5, 0x80, 0x80, 0x80, 8, 0x80, 0x80, 0x80, 11, 0x80, 0x80, 0x80]
    const GreenLanes = cast(Math.Simd.U8x16) [1'u8, 0x80, 0x80, 0x80, 4, 0x80, 0x80, 0x80, 7, 0x80, 0x80, 0x80, 10, 0x80, 0x80, 0x80]
    const BlueLanes  = cast(Math.Simd.U8x16) [0'u8, 0x80, 0x80, 0x80, 3, 0x80, 0x80, 0x80, 6, 0x80, 0x80, 0x80, 9, 0x80, 0x80, 0x80]
}

impl ColorRGB
{
    mtd const opCompare(other: ColorRGB)->s32
    {
        let bCmp = .b <=> other.b
        if bCmp do
            return bCmp

        let gCmp = .g <=> other.g
        if gCmp do
            return gCmp

        return .r <=> other.r
    }
}

impl BitString
{
    mtd const opCompare(other: BitString)->s32
    {
        let lenCmp = .length <=> other.length
        if lenCmp do
            return lenCmp

        return .value <=> other.value
    }
}

// Encodes baseline JPEG images with configurable quality.
//
// The encoder is opaque; pass [[Jpg.EncodeOptions]] through the generic image
// encoding API to control quality.
#[Swag.Opaque]
internal struct Encoder
{
    // Baseline JPEG encoding state: the padded source, the quantization and Huffman tables,
    // and the 8x8 block being transformed. Encode through the module entry points.

    private
    {
        imageX:    u16                // Width of the padded source, a multiple of eight.
        imageY:    u16                // Height of the padded source, a multiple of eight.
        bufferRGB: Array'ColorRGB     // Padded source pixels.

        stream: *ConcatBuffer?     // Output buffer segments are appended to.

        bitBuffer: u32     // Pending entropy bits, right-aligned in the accumulator.
        bitCount:  u32     // Number of valid bits held in 'bitBuffer'.

        outBuf:   [OutBufSize] u8     // Bytes staged before they reach 'stream'.
        outCount: u32                 // Bytes currently staged in 'outBuf'.

        scaleFactor: u8 = 10     // Quality scale applied to the quantization tables.

        dqtInfo: DQTInfoType         // Quantization table segment.
        dhtInfo: DHTInfoType         // Huffman table segment.
        htYDC:   [12] BitString      // Luma DC code table.
        htCbDC:  [12] BitString      // Chroma DC code table.
        htYAC:   [256] BitString     // Luma AC code table.
        htCbAC:  [256] BitString     // Chroma AC code table.

        fdtblY:  [64] f32     // Scaled luma quantization table.
        fdtblCb: [64] f32     // Scaled chroma quantization table.

        // Samples of the current block, already level shifted.
        duY:  [64] s16     // Luma samples of the current block.
        duCb: [64] s16     // Blue-chroma samples of the current block.
        duCr: [64] s16     // Red-chroma samples of the current block.
        du:   [64] s16     // Quantized coefficients of the current block, in zigzag order.

        categoryAlloc: Array'u8            // Storage for the magnitude-category table.
        category:      [*] u8?             // Magnitude-category table, biased to signed input.
        bitcodeAlloc:  Array'BitString     // Storage for the magnitude-code table.
        bitcode:       [*] BitString?      // Magnitude-code table, biased to signed input.
    }
}

impl Encoder
{
    mtd loadBitmap(image: Image)
    {
        .imageX = cast(u16) image.width
        .imageY = cast(u16) image.height

        var xDiv8, yDiv8: u32
        if .imageX % 8 != 0 do
            xDiv8 = (.imageX / 8) * 8'u32 + 8
        else do
            xDiv8 = .imageX
        if .imageY % 8 != 0 do
            yDiv8 = (.imageY / 8) * 8'u32 + 8
        else do
            yDiv8 = .imageY

        // The conversion reads whole vectors, so the last pixels of the source are followed by
        // enough slack for a sixteen-byte read that starts on them.
        .bufferRGB.resize(cast(u64) xDiv8 * yDiv8 + 8)
        let pdst = .bufferRGB.buffer!
        var pref = image.pixels.buffer!

        // The image rows are stored bottom up and a scan is coded top down, so each row is
        // written straight to its mirrored position instead of being copied and then swapped.
        for nrline in .imageY
        {
            let line = pdst + (cast(u32) .imageY - 1 - nrline) * xDiv8
            switch image.pixelFormat
            {
            case .BGR8:
                for column in .imageX
                {
                    line[column].b = pref[0]
                    line[column].g = pref[1]
                    line[column].r = pref[2]
                    pref           += 3
                }

            case .RGB8:
                for column in .imageX
                {
                    line[column].b = pref[2]
                    line[column].g = pref[1]
                    line[column].r = pref[0]
                    pref           += 3
                }

            case .BGRA8:
                for column in .imageX
                {
                    line[column].b = pref[0]
                    line[column].g = pref[1]
                    line[column].r = pref[2]
                    pref           += 4
                }

            case .RGBA8:
                for column in .imageX
                {
                    line[column].b = pref[2]
                    line[column].g = pref[1]
                    line[column].r = pref[0]
                    pref           += 4
                }
            }

            let lastcolor = line[.imageX - 1]
            for var column = .imageX; column < xDiv8; column += 1 do
                line[column] = lastcolor
        }

        .imageX = cast(u16) xDiv8

        // Height completion: the padded rows repeat the last coded row.
        let dimline  = cast(u64) .imageX * #sizeof(ColorRGB)
        let lastLine = pdst + (cast(u32) .imageY - 1) * cast(u32) .imageX
        for var nrLine = cast(u32) .imageY; nrLine < yDiv8; nrLine += 1 do
            Memory.copy(pdst + nrLine * cast(u32) .imageX, lastLine, dimline)

        .imageY = cast(u16) yDiv8
    }

    mtd encoder()
    {
        var dcy:  s16 = 0
        var dccb: s16 = 0
        var dccr: s16 = 0
        for var ypos = 0'u16; ypos < .imageY; ypos += 8
        {
            for var xpos = 0'u16; xpos < .imageX; xpos += 8
            {
                .loadFromRGB(xpos, ypos)
                .processDU(.duY, .fdtblY, &dcy, .htYDC, .htYAC)
                .processDU(.duCb, .fdtblCb, &dccb, .htCbDC, .htCbAC)
                .processDU(.duCr, .fdtblCb, &dccr, .htCbDC, .htCbAC)
            }
        }
    }
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"JPEG - Joint Photographic Experts Group", ".jpg;.jpeg"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        var opt: EncodeOptions
        if options.buffer != null
        {
            Debug.assert(Swag.kindOf(options) == EncodeOptions)
            opt = options.buffer![as EncodeOptions]
        }

        .stream      = result
        .scaleFactor = cast(u8) (100 - Math.clamp(opt.quality, 1'u8, 100'u8))

        .loadBitmap(image)

        .setDQTinfo()
        .setDHTinfo()
        .initHuffmanTables()
        .setNumbersCategoryAndBitcode()
        .prepareQuantTables()

        .writeWord(0xFFD8)     // SOI

        .writeMetadata(&image)
        .writeDQTinfo()
        .writeSOF0info(&image)
        .writeDHTinfo()
        .writeSOSinfo()

        .bitBuffer = 0
        .bitCount  = 0
        .encoder()

        // The last byte of the scan is padded with one bits, so a decoder cannot read the marker
        // that follows as entropy-coded data.
        let padding = 8 - .bitCount
        .writeBits({cast(u8) padding, cast(u16) ((1'u32 << padding) - 1)})

        .writeWord(0xFFD9)     // EOI
        .flushStaged()
    }
}
