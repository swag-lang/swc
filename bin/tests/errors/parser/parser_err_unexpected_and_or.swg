#global fileprivate

// Both C-style boolean operators '&&' and '||' are rejected in favor of 'and' / 'or'.
#assert(A and (B || C))                  // swc-expected-error {{parser_err_unexpected_and_or}}
#assert(A || B)                          // swc-expected-error {{parser_err_unexpected_and_or}}
#assert(A && B)                          // swc-expected-error {{parser_err_unexpected_and_or}}
