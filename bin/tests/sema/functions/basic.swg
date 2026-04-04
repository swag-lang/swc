#global fileprivate

func A() {}
func B(x: s32) {}
func C(x: s32, y: s32) {}
func D(x, y: s32 = 0) {}
struct Point
{
    x: s32
    y: s32
}
struct SingleInt
{
    value: s32
}
struct SingleString
{
    value: string
}
struct RequiredPoint
{
    x: s32 = undefined
    y: s32 = 5
    z: s32 = undefined
}

func D0(me) {}  // swc-expected-error {{sema_err_tok_outside_impl}}
mtd E() {}      // swc-expected-error {{sema_err_method_outside_impl}}

func T()->s32
{
    let a = T()
    return a
}

func T1(a0, b0: s32)->s32
{
    let c = a0
    return c
}

namespace NS {}
#test
{
    NS() // swc-expected-error {{sema_err_not_callable}}
}

#test
{
    F0()
    F1(1)
    F0(1) // swc-expected-error {{sema_err_too_many_arguments}}
}

#test
{
    A()
    B(10)
    C(1, 2)
    D(1)
    D(1, 2)
    F5(1)
    F5(1, 2)
    F6(1)
    F6(1, 2)
}

#test
{
    F1(1.5) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    F5(1, 2, 3) // swc-expected-error {{sema_err_too_many_arguments}}
}

func TakePoint(p: Point) {}
func TakeSingleString(v: SingleString) {}
func TakeRequiredPoint(v: RequiredPoint) {}
func TakeArray2(v: [2] s32) {}
func TakeMatrix2(v: [2, 2] s32) {}
func TakeArrayU32(v: [2] u32) {}
func TakeByteU8(v: u8) {}

#test
{
    TakePoint({x: 1, x: 2, y: 3}) // swc-expected-error {{sema_err_struct_cast_duplicate_field}}
}

#test
{
    const src: SingleInt = {1}
    TakeSingleString(src) // swc-expected-error {{sema_err_struct_cast_field_type}}
}

#test
{
    TakeRequiredPoint({x: 1}) // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    const values: [3] s32 = [1, 2, 3]
    TakeArray2(values) // swc-expected-error {{sema_err_array_cast_dim_mismatch}}
}

#test
{
    TakeMatrix2([[1, 2], [3, 4, 5]]) // swc-expected-error {{sema_err_array_cast_too_many_values}}
}

#test
{
    const values: [4] s32 = [1, 2, 3, 4]
    TakeMatrix2(values) // swc-expected-error {{sema_err_array_cast_num_dims}}
}

#test
{
    var values: [2] s32 = [1, 2]
    TakeArrayU32(values) // swc-expected-error {{sema_err_array_cast_requires_const_folding}}
}

#test
{
    const values: [2] s32 = [1, 2]
    TakeArrayU32(values) // swc-expected-error {{sema_err_array_cast_expected_aggregate_constant}}
}

#test
{
    TakeByteU8(300) // swc-expected-error {{sema_err_literal_overflow}}
}

#test
{
    TakeByteU8(-1) // swc-expected-error {{sema_err_signed_unsigned}}
}

func F0() {}
func F1(x: s32) {}

// swc-expected-error@(+1,+2) {{sema_err_already_defined}}
func F2(a, b, c: s32) {}
func F2(x, y, z: s32) {}

func F4(a: s32 = 0, b: s32) {} // swc-expected-error {{sema_err_parameter_default_value_not_last}}

func F5(a: s32, b: s32 = 0) {}
func F6(a, b: s32 = 0) {}
