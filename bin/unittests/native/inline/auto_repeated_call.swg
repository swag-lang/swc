#global private

func repeatedCallRecursive(values: [*] s32, depth: u32)->s32
{
    if depth == 0 do
        return 0
    return repeatedCallChecked(values) + repeatedCallRecursive(values, depth - 1)
}

#[Swag.NoInline]
func repeatedCallLoop(values: [*] s32)->s32
{
    var total = 0
    for index in 4
    {
        let selected: [*] s32? = index == 0 ? null : values
        total += repeatedCallGuarded(selected)
    }
    return total
}

#[Swag.NoInline]
func repeatedCallReturnLoop(values: [*] s32)->s32
{
    var total = 0
    for index in 4
    {
        let selected = repeatedCallOptional(values, cast(s32, index))
        if selected do
            total += selected[0]
    }
    return total
}

#[Swag.NoInline]
func repeatedCallSetup(values: [*] s32)->s32 => repeatedCallCold(values)

#test
{
    var values = [7's32, 11]
    Swag.assert(repeatedCallRecursive(values.buffer, 4) == 28)
    Swag.assert(repeatedCallRecursive(values.buffer, 0) == 0)
    Swag.assert(repeatedCallLoop(values.buffer) == 20)
    Swag.assert(repeatedCallReturnLoop(values.buffer) == 21)
    Swag.assert(repeatedCallSetup(values.buffer) == 7)
}
