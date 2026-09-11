/*
--- Day 5: A Maze of Twisty Trampolines, All Alike ---
The input is a list of relative jump offsets. Start at the first entry, read its offset,
increment that entry, then move by the original offset. Count the jumps needed to leave
the list. The example offsets 0, 3, 0, 1, -3 take five jumps.
*/

using Core

func day5A()
{
    // Time.Stopwatch.scopeMeasure()
    let dataPath = Path.combine(Path.directoryName(#file), "5.txt")
    let lines    = expect File.readAllLines(dataPath)
    var jumps    = Slice.map(lines[to], func(x) => expect StrConv.toS32(x))

    var it, step = 0
    while it < jumps.count
    {
        step      += 1
        jumps[it] += 1
        it        += jumps[it] - 1
    }

    Swag.assert(step == 359348)
}
