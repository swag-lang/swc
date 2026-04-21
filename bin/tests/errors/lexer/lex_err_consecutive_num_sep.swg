#global fileprivate

// Consecutive '_' separators are forbidden in every numeric-literal shape.
// The fraction/exponent variants need a digit before the run so the leading-sep check does not pre-empt us.
0b__0          // swc-expected-error {{lex_err_consecutive_num_sep}}
0x__F          // swc-expected-error {{lex_err_consecutive_num_sep}}
1__5           // swc-expected-error {{lex_err_consecutive_num_sep}}
1.5__6         // swc-expected-error {{lex_err_consecutive_num_sep}}
1e5__6         // swc-expected-error {{lex_err_consecutive_num_sep}}
