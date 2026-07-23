#global private

struct(T) RequiresBool where 1
{
    value: T
}

#test
{
    var value: RequiresBool's32     // swc-expected-error {{sema_err_generic_struct_where_not_bool}}
    @print(value)
}
