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
        let first = Tokenize.split(l[], ' 'u8)

        var prev = 0, ls = 0
        var bad  = false
        for v, index in first
        {
            let a = expect StrConv.toS32(v)
            if index
            {
                let diff = a - prev
                if Swag.abs(diff) < 1 or Swag.abs(diff) > 3 do
                    bad = true
                if ls and Math.sign(diff) != ls do
                    bad = true
                ls = Math.sign(diff)
            }

            prev = a
        }

        total += bad == false ? 1 : 0
    }

    Swag.assert(total == 549)
}
