#global fileprivate

// Letters and decimal digits 2-9 are both rejected after a binary literal.
0b01G          // swc-expected-error {{lex_err_invalid_bin_digit}}
0b01a          // swc-expected-error {{lex_err_invalid_bin_digit}}
0b012          // swc-expected-error {{lex_err_invalid_bin_digit}}
0B019          // swc-expected-error {{lex_err_invalid_bin_digit}}
