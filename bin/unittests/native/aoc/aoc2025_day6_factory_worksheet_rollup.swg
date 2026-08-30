#global private

// Real-life example: roll up a wide factory worksheet where each vertical
// column group describes one batch operation to validate.

struct WorksheetRollup
{
    problemCount:         u32
    additiveProblemCount: u32
    multiplicativeCount:  u32
    grandTotal:           u64
    largestProblemValue:  u64
}

struct ProblemValue
{
    value:      u64
    isAdditive: bool
}

func maxU64(lhs, rhs: u64)->u64
{
    return lhs > rhs ? lhs : rhs
}

func hasVisibleChar(sheet: const [..] string, column: u32)->bool
{
    for line in sheet
    {
        let bytes = cast(const [..] u8) line
        Swag.assert(column < bytes.count)

        if bytes[column] != ' ' do
            return true
    }

    return false
}

func parseAlignedNumber(line: string, firstColumn, lastColumn: u32, value: *u64)->bool
{
    let bytes = cast(const [..] u8) line

    var foundDigit = false
    var result: u64

    for column in firstColumn to lastColumn
    {
        let c = bytes[column]
        if c >= '0' and c <= '9'
        {
            foundDigit = true
            result     = result * 10'u64 + cast(u64) (c - '0')
        }
    }

    if foundDigit do
        value[] = result
    return foundDigit
}

func evaluateProblem(sheet: const [..] string, firstColumn, lastColumn: u32)->ProblemValue
{
    Swag.assert(sheet.count >= 2)

    let operatorLine = cast(const [..] u8) sheet[sheet.count - 1]

    var op: u8
    for column in firstColumn to lastColumn
    {
        if operatorLine[column] == '+' or operatorLine[column] == '*'
        {
            op = operatorLine[column]
            break
        }
    }

    Swag.assert(op == '+' or op == '*')

    var value:       u64
    var numberCount: u32

    for row in 0 to sheet.count - 1
    {
        var parsedValue: u64
        if parseAlignedNumber(sheet[row], firstColumn, lastColumn, &parsedValue)
        {
            if numberCount == 0
            {
                value = parsedValue
            }
            else
            {
                if op == '+' do
                    value += parsedValue
                if op == '*' do
                    value *= parsedValue
            }

            numberCount += 1
        }
    }

    Swag.assert(numberCount > 0)

    var result: ProblemValue
    result.value      = value
    result.isAdditive = op == '+'
    return result
}

func rollupWorksheet(sheet: const [..] string)->WorksheetRollup
{
    Swag.assert(sheet.count >= 2)

    let firstLine = cast(const [..] u8) sheet[0]
    let width     = cast(u32) firstLine.count

    for line in sheet
    {
        Swag.assert((cast(const [..] u8) line).count == width)
    }

    var result: WorksheetRollup
    var column: u32

    while column < width
    {
        while column < width and hasVisibleChar(sheet, column) == false
        {
            column += 1
        }

        if column == width do
            break

        let firstColumn = column

        while column < width and hasVisibleChar(sheet, column)
        {
            column += 1
        }

        let problemValue = evaluateProblem(sheet, firstColumn, column - 1)

        result.problemCount        += 1
        result.grandTotal          += problemValue.value
        result.largestProblemValue = maxU64(result.largestProblemValue, problemValue.value)

        if problemValue.isAdditive do
            result.additiveProblemCount += 1
        if problemValue.isAdditive == false do
            result.multiplicativeCount += 1
    }

    return result
}

#test
{
    const sampleSheet: [4] string =
        [
        "123 328  51 64 ",
        " 45 64  387 23 ",
        "  6 98  215 314",
        "*   +   *   +  "
        ]

    let sampleRollup = rollupWorksheet(sampleSheet)

    Swag.assert(sampleRollup.problemCount == 4'u32)
    Swag.assert(sampleRollup.additiveProblemCount == 2'u32)
    Swag.assert(sampleRollup.multiplicativeCount == 2'u32)
    Swag.assert(sampleRollup.grandTotal == 4277556'u64)
    Swag.assert(sampleRollup.largestProblemValue == 4243455'u64)

    const eveningSheet: [5] string =
        [
        " 88  900  12",
        "125   75 340",
        "  7        8",
        "      25    ",
        "*    +    * "
        ]

    let eveningRollup = rollupWorksheet(eveningSheet)

    Swag.assert(eveningRollup.problemCount == 3'u32)
    Swag.assert(eveningRollup.additiveProblemCount == 1'u32)
    Swag.assert(eveningRollup.multiplicativeCount == 2'u32)
    Swag.assert(eveningRollup.grandTotal == 110640'u64)
    Swag.assert(eveningRollup.largestProblemValue == 77000'u64)
}
