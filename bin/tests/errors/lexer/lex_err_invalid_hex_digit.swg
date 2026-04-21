#global fileprivate

// Non-hex character as the first digit of an \x / \u / \U escape, or right after a hex literal.
'\xG'          // swc-expected-error {{lex_err_invalid_hex_digit}}
"\xG"          // swc-expected-error {{lex_err_invalid_hex_digit}}
"\uG"          // swc-expected-error {{lex_err_invalid_hex_digit}}
0x1G           // swc-expected-error {{lex_err_invalid_hex_digit}}
