//! Format: Joint Photographic Experts Group (JPEG) encoder component.
//! Supported: Baseline Huffman-coded lossy output from 8-bit RGB/BGR images with configurable quality.
//! Not supported: Progressive, arithmetic, lossless, CMYK/YCCK, and alpha output.
//! Role: This file owns JPEG bitstream and marker emission.
//
#global namespace Jpg

using Core

impl Encoder
{
    #[Swag.Inline]
    mtd writeByte(b: u8)
    {
        .outBuf[.outCount] = b
        .outCount          += 1
        if .outCount == OutBufSize do
            .flushStaged()
    }

    #[Swag.Inline]
    mtd writeWord(w: u16)
    {
        .writeByte(cast(u8) (w >> 8))
        .writeByte(cast(u8) (w & 0xFF))
    }

    mtd writeBytes(s: const [..] u8)
    {
        // Everything the encoder emits goes through the staging buffer, so a bulk segment has to
        // hand over what is already staged before appending itself.
        .flushStaged()
        let stream = .stream!
        stream.addBytes(s)
    }

    // Hands the staged bytes to the output buffer. Call it once the stream is complete.
    mtd flushStaged()
    {
        if !.outCount do
            return

        let stream = .stream!
        stream.addBytes(@mkslice(cast(const [*] u8) &.outBuf[0], cast(u64) .outCount))
        .outCount = 0
    }

    // Appends one Huffman or magnitude code to the entropy-coded segment.
    //
    // The pending bits are kept right-aligned in an accumulator that never holds a full byte on
    // entry, so a code costs one shift and the loop below only runs when a byte completed.
    mtd writeBits(bs: BitString)
    {
        let length = cast(u32) bs.length
        .bitBuffer = (.bitBuffer << #wrap length) | (cast(u32) bs.value & ((1'u32 << length) - 1))
        .bitCount  += length

        while .bitCount >= 8
        {
            .bitCount -= 8
            let written = cast(u8) ((.bitBuffer >> .bitCount) & 0xFF)
            .writeByte(written)

            // A 0xFF inside entropy-coded data is stuffed, or a decoder reads it as a marker.
            if written == 0xFF do
                .writeByte(0)
        }
    }

    mtd writeMetadata(image: const *Image)
    {
        for md in image.metadata
        {
            .writeWord(0xFFE0'u16 + cast(u16) md.signature)
            .writeWord(3 + cast(u16) md.tag.count + cast(u16) md.value.count)
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
        .writeWord(cast(u16) image.height)
        .writeWord(cast(u16) image.width)
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
