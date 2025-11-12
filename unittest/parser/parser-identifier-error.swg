func toto()
{
    let (a, 0) = titi() // swc-expected-error {{parser_err_expected_token_fam}}
    let (a, ) = titi() // swc-expected-error {{parser_err_expected_token_fam}}
    let (a, b = titi() // swc-expected-error {{parser_err_expected_closing_before}}
    let (a, b) titi() // swc-expected-error {{parser_err_expected_token_before}}
}