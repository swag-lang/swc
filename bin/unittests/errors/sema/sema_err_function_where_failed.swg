#global private

func(T) requiresText(value: T)->T where T == string
{
    return value
}

#test
{
    requiresText(1)     // swc-expected-error {{sema_err_function_where_failed}}
}
