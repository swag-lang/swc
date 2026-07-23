#global private

struct(T) RequiresText where T == string
{
    value: T
}

#test
{
    var value: RequiresText's32     // swc-expected-error {{sema_err_generic_struct_where_failed}}
    @print(value)
}
