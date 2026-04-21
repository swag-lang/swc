#global fileprivate

// Struct and union field declarations must not use 'var'; the field name and type are enough.
struct A
{
    var a: s32                        // swc-expected-error {{parser_err_var_struct}}
    var b: bool                       // swc-expected-error {{parser_err_var_struct}}
}

union B
{
    var x: s32                        // swc-expected-error {{parser_err_var_struct}}
}
