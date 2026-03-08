#global fileprivate

var defaultCounter: s32 = 0

func assertDefaultVoid(a: s32 = 6)
{
    @assert(a == 6)
}

func addDefault(a: s32, b: s32 = 5, c: s32 = 6)->s32
{
    return a + b + c
}

func bumpDefault(v: s32 = 3)
{
    defaultCounter += v
}

func callDefaultsManyTimes()
{
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()
    assertDefaultVoid()

    bumpDefault()
    bumpDefault()
    bumpDefault()
    bumpDefault()
    bumpDefault()
    bumpDefault()
    bumpDefault()
    bumpDefault()
    bumpDefault()
    bumpDefault()
}

#run
{
    callDefaultsManyTimes()
    callDefaultsManyTimes()

    @assert(addDefault(1) == 12)
    @assert(addDefault(1, 2) == 9)
    @assert(addDefault(1, 2, 3) == 6)
    @assert(addDefault(c: 3, a: 1) == 9)
    @assert(addDefault(a: 1, c: 3) == 9)
    @assert(addDefault(a: 1, b: 2, c: 3) == 6)

    @assert(defaultCounter == 60)
}
