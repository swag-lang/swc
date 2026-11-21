using Core, Core.Parser

struct GuardSleepStats
{
    minutesByGuard: [60] HashTable'(s32, s32)
    totalByGuard:   HashTable'(s32, s32)
}

func readGuardSleepStats(dataPath: string)->GuardSleepStats
{
    let lines = expect File.readAllLines(dataPath)

    Slice.sort(lines[to], func(x, y)->s32
    {
        let leftDate  = expect Time.DateTime.parse(x[1 to 16])
        let rightDate = expect Time.DateTime.parse(y[1 to 16])
        return leftDate.value <=> rightDate.value
    })

    var timestamp   = expect RegExp.create("(\\d+)-(\\d+)-(\\d+) (\\d+):(\\d+)")
    var shiftStart  = expect RegExp.create("Guard #(\\d+) begins shift")
    var fallsAsleep = expect RegExp.create("falls asleep")
    var wakesUp     = expect RegExp.create("wakes up")

    var stats: GuardSleepStats
    var currentGuard, sleepStart, currentMinute = 0

    for line in lines
    {
        discard timestamp.grep(line[])
        currentMinute = expect StrConv.toS32(timestamp[5])

        if shiftStart.grep(line[])
        {
            currentGuard = expect StrConv.toS32(shiftStart[1])
        }
        elif fallsAsleep.grep(line[])
        {
            sleepStart = currentMinute
        }
        elif wakesUp.grep(line[])
        {
            while sleepStart < currentMinute
            {
                stats.minutesByGuard[sleepStart].findOrAdd(currentGuard).value += 1
                stats.totalByGuard.findOrAdd(currentGuard).value += 1
                sleepStart += 1
            }
        }
    }

    return stats
}
