func toto()
{
    foreach & in A {} // swc-expected-error {{parser_err_expected_token_fam_before}}
    foreach a, in A {} // swc-expected-error {{parser_err_expected_token_fam_before}}
    foreach a, b A {} // swc-expected-error {{parser_err_expected_token_before}}
}