#global fileprivate

func(var T) genericPair(value: T, other: T) {}

#test
{
    genericPair(1, true) // swc-expected-error {{sema_err_generic_type_deduction_conflict}}
}
