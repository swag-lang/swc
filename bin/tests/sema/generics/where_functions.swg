#global fileprivate

#[Swag.Overload]
func(T) kind(value: T)->u8
    where T == f32 or T == f64
{
    return 1
}

#[Swag.Overload]
func(T) kind(value: T)->u8
    where T == s32 or T == s64
{
    return 2
}

func(T) onlyFloat(value: T)->T
    where T == f32 or T == f64
{
    return value
}

struct(T) Wrapper
{
    value: T
}

impl Wrapper
{
    func(U) pairValue(const me, other: U)->U
        where T == f32 and U == s32
    {
        return other
    }
}

#test
{
    @assert(kind(1.0'f32) == 1)
    @assert(kind(1's64) == 2)

    let floatBox: Wrapper'f32 = {value: 1.5}

    @assert(floatBox.pairValue's32(99) == 99)
}

#test
{
    onlyFloat(1's32) // swc-expected-error {{sema_err_function_where_failed}}
}

#test
{
    kind(true) // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    let intBox: Wrapper's32 = {value: 7}
    intBox.pairValue's32(99) // swc-expected-error {{sema_err_function_where_failed}}
}
