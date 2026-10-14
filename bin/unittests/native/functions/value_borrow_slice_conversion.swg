#global private

#[Swag.Inline]
func first(values: const [..] s32)->s32 => values[0]

#[Swag.Inline]
func matches(values: *[3] s32, expected: const [..] s32)->bool
{
    if expected.count != 3 do
        return false
    for value, index in values[]
    {
        if value != expected[index] do
            return false
    }
    return true
}

// The borrowed address must name a slice descriptor, not the literal's element storage.
#test
{
    let observed = first([1, 2, 3])
    Swag.assert(observed == 1)
}

#test
{
    var values   = [1, 2, 3]
    let observed = matches(&values, [1, 2, 3])
    Swag.assert(observed)
}

// Element conversion must also survive the detached inline initializer.
#test
{
    let observed = first([1'u8, 2'u8, 3'u8])
    Swag.assert(observed == 1)
}

#test
{
    var head     = 7
    let observed = first([head, 2, 3])
    Swag.assert(observed == 7)
}
