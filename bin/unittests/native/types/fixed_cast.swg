// 

#global private

struct CastTriple
{
    x, y, z: s64 = 456
}

struct CastWide
{
    value:  s64 = 456
    value1: s64 = 456
    value2: s64 = 456
    value3: s64 = 456
    value4: s64 = 456
}

func castVariadicValue(x: ...)
{
    let refValue  = cast(const *CastTriple) x[0]
    var copyValue = cast(CastTriple) x[0]
    copyValue.x = 100
    Swag.assert(refValue.x == 456)
    Swag.assert(copyValue.x == 100)
    Swag.assert(copyValue.y == 456)
    Swag.assert(copyValue.z == 456)
}

#test
{
    var value: CastTriple
    castVariadicValue(value)
    Swag.assert(value.x == 456)
}

#test
{
    var value: CastWide
    var boxed: any = value
    let copyValue  = cast(CastWide) boxed
    Swag.assert(copyValue.value == 456)
    Swag.assert(copyValue.value4 == 456)
}

#test
{
    var value: CastTriple
    var boxed: any = value
    var copyValue  = cast(CastTriple) boxed
    let refValue   = cast(const *CastTriple) boxed
    copyValue.y = 99
    Swag.assert(copyValue.x == 456)
    Swag.assert(copyValue.y == 99)
    Swag.assert(copyValue.z == 456)
    Swag.assert(refValue.x == 456)
    Swag.assert(refValue.y == 456)
    Swag.assert(refValue.z == 456)
}
