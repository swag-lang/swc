#global private

func semaTest001()
{
    var a: any = 12
    var b: s32 = cast() a
    Swag.assert(b == 12)
}

func semaTest002()
{
    func takes(v: s32) {}
    var a: any = 12
    takes(cast() a)
}

func semaTest003()
{
    var a: any = true
    if cast(bool) a {}
}

func semaTest004()
{
    var a: any   = 42
    let refValue = cast(const *s32) a
    let ptrValue = cast(const *s32) a
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

func semaTest005()
{
    var boxed: any = AnyCastDerived{base: {value: 9}, extra: 2}
    let baseRef    = cast(const *AnyCastBase) boxed
    let basePtr    = cast(const *AnyCastBase) boxed
    Swag.assert(baseRef.value == 9)
    Swag.assert(basePtr.value == 9)
}

func semaTest006()
{
    var x: any = 6
    Swag.assert(x == s32)
    Swag.assert(x != bool)

    x = AnyCompareType{}
    Swag.assert(x == AnyCompareType)
}

func acceptNullableStringFromAny(value: #null string)
{
    Swag.assert(value == "desc")
}

func semaTest007()
{
    var value: #null any = "desc"
    acceptNullableStringFromAny(value)
}
