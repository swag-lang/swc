#global fileprivate

// A trailing '_' is rejected in every part of every numeric literal.
0b0_           // swc-expected-error {{lex_err_trailing_num_sep}}
0x1_           // swc-expected-error {{lex_err_trailing_num_sep}}
123_           // swc-expected-error {{lex_err_trailing_num_sep}}
1.5_           // swc-expected-error {{lex_err_trailing_num_sep}}
1.5e2_         // swc-expected-error {{lex_err_trailing_num_sep}}
