#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui.Testing

const RepeatedTestBlockSize = 64 * 1024'u64

// Duplicate findings stay capped while the rest of the analysis reaches the end of the range.
#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("scope-hex-repeat-pair-cap-", ".bin")
    defer discard catch File.delete(fileName)

    const BlockCount = 258'u64
    var payload: Array'u8
    payload.resize(RepeatedTestBlockSize * BlockCount)
    for index in payload.count do
        payload[index] = 0xA5
    expect File.writeAllBytes(fileName, payload.toSlice())

    let result = Viewers.Hex.analyzeRange(fileName, Viewers.Hex.AnalysisRange{0, payload.count})
    Swag.require(result.failureReason.isEmpty() and result.scanned == payload.count)
    Swag.require(result.repeatedBlocks.count == 256 and result.repeatHintsTruncated)
    Swag.require(not result.repeatScanTruncated)
    Swag.require(result.repeatedBlocks[0].firstOffset == 0 and
                 result.repeatedBlocks[0].repeatedOffset == RepeatedTestBlockSize)
    Swag.require(result.repeatedBlocks[255].repeatedOffset == RepeatedTestBlockSize * 256)
}

// The representative byte copies are capped even when every fixed block has unique contents.
#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("scope-hex-repeat-representative-cap-", ".bin")
    defer discard catch File.delete(fileName)

    const BlockCount = 257'u64
    var payload: Array'u8
    payload.resize(RepeatedTestBlockSize * BlockCount)
    for blockIndex in BlockCount
    {
        let offset = blockIndex * RepeatedTestBlockSize
        for byteIndex in RepeatedTestBlockSize do
            payload[offset + byteIndex] = 0xA5
        payload[offset] = cast(u8, blockIndex)
        payload[offset + 1] = cast(u8, blockIndex >> 8)
    }
    expect File.writeAllBytes(fileName, payload.toSlice())

    let result = Viewers.Hex.analyzeRange(fileName, Viewers.Hex.AnalysisRange{0, payload.count})
    Swag.require(result.failureReason.isEmpty() and result.scanned == payload.count)
    Swag.require(result.repeatedBlocks.isEmpty() and result.repeatScanTruncated)
    Swag.require(not result.repeatHintsTruncated)
}
