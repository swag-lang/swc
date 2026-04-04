#global fileprivate

enum A { B = 1'any } // swc-expected-error {{parser_err_invalid_literal_suffix}}
