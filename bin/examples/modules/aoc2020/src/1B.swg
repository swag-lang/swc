/*
--- Part Two ---
The Elves in accounting are thankful for your help; one of them even offers you a starfish coin they had left over from a past vacation. They offer you a second one if you can find three numbers in your expense report that meet the same criteria.

Using the above example again, the three entries that sum to 2020 are 979, 366, and 675. Multiplying them together produces the answer, 241861950.

In your expense report, what is the product of the three entries that sum to 2020?
*/

using Core

func day1B()
{
    const TargetSum = 2020
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "1.txt")
    let lines    = expect File.readAllLines(dataPath)

    var expenseEntries: Array's32
    for line in lines do
        expenseEntries.add(expect StrConv.toS32(line[]))

    expenseEntries.sort()

    for firstValue, firstIndex in expenseEntries
    {
        for secondValue, secondIndex in expenseEntries[firstIndex to]
        {
            let matchingValue = TargetSum - (firstValue + secondValue)
            if matchingValue < 0 do
                continue

            if Slice.containsSorted(expenseEntries[secondIndex to], matchingValue)
            {
                Swag.assert(firstValue * secondValue * matchingValue == 165795564)
                return
            }
        }
    }
}
