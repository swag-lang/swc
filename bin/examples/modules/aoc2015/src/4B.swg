/*
--- Part Two ---
Now find one that starts with six zeroes.
*/

using Core

internal var best: u64 = Swag.U64.Max

func day4B()
{
    #static if #cfg == "release"
    {
        if Swag.jit() do
            return

        // Time.Stopwatch.scopeMeasure()
        // One lane per worker, each striding by the lane count so the whole search space is
        // covered exactly once. A lane stops as soon as another one has published a lower hit.
        let lanes = Math.max(1'u64, cast(u64) Swag.workerCount())

        var results: Array'u64
        results.resize(lanes)
        for &r in results do
            r[] = Swag.U64.Max

        parallel for |&results, lanes| lane in lanes
        {
            var index = lane
            var buffer: [16] u8
            day4InitBuffer(buffer)

            for
            {
                if Atomic.get(&best) < index do
                    break

                let v = Hash.Md5.compute(day4BuildInput(buffer, index))
                if v[0] == 0 and v[1] == 0 and v[2] == 0
                {
                    discard Atomic.exchange(&best, index)
                    results[lane] = index
                    break
                }

                index += lanes
            }
        }

        var total: u64 = Swag.U64.Max
        for r in results do
            total = Math.min(total, r)

        // Console.print("total: ", total)
        Swag.assert(total == 9962624)
    }
}
