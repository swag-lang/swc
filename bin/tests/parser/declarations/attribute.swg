#[A]
enum B { Z }

#[A()]
enum B { Z }

#[A, B, A.C()]
enum B { Z }

#[A, B, A.C("0", 1, 2, 3)]
#[A, B, A.C("0", 1, 2, 3)]
#[A, B, A.C("0", 1, 2, 3)]
enum B { Z }

#[]
enum B { Z }

#[
/* toto */
]
enum B { Z }

#[A B] // swc-expected-error {{parser_err_expected_token_before}}
enum B { Z }

#[A(] // swc-expected-error {{parser_err_unexpected_token}} {{parser_err_expected_closing}}
enum B { Z }

#[A // swc-expected-error {{parser_err_expected_closing}}
enum B { Z } // swc-expected-error {{parser_err_expected_token_before}}

