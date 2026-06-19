#global fileprivate

// A type position must begin with a valid type starter; keywords like 'enum' and 'interface' are not types.
enum A: enum { Z }                       // swc-expected-error {{parser_err_invalid_type}}
enum B: interface { Z }                  // swc-expected-error {{parser_err_invalid_type}}
enum C: if { Z }                         // swc-expected-error {{parser_err_invalid_type}}
