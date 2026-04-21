#global fileprivate

// '0x' and '0X' require at least one hex digit, even when a separator follows.
0x             // swc-expected-error {{lex_err_missing_hex_digit}}
0X             // swc-expected-error {{lex_err_missing_hex_digit}}
0x_            // swc-expected-error {{lex_err_missing_hex_digit}}
