#global private

// A label only one jump reaches reads memory as that jump left it, so the arm a
// test skips to reuses the element the test loaded. A store or a call on the
// way must still force the read again.

#[Swag.Optimize(true), Swag.NoInline]
func maxAbsIndex(a: const [*] s32, n: u64)->u64
{
    var best    = 0'u64
    var bestVal = 0's32
    for i in n
    {
        let v = a[i] < 0 ? -a[i] : a[i]
        if v > bestVal
        {
            bestVal = v
            best    = i
        }
    }

    return best
}

#[Swag.Optimize(true), Swag.NoInline]
func bumpThenRead(p: [*] s32)->s32
{
    let v = p[0]
    p[0] = v + 1
    if v < 0 do
        return -p[0]
    return p[0]
}

#[Swag.NoInline]
func clobber(p: [*] s32)
{
    p[0] = 100
}

#[Swag.Optimize(true), Swag.NoInline]
func readAcrossCall(p: [*] s32, c: bool)->s32
{
    if p[0] > 0
    {
        clobber(p)
        if c do
            return p[0] + 1
        return p[0]
    }

    return p[0]
}

#[Swag.Optimize(true), Swag.NoInline]
func armStore(p: [*] s32, c: bool)->s32
{
    let v = p[0]
    if c
    {
        p[0] = v * 2
        return p[0] + v
    }

    return p[0] - v
}

#test
{
    var values: [6] s32 = [3, -9, 4, 8, -2, 9]
    Swag.assert(maxAbsIndex(&values[0], 6) == 1)
    Swag.assert(maxAbsIndex(&values[0], 1) == 0)
    Swag.assert(maxAbsIndex(&values[0], 0) == 0)

    var cell: [1] s32 = [5]
    Swag.assert(bumpThenRead(&cell[0]) == 6)
    cell[0] = -5
    Swag.assert(bumpThenRead(&cell[0]) == 4)

    cell[0] = 5
    Swag.assert(readAcrossCall(&cell[0], true) == 101)
    cell[0] = 5
    Swag.assert(readAcrossCall(&cell[0], false) == 100)
    cell[0] = -5
    Swag.assert(readAcrossCall(&cell[0], true) == -5)

    cell[0] = 7
    Swag.assert(armStore(&cell[0], true) == 21)
    cell[0] = 7
    Swag.assert(armStore(&cell[0], false) == 0)
}
