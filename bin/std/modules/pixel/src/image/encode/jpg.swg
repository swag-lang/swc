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

    const StdDcLuminanceNrCodes   = [0'u8, 0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0]
    const StdDcLuminanceValues    = [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    const StdDcChrominanceNrCodes = [0'u8, 0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0]
    const StdDcChrominanceValues  = [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    const StdAcLuminanceNrCodes   = [0'u8, 0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D]
    const StdAcChrominanceNrCodes = [0'u8, 0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77]
    const Mask                    = [1'u16, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768]

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

    const StdAcLuminanceValues: [?] u8 = [
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
        0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
        0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
        0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
        0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA]

    const StdAcChrominanceValues: [?] u8 = [
        0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
        0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26,
        0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
        0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
        0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4,
        0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA,
        0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA]

    var TabYR:  [256] s32 = undefined
    var TabYG:  [256] s32 = undefined
    var TabYB:  [256] s32 = undefined
    var TabCbR: [256] s32 = undefined
    var TabCbG: [256] s32 = undefined
    var TabCbB: [256] s32 = undefined
    var TabCrR: [256] s32 = undefined
    var TabCrG: [256] s32 = undefined
    var TabCrB: [256] s32 = undefined
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

// Precalculate YCbCr tables
#run
{
    for r in 256
    {
        let rr = cast(s32) r
        TabYR[r]  = cast(s32) (65536.0 * 0.299 + 0.5) * rr
        TabCbR[r] = cast(s32) (65536.0 * -0.16874 + 0.5) * rr
        TabCrR[r] = cast(s32) 32768 * rr

        TabYG[r]  = cast(s32) (65536.0 * 0.587 + 0.5) * rr
        TabCbG[r] = cast(s32) (65536.0 * -0.33126 + 0.5) * rr
        TabCrG[r] = cast(s32) (65536.0 * -0.41869 + 0.5) * rr

        TabYB[r]  = cast(s32) (65536.0 * 0.114 + 0.5) * rr
        TabCbB[r] = cast(s32) 32768 * rr
        TabCrB[r] = cast(s32) (65536.0 * -0.08131 + 0.5) * rr
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

        stream: #null *ConcatBuffer     // Output buffer segments are appended to.

        bytenew: u8     // Bit accumulator of the entropy coder.
        bytepos: s8     // Free bit position inside 'bytenew'.

        scaleFactor: u8 = 10     // Quality scale applied to the quantization tables.

        dqtInfo: DQTInfoType         // Quantization table segment.
        dhtInfo: DHTInfoType         // Huffman table segment.
        htYDC:   [12] BitString      // Luma DC code table.
        htCbDC:  [12] BitString      // Chroma DC code table.
        htYAC:   [256] BitString     // Luma AC code table.
        htCbAC:  [256] BitString     // Chroma AC code table.

        fdtblY:  [64] f32     // Scaled luma quantization table.
        fdtblCb: [64] f32     // Scaled chroma quantization table.

        duY:   [64] s8      // Luma samples of the current block.
        duCb:  [64] s8      // Blue-chroma samples of the current block.
        duCr:  [64] s8      // Red-chroma samples of the current block.
        duDct: [64] s16     // Transformed coefficients of the current block.
        du:    [64] s16     // Quantized coefficients of the current block.

        categoryAlloc: Array'u8                // Storage for the magnitude-category table.
        category:      #null [*] u8            // Magnitude-category table, biased to signed input.
        bitcodeAlloc:  Array'BitString         // Storage for the magnitude-code table.
        bitcode:       #null [*] BitString     // Magnitude-code table, biased to signed input.
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

        .bufferRGB.resize(cast(u64) xDiv8 * yDiv8)
        let pdst = .bufferRGB.buffer!
        var pref = image.pixels.buffer!

        for nrline in .imageY
        {
            let line = pdst + nrline * xDiv8
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
        let tmpline = Array'u8.createBuffer(cast(u64) .imageX * #sizeof(ColorRGB))

        // Reorder in memory the inversed bitmap
        var nrLineUp = cast(u32) .imageY - 1
        var nrLineDn = 0'u32
        let dimline  = cast(u64) .imageX * #sizeof(ColorRGB)
        while nrLineUp > nrLineDn
        {
            Memory.copy(tmpline.buffer, pdst + nrLineUp * .imageX, dimline)
            Memory.copy(pdst + nrLineUp * .imageX, pdst + nrLineDn * .imageX, dimline)
            Memory.copy(pdst + nrLineDn * .imageX, tmpline.buffer, dimline)
            nrLineUp -= 1
            nrLineDn += 1
        }

        // Y completion
        Memory.copy(tmpline.buffer, pdst + (.imageY - 1) * cast(u32) .imageX, dimline)
        for var nrLine = .imageY; nrLine < yDiv8; nrLine += 1 do
            Memory.copy(pdst + nrLine * cast(u32) .imageX, tmpline.buffer, dimline)

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

    mtd impl encode(result: *ConcatBuffer, image: Image, options: #null any) fail
    {
        var opt: EncodeOptions
        if @dataof(options) != null
        {
            Debug.assert(@kindof(options) == EncodeOptions)
            opt = (cast(*EncodeOptions) @dataof(options)!)[]
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

        .bytenew = 0
        .bytepos = 7
        .encoder()

        if .bytepos >= 0
        {
            var fillbits: BitString
            fillbits.length = cast(u8) (.bytepos + 1)
            fillbits.value  = cast(u16) ((1 << (.bytepos + 1)) - 1)
            .writeBits(fillbits)
        }

        .writeWord(0xFFD9)     // EOI
    }
}
