#global internal

const A = 0

#test
{
    const L = #location(A)
    #assert(L.fileName != null)
    #assert(L.lineStart == 3)
}

#test
{
    const L = #location(1 + 2) // swc-expected-error {{sema_err_invalid_location}}
}

#test
{
    const L = #location(Unknown) // swc-expected-error {{sema_err_unknown_symbol}}
}
