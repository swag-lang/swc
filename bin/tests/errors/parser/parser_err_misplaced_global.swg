#global fileprivate

// '#global' must appear at the top of the file, before any declarations or 'using' statements.
func before() {}
#global fileprivate                      // swc-expected-error {{parser_err_misplaced_global}}

var x = 1
#global namespace Test                   // swc-expected-error {{parser_err_misplaced_global}}
