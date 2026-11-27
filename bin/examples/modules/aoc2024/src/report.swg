using Core

func isReportSafe(levels: const [..] s32, skipIndex: u64 = Swag.U64.Max)->bool
{
    var previous    = 0, direction = 0
    var hasPrevious = false

    for level, index in levels
    {
        if index == skipIndex
        {
            continue
        }

        if hasPrevious
        {
            let diff = level - previous
            if Swag.abs(diff) < 1 or Swag.abs(diff) > 3
            {
                return false
            }

            if direction and Math.sign(diff) != direction
            {
                return false
            }

            direction = Math.sign(diff)
        }
        else
        {
            hasPrevious = true
        }

        previous = level
    }

    return true
}
