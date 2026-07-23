/*
--- Part Two ---
You just finish implementing your winning light pattern when you realize you mistranslated Santa's message from Ancient Nordic Elvish.

The light grid you bought actually has individual brightness controls; each light can have a brightness of zero or more. The lights all start at zero.

The phrase turn on actually means that you should increase the brightness of those lights by 1.

The phrase turn off actually means that you should decrease the brightness of those lights by 1, to a minimum of zero.

The phrase toggle actually means that you should increase the brightness of those lights by 2.

What is the total brightness of all lights combined after following Santa's instructions?

For example:

turn on 0,0 through 0,0 would increase the total brightness by 1.
toggle 0,0 through 999,999 would increase the total brightness by 2000000.
*/

using Core

func day6B()
{
    // Time.Stopwatch.scopeMeasure()

    day6EnsureInstructions()
    var lights: Array's32
    lights.resize(DAY6_GRID_SIZE * DAY6_GRID_SIZE)

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
                var scan = lights.buffer + (y * DAY6_GRID_SIZE) + x0
                for writeCount
                {
                    scan[0] += 1
                    scan    += 1
                }
            }

        case .TurnOff:
            for y in y0 to y1
            {
                var scan = lights.buffer + (y * DAY6_GRID_SIZE) + x0
                for writeCount
                {
                    if scan[0] do
                        scan[0] -= 1
                    scan        += 1
                }
            }

        case .Toggle:
            for y in y0 to y1
            {
                var scan = lights.buffer + (y * DAY6_GRID_SIZE) + x0
                for writeCount
                {
                    scan[0] += 2
                    scan    += 1
                }
            }
        }
    }

    var total: s64
    for v in lights do
        total += v

    // Console.print("total: ", total)
    @assert(total == 14110788)
}
