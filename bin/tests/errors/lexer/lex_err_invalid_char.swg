#global fileprivate

// Non-ASCII and stray ASCII symbols fall through to the invalid-char diagnostic.
¤              // swc-expected-error {{lex_err_invalid_char}}
€              // swc-expected-error {{lex_err_invalid_char}}
$              // swc-expected-error {{lex_err_invalid_char}}
