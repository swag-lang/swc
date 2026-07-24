/*
--- Day 6: Probably a Fire Hazard ---
Because your neighbors keep defeating you in the holiday house decorating contest year after year, you've decided to deploy one million lights in a 1000x1000 grid.

Furthermore, because you've been especially nice this year, Santa has mailed you instructions on how to display the ideal lighting configuration.

Lights in your grid are numbered from 0 to 999 in each direction; the lights at each corner are at 0,0, 0,999, 999,999, and 999,0. The instructions include whether to turn on, turn off, or toggle various inclusive ranges given as coordinate pairs. Each coordinate pair represents opposite corners of a rectangle, inclusive; a coordinate pair like 0,0 through 2,2 therefore refers to 9 lights in a 3x3 square. The lights all start turned off.

To defeat your neighbors this year, all you have to: is set up your lights by doing the instructions Santa sent you in order.

For example:

turn on 0,0 through 999,999 would turn on (or leave on) every light.
toggle 0,0 through 999,0 would toggle the first line of 1000 lights, turning off the ones that were on, and turning on the ones that were off.
turn off 499,499 through 500,500 would turn off (or leave off) the middle four lights.
After following the instructions, how many lights are lit?
*/

using Core

internal const DAY6_GRID_SIZE = 1000'u64
internal const DAY6_GRID_SIZE32 = 1000'u32

internal enum Day6Action
{
    TurnOn
    TurnOff
    Toggle
}

internal struct Day6Instruction
{
    action: Day6Action
    x0:     u16
    y0:     u16
    x1:     u16
    y1:     u16
}

internal var day6InstructionsLoaded = false
internal var day6Instructions: Array'Day6Instruction

internal func day6ParseNumber(line: string, cursor: &u64)->u16
{
    while cursor < @countof(line) and (line[cursor] < '0' or line[cursor] > '9') do
        cursor += 1

    var result = 0'u16
    while cursor < @countof(line) and line[cursor] >= '0' and line[cursor] <= '9'
    {
        result *= 10
        result += cast(u16) line[cursor] - '0'
        cursor += 1
    }

    return result
}

internal func day6EnsureInstructions()
{
    if day6InstructionsLoaded do
        return

    let dataPath = Path.combine(Path.getDirectoryName(#file), "6.txt")
    let lines    = assume File.readAllLines(dataPath)

    day6Instructions.reserve(lines.count)
    for line in lines
    {
        var cursor = 0'u64
        var instruction: Day6Instruction

        if line[6] == 'n' do
            instruction.action = .TurnOn
        elif line[6] == 'f' do
            instruction.action = .TurnOff
        else do
            instruction.action = .Toggle

        instruction.x0 = day6ParseNumber(line, &cursor)
        instruction.y0 = day6ParseNumber(line, &cursor)
        instruction.x1 = day6ParseNumber(line, &cursor)
        instruction.y1 = day6ParseNumber(line, &cursor)
        day6Instructions.add(instruction)
    }

    day6InstructionsLoaded = true
}

func day6A()
{
    day6A0()
    day6A1()
    day6A2()
}

/////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////
func day6A0()
{
    // Time.Stopwatch.scopeMeasure()

    day6EnsureInstructions()
    var lights: HashSet'u32
    lights.reserve(DAY6_GRID_SIZE * DAY6_GRID_SIZE)

    for instruction in day6Instructions
    {
        let x0         = cast(u32) instruction.x0
        let y0         = cast(u32) instruction.y0
        let y1         = cast(u32) instruction.y1
        let writeCount = cast(u32) instruction.x1 - x0 + 1

        switch instruction.action
        {
        case .TurnOn:
            for y in y0 to y1
            {
                var coord = x0 + (y * DAY6_GRID_SIZE32)
                for writeCount
                {
                    lights.add(coord)
                    coord += 1
                }
            }

        case .TurnOff:
            for y in y0 to y1
            {
                var coord = x0 + (y * DAY6_GRID_SIZE32)
                for writeCount
                {
                    lights.remove(coord)
                    coord += 1
                }
            }

        case .Toggle:
            for y in y0 to y1
            {
                var coord = x0 + (y * DAY6_GRID_SIZE32)
                for writeCount
                {
                    lights.toggleKey(coord)
                    coord += 1
                }
            }
        }
    }

    // Console.print("total: ", lights.count)
    @assert(lights.count == 377891)
}

/////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////
func day6A1()
{
    // Time.Stopwatch.scopeMeasure()

    day6EnsureInstructions()
    var lights: Array'bool
    lights.resize(DAY6_GRID_SIZE * DAY6_GRID_SIZE)
    let lightsBuf = notnull lights.buffer

    for instruction in day6Instructions
    {
        let x0         = cast(u64) instruction.x0
        let y0         = cast(u64) instruction.y0
        let y1         = cast(u64) instruction.y1
        let writeCount = cast(u64) instruction.x1 - x0 + 1

        switch instruction.action
        {
        case .TurnOn:
            for y in y0 to y1
            {
                var scan = lightsBuf + (y * DAY6_GRID_SIZE) + x0
                for writeCount
                {
                    scan[0] = true
                    scan    += 1
                }
            }

        case .TurnOff:
            for y in y0 to y1
            {
                var scan = lightsBuf + (y * DAY6_GRID_SIZE) + x0
                for writeCount
                {
                    scan[0] = false
                    scan    += 1
                }
            }

        case .Toggle:
            for y in y0 to y1
            {
                var scan = lightsBuf + (y * DAY6_GRID_SIZE) + x0
                for writeCount
                {
                    scan[0] = !scan[0]
                    scan    += 1
                }
            }
        }
    }

    var total: u64
    for v in lights do
        total += cast(s32) v

    // Console.print("total: ", total)
    @assert(total == 377891)
}

/////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////
func day6A2()
{
    // Time.Stopwatch.scopeMeasure()

    day6EnsureInstructions()
    var lights: BitArray
    lights.reserve(DAY6_GRID_SIZE * DAY6_GRID_SIZE, false)

    for instruction in day6Instructions
    {
        let x0         = cast(u64) instruction.x0
        let y0         = cast(u64) instruction.y0
        let y1         = cast(u64) instruction.y1
        let writeCount = cast(u64) instruction.x1 - x0 + 1

        switch instruction.action
        {
        case .TurnOn:
            for y in y0 to y1
            {
                var coord = x0 + (y * DAY6_GRID_SIZE)
                for writeCount
                {
                    lights.set(coord, true)
                    coord += 1
                }
            }

        case .TurnOff:
            for y in y0 to y1
            {
                var coord = x0 + (y * DAY6_GRID_SIZE)
                for writeCount
                {
                    lights.set(coord, false)
                    coord += 1
                }
            }

        case .Toggle:
            for y in y0 to y1
            {
                var coord = x0 + (y * DAY6_GRID_SIZE)
                for writeCount
                {
                    lights.invert(coord)
                    coord += 1
                }
            }
        }
    }

    var total: u64
    for v in lights do
        total += cast(s32) v

    // Console.print("total: ", total)
    @assert(total == 377891)
}
