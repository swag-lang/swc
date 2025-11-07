// ============================================================================
// Parser Types Error
// ============================================================================

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
