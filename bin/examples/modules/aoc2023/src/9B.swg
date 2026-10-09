/*
--- Part Two ---
Of course, it would be nice to have even more history included in your report. Surely it's safe to just extrapolate backwards as well, right?

For each history, repeat the process of finding differences until the sequence of differences is entirely zero. Then, rather than adding a zero to the end and filling in the next values of each previous sequence, you should instead add a zero to the beginning of your sequence of zeroes, then fill in new first values for each previous sequence.

In particular, here is what the third example history looks like when extrapolating back in time:

5  10  13  16  21  30  45
  5   3   3   5   9  15
   -2   0   2   4   6
      2   2   2   2
        0   0   0
Adding the new values on the left side of each sequence from bottom to top eventually reveals the new left-most history value: 5.

Doing this for the remaining example data above results in previous values of -3 for the first history and 0 for the second history. Adding all three new values together produces 2.

Analyze your OASIS report again, this time extrapolating the previous value for each history. What is the sum of these extrapolated values?
*/

using Core

func day9B()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "9.txt")
    let lines    = expect File.readAllLines(dataPath)

    var total: s64

    for line in lines
    {
        let valueTokens = Tokenize.split(line[], ' 'u8)

        var differences: Array's64
        for token in valueTokens do
            differences.add(expect StrConv.toS64(token))

        var firstValues: Array's64
        firstValues.add(differences[0])

        var hasNonzeroDifference = true
        while hasNonzeroDifference
        {
            hasNonzeroDifference = false
            var nextDifferences: Array's64
            for index in 0 until differences.count - 1
            {
                let difference = differences[index + 1] - differences[index]
                hasNonzeroDifference = difference or hasNonzeroDifference
                nextDifferences.add(difference)

                if index == 0 do
                    firstValues.add(difference)
            }

            differences = nextDifferences
        }

        var previousValue: s64
        for firstValue in firstValues.reversed()
        {
            previousValue = firstValue - previousValue
        }

        total += previousValue
    }

    Swag.assert(total == 1019)
}
