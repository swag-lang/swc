#global namespace Jpg

using Core

impl Encoder
{
    mtd setQuantTable(basicTable: const [*] u8, newTable: [*] u8)
    {
        for [i] in 64
        {
            var temp = (cast(s32) basicTable[i] * .scaleFactor + 50) / 100
            temp                = Math.clamp(temp, 1, 255)
            newTable[ZigZag[i]] = cast(u8) temp
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

    mtd setDHTinfo()
    {
        .dhtInfo.marker     = 0xFFC4
        .dhtInfo.length     = 0x01A2
        .dhtInfo.infoHTYDC  = 0
        .dhtInfo.infoHTYAC  = 0x10
        .dhtInfo.infoHTCbDC = 1
        .dhtInfo.infoHTCbAC = 0x11

        for [i] in 16 do
            .dhtInfo.nrcodesYDC[i] = StdDcLuminanceNrCodes[i + 1]
        for [i] in 12 do
            .dhtInfo.valuesYDC[i] = StdDcLuminanceValues[i]
        for [i] in 16 do
            .dhtInfo.nrcodesYAC[i] = StdAcLuminanceNrCodes[i + 1]
        for [i] in 162 do
            .dhtInfo.valuesYAC[i] = StdAcLuminanceValues[i]
        for [i] in 16 do
            .dhtInfo.nrcodesCbDC[i] = StdDcChrominanceNrCodes[i + 1]
        for [i] in 12 do
            .dhtInfo.valuesCbDC[i] = StdDcChrominanceValues[i]
        for [i] in 16 do
            .dhtInfo.nrcodesCbAC[i] = StdAcChrominanceNrCodes[i + 1]
        for [i] in 162 do
            .dhtInfo.valuesCbAC[i] = StdAcChrominanceValues[i]
    }

    func computeHuffmanTable(nrCodes: const [*] u8, stdTable: const [*] u8, hT: [*] BitString)
    {
        var codevalue  = 0'u16
        var posInTable = 0
        for [k] in 1 to 16
        {
            for var j = 1; j <= nrCodes[k]; j += 1
            {
                hT[stdTable[posInTable]].value  = codevalue
                hT[stdTable[posInTable]].length = cast(u8) k
                posInTable                      += 1
                codevalue                       += #wrap 1
            }

            codevalue *= #wrap 2
        }
    }

    mtd initHuffmanTables()
    {
        computeHuffmanTable(StdDcLuminanceNrCodes, StdDcLuminanceValues, .htYDC)
        computeHuffmanTable(StdDcChrominanceNrCodes, StdDcChrominanceValues, .htCbDC)
        computeHuffmanTable(StdAcLuminanceNrCodes, StdAcLuminanceValues, .htYAC)
        computeHuffmanTable(StdAcChrominanceNrCodes, StdAcChrominanceValues, .htCbAC)
    }

    mtd setNumbersCategoryAndBitcode()
    {
        .categoryAlloc.resize(65535)
        .bitcodeAlloc.resize(65535)
        .category = cast([*] u8) (notnull .categoryAlloc.buffer) + 32767
        .bitcode  = cast([*] BitString) (notnull .bitcodeAlloc.buffer) + 32767

        var nrlower = 1
        var nrupper = 2
        for [cat] in 1 to 15
        {
            for [nr] in nrlower until nrupper
            {
                .category[nr]       = cast(u8) cat
                .bitcode[nr].length = cast(u8) cat
                .bitcode[nr].value  = cast(u16) nr
            }

            for [nr] in -(nrupper - 1) to -nrlower
            {
                let nof = cast #bit (u64) cast(s64) nr
                .category[nof]       = cast(u8) cat
                .bitcode[nof].length = cast(u8) cat
                .bitcode[nof].value  = cast(u16) (nrupper - 1 + nr)
            }

            nrlower <<= 1
            nrupper <<= 1
        }
    }

    mtd prepareQuantTables()
    {
        const AanSf: [8] f64 = [1.0, 1.387039845, 1.306562965, 1.175875602, 1.0, 0.785694958, 0.541196100, 0.275899379]
        var i = 0
        for [row] in 8
        {
            for [col] in 8
            {
                .fdtblY[i]  = cast(f32) (1.0 / (cast(f64) .dqtInfo.tableY[ZigZag[i]] * AanSf[row] * AanSf[col] * 8.0))
                .fdtblCb[i] = cast(f32) (1.0 / (cast(f64) .dqtInfo.tableCb[ZigZag[i]] * AanSf[row] * AanSf[col] * 8.0))
                i           += 1
            }
        }
    }
}
