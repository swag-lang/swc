#global fileprivate

// A character literal must close before the line ends (or the file ends).
// swc-expected-error@+ {{lex_err_unclosed_char}}
'a
// swc-expected-error@+ {{lex_err_unclosed_char}}
'\n
// swc-expected-error@+ {{lex_err_unclosed_char}}
'
