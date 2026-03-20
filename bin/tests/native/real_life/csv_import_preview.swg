#global fileprivate

// Real-life example: inspect a CSV import preview before ingesting it.

struct CsvPreview
{
    rowCount:            u32
    columnCount:         u32
    numericCellCount:    u32
    longestLineLength:   u32
    hasQuotedField:      bool
    byteCount:           u32
}

func countRows(csv: string)->u32
{
    let bytes = cast(const [..] u8) csv
    if !@countof(bytes) do
        return 0

    var result = 1'u32
    foreach ch in bytes
    {
        if ch == '\n''u8 do
            result += 1
    }

    return result
}

func countColumns(csv: string)->u32
{
    let bytes = cast(const [..] u8) csv
    if !@countof(bytes) do
        return 0

    var result = 1'u32
    foreach ch in bytes
    {
        if ch == '\n''u8 do
            break

        if ch == ',''u8 do
            result += 1
    }

    return result
}

func countNumericCells(csv: string)->u32
{
    let bytes = cast(const [..] u8) csv

    var result: u32
    var rowIndex: u32
    var cellStart = true

    foreach ch in bytes
    {
        if rowIndex != 0 and cellStart and ch >= '0''u8 and ch <= '9''u8 do
            result += 1

        cellStart = false
        if ch == ',''u8 do
            cellStart = true

        if ch == '\n''u8
        {
            rowIndex += 1
            cellStart = true
        }
    }

    return result
}

func longestLineLength(csv: string)->u32
{
    let bytes = cast(const [..] u8) csv

    var best: u32
    var current: u32

    foreach ch in bytes
    {
        if ch == '\n''u8
        {
            if current > best do
                best = current
            current = 0
        }
        else
        {
            current += 1
        }
    }

    if current > best do
        best = current

    return best
}

func hasQuotedField(csv: string)->bool
{
    let bytes = cast(const [..] u8) csv
    foreach ch in bytes
    {
        if ch == '"''u8 do
            return true
    }

    return false
}

func buildCsvPreview(csv: string)->CsvPreview
{
    let bytes = cast(const [..] u8) csv

    var result: CsvPreview
    result.rowCount = countRows(csv)
    result.columnCount = countColumns(csv)
    result.numericCellCount = countNumericCells(csv)
    result.longestLineLength = longestLineLength(csv)
    result.hasQuotedField = hasQuotedField(csv)
    result.byteCount = cast(u32) @countof(bytes)
    return result
}

#test
{
    const csv = "id,name,qty,price_cents\n1,keyboard,4,12900\n2,\"mouse pad\",12,2500\n3,cable,8,900"

    @assert(countRows(csv) == 4)
    @assert(countColumns(csv) == 4)
    @assert(countNumericCells(csv) == 9)
    @assert(longestLineLength(csv) == 23)
    @assert(hasQuotedField(csv))

    let preview = buildCsvPreview(csv)

    @assert(preview.rowCount == 4)
    @assert(preview.columnCount == 4)
    @assert(preview.numericCellCount == 9)
    @assert(preview.longestLineLength == 23)
    @assert(preview.hasQuotedField)
    @assert(preview.byteCount == 78)
}
