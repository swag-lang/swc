#global fileprivate

var defaultCounter: s32 = 0

struct DefaultVec
{
    x: s32
    y: s32
}

enum DefaultKind
{
    A
    B
    C
}

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

    bumpDefault()
    bumpDefault()
    bumpDefault()
    bumpDefault()
    bumpDefault()
}

func boolDefault(flag: bool = true)->s32
{
    if flag do
        return 7

    return 3
}

func floatDefault(a: f64 = 1.5, b: f64 = 2.0)->f64
{
    return a + b
}

func stringDefaultTag(value: string = "abc")->s32
{
    if value == "abc" do
        return 1
    if value == "hello" do
        return 2
    if value == null do
        return 3
    return 0
}

func pointerDefaultIsNull(ptr: *s32 = null)->bool
{
    return ptr == null
}

func enumDefault(kind: DefaultKind = DefaultKind.B)->s32
{
    if kind == DefaultKind.A do
        return 10
    if kind == DefaultKind.B do
        return 20
    return 30
}

func vecDefaultSum(v: DefaultVec = {x: 10, y: 20})->s32
{
    return v.x + v.y
}

func arrayDefaultSum(values: [3] s32 = [1, 2, 3])->s32
{
    return values[0] + values[1] + values[2]
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
    @assert(defaultCounter == 30)
}

#run
{
    @assert(boolDefault() == 7)
    @assert(boolDefault(false) == 3)
    @assert(boolDefault(flag: true) == 7)

    @assert(floatDefault() == 3.5)
    @assert(floatDefault(3.0) == 5.0)
    @assert(floatDefault(b: 4.5, a: 0.5) == 5.0)
}

/*#run
{
    @assert(stringDefaultTag() == 1)
    @assert(stringDefaultTag("hello") == 2)
    @assert(stringDefaultTag(value: null) == 3)

    @assert(pointerDefaultIsNull())
    var local: s32 = 10
    @assert(!pointerDefaultIsNull(&local))
    @assert(pointerDefaultIsNull(ptr: null))
}*/

#run
{
    @assert(enumDefault() == 20)
    @assert(enumDefault(DefaultKind.A) == 10)
    @assert(enumDefault(kind: DefaultKind.C) == 30)

    @assert(vecDefaultSum() == 30)
    @assert(vecDefaultSum({x: 3, y: 4}) == 7)
    @assert(vecDefaultSum(v: {x: -1, y: 8}) == 7)
}

#run
{
    @assert(arrayDefaultSum() == 6)
    @assert(arrayDefaultSum([5, 6, 7]) == 18)
    @assert(arrayDefaultSum(values: [9, 0, 1]) == 10)
}
