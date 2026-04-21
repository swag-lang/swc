#global fileprivate

// Any literal followed by a lone "'" is an empty suffix.
enum A { B = 1' }                      // swc-expected-error {{parser_err_empty_literal_suffix}}
enum C { D = 0xFF' }                   // swc-expected-error {{parser_err_empty_literal_suffix}}
const E = 1.5'                         // swc-expected-error {{parser_err_empty_literal_suffix}}
