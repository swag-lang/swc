#global private

// Real-life example: inspect a CSV import preview before ingesting it.

struct CsvPreview
{
    rowCount:          u32
    columnCount:       u32
    numericCellCount:  u32
    longestLineLength: u32
    hasQuotedField:    bool
    byteCount:         u32
}

func countRows(csv: string)->u32
{
    let bytes = cast(const [..] u8, csv)
    if not bytes.count
    {
        return 0
    }

    var result = 1_u32
    for ch in bytes
    {
        if ch == '\n'_u8
        {
            result += 1
        }
    }

    return result
}

func countColumns(csv: string)->u32
{
    let bytes = cast(const [..] u8, csv)
    if not bytes.count
    {
        return 0
    }

    var result = 1_u32
    for ch in bytes
    {
        if ch == '\n'_u8
        {
            break
        }

        if ch == ','_u8
        {
            result += 1
        }
    }

    return result
}

func countNumericCells(csv: string)->u32
{
    let bytes = cast(const [..] u8, csv)

    var result:   u32
    var rowIndex: u32
    var cellStart = true

    for ch in bytes
    {
        if rowIndex != 0 and cellStart and ch >= '0'_u8 and ch <= '9'_u8
        {
            result += 1
        }

        cellStart = false
        if ch == ','_u8
        {
            cellStart = true
        }

        if ch == '\n'_u8
        {
            rowIndex  += 1
            cellStart = true
        }
    }

    return result
}

func longestLineLength(csv: string)->u32
{
    let bytes = cast(const [..] u8, csv)

    var best:    u32
    var current: u32

    for ch in bytes
    {
        if ch == '\n'_u8
        {
            if current > best
            {
                best = current
            }
            current = 0
        }
        else
        {
            current += 1
        }
    }

    if current > best
    {
        best = current
    }

    return best
}

func hasQuotedField(csv: string)->bool
{
    let bytes = cast(const [..] u8, csv)
    for ch in bytes
    {
        if ch == '"'_u8
        {
            return true
        }
    }

    return false
}

func buildCsvPreview(csv: string)->CsvPreview
{
    let bytes = cast(const [..] u8, csv)

    var result: CsvPreview
    result.rowCount          = countRows(csv)
    result.columnCount       = countColumns(csv)
    result.numericCellCount  = countNumericCells(csv)
    result.longestLineLength = longestLineLength(csv)
    result.hasQuotedField    = hasQuotedField(csv)
    result.byteCount         = cast(u32, bytes.count)
    return result
}

// CSV preview: row/column/cell counts and quoting
#test
{
    const csv = "id,name,qty,price_cents\n1,keyboard,4,12900\n2,\"mouse pad\",12,2500\n3,cable,8,900"

    Swag.require(countRows(csv) == 4)
    Swag.require(countColumns(csv) == 4)
    Swag.require(countNumericCells(csv) == 9)
    Swag.require(longestLineLength(csv) == 23)
    Swag.require(hasQuotedField(csv))

    let preview = buildCsvPreview(csv)

    Swag.require(preview.rowCount == 4)
    Swag.require(preview.columnCount == 4)
    Swag.require(preview.numericCellCount == 9)
    Swag.require(preview.longestLineLength == 23)
    Swag.require(preview.hasQuotedField)
    Swag.require(preview.byteCount == 78)
}
