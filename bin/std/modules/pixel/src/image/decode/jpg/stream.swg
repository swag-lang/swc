//! Format: Joint Photographic Experts Group (JPEG) decoder component.
//! Supported: Baseline and progressive Huffman-coded grayscale, YCbCr, and directly sampled RGB images.
//! Not supported: Arithmetic coding, lossless JPEG, CMYK/YCCK, and unsupported chroma sampling layouts.
//! Role: This file owns buffered bit reads, byte stuffing, marker traversal, and marker payload parsing.
//
#global namespace Jpg

using Swag, Core, Core.Errors

impl Decoder
{
    #[Discardable]
    mtd getBits1(numBits: s32)->u32
    {
        let i = .bitBuf >> cast(u32) (16 - numBits) & ((1'u32 << cast(u32) numBits) - 1)
        .bitsLeft -= numBits
        if .bitsLeft <= 0
        {
            .bitBuf = rol(.bitBuf, cast(u32) (numBits + .bitsLeft))
            let c1 = .getChar()
            let c2 = .getChar()

            .bitBuf   = (.bitBuf & 0xFFFF) | (cast(u32) c1 << 24) | (cast(u32) c2 << 16)
            .bitBuf   = rol(.bitBuf, cast(u32) -.bitsLeft)
            .bitsLeft += 16
        }
        else do
            .bitBuf = rol(.bitBuf, cast(u32) numBits)

        return i
    }

    #[Discardable]
    mtd getBits2(numBits: s32)->u32
    {
        let i = (.bitBuf >> cast(u32) (16 - numBits)) & ((1'u32 << cast(u32) numBits) - 1)
        .bitsLeft -= numBits
        if .bitsLeft <= 0
        {
            .bitBuf = rol(.bitBuf, cast(u32) (numBits + .bitsLeft))

            var c1, c2: u32
            let inBufOfs = .inBufOfs!

            // Two bytes that are neither a marker nor a stuffed 0xFF are what entropy-coded data
            // is almost entirely made of, and taking them here keeps the marker rules, the buffer
            // refill and their two calls out of the inner decoding loop.
            if .inBufLeft >= 2 and inBufOfs[0] != 0xFF and inBufOfs[1] != 0xFF
            {
                c1         = inBufOfs[0]
                c2         = inBufOfs[1]
                .inBufOfs  += 2
                .inBufLeft -= 2
            }
            else
            {
                c1 = .getOctet()
                c2 = .getOctet()
            }

            .bitBuf   = (.bitBuf & 0xFFFF) | (c1 << 24) | (c2 << 16)
            .bitBuf   = rol(.bitBuf, cast(u32) -.bitsLeft)
            .bitsLeft += 16
        }
        else do
            .bitBuf = rol(.bitBuf, cast(u32) numBits)

        return i
    }

    mtd getOctet()->u8
    {
        var paddingFlag: bool
        var c = .getChar(&paddingFlag)
        if c == 0xFF
        {
            if paddingFlag do
                return 0xFF

            c = .getChar(&paddingFlag)
            if paddingFlag
            {
                .stuffChar(0xFF)
                return 0xFF
            }

            if c == 0x00 do
                return 0xFF

            .stuffChar(cast(u8) c)
            .stuffChar(0xFF)
            return 0xFF
        }

        return cast(u8) c
    }

    mtd getChar(paddingFlag: *bool)->u32
    {
        if !.inBufLeft
        {
            .prepareInBuffer()
            if !.inBufLeft
            {
                paddingFlag[] = true
                let t = .temFlag
                .temFlag ^= 1
                if t do
                    return 0xD9
                return 0xFF
            }
        }

        paddingFlag[] = false
        let inBufOfs = .inBufOfs!
        let c        = inBufOfs[]
        .inBufOfs  += 1
        .inBufLeft -= 1
        return c
    }

    mtd getChar()->u32
    {
        if !.inBufLeft
        {
            .prepareInBuffer()
            if !.inBufLeft
            {
                let t = .temFlag
                .temFlag ^= 1
                if t do
                    return 0xD9
                return 0xFF
            }
        }

        let inBufOfs = .inBufOfs!
        let c        = inBufOfs[0]
        .inBufOfs  += 1
        .inBufLeft -= 1
        return c
    }

    mtd nextMarker()->Marker
    {
        var c: u32

        var bytes = 0
        while !c
        {
            while c != 0xFF
            {
                bytes += 1
                c     = .getBits1(8)
            }

            while c == 0xFF
            {
                c = .getBits1(8)
            }
        }

        return cast(Marker) c
    }

    #[Discardable]
    mtd processMarkers()->Marker fail
    {
        for
        {
            let c = .nextMarker()
            switch c
            {
            case .M_SOF0, .M_SOF1, .M_SOF2, .M_SOF3, .M_SOF5, .M_SOF6, .M_SOF7, .M_SOF9, .M_SOF10, .M_SOF11, .M_SOF13, .M_SOF14, .M_SOF15, .M_SOI, .M_EOI, .M_SOS:
                return c

            case .M_JPG, .M_RST0, .M_RST1, .M_RST2, .M_RST3, .M_RST4, .M_RST5, .M_RST6, .M_RST7, .M_TEM:
                fail InvalidFormatError{"unexpected marker"}

            case .M_DAC:
                fail UnsupportedFormatError{"no arithmetic support"}

            case .M_DHT:
                .readDhtMarker()

            case .M_DQT:
                .readDqtMarker()

            case .M_DRI:
                .readDriMarker()

            default:
                if cast(u32) c & cast(u32) M_APP0 == cast(u32) M_APP0 do
                    .readAppMarker(c)
                else do
                    .readVariableMarker(c)
            }
        }

        return Marker.M_ERROR
    }

    mtd readVariableMarker(_marker: Marker) fail
    {
        var left = .getBits1(16)
        if left < 2 do
            fail InvalidFormatError{"bad variable marker"}
        left -= 2

        @assert(!.acceptMetadata)
        while left
        {
            .getBits1(8)
            left -= 1
        }
    }

    mtd readDhtMarker() fail
    {
        var huffNumt: [17] u8
        var huffValt: [256] u8

        var left = .getBits1(16)
        if left < 2 do
            fail InvalidFormatError{"bad dht marker"}
        left -= 2

        while left
        {
            var index = .getBits1(8)
            var count = 0
            huffNumt[0] = 0
            for i in 1 to 16
            {
                huffNumt[i] = cast(u8) .getBits1(8)
                count       += huffNumt[i]
            }

            if count > 255 do
                fail InvalidFormatError{"bad dht counts"}
            for i in count
            {
                huffValt[i] = cast(u8) .getBits1(8)
            }

            let i = 1 + 16 + count
            if left < i do
                fail InvalidFormatError{"bad dht marker"}

            left -= i
            if (index & 0x10) > 0x10 do
                fail InvalidFormatError{"bad dht index"}

            index = (index & 0x0F) + ((index & 0x10) >> 4) * (MaxHuffTables >> 1)
            if index >= MaxHuffTables do
                fail InvalidFormatError{"bad dht index"}

            .huffNum[index].resize(17)
            .huffVal[index].resize(256)
            Memory.copy(.huffNum[index].buffer, huffNumt, 17)
            Memory.copy(.huffVal[index].buffer, huffValt, 256)
        }
    }

    mtd readDqtMarker() fail
    {
        var left = .getBits1(16)
        if left < 2 do
            fail InvalidFormatError{"bad dqt marker"}
        left -= 2

        while left
        {
            var n    = .getBits1(8)
            let prec = n >> 4
            n &= 0x0F
            if n >= MaxQuantTables do
                fail InvalidFormatError{"bad dqt table"}

            .quant[n].resize(64)
            let qbuf = .quant[n].buffer!
            for i in 64
            {
                var temp = .getBits1(8)
                if prec do
                    temp = (temp << 8) + .getBits1(8)
                qbuf[i] = cast(s16) temp
            }

            var i = 64 + 1
            if prec do
                i += 64
            if left < i do
                fail InvalidFormatError{"bad dqt length"}
            left -= i
        }
    }

    mtd readDriMarker() fail
    {
        if .getBits1(16) != 4 do
            fail InvalidFormatError{"bad dri length"}
        .restartInterval = .getBits1(16)
    }

    mtd readSofMarker() fail
    {
        let left = .getBits1(16)
        if .getBits1(8) != 8 do
            fail InvalidFormatError{"bad precision"}

        .imageSizeY = .getBits1(16)
        .imageSizeX = .getBits1(16)

        if (.imageSizeY < 1) or (.imageSizeY > MaxHeight) do
            fail InvalidFormatError{"bad height"}
        if (.imageSizeX < 1) or (.imageSizeX > MaxWidth) do
            fail InvalidFormatError{"bad width"}

        .compsInFrame = .getBits1(8)
        if .compsInFrame > MaxComponents do
            fail InvalidFormatError{"too many components"}
        if left != (.compsInFrame * 3 + 8) do
            fail InvalidFormatError{"bad sof length"}

        for i in .compsInFrame
        {
            .compIdent[i] = .getBits1(8)
            .compSampH[i] = .getBits1(4)
            .compSampV[i] = .getBits1(4)
            .compQuant[i] = .getBits1(8)
        }
    }

    mtd readAppMarker(marker: Marker) fail
    {
        var left = .getBits1(16)
        if left < 2 do
            fail InvalidFormatError{"Bad app marker"}
        left -= 2

        var prefix:      [12] u8
        var prefixCount: u32
        var inValue = false
        var meta:        ImageMetadata
        meta.signature = cast(u32) marker - cast(u32) Marker.M_APP0

        while left
        {
            let c = cast(u8) .getBits1(8)
            left -= 1

            if prefixCount < @countof(prefix)
            {
                prefix[prefixCount] = c
                prefixCount         += 1
            }

            if .decOptions.decodeMetadata
            {
                if !inValue and c == 0 do
                    inValue = true
                elif inValue do
                    meta.value.add(c)
                else do
                    meta.tag.add(c)
            }
        }

        if marker == .M_APP0 and prefixCount >= 5 and prefix[0] == 'J' and prefix[1] == 'F' and prefix[2] == 'I' and prefix[3] == 'F' and prefix[4] == 0
        {
            .hasJfifMarker = true
        }

        if cast(u32) marker == cast(u32) Marker.M_APP0 + 14 and prefixCount == @countof(prefix) and prefix[0] == 'A' and prefix[1] == 'd' and prefix[2] == 'o' and prefix[3] == 'b' and prefix[4] == 'e'
        {
            .hasAdobeMarker = true
            .adobeTransform = prefix[11]
        }

        if .decOptions.decodeMetadata do
            .metadata.add(meta)
    }

    mtd readSosMarker() fail
    {
        var left = .getBits1(16)
        let n    = .getBits1(8)
        .compsInScan = n
        left         -= 3

        if (left != (n * 2 + 3)) or (n < 1) or (n > MaxCompsInScan) do
            fail InvalidFormatError{"bad sos length"}

        for i in n
        {
            let cc = .getBits1(8)
            let c  = .getBits1(8)
            left -= 2

            var ci = 0
            while ci < .compsInFrame
            {
                if cc == .compIdent[ci] do
                    break
                ci += 1
            }

            if ci >= .compsInFrame do
                fail InvalidFormatError{"bad sos comp id"}

            .compList[i]   = ci
            .compDcTab[ci] = (c >> 4) & 15
            .compAcTab[ci] = (c & 15) + (MaxHuffTables >> 1)
        }

        .spectralStart  = .getBits1(8)
        .spectralEnd    = .getBits1(8)
        .successiveHigh = .getBits1(4)
        .successiveLow  = .getBits1(4)

        if !.progressiveFlag
        {
            .spectralStart = 0
            .spectralEnd   = 63
        }

        left -= 3
        while left
        {
            .getBits1(8)
            left -= 1
        }
    }

    mtd locateSosMarker()->bool fail
    {
        let c = .processMarkers()
        if c == .M_EOI do
            return false
        elif c != .M_SOS do
            fail InvalidFormatError{"unexpected marker"}
        .readSosMarker()
        return true
    }

    mtd locateSoiMarker() fail
    {
        var lastRune = .getBits1(8)
        var thisChar = .getBits1(8)
        if (lastRune == 0xFF) and (thisChar == Marker.M_SOI) do
            return
        var bytesLeft = 512
        for
        {
            bytesLeft -= 1
            if bytesLeft == 0 do
                fail InvalidFormatError{"not a jpeg"}
            lastRune = thisChar
            thisChar = .getBits1(8)
            if (lastRune == 0xFF) and (thisChar == Marker.M_SOI) do
                break
        }

        thisChar = (.bitBuf >> 8) & 0xFF
        if thisChar != 0xFF do
            fail InvalidFormatError{"not a jpeg"}
    }

    mtd locateSofMarker() fail
    {
        .locateSoiMarker()
        let c = .processMarkers()
        switch c
        {
        case .M_SOF2:
            .progressiveFlag = true
            try .readSofMarker()

        case .M_SOF0, .M_SOF1:
            .readSofMarker()

        case .M_SOF9:
            fail UnsupportedFormatError{"no arithmetic support"}

        default:
            fail UnsupportedFormatError{"unsupported marker"}
        }
    }

    func memset16(p: [*] void, c: u16, n: u32)
    {
        var ps = cast([*] u16) p
        for n
        {
            ps[] = c
            ps   += 1
        }
    }

    mtd prepareInBuffer()
    {
        .inBufLeft = 0
        .inBufOfs  = .inBuf
        if .eofReached do
            return

        for
        {
            var size = InBufSize - .inBufLeft
            if size + .streamSeek > .streamLen
            {
                size        = .streamLen - .streamSeek
                .eofReached = 1
            }

            let bytesRead = size
            Memory.copy(cast([*] u8) &.inBuf[0] + .inBufLeft, .stream + .streamSeek, cast(u64) size)
            .streamSeek += size
            .inBufLeft  += bytesRead
            if .inBufLeft >= InBufSize or .eofReached do
                break
        }

        .totalBytesRead += .inBufLeft
        memset16(.safeInBufOfs() + .inBufLeft, 0xD9FF, 64)
    }
}
