#global private

#[Swag.Strict]
alias AnyCastStrictAny = any

#test
{
    var a: any = 12
    var b: s32 = cast #assume() a
    Swag.assert(b == 12)
}

#test
{
    func takes(v: s32) {}
    var a: any = 12
    Swag.assert(cast #assume(s32) a == 12)
}

#test
{
    func takes(v: s32) {}
    var a: any = 12
    var b: s32 = cast #assume() a
    takes(b)
    Swag.assert(b == 12)
}

#test
{
    var a: any = true
    var passed = false
    if cast #assume(bool) a
    {
        passed = true
    }
    Swag.assert(passed)
}

#test
{
    var a: any   = 42
    let refValue = cast #assume(const *s32) a
    let ptrValue = cast #assume(const *s32) a
    Swag.assert(refValue[] == 42)
    Swag.assert(ptrValue[] == 42)
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
    var boxed: any = AnyCastDerived{base: {value: 9}, extra: 2}
    let baseRef    = cast #assume(const *AnyCastBase) boxed
    let basePtr    = cast #assume(const *AnyCastBase) boxed
    Swag.assert(baseRef.value == 9)
    Swag.assert(basePtr.value == 9)
}

#test
{
    var x: any = 6
    Swag.assert(cast #try (*s32) x != null)
    Swag.assert(cast #try (*bool) x == null)

    x = "string"
    Swag.assert(cast #try (*string) x != null)
    Swag.assert(cast #try (*s32) x == null)

    x = AnyCompareType{}
    Swag.assert(cast #try (*AnyCompareType) x != null)
}

#test
{
    var raw: any = 12
    let boxed    = (cast(const *AnyCastStrictAny) (&raw))[]

    Swag.assert(cast #assume(s32) boxed == 12)
}

#test
{
    let boxed = cast(AnyCastStrictAny) 21

    Swag.assert(cast #assume(s32) boxed == 21)
}

#test
{
    var raw: any = 42
    let boxed    = (cast(const *AnyCastStrictAny) (&raw))[]
    let refValue = cast #assume(const *s32) boxed
    let ptrValue = cast #assume(const *s32) boxed

    Swag.assert(refValue[] == 42)
    Swag.assert(ptrValue[] == 42)
}

#test
{
    var raw: any = AnyCastDerived{base: {value: 9}, extra: 2}
    let boxed    = (cast(const *AnyCastStrictAny) (&raw))[]
    let baseRef  = cast #assume(const *AnyCastBase) boxed
    let basePtr  = cast #assume(const *AnyCastBase) boxed

    Swag.assert(baseRef.value == 9)
    Swag.assert(basePtr.value == 9)
}
