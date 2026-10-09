/*
--- Part Two ---
As the race is about to start, you realize the piece of paper with race times and record distances you got earlier actually just has very bad kerning. There's really only one race - ignore the spaces between the numbers on each line.

So, the example from before:

Time:      7  15   30
Distance:  9  40  200
...now instead means this:

Time:      71530
Distance:  940200
Now, you have to figure out how many ways there are to win this single race. In this example, the race lasts for 71530 milliseconds and the record distance you need to beat is 940200 millimeters. You could hold the button anywhere from 14 to 71516 milliseconds and beat the record, a total of 71503 ways!

How many ways can you beat the record in this one much longer race?
*/

using Core

func day6B()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "6.txt")
    let lines    = expect File.readAllLines(dataPath)

    let timeField      = Tokenize.split(lines[0], ':'u8)
    let distanceField  = Tokenize.split(lines[1], ':'u8)
    let timeTokens     = Tokenize.split(timeField[1], ' 'u8)
    let distanceTokens = Tokenize.split(distanceField[1], ' 'u8)

    var raceTimes:       Array'u64
    var recordDistances: Array'u64

    var timeDigits, distanceDigits: String = ""
    for token in timeTokens do
        timeDigits += token
    for token in distanceTokens do
        distanceDigits += token

    raceTimes.add(expect StrConv.toU64(timeDigits))
    recordDistances.add(expect StrConv.toU64(distanceDigits))

    var total: u64 = 1
    for raceTime, raceIndex in raceTimes
    {
        var winningCount   = 0
        let recordDistance = recordDistances[raceIndex]
        for holdTime in raceTime
        {
            let travelDistance = (raceTime - holdTime) * holdTime
            if travelDistance > recordDistance do
                winningCount += 1
        }

        total *= winningCount
    }

    Swag.assert(total == 33875953)
}
