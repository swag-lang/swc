// 

#global private

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

#[Swag.Strict]
alias StrictDefaultKind  = DefaultKind

#[Swag.Strict]
alias StrictDefaultFloat = f32

func assertDefaultVoid(a: s32 = 6)
{
    Swag.assert(a == 6)
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

func pointerDefaultIsNull(ptr: #null *s32 = null)->bool
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

func strictEnumDefault(kind: StrictDefaultKind = cast(StrictDefaultKind) DefaultKind.B)->s32
{
    if kind == cast(StrictDefaultKind) DefaultKind.A do
        return 10
    if kind == cast(StrictDefaultKind) DefaultKind.B do
        return 20
    return 30
}

func strictFloatDefault(value: StrictDefaultFloat = cast(StrictDefaultFloat) 1.25)->bool
{
    return value == cast(StrictDefaultFloat) 1.25
}

func vecDefaultSum(v: DefaultVec = {x: 10, y: 20})->s32
{
    return v.x + v.y
}

func arrayDefaultSum(values: [3] s32 = [1, 2, 3])->s32
{
    return values[0] + values[1] + values[2]
}

#test
{
    callDefaultsManyTimes()
    callDefaultsManyTimes()

    Swag.assert(addDefault(1) == 12)
    Swag.assert(addDefault(1, 2) == 9)
    Swag.assert(addDefault(1, 2, 3) == 6)
    Swag.assert(addDefault(c: 3, a: 1) == 9)
    Swag.assert(addDefault(a: 1, c: 3) == 9)
    Swag.assert(addDefault(a: 1, b: 2, c: 3) == 6)
    Swag.assert(defaultCounter == 30)
}

#test
{
    Swag.assert(boolDefault() == 7)
    Swag.assert(boolDefault(false) == 3)
    Swag.assert(boolDefault(flag: true) == 7)

    Swag.assert(floatDefault() == 3.5)
    Swag.assert(floatDefault(3.0) == 5.0)
    Swag.assert(floatDefault(b: 4.5, a: 0.5) == 5.0)
}

#test
{
    Swag.assert(stringDefaultTag() == 1)
    Swag.assert(stringDefaultTag("hello") == 2)
    Swag.assert(pointerDefaultIsNull())

    Swag.assert(pointerDefaultIsNull())
    var local: s32 = 10
    Swag.assert(!pointerDefaultIsNull(&local))
    Swag.assert(pointerDefaultIsNull(ptr: null))
}

#test
{
    Swag.assert(enumDefault() == 20)
    Swag.assert(enumDefault(DefaultKind.A) == 10)
    Swag.assert(enumDefault(kind: DefaultKind.C) == 30)
    Swag.assert(strictEnumDefault() == 20)
    Swag.assert(strictEnumDefault(cast(StrictDefaultKind) DefaultKind.A) == 10)
    Swag.assert(strictFloatDefault())

    Swag.assert(vecDefaultSum() == 30)
    Swag.assert(vecDefaultSum({x: 3, y: 4}) == 7)
    Swag.assert(vecDefaultSum(v: {x: -1, y: 8}) == 7)
}

#test
{
    Swag.assert(arrayDefaultSum() == 6)
    Swag.assert(arrayDefaultSum([5, 6, 7]) == 18)
    Swag.assert(arrayDefaultSum(values: [9, 0, 1]) == 10)
}
