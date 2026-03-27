#global fileprivate

func(T) identity(value: T)->T => value

struct(T) Box
{
    value: T
}

#test
{
    identity'(10)(1) // swc-expected-error {{sema_err_not_type}}
}

#test
{
    var bad: Box'10 // swc-expected-error {{sema_err_not_type}}
}
