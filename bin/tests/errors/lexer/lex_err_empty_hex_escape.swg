#global fileprivate

// '\x', '\u', '\U' must be followed by hex digits, in every containing literal.
'\x'           // swc-expected-error {{lex_err_empty_hex_escape}}
"\x"           // swc-expected-error {{lex_err_empty_hex_escape}}
"\u"           // swc-expected-error {{lex_err_empty_hex_escape}}
"\U"           // swc-expected-error {{lex_err_empty_hex_escape}}
