enum TOTO: const [..] s32
{
    R = 1
    G = 3
    B = 0
}

enum A : B { B = 0, C = 1, }

enum A : u32 { Z }
enum A : *T { Z }
enum A : **T { Z }

enum A : [*] s32 { Z }
enum A : [..] s32 { Z }
enum A : [?] s32 { Z }
enum A : [5] A { Z }
enum A : [5][10] A { Z }
enum A : [5][10] ****A { Z }
enum A : [5][..] ****A { Z }
enum A : &A { Z }
enum A : &&A { Z }
enum A : *const *A { Z }

enum A : [/* toto */ * ] s32 { Z }

// Valid: pointers + arrays + qualifiers
enum A : *A { Z }
enum A : *const A { Z }
enum A : **A { Z }
enum A : *const *A { Z }
enum A : *[5]A { Z }
enum A : [5]*A { Z }
enum A : [5][10]*const A { Z }
enum A : [/* c */5] A { Z }
enum A : [5] /* c */ [10] A { Z }
enum A : &*A { Z }
enum A : &&*A { Z }
enum A : [5][..] *const *A { Z }
enum A : [*] *A { Z }
enum A : [..] &A { Z }
enum A : [?] &A { Z }

enum A : [* /* stuck */ ] s32 { Z }
enum A : [.. /* stuck */ ] s32 { Z }
enum A : [? /* stuck */ ] s32 { Z }

// Valid: more combos to stress nesting
enum A : [1][2][3] ***A { Z }
enum A : & & A { Z }
enum A : *const [5]A { Z }
enum A : [5]*const *A { Z }

enum AA: const [2, 2] s32 { Z }
enum AA: const [2, 2, 3, 5][1, 2] s32 { Z }

enum A: const const *s32 { Z } // swc-expected-error {{parser_err_duplicate_type_qualifier}}
enum A: #null #null *s32 { Z } // swc-expected-error {{parser_err_duplicate_type_qualifier}}
enum A: const #null *s32 { Z } // swc-expected-error {{parser_err_misplace_type_qualifier}}

enum A : *enum { Z } // swc-expected-error {{parser_err_invalid_type}}

enum A : [? /* toto */ s32 { Z } // swc-expected-error {{parser_err_expected_closing}}
enum A : [* /* toto */ s32 { Z } // swc-expected-error {{parser_err_expected_closing}}
enum A : [.. /* toto */ s32 { Z } // swc-expected-error {{parser_err_expected_closing}}
enum A : [0 /* toto */ s32 { Z } // swc-expected-error {{parser_err_expected_closing}}

// Invalid: missing/invalid type pieces
enum A : enum { Z } // swc-expected-error {{parser_err_invalid_type}}
enum A : [] s32 { Z } // swc-expected-error {{parser_err_expected_array_dim}}
enum A : [5][] A { Z } // swc-expected-error {{parser_err_expected_array_dim}}
enum A : [ /* toto */ ] s32 { Z } // swc-expected-error {{parser_err_expected_array_dim}}

// Invalid: bad bracket/closing handling
enum A : [5 /* toto */
A { Z } // swc-expected-error {{parser_err_expected_closing}}

// Invalid: unexpected tokens after a valid construct
enum A : [5] A ) { Z } // swc-expected-error {{parser_err_expected_token}}
enum A : [*] [] s32 { Z } // swc-expected-error {{parser_err_expected_array_dim}}
enum A : [..] [] s32 { Z } // swc-expected-error {{parser_err_expected_array_dim}}
enum A : [?] [] s32 { Z } // swc-expected-error {{parser_err_expected_array_dim}}

enum A : [ /* open only */ 0 { Z } // swc-expected-error {{parser_err_expected_closing}}

