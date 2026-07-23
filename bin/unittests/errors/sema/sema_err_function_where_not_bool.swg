#global private

func(T) requiresBool(value: T)->T where 1
{
    return value
}

#test
{
    requiresBool(1) // swc-expected-error {{sema_err_function_where_not_bool}}
}
