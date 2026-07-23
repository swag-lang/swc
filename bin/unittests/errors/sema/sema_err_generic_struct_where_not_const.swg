#global private

var RuntimeConstraint: bool

struct(T) RequiresConstant where RuntimeConstraint
{
    value: T
}

#test
{
    var value: RequiresConstant's32 // swc-expected-error {{sema_err_generic_struct_where_not_const}}
    @print(value)
}
