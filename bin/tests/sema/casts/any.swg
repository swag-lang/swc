#global fileprivate

#test
{
    var a: any = 12
    var b: s32 = a // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: any = 12
    var b: s32 = cast() a
    @assert(b == 12)
}

#test
{
    func takes(v: s32) {}
    var a: any = 12
    takes(a) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    func takes(v: s32) {}
    var a: any = 12
    takes(cast() a)
}

#test
{
    var a: any = true
    if a {} // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: any = true
    if cast(bool) a {}
}

#test
{
    var a: any = 42
    let refValue = cast(const &s32) a
    let ptrValue = cast(const *s32) a
    @assert(refValue == 42)
    @assert(dref ptrValue == 42)
}

struct AnyCastBase
{
    value: s32 = 0
}

struct AnyCastDerived
{
    using base: AnyCastBase
    extra: s32 = 0
}

struct AnyCompareType
{
}

#test
{
    var boxed: any = AnyCastDerived{base: {value: 9}, extra: 2}
    let baseRef = cast(const &AnyCastBase) boxed
    let basePtr = cast(const *AnyCastBase) boxed
    @assert(baseRef.value == 9)
    @assert(basePtr.value == 9)
}

#test
{
    var x: any = 6
    @assert(x == s32)
    @assert(x != bool)

    x = AnyCompareType{}
    @assert(x == AnyCompareType)
}
