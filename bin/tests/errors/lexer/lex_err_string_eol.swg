#global fileprivate

// A single-line string cannot cross a line boundary; each unterminated line is flagged.
// swc-expected-error@+ {{lex_err_string_eol}}
"abc
// swc-expected-error@+ {{lex_err_string_eol}}
"def with spaces
// swc-expected-error@+ {{lex_err_string_eol}}
"last
