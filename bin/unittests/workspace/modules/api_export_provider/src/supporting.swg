#global public

// A published generic body names what the module keeps to itself: the interface carries those
// declarations too, with their own access, so an importer can instantiate the body.

private const SupportScale = 3

private struct DepSupportPair
{
    first:  s32
    second: s32
}

private func depSupportInner(value: s32)->s32 => value * 2
private func depSupportOuter(value: s32)->s32 => depSupportInner(value) + 1

// Scales through two private helpers and a private aggregate.
func(T) depSupportCompute(value: T)->s32
{
    var pair: DepSupportPair
    pair.first  = depSupportOuter(cast(s32, value))
    pair.second = SupportScale
    return pair.first * pair.second
}

struct DepSupportReader
{
    public value: s32
}

impl DepSupportReader
{
    internal mtd bump()
    {
        .value += 1
    }

    // Reads after an internal method the interface publishes beside it.
    mtd(T) read()->T
    {
        .bump()
        return cast(T, .value)
    }
}
