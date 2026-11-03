#global private

#[Swag.Strict]
alias AnyCastStrictAny = any

#test
{
    var a: any = 12
    var b: s32 = assume cast(a)
    Swag.require(b == 12)
}

#test
{
    func takes(_: s32) {}
    var a: any = 12
    Swag.require(assume cast(s32, a) == 12)
}

#test
{
    func takes(_: s32) {}
    var a: any = 12
    var b: s32 = assume cast(a)
    takes(b)
    Swag.require(b == 12)
}

#test
{
    var a: any = true
    var passed = false
    if assume cast(bool, a)
    {
        passed = true
    }
    Swag.require(passed)
}

#test
{
    var a: any   = 42
    let refValue = assume cast(const *s32, a)
    let ptrValue = assume cast(const *s32, a)
    Swag.require(refValue[] == 42)
    Swag.require(ptrValue[] == 42)
}

struct AnyCastBase
{
    value: s32 = 0
}

struct AnyCastDerived
{
    using base: AnyCastBase
    extra:      s32 = 0
}

struct AnyCompareType {}

#test
{
    var boxed: any = AnyCastDerived{base: AnyCastBase{value: 9}, extra: 2}
    let baseRef    = assume cast(const *AnyCastBase, boxed)
    let basePtr    = assume cast(const *AnyCastBase, boxed)
    Swag.require(baseRef.value == 9)
    Swag.require(basePtr.value == 9)
}

#test
{
    var x: any = 6
    Swag.require(x is s32)
    Swag.require(not (x is bool))

    x = "string"
    Swag.require(x is string)
    Swag.require(not (x is s32))

    x = AnyCompareType{}
    Swag.require(x is AnyCompareType)
}

#test
{
    var raw: any = 12
    let boxed    = cast(const *AnyCastStrictAny, (&raw))[]

    Swag.require(assume cast(s32, boxed) == 12)
}

#test
{
    let boxed = cast(AnyCastStrictAny, 21)

    Swag.require(assume cast(s32, boxed) == 21)
}

#test
{
    var raw: any = 42
    let boxed    = cast(const *AnyCastStrictAny, (&raw))[]
    let refValue = assume cast(const *s32, boxed)
    let ptrValue = assume cast(const *s32, boxed)

    Swag.require(refValue[] == 42)
    Swag.require(ptrValue[] == 42)
}

#test
{
    var raw: any = AnyCastDerived{base: AnyCastBase{value: 9}, extra: 2}
    let boxed    = cast(const *AnyCastStrictAny, (&raw))[]
    let baseRef  = assume cast(const *AnyCastBase, boxed)
    let basePtr  = assume cast(const *AnyCastBase, boxed)

    Swag.require(baseRef.value == 9)
    Swag.require(basePtr.value == 9)
}
