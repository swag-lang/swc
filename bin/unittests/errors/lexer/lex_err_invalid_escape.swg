#global fileprivate

// Invalid escapes in strings and character literals; uppercase letters trigger did-you-mean.
"\c"           // swc-expected-error {{lex_err_invalid_escape}}
'\k'           // swc-expected-error {{lex_err_invalid_escape}}
"\N"           // swc-expected-error {{lex_err_invalid_escape}}
"\T"           // swc-expected-error {{lex_err_invalid_escape}}
