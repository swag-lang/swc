/*
--- Day 2: Red-Nosed Reports ---
Each input line is a report containing a sequence of integer levels. A report is safe
when its levels are either strictly increasing or strictly decreasing, and every pair
of adjacent levels differs by at least one and at most three. Count the safe reports.
*/

using Core

func day2A()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "2.txt")
    let lines    = expect File.readAllLines(dataPath)

    var total = 0
    for l in lines
    {
        let levels = Slice.map(Tokenize.split(l[], ' 'u8).toSlice(),
                               func(value) => expect StrConv.toS32(value))
        total += isReportSafe(levels.toSlice()) ? 1 : 0
    }

    Swag.assert(total == 549)
}
