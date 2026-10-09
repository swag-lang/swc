/*
--- Part Two ---
By the time you calculate the answer to the Elves' question, they've already realized that the Elf carrying the most Calories of food might eventually run out of snacks.

To avoid this unacceptable situation, the Elves would instead like to know the total Calories carried by the top three Elves carrying the most Calories. That way, even if one of those Elves runs out of snacks, they still have two backups.

In the example above, the top three Elves are the fourth Elf (with 24000 Calories), then the third Elf (with 11000 Calories), then the fifth Elf (with 10000 Calories). The sum of the Calories carried by these three elves is 45000.

Find the top three Elves carrying the most Calories. How many Calories are those Elves carrying in total?
*/

using Core

func day1B()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "1.txt")
    let lines    = expect File.readAllLines(dataPath)

    // A blank line separates two elves; it carries no number, and parsing one is an error.
    var topThreeCalories: [3] u64
    var currentCalories:  u64
    for l, index in lines
    {
        if not l.isEmpty() do
            currentCalories += expect StrConv.toU64(l[])

        if l.isEmpty() or index == lines.count - 1
        {
            switch
            {
            case currentCalories > topThreeCalories[0]: topThreeCalories[0] = currentCalories
            case currentCalories > topThreeCalories[1]: topThreeCalories[1] = currentCalories
            case currentCalories > topThreeCalories[2]: topThreeCalories[2] = currentCalories
            }

            Slice.sort(topThreeCalories[to])
            currentCalories = 0
        }
    }

    let total = topThreeCalories[0] + topThreeCalories[1] + topThreeCalories[2]

    Swag.assert(total == 203002)
}
