#global fileprivate

// A type/family was expected immediately before a following token.
enum {}                                   // swc-expected-error {{parser_err_expected_token_fam_before}}
struct {}                                 // swc-expected-error {{parser_err_expected_token_fam_before}}
