#global fileprivate

struct A
{
    var value: s32 // swc-expected-error {{parser_err_var_struct}}
}
