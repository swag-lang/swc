#global fileprivate

// Inside an intrinsic argument list, a missing ',' between arguments is reported.
func bad()
{
    @print(1 2)                   // swc-expected-error {{parser_err_expected_token}}
    @assert(true false)           // swc-expected-error {{parser_err_expected_token}}
}
