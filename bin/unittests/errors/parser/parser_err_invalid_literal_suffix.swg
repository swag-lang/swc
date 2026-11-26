#global private

// Literal suffixes must be scalar numeric types, 'bool', or '_rune'.
enum A { B = 1_any }                     // swc-expected-error {{parser_err_invalid_literal_suffix}}
enum C { D = 1_string }                  // swc-expected-error {{parser_err_invalid_literal_suffix}}
enum E { F = 1_void }                    // swc-expected-error {{parser_err_invalid_literal_suffix}}
