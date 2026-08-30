#global private

// Inside an intrinsic argument list, a missing ',' between arguments is reported.
func bad()
{
    Swag.print(1 2)                   // swc-expected-error {{parser_err_expected_token}}
    Swag.assert(true false)           // swc-expected-error {{parser_err_expected_token}}
}
