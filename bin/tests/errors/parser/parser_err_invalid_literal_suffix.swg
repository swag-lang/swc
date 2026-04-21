#global fileprivate

// Literal suffixes must be scalar numeric types, 'bool', or 'rune'.
enum A { B = 1'any }                     // swc-expected-error {{parser_err_invalid_literal_suffix}}
enum C { D = 1'string }                  // swc-expected-error {{parser_err_invalid_literal_suffix}}
enum E { F = 1'void }                    // swc-expected-error {{parser_err_invalid_literal_suffix}}
