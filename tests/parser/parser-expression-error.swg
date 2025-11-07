// ============================================================================
// Parser Expressions Error
// ============================================================================

#assert A // swc-expected-error {{parser_err_expected_token}}
// swc-expected-error@+ {{parser_err_expected_closing}}
#assert(A)
#assert(A) #assert(A) // swc-expected-error {{parser_err_expected_eol}}

#assert(A and (B || C)) // swc-expected-error {{parser_err_unexpected_and_or}}
#assert(A && (B and C)) // swc-expected-error {{parser_err_unexpected_and_or}}

#assert(cast #bit #bit (s32) 9) // swc-expected-error {{parser_err_duplicated_modifier}}
#assert(cast #ref1 (s32) 9) // swc-expected-error {{parser_err_invalid_modifier}}
#assert(a + #wrap b)

#assert(a + / b) // swc-expected-error {{parser_err_unexpected_token}}
