#global fileprivate

// Any identifier glued to a numeric literal is reported as an unexpected suffix.
123abc         // swc-expected-error {{lex_err_invalid_number_suffix}}
1.5xyz         // swc-expected-error {{lex_err_invalid_number_suffix}}
1e5abc         // swc-expected-error {{lex_err_invalid_number_suffix}}
