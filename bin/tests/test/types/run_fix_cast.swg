// swc-option suite-test

#global fileprivate

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
    let refValue = cast(const &CastTriple) x[0]
    var copyValue = cast(CastTriple) x[0]
    copyValue.x = 100
    @assert(refValue.x == 456)
    @assert(copyValue.x == 100)
    @assert(copyValue.y == 456)
    @assert(copyValue.z == 456)
}

#test
{
    var value: CastTriple
    castVariadicValue(value)
}

#test
{
    var value: CastWide
    var boxed: any = value
    let copyValue = cast(CastWide) boxed
    @assert(copyValue.value == 456)
    @assert(copyValue.value4 == 456)
}

#test
{
    var value: CastTriple
    var boxed: any = value
    var copyValue = cast(CastTriple) boxed
    let refValue = cast(const &CastTriple) boxed
    copyValue.y = 99
    @assert(copyValue.x == 456)
    @assert(copyValue.y == 99)
    @assert(copyValue.z == 456)
    @assert(refValue.x == 456)
    @assert(refValue.y == 456)
    @assert(refValue.z == 456)
}
