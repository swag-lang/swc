/*
--- Day 2: I Was Told There Would Be No Math ---
The elves are running low on wrapping paper, and so they need to submit an order for more. They have a list of the dimensions (length l, width w, and height h) of each present, and only want to order exactly as much as they need.

Fortunately, every present is a box (a perfect right rectangular prism), which makes calculating the required wrapping paper for each gift a little easier: find the surface area of the box, which is 2*l*w + 2*w*h + 2*h*l. The elves also need a little extra paper for each present: the area of the smallest side.

For example:

A present with dimensions 2x3x4 requires 2*6 + 2*12 + 2*8 = 52 square feet of wrapping paper plus 6 square feet of slack, for a total of 58 square feet.
A present with dimensions 1x1x10 requires 2*1 + 2*10 + 2*10 = 42 square feet of wrapping paper plus 1 square foot of slack, for a total of 43 square feet.
All numbers in the elves' list are in feet. How many total square feet of wrapping paper should they order?
*/

using Core

internal struct Day2Present
{
    x: u32
    y: u32
    z: u32
}

internal var day2PresentsLoaded = false
internal var day2Presents: Array'Day2Present

internal func day2ParseNumber(line: string, cursor: &u64)->u32
{
    var result = 0'u32
    while cursor < @countof(line) and line[cursor] >= '0' and line[cursor] <= '9'
    {
        result *= 10
        result += cast(u32) line[cursor] - '0'
        cursor += 1
    }

    if cursor < @countof(line) and line[cursor] == 'x' do
        cursor += 1

    return result
}

internal func day2EnsurePresents()
{
    if day2PresentsLoaded do
        return

    let dataPath = Path.combine(Path.getDirectoryName(#file), "2.txt")
    let lines    = assume File.readAllLines(dataPath)

    day2Presents.reserve(lines.count)
    foreach line in lines
    {
        var cursor = 0'u64
        var x = day2ParseNumber(line, &cursor)
        var y = day2ParseNumber(line, &cursor)
        var z = day2ParseNumber(line, &cursor)
        orderMinMax(&x, &y)
        orderMinMax(&y, &z)
        orderMinMax(&x, &y)
        day2Presents.add(Day2Present{x, y, z})
    }

    day2PresentsLoaded = true
}

func day2A()
{
    day2EnsurePresents()

    var total: u64
    foreach gift in day2Presents do
        total += 3 * gift.x * gift.y + 2 * gift.y * gift.z + 2 * gift.z * gift.x

    //Console.print("total: ", total)
    @assert(total == 1588178)
}
