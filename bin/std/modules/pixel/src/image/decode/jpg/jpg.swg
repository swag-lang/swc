//! Format: Joint Photographic Experts Group (JPEG) decoder component.
//! Supported: Baseline and progressive Huffman-coded grayscale, YCbCr, directly sampled RGB, and CMYK or YCCK images.
//! Not supported: Arithmetic coding, lossless JPEG, and unsupported chroma sampling layouts.
//! Role: This file owns marker parsing, component metadata, and top-level decoding.
//
#global namespace Jpg

using Swag, Core, Core.Errors

private const DecoderFormat: ImageFormat = {"JPEG - Joint Photographic Experts Group", ".jpg;.jpeg;.jpe;.jfif;.jif;.jfi;.jps"}

// Reports whether the filename extension selects the built-in JPEG decoder.
public func matchesFileName(fileName: string)->bool => DecoderFormat.matches(fileName)

private
{
    // Marker lookahead may return four bytes before the current input window.
    const PushbackBytes   = 4
    const InBufSize       = 4096
    const MaxComponents   = 4
    const MaxQuantTables  = 4
    const MaxHuffTables   = 8
    const MaxBlocksPerMcu = 10
    const MaxCompsInScan  = 4
    const GrayScale       = 0
    const YH1V1           = 1
    const YH2V1           = 2
    const YH1V2           = 3
    const YH2V2           = 4
    const RGBH1V1         = 5
    const CmykH1V1        = 6
    const YGeneric        = 7
    const Failed          = -1
    const ConstBits       = 13'u32
    const Pass1Bits       = 2'u32
    const Fix_0_298631336 = 2446
    const Fix_0_390180644 = 3196
    const Fix_0_541196100 = 4433
    const Fix_0_765366865 = 6270
    const Fix_0_899976223 = 7373
    const Fix_1_175875602 = 9633
    const Fix_1_501321110 = 12299
    const Fix_1_847759065 = 15137
    const Fix_1_961570560 = 16069
    const Fix_2_053119869 = 16819
    const Fix_2_562915447 = 20995
    const Fix_3_072711026 = 25172

    const HuffLookupBits        = 8
    const HuffLookupCount       = 1 << HuffLookupBits
    const BaselineAcLookupBits  = 10
    const BaselineAcLookupCount = 1 << BaselineAcLookupBits

    // Fixed-point chroma-to-colour coefficients, in 16.16. The rounding of each one is part of
    // the decoded value, so the scalar and vector paths must read them from here.
    const FixCrToR = cast(s32, ((1.40200 / 2) * (1 << 16) + 0.5))
    const FixCbToB = cast(s32, ((1.77200 / 2) * (1 << 16) + 0.5))
    const FixCrToG = cast(s32, -((0.71414 / 2) * (1 << 16) + 0.5))
    const FixCbToG = cast(s32, -((0.34414 / 2) * (1 << 16) + 0.5))

    // One decoding table of a scan.
    //
    // An eight-bit prefix indexes `lookUp`. Baseline AC instead uses a wider table whose
    // entries may also hold the signed coefficient and total bits of a short code plus its
    // amplitude. Both formats place the raw symbol and code length in the low bytes, and a
    // negative entry selects a subtree for a long code.
    struct HuffTables
    {
        lookUp:     [HuffLookupCount] s32
        baselineAc: Array's32
        tree:       [512] s32
        ready:      bool
    }

    struct CoeffBuf
    {
        values:    Array's16
        blockNumX: s32
        blockNumY: s32
    }

    #[Swag.Incomplete]
    enum Marker
    {
        M_SOF0  = 0xC0
        M_SOF1  = 0xC1
        M_SOF2  = 0xC2
        M_SOF3  = 0xC3
        M_SOF5  = 0xC5
        M_SOF6  = 0xC6
        M_SOF7  = 0xC7
        M_JPG   = 0xC8
        M_SOF9  = 0xC9
        M_SOF10 = 0xCA
        M_SOF11 = 0xCB
        M_SOF13 = 0xCD
        M_SOF14 = 0xCE
        M_SOF15 = 0xCF
        M_DHT   = 0xC4
        M_DAC   = 0xCC
        M_RST0  = 0xD0
        M_RST1  = 0xD1
        M_RST2  = 0xD2
        M_RST3  = 0xD3
        M_RST4  = 0xD4
        M_RST5  = 0xD5
        M_RST6  = 0xD6
        M_RST7  = 0xD7
        M_SOI   = 0xD8
        M_EOI   = 0xD9
        M_SOS   = 0xDA
        M_DQT   = 0xDB
        M_DNL   = 0xDC
        M_DRI   = 0xDD
        M_DHP   = 0xDE
        M_EXP   = 0xDF
        M_APP0  = 0xE0
        M_APP15 = 0xEF
        M_JPG0  = 0xF0
        M_JPG13 = 0xFD
        M_COM   = 0xFE
        M_TEM   = 0x01
        M_ERROR = 0x100
    }

    const ExtendOff: [16] s32 = [
        0,
        (-1 << 1) + 1, (-1 << 2) + 1, (-1 << 3) + 1, (-1 << 4) + 1,
        (-1 << 5) + 1, (-1 << 6) + 1, (-1 << 7) + 1, (-1 << 8) + 1,
        (-1 << 9) + 1, (-1 << 10) + 1, (-1 << 11) + 1, (-1 << 12) + 1,
        (-1 << 13) + 1, (-1 << 14) + 1, (-1 << 15) + 1]

    const ExtendTest: [16] s32 = [
        0, 0x0001, 0x0002, 0x0004, 0x0008, 0x0010, 0x0020,
        0x0040, 0x0080, 0x0100, 0x0200, 0x0400, 0x0800,
        0x1000, 0x2000, 0x4000]

    const Zag: [64] u32 = [
        0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
        12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21,
        28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37,
        44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47,
        55, 62, 63]

    #[Inline]
    {
        func descale(x: s32, n: u32)->s32 => cast(s32, ((x + (1's32 << (n - 1))) >> n))
        func clamp(i: s32)->u8 => cast(u8, ((i & cast #bit (s32, 0xFFFFFF00)) ? ((~i >> 31) & 0xFF) : i))

        func extendSign(r: u32, s: s32)->s32
        {
            let value = cast(s32, r)
            return value < ExtendTest[s] ? value + ExtendOff[s] : value
        }

        func rol(i, j: u32)->u32 => Math.rol(i, cast(u8, j & 31))
    }
}

// Tables and the DC predictor for one block position in a baseline MCU.
struct BaselineBlock
{
    dc:         *HuffTables?
    ac:         *HuffTables?
    quant:      const [*] s16?
    previousDc: *s32?
}

// Decodes baseline and progressive JPEG image data.
//
// The decoder is opaque and reusable only through its public decoding operations.
#[Opaque]
internal struct Decoder
{
    // Decoding state of one image: the entropy-coded bit cursor, the frame and scan tables,
    // and the coefficient and scanline buffers. Decode through the module entry points;
    // nothing here survives the call.

    private
    {
        stream:     const [*] u8?
        inBufOfs:   [*] u8?
        pSampleBuf: [*] u8?

        imageSizeX:          s32
        imageSizeY:          s32
        streamLen:           s32
        streamSeek:          s32
        bitBuf:              u32
        bitSyntheticMask:    u32
        lastBitsSynthetic:   bool
        lastCharSynthetic:   bool
        lastMarkerSynthetic: bool
        bitsLeft:            s32
        inBufLeft:           s32
        temFlag:             s32
        eofReached:          s32
        totalBytesRead:      s32
        compsInFrame:        s32
        restartInterval:     s32
        scanType:            s32
        maxBlocksPerMcu:     s32
        maxMcuSizeX:         s32
        maxMcuSizeY:         s32
        blocksPerMcu:        u32
        maxMcusPerRow:       s32
        maxMcusPerCol:       s32
        maxBlocksPerRow:     s32
        totalLinesLeft:      s32
        mcuLinesLeft:        s32
        spectralStart:       s32
        spectralEnd:         s32
        successiveLow:       s32
        successiveHigh:      s32
        mcusPerRow:          s32
        mcusPerCol:          s32
        eobRun:              s32
        restartsLeft:        s32
        nextRestartNum:      s32
        compsInScan:         u32

        destBytesPerPixel:        s32
        realDestBytesPerScanLine: s32
        destBytesPerScanLine:     s32

        acceptMetadata:  bool
        progressiveFlag: bool
        hasAdobeMarker:  bool
        hasJfifMarker:   bool
        adobeTransform:  u8

        inBuf:       [PushbackBytes + InBufSize + 128] u8
        compSampH:   [MaxComponents] s32
        compSampV:   [MaxComponents] s32
        compQuant:   [MaxComponents] u32
        compIdent:   [MaxComponents] s32
        compList:    [MaxCompsInScan] u32
        compDcTab:   [MaxComponents] s32
        compAcTab:   [MaxComponents] s32
        compBlocksH: [MaxComponents] s32
        compBlocksV: [MaxComponents] s32
        mcuOrg:      [MaxBlocksPerMcu] u32
        h:           [MaxHuffTables] HuffTables
        blockMcuY:   [MaxComponents] s32
        lastDcVal:   [MaxComponents] s32

        baselineBlocks: [MaxBlocksPerMcu] BaselineBlock

        coefficients: [MaxComponents] CoeffBuf
        huffNum:      [MaxHuffTables] Array'u8
        huffVal:      [MaxHuffTables] Array'u8
        quant:        [MaxQuantTables] Array's16
        scanLine0:    Array'u8
        scanLine1:    Array'u8
        sampleBuf:    Array'u8
        decOptions:   DecodeOptions
        metadata:     Array'ImageMetadata
    }
}

impl Decoder
{
    mtd safeSampleBuf()->[*] u8 => unwrap .pSampleBuf

    mtd init(buffer: const [..] u8, options: DecodeOptions) fail
    {
        .decOptions = options
        .stream     = buffer.buffer
        .streamLen  = cast(s32, buffer.count)

        .prepareInBuffer()
        .primeMarkerBits()
        try .locateSofMarker()
    }

    mtd start() fail
    {
        try .initFrame()

        // A geometry probe needs the frame and first scan headers. Pixels and metadata can
        // depend on later scans, so requests for either still read the progressive stream.
        if .progressiveFlag and (.decOptions.decodePixels or .decOptions.decodeMetadata) do
            try .initProgressive()
        else do
            try .initFirstScan()
    }

    mtd doit(buf: [*] u8) fail
    {
        let stride      = cast(u64, .imageSizeX) * 3
        var destination = buf + cast(u64, .imageSizeY - 1) * stride
        if .compsInFrame == 1
        {
            for .imageSizeY
            {
                let source = try .decodeScanLine()
                expandGrayRow(destination, source, .imageSizeX)
                destination -= stride
            }

            return
        }

        // A complete MCU row can go straight to the image when it has no right-edge padding.
        let direct = .destBytesPerScanLine == .realDestBytesPerScanLine
        for .imageSizeY
        {
            let source = try .decodeScanLine(direct ? destination : null)
            if source != destination do
                Memory.copy(destination, source, stride)
            destination -= stride
        }
    }
}

internal impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => DecoderFormat

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        // Readers reuse this decoder for the index probe and for subsequent reads.
        defer
        {
            Swag.drop(me, 1)
            Swag.init(me, 1)
        }

        var result: #returntype
        try .init(buffer, options)
        try options.checkImage(.imageSizeX, .imageSizeY, .BGR8)
        try .start()

        // Creates image
        result.init(.imageSizeX, .imageSizeY, PixelFormat.BGR8)
        if not options.decodePixels
        {
            result.metadata = #move .metadata
            return result
        }

        result.allocPixels()

        try .doit(cast([*] u8, result.pixels.storage()))
        result.metadata = #move .metadata

        return result
    }
}
