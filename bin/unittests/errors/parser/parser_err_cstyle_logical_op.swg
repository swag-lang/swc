#global private

// The C-style boolean operators are rejected in favor of the words Swag spells them with.
// A prefix '!' joins them: negation is 'not', which leaves '!' its postfix not-null meaning.
#assert(A and (B || C))                  // swc-expected-error {{parser_err_cstyle_logical_op}}
#assert(A || B)                          // swc-expected-error {{parser_err_cstyle_logical_op}}
#assert(A && B)                          // swc-expected-error {{parser_err_cstyle_logical_op}}
#assert(!A)                              // swc-expected-error {{parser_err_cstyle_logical_op}}
