#global fileprivate

// A '_' must sit between digits; it cannot lead the fractional or exponent part.
123._456       // swc-expected-error {{lex_err_leading_num_sep}}
1e_5           // swc-expected-error {{lex_err_leading_num_sep}}
1e+_5          // swc-expected-error {{lex_err_leading_num_sep}}
