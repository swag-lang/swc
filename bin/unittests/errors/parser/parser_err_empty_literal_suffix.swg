#global private

// A literal followed by a lone underscore has an empty suffix.
enum A { B = 1_ }                      // swc-expected-error {{parser_err_empty_literal_suffix}}
enum C { D = 0xFF_ }                   // swc-expected-error {{parser_err_empty_literal_suffix}}
const E = 1.5_                         // swc-expected-error {{parser_err_empty_literal_suffix}}
