#global fileprivate

func(var T) genericPair(value: T, other: T) {}
func(const N: s32) genericArray(values: [N] s32) {}

#test
{
    genericPair(1, true) // swc-expected-error {{sema_err_bad_function_match}}
}

#test
{
    genericArray([1, 2], [3, 4]) // swc-expected-error {{sema_err_bad_function_match}}
}
