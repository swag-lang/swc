#global fileprivate
#test
{
    var _ok = 10
    #assert(_ok == 10)
}

#test
{
    var __bad = 10 // swc-expected-error {{lex_err_reserved_identifier}}
}
