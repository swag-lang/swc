//! Format: Joint Photographic Experts Group (JPEG) encoder component.
//! Supported: Baseline Huffman-coded lossy output from 8-bit RGB/BGR images with configurable quality.
//! Not supported: Progressive, arithmetic, lossless, CMYK/YCCK, and alpha output.
//! Role: This file owns JPEG bitstream and marker emission.
//
#global namespace Jpg

using Core, Core.Errors

impl Encoder
{
    #[Swag.Inline]
    mtd writeByte(b: u8)
    {
        .outBuf[.outCount] = b
        .outCount += 1
        if .outCount == OutBufSize
        {
            .flushStaged()
        }
    }

    #[Swag.Inline]
    mtd writeWord(w: u16)
    {
        .writeByte(cast(u8, (w >> 8)))
        .writeByte(cast(u8, (w & 0xFF)))
    }

    mtd writeBytes(s: const [..] u8)
    {
        // Everything the encoder emits goes through the staging buffer, so a bulk segment has to
        // hand over what is already staged before appending itself.
        .flushStaged()
        .stream!.addBytes(s)
    }

    // Hands the staged bytes to the output buffer. Call it once the stream is complete.
    mtd flushStaged()
    {
        if not .outCount
        {
            return
        }

        .stream!.addBytes(Swag.makeSlice(cast(const [*] u8, &.outBuf[0]), cast(u64, .outCount)))
        .outCount = 0
    }

    // Split a code at the word boundary and carry its unwritten suffix into the next word.
    #[Swag.Inline]
    mtd writePackedCode(code: u32)
    {
        .appendEntropyBits(code >> PackedLengthShift, code & PackedBitsMask)
    }

    #[Swag.Inline]
    mtd writeAmplitude(code: u32, value: s32, category: u8)
    {
        let mask      = (1_u32 << category) - 1
        let amplitude = cast #bit(u32, (value + (value >> 31))) & mask
        .appendEntropyBits(code >> PackedLengthShift, (code & PackedBitsMask) | amplitude)
    }

    #[Swag.Inline]
    mtd appendEntropyBits(length: u32, bits: u32)
    {
        let total = .bitCount + length
        if total < 64
        {
            .bitBuffer = (.bitBuffer << length) | bits
            .bitCount  = total
        }
        else
        {
            let remaining = total - 64
            let word      = (.bitBuffer << (64 - .bitCount)) | (cast(u64, bits) >> remaining)
            .bitBuffer = bits
            .bitCount  = remaining
            .writeEntropyWord(word)
        }
    }

    #[Swag.Inline]
    private mtd writeEntropyByte(byte: u8)
    {
        .writeByte(byte)
        if byte == 0xFF
        {
            .writeByte(0)
        }
    }

    #[Swag.NoInline]
    private mtd writeEntropyWord(word: u64)
    {
        let low         = word & 0x7F7F_7F7F_7F7F_7F7F_u64
        let hasStuffing = ((low + 0x0101_0101_0101_0101_u64) & word & 0x8080_8080_8080_8080_u64) != 0
        if not hasStuffing and .outCount <= OutBufSize - 8
        {
            cast([*] u64, &.outBuf[.outCount])[] = Math.nativeToBigEndian(word)
            .outCount += 8
            if .outCount == OutBufSize
            {
                .flushStaged()
            }
        }
        else
        {
            for byteIndex in 8
            {
                .writeEntropyByte(cast(u8, (word >> (56 - byteIndex * 8)) & 0xFF))
            }
        }
    }

    mtd flushEntropyBytes()
    {
        while .bitCount >= 8
        {
            .bitCount -= 8
            .writeEntropyByte(cast(u8, ((.bitBuffer >> .bitCount) & 0xFF)))
        }
    }

    mtd writeMetadata(image: const *Image) fail
    {
        for md in image.metadata
        {
            if md.signature > 15
            {
                fail UnsupportedFormatError{"JPEG metadata signatures must be from 0 through 15"}
            }

            for c in md.tag where c == 0
            {
                fail UnsupportedFormatError{"JPEG metadata tags cannot contain NUL"}
            }

            if md.tag.count > 65_532
            {
                fail UnsupportedFormatError{"JPEG metadata tag and value exceed the segment size limit"}
            }

            if md.value.count > 65_532 - md.tag.count
            {
                fail UnsupportedFormatError{"JPEG metadata tag and value exceed the segment size limit"}
            }
        }

        for md in image.metadata
        {
            .writeWord(0xFFE0_u16 + cast(u16, md.signature))
            .writeWord(3 + cast(u16, md.tag.count) + cast(u16, md.value.count))
            .writeBytes(md.tag.toSlice())
            .writeByte(0)
            .writeBytes(md.value.toSlice())
        }
    }

    mtd writeDQTinfo()
    {
        .writeWord(.dqtInfo.marker)
        .writeWord(.dqtInfo.length)
        .writeByte(.dqtInfo.infoQty)
        .writeBytes(.dqtInfo.tableY)
        .writeByte(.dqtInfo.infoQtcb)
        .writeBytes(.dqtInfo.tableCb)
    }

    mtd writeSOF0info(image: const *Image)
    {
        .writeWord(SOF0info.marker)
        .writeWord(SOF0info.length)
        .writeByte(SOF0info.precision)
        .writeWord(cast(u16, image.height))
        .writeWord(cast(u16, image.width))
        .writeByte(SOF0info.numComponents)
        .writeByte(SOF0info.idy)
        .writeByte(SOF0info.hvy)
        .writeByte(SOF0info.qty)
        .writeByte(SOF0info.idcb)
        .writeByte(SOF0info.hvcb)
        .writeByte(SOF0info.qtcb)
        .writeByte(SOF0info.idcr)
        .writeByte(SOF0info.hvcr)
        .writeByte(SOF0info.qtcr)
    }

    mtd writeDHTinfo()
    {
        .writeWord(.dhtInfo.marker)
        .writeWord(.dhtInfo.length)
        .writeByte(.dhtInfo.infoHTYDC)
        .writeBytes(.dhtInfo.nrcodesYDC)
        .writeBytes(.dhtInfo.valuesYDC)
        .writeByte(.dhtInfo.infoHTYAC)
        .writeBytes(.dhtInfo.nrcodesYAC)
        .writeBytes(.dhtInfo.valuesYAC)
        .writeByte(.dhtInfo.infoHTCbDC)
        .writeBytes(.dhtInfo.nrcodesCbDC)
        .writeBytes(.dhtInfo.valuesCbDC)
        .writeByte(.dhtInfo.infoHTCbAC)
        .writeBytes(.dhtInfo.nrcodesCbAC)
        .writeBytes(.dhtInfo.valuesCbAC)
    }

    mtd writeSOSinfo()
    {
        .writeWord(SOSinfo.marker)
        .writeWord(SOSinfo.length)
        .writeByte(SOSinfo.numComponents)
        .writeByte(SOSinfo.idy)
        .writeByte(SOSinfo.hty)
        .writeByte(SOSinfo.idcb)
        .writeByte(SOSinfo.htcb)
        .writeByte(SOSinfo.idcr)
        .writeByte(SOSinfo.htcr)
        .writeByte(SOSinfo.ss)
        .writeByte(SOSinfo.se)
        .writeByte(SOSinfo.bf)
    }
}
