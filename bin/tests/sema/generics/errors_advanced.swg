#global fileprivate

func(T) identity(value: T)->T => value
func(N: s32) constVal()->s32 => N
func(N: u8) tinyArrayLen(values: [N] s32)->u8 => N
func(T, N: s32) arrayLen(values: [N] T)->s32 => N

struct(T) Box
{
    value: T
}

struct(T, N: s32) Buffer
{
    values: [N] T
}

// Passing a value literal where a type is expected (function)
#test
{
    identity'(42)(1) // swc-expected-error {{sema_err_not_type}}
}

// Passing a value literal where a type is expected (struct)
#test
{
    var b: Box'42 // swc-expected-error {{sema_err_not_type}}
}

// Passing a non-const variable as const param
#test
{
    var n = 3
    constVal'(n)() // swc-expected-error {{sema_err_expr_not_const}}
}

// Non-const in struct const param
#test
{
    var n = 4
    var b: Buffer'(s32, n) // swc-expected-error {{sema_err_expr_not_const}}
}

// Non-const in array-generic deduction context
#test
{
    var n = 3
    var b: [n] s32 // swc-expected-error {{sema_err_expr_not_const}}
}

// Passing a literal where type expected in multi-param generic
#test
{
    arrayLen'(10, 2)([1, 2]) // swc-expected-error {{sema_err_not_type}}
}

// Deduction must report a regular cast failure instead of asserting when the const arg overflows.
#test
{
    var values: [256] s32
    tinyArrayLen(values) // swc-expected-error {{sema_err_literal_overflow}}
}
