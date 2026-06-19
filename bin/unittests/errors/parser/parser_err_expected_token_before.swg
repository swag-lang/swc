#global fileprivate

// Missing specific token where the parser expected one before the next token.
#[A B]                            // swc-expected-error {{parser_err_expected_token_before}}

// '#assert' expects '(' directly after it.
#assert A                         // swc-expected-error {{parser_err_expected_token_before}}
