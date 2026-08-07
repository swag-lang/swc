#global namespace Jpg

using Swag, Core, Core.Errors

private
{
    const InBufSize       = 4096
    const MaxHeight       = 8192
    const MaxWidth        = 8192
    const MaxComponents   = 4
    const MaxQuantTables  = 4
    const MaxHuffTables   = 8
    const MaxBocksPerMcu  = 10
    const MaxBlocksPerRow = 6144
    const MaxCompsInScan  = 4
    const GrayScale       = 0
    const YH1V1           = 1
    const YH2V1           = 2
    const YH1V2           = 3
    const YH2V2           = 4
    const RGBH1V1         = 5
    const Failed          = -1
    const Done            = 1
    const Okay            = 0
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

    struct HuffTables
    {
        lookUp:   [256] s32
        codeSize: [256] u8
        tree:     [512] s32
    }

    struct CoeffBuf
    {
        pdata:     Array'u8
        blockNumX: s32
        blockNumY: s32
        blockLenX: s32
        blockLenY: s32
        blockSize: s32
    }

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
        func descale(x: s32, n: u32)->s32 => cast(s32) ((x + (1's32 << (n - 1))) >> n)
        func clamp(i: s32)->u8            => cast(u8) ((i & cast #bit (s32) 0xFFFFFF00) ? ((~i >> 31) & 0xFF) : i)

        func extendSign(r: u32, s: s32)->s32
        {
            let value = cast(s32) r
            return value < ExtendTest[s] ? value + ExtendOff[s] : value
        }

        func rol(i, j: u32)->u32
        {
            let shift = j & 31
            if !shift do
                return i
            return cast(u32) ((i << #wrap shift) | (i >> (32 - shift)))
        }
    }
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
        stream:     #null const [*] u8
        inBufOfs:   #null [*] u8
        pSampleBuf: #null [*] u8

        imageSizeX:      s32
        imageSizeY:      s32
        streamLen:       s32
        streamSeek:      s32
        bitBuf:          u32
        bitsLeft:        s32
        inBufLeft:       s32
        temFlag:         s32
        eofReached:      s32
        totalBytesRead:  s32
        compsInFrame:    s32
        restartInterval: s32
        scanType:        s32
        maxBlocksPerMcu: s32
        maxMcuSizeX:     s32
        maxMcuSizeY:     s32
        blocksPerMcu:    u32
        maxMcusPerRow:   s32
        maxMcusPerCol:   s32
        maxBlocksPerRow: s32
        totalLinesLeft:  s32
        mcuLinesLeft:    s32
        spectralStart:   s32
        spectralEnd:     s32
        successiveLow:   s32
        successiveHigh:  s32
        mcusPerRow:      s32
        mcusPerCol:      s32
        eobRun:          s32
        restartsLeft:    s32
        nextRestartNum:  s32
        compsInScan:     u32

        destBytesPerPixel:        s32
        realDestBytesPerScanLine: s32
        destBytesPerScanLine:     s32

        acceptMetadata:  bool
        progressiveFlag: bool
        hasAdobeMarker:  bool
        hasJfifMarker:   bool
        adobeTransform:  u8

        inBuf:          [InBufSize + 128] u8
        compSampH:      [MaxComponents] s32
        compSampV:      [MaxComponents] s32
        compQuant:      [MaxComponents] u32
        compIdent:      [MaxComponents] s32
        blockMaxZagSet: [MaxBlocksPerRow] s32
        blockSeg:       [MaxBlocksPerRow] #null [*] s16
        compList:       [MaxCompsInScan] u32
        compDcTab:      [MaxComponents] s32
        compAcTab:      [MaxComponents] s32
        compBlocksH:    [MaxComponents] s32
        compBlocksV:    [MaxComponents] s32
        mcuOrg:         [MaxBocksPerMcu] u32
        h:              [MaxHuffTables] HuffTables
        dcHuffSeg:      [MaxBocksPerMcu] #null *HuffTables
        acHuffSeg:      [MaxBocksPerMcu] #null *HuffTables
        blockMcuY:      [MaxComponents] s32
        component:      [MaxBocksPerMcu] #null *u32
        lastDcVal:      [MaxComponents] s32
        dcCoeffs:       [MaxComponents] CoeffBuf
        acCoeffs:       [MaxComponents] CoeffBuf
        tempBlock:      [64] s16
        crr:            [256] s32
        cbb:            [256] s32
        crg:            [256] s32
        cbg:            [256] s32

        huffNum:    [MaxHuffTables] Array'u8
        huffVal:    [MaxHuffTables] Array'u8
        quant:      [MaxQuantTables] Array's16
        scanLine0:  Array'u8
        scanLine1:  Array'u8
        quantBuf:   Array'u8
        sampleBuf:  Array'u8
        decOptions: DecodeOptions
        metadata:   Array'ImageMetadata
    }
}

impl Decoder
{
    mtd safeSampleBuf()->[*] u8 => .pSampleBuf!
    mtd safeInBufOfs()->[*] u8  => .inBufOfs!

    mtd init(buffer: const [..] u8) fail
    {
        @init(me, 1)
        .stream    = @dataof(buffer)
        .streamLen = cast(s32) @countof(buffer)

        .inBufOfs = .inBuf
        .prepareInBuffer()
        .bitsLeft = 16
        .getBits1(16)
        .getBits1(16)
        for [i] in MaxBlocksPerRow do
            .blockMaxZagSet[i] = 64

        .locateSofMarker()
    }

    mtd start() fail
    {
        .initFrame()
        if .progressiveFlag do
            .initProgressive()
        else do
            .initSequential()
    }

    mtd doit(buf: [*] u8) fail
    {
        var scanLineOfs: #null *void
        var scanLineLen: u32

        // Gray scale (1BPP)
        if .compsInFrame == 1
        {
            var pdest = buf
            pdest += (.imageSizeY - 1) * .imageSizeX * 3
            for
            {
                if .decode(&scanLineOfs, &scanLineLen) do
                    break

                var pdest1 = pdest
                var psrc   = cast([*] u8) scanLineOfs!
                for .imageSizeX
                {
                    pdest1[0] = dref psrc
                    pdest1[1] = dref psrc
                    pdest1[2] = dref psrc
                    pdest1    += 3
                    psrc      += 1
                }

                pdest -= .imageSizeX * 3
            }
        }

        // 3 BPP
        else
        {
            var pdest = buf
            pdest += (.imageSizeY - 1) * .imageSizeX * 3
            for
            {
                if .decode(&scanLineOfs, &scanLineLen) do
                    break
                Memory.copy(pdest, cast(*void) scanLineOfs!, cast(u64) .imageSizeX * 3)
                pdest -= .imageSizeX * 3
            }
        }
    }
}

internal impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"JPEG - Joint Photographic Experts Group", ".jpg;.jpeg"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        var result: retval
        .decOptions = options

        .init(buffer)
        .start()

        // Creates image
        result.init(.imageSizeX, .imageSizeY, PixelFormat.BGR8)
        if !options.decodePixels do
            return result
        result.allocPixels()

        .doit(cast([*] u8) result.pixels.buffer!)
        result.metadata = #move .metadata

        return result
    }
}
