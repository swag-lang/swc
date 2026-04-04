#global fileprivate

enum A { B = 1' } // swc-expected-error {{parser_err_empty_literal_suffix}}
