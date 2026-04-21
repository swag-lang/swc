#global fileprivate

// Fewer hex digits than required by the escape form.
'\x1'          // swc-expected-error {{lex_err_incomplete_hex_escape}}
"\x1"          // swc-expected-error {{lex_err_incomplete_hex_escape}}
"\u12A"        // swc-expected-error {{lex_err_incomplete_hex_escape}}
"\U1234567"    // swc-expected-error {{lex_err_incomplete_hex_escape}}
