/*
--- Day 3: Toboggan Trajectory ---
The input is a map of open squares (.) and trees (#) that repeats horizontally.
Starting at the top-left square, move three columns right and one row down at each step.
Count the trees encountered before reaching the bottom row.
*/

using Core

func day3A()
{
    let dataPath = Path.combine(Path.directoryName(#curlocation.fileName), "3.txt")
    let lines    = expect File.readAllLines(dataPath)

    var total: u32
    var x, y = 0
    while y != lines.count - 1
    {
        x     = cast(s32) ((x + 3) % lines[0].length)
        y     += 1
        total += lines[y][x] == '#' ? 1 : 0
    }

    // Console.print("total: ", total)
    Swag.assert(total == 211)
}
