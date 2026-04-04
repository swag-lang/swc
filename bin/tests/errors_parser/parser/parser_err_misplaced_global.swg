#global fileprivate

func before() {}
#global fileprivate // swc-expected-error {{parser_err_misplaced_global}}
