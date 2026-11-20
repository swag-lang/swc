#global private

struct CastPointer
{
    pointer: *void
}

func inferredScalar(value: s32)->s64
{
    return cast(value)     // swc-expected-error {{parser_err_cast_requires_target}}
}

func inferredAggregate(value: u32)
{
    let fields = CastPointer{pointer: cast(value)}     // swc-expected-error {{parser_err_cast_requires_target}}
}

func inferredArray(value: u32)
{
    let pointers: [1] *void = [cast(value)]     // swc-expected-error {{parser_err_cast_requires_target}}
}

func inferredWrap(value: u64)->u16
{
    return cast #wrap (value)     // swc-expected-error {{parser_err_cast_requires_target}}
}

func inferredBitPattern(value: u32)->f32
{
    return cast #bit (value)     // swc-expected-error {{parser_err_cast_requires_target}}
}

func inferredUnconst(value: const *u8)->*u8
{
    return cast #unconst (value)     // swc-expected-error {{parser_err_cast_requires_target}}
}

func nestedOperand(value: any)->s32
{
    return assume cast(cast(any, value))     // swc-expected-error {{parser_err_cast_requires_target}}
}
