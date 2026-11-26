//! Format: Joint Photographic Experts Group (JPEG) encoder component.
//! Supported: Baseline Huffman-coded lossy output from 8-bit RGB/BGR images with configurable quality.
//! Not supported: Progressive, arithmetic, lossless, CMYK/YCCK, and alpha output.
//! Role: This file owns Huffman table construction and entropy encoding.
//
#global namespace Jpg

using Core

impl Encoder
{
    mtd setQuantTable(basicTable: const [*] u8, newTable: [*] u8)
    {
        for i in 64
        {
            var temp = (cast(s32, basicTable[i]) * .scaleFactor + 50) / 100
            temp = Math.clamp(temp, 1, 255)
            newTable[ZigZag[i]] = cast(u8, temp)
        }
    }

    mtd setDQTinfo()
    {
        .dqtInfo.marker   = 0xFFDB
        .dqtInfo.length   = 132
        .dqtInfo.infoQty  = 0
        .dqtInfo.infoQtcb = 1
        .setQuantTable(LuminanceQt, .dqtInfo.tableY)
        .setQuantTable(ChrominanceQt, .dqtInfo.tableCb)
    }

    // Writes the Huffman tables of the specification into the stream.
    //
    // They live beside the decoder, in `decode/jpg.huffman.swg`: this encoder writes them into
    // every stream, and that decoder substitutes them into a stream that defines none.
    mtd setDHTinfo()
    {
        .dhtInfo.marker     = 0xFFC4
        .dhtInfo.length     = 0x01A2
        .dhtInfo.infoHTYDC  = 0
        .dhtInfo.infoHTYAC  = 0x10
        .dhtInfo.infoHTCbDC = 1
        .dhtInfo.infoHTCbAC = 0x11

        for i in 16 do
            .dhtInfo.nrcodesYDC[i] = StdDcLuminanceNrCodes[i + 1]
        for i in 12 do
            .dhtInfo.valuesYDC[i] = StdDcLuminanceValues[i]
        for i in 16 do
            .dhtInfo.nrcodesYAC[i] = StdAcLuminanceNrCodes[i + 1]
        for i in 162 do
            .dhtInfo.valuesYAC[i] = StdAcLuminanceValues[i]
        for i in 16 do
            .dhtInfo.nrcodesCbDC[i] = StdDcChrominanceNrCodes[i + 1]
        for i in 12 do
            .dhtInfo.valuesCbDC[i] = StdDcChrominanceValues[i]
        for i in 16 do
            .dhtInfo.nrcodesCbAC[i] = StdAcChrominanceNrCodes[i + 1]
        for i in 162 do
            .dhtInfo.valuesCbAC[i] = StdAcChrominanceValues[i]
    }

    const LumaDcCodes   = #run compileCodes'12(StdDcLuminanceNrCodes, StdDcLuminanceValues, false)
    const LumaAcCodes   = #run compileCodes'256(StdAcLuminanceNrCodes, StdAcLuminanceValues, true)
    const ChromaDcCodes = #run compileCodes'12(StdDcChrominanceNrCodes, StdDcChrominanceValues, false)
    const ChromaAcCodes = #run compileCodes'256(StdAcChrominanceNrCodes, StdAcChrominanceValues, true)

    // A symbol already determines the category. Keep the shifted prefix and combined bit count.
    func(Size: u64) compileCodes(counts, symbols: const [..] u8, ac: bool)->[Size] u32
    {
        var packed: #returntype
        if ac
        {
            // Undefined symbols still carry the amplitude bits, as with a zero-length prefix.
            for i in packed.count do
                packed[i] = (cast(u32, i) & 15) << PackedLengthShift
        }

        var code  = 0'u16
        var index = 0
        for length in 1 to 16
        {
            for counts[length]
            {
                let symbol   = symbols[index]
                let category = ac ? symbol & 15 : symbol
                let total    = cast(u32, length) + category
                packed[symbol] = (total << PackedLengthShift) | (cast(u32, code) << category)
                code  += #wrap 1
                index += 1
            }

            code *= #wrap 2
        }

        return packed
    }

    mtd prepareQuantTables()
    {
        const AanSf: [8] f64 = [1.0, 1.387039845, 1.306562965, 1.175875602, 1.0, 0.785694958, 0.541196100, 0.275899379]
        var i = 0
        for row in 8
        {
            for col in 8
            {
                .fdtblY[i]  = cast(f32, (1.0 / (cast(f64, .dqtInfo.tableY[ZigZag[i]]) * AanSf[row] * AanSf[col] * 8.0)))
                .fdtblCb[i] = cast(f32, (1.0 / (cast(f64, .dqtInfo.tableCb[ZigZag[i]]) * AanSf[row] * AanSf[col] * 8.0)))
                i += 1
            }
        }
    }
}
