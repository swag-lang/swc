#global fileprivate

struct(T) List
{
    value: T
}

#test
{
    var a5 = 0
    var b5 = a5[0] // swc-expected-error {{sema_err_type_not_indexable}}
}

#test
{
    var a1 = 0
    var b1 = a1[0] // swc-expected-error {{sema_err_type_not_indexable}}
}

#test
{
    var list: List'(s32)
    var item = list[0] // swc-expected-error {{sema_err_type_not_indexable}}
}
