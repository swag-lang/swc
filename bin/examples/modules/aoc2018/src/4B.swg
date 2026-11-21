/*
--- Part Two ---
Strategy 2: Of all guards, which guard is most frequently asleep on the same minute?

In the example above, Guard #99 spent minute 45 asleep more than any other guard or minute - three times in total. (In all other cases, any guard spent any minute asleep at most twice.)

What is the ID of the guard you chose multiplied by the minute you chose? (In the above example, the answer would be 99 * 45 = 4455.)
*/

using Core, Core.Parser

func day4B()
{
    let dataPath = Path.combine(Path.directoryName(#file), "4.txt")
    let stats    = readGuardSleepStats(dataPath)

    var bestMinuteCount, bestMinute, bestGuard = 0'u64
    for guardCounts, minute in stats.minutesByGuard
    {
        for guard, minuteCount in guardCounts
        {
            if minuteCount > bestMinuteCount
            {
                bestMinuteCount = minuteCount
                bestMinute      = minute
                bestGuard       = guard
            }
        }
    }

    Swag.assert(bestGuard * bestMinute == 10491)
}
