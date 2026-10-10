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
    var column, row = 0
    while row != lines.count - 1
    {
        column = cast(s32, ((column + 3) % lines[0].length))
        row    += 1
        total  += lines[row][column] == '#' ? 1 : 0
    }

    Swag.assert(total == 211)
}
