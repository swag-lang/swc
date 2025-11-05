// ============================================================================
// Parser Attributes Error
// ============================================================================

#[] // swc-expected-error {{parser_err_empty_attribute}}
enum B {}

#[ // swc-expected-error {{parser_err_empty_attribute}}
/* toto */
]
enum B {}

#[A(] // swc-expected-error {{parser_err_unexpected_token}} {{parser_err_expected_closing}}
enum B {}

#[A // swc-expected-error {{parser_err_expected_closing}}
enum B {} // swc-expected-error {{parser_err_expected_token_before}}