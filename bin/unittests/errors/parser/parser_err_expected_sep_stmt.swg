#global fileprivate

// Two statements on the same line must be separated by ';'.
#assert(true) #assert(true)                    // swc-expected-error {{parser_err_expected_sep_stmt}}
#assert(true) #assert(false) #assert(true)     // swc-expected-error@* {{parser_err_expected_sep_stmt}}

func bad()
{
    var a = 1 var b = 2                        // swc-expected-error {{parser_err_expected_sep_stmt}}
}
