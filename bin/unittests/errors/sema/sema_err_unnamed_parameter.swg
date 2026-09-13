#global private

func(T) pair(first: T, second: T)->T => first + second
#test { var r = pair(first: 1's32, 2) }     // swc-expected-error {{sema_err_unnamed_parameter}}

func Sum3(a: s32, b: s32, c: s32)->s32
{
    return a + b + c
}

#test { var R = Sum3(b: 2, 1) }     // swc-expected-error {{sema_err_unnamed_parameter}}
