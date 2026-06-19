#global fileprivate

// Character literals hold exactly one character: raw chars, escapes, or both.
'ab'           // swc-expected-error {{lex_err_too_many_char_char}}
'abc'          // swc-expected-error {{lex_err_too_many_char_char}}
'a\n'          // swc-expected-error {{lex_err_too_many_char_char}}
'\n\t'         // swc-expected-error {{lex_err_too_many_char_char}}
