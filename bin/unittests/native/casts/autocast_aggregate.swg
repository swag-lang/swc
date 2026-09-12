#global private

struct AggregateCastFields
{
    small: u16
    whole: s32
}

struct AggregateCastBits
{
    number: f32
}

func makeAggregateCastFields(small: u64, fraction: f64)->AggregateCastFields
{
    return AggregateCastFields{small: cast() small, whole: cast() fraction}
}

#test
{
    let fields = makeAggregateCastFields(1234, 19.75)
    Swag.assert(fields.small == 1234)
    Swag.assert(fields.whole == 19)

    var small:    u64 = 5432
    var fraction: f64 = -27.5
    let positional    = AggregateCastFields{cast() small, cast() fraction}
    Swag.assert(positional.small == 5432)
    Swag.assert(positional.whole == -27)
}

#test
{
    const fields = AggregateCastFields{small: cast #wrap () 65537'u64, whole: cast() 3.75}
    Swag.assert(fields.small == 1)
    Swag.assert(fields.whole == 3)
    const bits = AggregateCastBits{number: cast #bit () 0x3F800000'u32}
    Swag.assert(bits.number == 1.0)

    var first:  u64     = 12
    var second: u64     = 34
    let values: [2] u16 = [cast() first, cast() second]
    Swag.assert(values == [12'u16, 34'u16])
    const wrapped: [2] u16 = [cast #wrap () 65537'u64, cast() 2'u64]
    Swag.assert(wrapped == [1'u16, 2'u16])
}

func aggregateCastArgument(value: u16)->u16 => value

#test
{
    Swag.assert(aggregateCastArgument(cast #wrap () 65537'u64) == 1)
}
