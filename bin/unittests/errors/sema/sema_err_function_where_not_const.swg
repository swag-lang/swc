#global private

var RuntimeConstraint: bool

func(T) requiresConstant(value: T)->T where RuntimeConstraint
{
    return value
}

#test
{
    requiresConstant(1)     // swc-expected-error {{sema_err_function_where_not_const}}
}
