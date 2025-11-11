func toto()
{
    let (a, 0) = titi() // swc-expected-error {{parser_err_expected_token_fam}}
    let (a, ) = titi() // swc-expected-error {{parser_err_expected_token_fam}}
    let (a, b = titi() // swc-expected-error {{parser_err_expected_closing_before}}
    let (a, b) titi() // swc-expected-error {{parser_err_expected_token_before}}
}

var 0 = titi() // swc-expected-error {{parser_err_expected_token_fam}}
var A, = 0 // swc-expected-error {{parser_err_expected_token_fam_before}}
const B 0 // swc-expected-error {{parser_err_empty_var_decl}} {{parser_err_unexpected_token}}
