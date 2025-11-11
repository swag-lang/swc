#[] // swc-expected-error {{parser_err_empty_attribute}}
enum B { Z }

#[ // swc-expected-error {{parser_err_empty_attribute}}
/* toto */
]
enum B { Z }

#[A B] // swc-expected-error {{parser_err_missing_attribute_sep}}
enum B { Z }

#[A(] // swc-expected-error {{parser_err_unexpected_token}} {{parser_err_expected_closing}}
enum B { Z }

#[A // swc-expected-error {{parser_err_expected_closing}}
enum B { Z } // swc-expected-error {{parser_err_expected_token_before}}

