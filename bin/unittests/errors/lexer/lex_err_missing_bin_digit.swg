#global fileprivate

// '0b' and '0B' require at least one digit, even when a separator follows.
0b             // swc-expected-error {{lex_err_missing_bin_digit}}
0B             // swc-expected-error {{lex_err_missing_bin_digit}}
0b_            // swc-expected-error {{lex_err_missing_bin_digit}}
