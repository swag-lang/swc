#global internal

struct S
{
    value: s32
}

#test
{
    const V = #run S{42}
    #assert(#typeof(V) == S)
}

#test
{
    const V = #run unknownSymbol // swc-expected-error {{sema_err_unknown_symbol}}
}
