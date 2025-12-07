#assert((A))
#assert((A and B))
#assert(A and B or C)
#assert(A and (B or C))

#assert(A + 5)
#assert(A + 5 > 5 and true)
#assert((A or B) and C)
#assert(A == B)
#assert(A != B and C)
#assert(A < B or B < C)
#assert(A <= B and B <= C)
#assert(A + B * C)
#assert((A + B) * C)
#assert(A / (B - C))
#assert((A + 5) * (B - 3) > 0)

#assert(A == [5])
#assert(A == [5, 4+A])

#assert A // swc-expected-error {{parser_err_expected_token}}
#assert(A)
#assert(A) #assert(A) // swc-expected-error {{parser_err_expected_sep_stmt}}

#assert(A and (B || C)) // swc-expected-error {{parser_err_unexpected_and_or}}
#assert(A && (B and C)) // swc-expected-error {{parser_err_unexpected_and_or}}

#assert(cast #bit #bit (s32) 9) // swc-expected-error {{parser_err_duplicated_modifier}}
#assert(a + #wrap b)

#assert(a + / b) // swc-expected-error {{parser_err_unexpected_token}}

#assert(!!a) // swc-expected-error {{parser_err_unexpected_token}}
#assert(!!!a) // swc-expected-error {{parser_err_unexpected_token}}
#assert(--a) // swc-expected-error {{parser_err_unexpected_token}}
#assert(-+a) // swc-expected-error {{parser_err_unexpected_token}}
#assert(!-a) // swc-expected-error {{parser_err_unexpected_token}}