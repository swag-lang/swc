#global fileprivate

// In an alias declaration, '=' must be followed by a type or qualified name, not an expression.
alias A = 1 + 2                   // swc-expected-error {{parser_err_expected_type_or_symbol}}
alias B = "hello"                 // swc-expected-error {{parser_err_expected_type_or_symbol}}
alias C = 42                      // swc-expected-error {{parser_err_expected_type_or_symbol}}
