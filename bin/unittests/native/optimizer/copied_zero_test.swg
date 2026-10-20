#global private

#[Swag.NoInline]
func samePrefix(left, right: [*] u8, count: u64, initial: bool)->bool
{
    var same = initial
    var i    = 0'u64
    while same and i < count
    {
        if left[i] != right[i] do
            same = false
        i += 1
    }
    return same
}

#[Swag.NoInline, Swag.Optimize(false)]
func referencePrefix(left, right: [*] u8, count: u64, initial: bool)->bool
{
    var same = initial
    var i    = 0'u64
    while same and i < count
    {
        if left[i] != right[i] do
            same = false
        i += 1
    }
    return same
}

#test
{
    for initial in [false, true]
    {
        for count in 0'u64 until 34
        {
            for mismatch in -1 until 33
            {
                var left, right: [33] u8
                for i in 33
                {
                    left[i]  = cast(u8, i + 1)
                    right[i] = left[i]
                }
                if mismatch >= 0 do
                    right[mismatch] = 0

                let actual   = samePrefix(&left[0], &right[0], count, initial)
                let expected = referencePrefix(&left[0], &right[0], count, initial)
                Swag.assert(actual == expected)
            }
        }
    }
}
