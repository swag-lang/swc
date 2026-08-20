#global namespace Jpg

using Core

impl Encoder
{
    #[Swag.Inline]
    mtd writeByte(b: u8)
    {
        let stream = .stream!
        stream.addNative(b)
    }

    #[Swag.Inline]
    mtd writeWord(w: u16)
    {
        let stream = .stream!
        stream.addNative(cast(u8) (w >> 8))
        stream.addNative(cast(u8) (w & 0xFF))
    }

    #[Swag.Inline]
    mtd writeBytes(s: const [..] u8)
    {
        let stream = .stream!
        stream.addBytes(s)
    }

    mtd writeBits(bs: BitString)
    {
        let value  = bs.value
        var posval = cast(s32) bs.length - 1
        while posval >= 0
        {
            if value & Mask[posval] do
                .bytenew |= cast(u8) Mask[.bytepos]
            posval   -= 1
            .bytepos -= 1
            if .bytepos < 0
            {
                let written = .bytenew
                .writeByte(written)
                if written == 0xFF do
                    .writeByte(0)

                .bytepos = 7
                .bytenew = 0
            }
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
