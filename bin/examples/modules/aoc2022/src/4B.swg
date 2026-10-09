/*
--- Part Two ---
It seems like there is still quite a bit of duplicate work planned. Instead, the Elves would like to know the number of pairs that overlap at all.

In the above example, the first two pairs (2-4,6-8 and 2-3,4-5) don't overlap, while the remaining four pairs (5-7,7-9, 2-8,3-7, 6-6,4-6, and 2-6,4-8): overlap:

5-7,7-9 overlaps in a single section, 7.
2-8,3-7 overlaps all of the sections 3 through 7.
6-6,4-6 overlaps in a single section, 6.
2-6,4-8 overlaps in sections 4, 5, and 6.
So, in this example, the number of overlapping assignment pairs is 4.

In how many assignment pairs do the ranges overlap?
*/

using Core

func day4B()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "4.txt")
    let lines    = expect File.readAllLines(dataPath)

    var total: u64
    for l in lines
    {
        let assignmentRanges = Tokenize.split(l[], ','u8)
        let firstRange       = Tokenize.split(assignmentRanges[0], '-'u8)
        let secondRange      = Tokenize.split(assignmentRanges[1], '-'u8)
        let firstStart       = expect StrConv.toS32(firstRange[0])
        let firstEnd         = expect StrConv.toS32(firstRange[1])
        let secondStart      = expect StrConv.toS32(secondRange[0])
        let secondEnd        = expect StrConv.toS32(secondRange[1])

        if not (firstEnd < secondStart or firstStart > secondEnd) do
            total += 1
    }

    Swag.assert(total == 888)
}
