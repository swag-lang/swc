#assert A // swc-expected-error {{parser_err_expected_token}}
#assert(A)
#assert(A) #assert(A) // swc-expected-error {{parser_err_expected_sep_stmt}}

#assert(A and (B || C)) // swc-expected-error {{parser_err_unexpected_and_or}}
#assert(A && (B and C)) // swc-expected-error {{parser_err_unexpected_and_or}}

#assert(cast #bit #bit (s32) 9) // swc-expected-error {{parser_err_duplicated_modifier}}
#assert(a + #wrap b)

#assert(a + / b) // swc-expected-error {{parser_err_unexpected_token}}
