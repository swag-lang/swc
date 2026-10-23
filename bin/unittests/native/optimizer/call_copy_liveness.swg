#global private

struct Trace
{
    checksum: s64
    calls:    u64
}

#[Swag.NoInline]
func record(trace: *Trace, current, next: s64)
{
    trace.checksum ^= current * 3 + next * 5
    trace.calls    += 1
}

#[Swag.Optimize(true), Swag.NoInline]
func advance(trace: *Trace, seed, steps: s64)->s64
{
    var current = seed
    for i in 0 until steps
    {
        let next = current + i + 3
        record(trace, current, next)
        current = next
    }
    return current
}

#test
{
    for seed in -16's64 to 16
    {
        for steps in 0's64 to 64
        {
            var expected = Trace{}
            var current  = seed
            for i in 0 until steps
            {
                let next = current + i + 3
                expected.checksum ^= current * 3 + next * 5
                current = next
            }
            var actual = Trace{}
            let result = advance(&actual, seed, steps)
            Swag.assert(result == seed + steps * (steps - 1) / 2 + 3 * steps)
            Swag.assert(actual.checksum == expected.checksum)
            Swag.assert(actual.calls == cast(u64, steps))
        }
    }
}
