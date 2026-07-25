#global private

struct Pair
{
    x, y: s32
}

// 'name: Type{...}' was the only declaration form that initialized without '=';
// it is now rejected in favour of the two '=' spellings.
#test
{
    let v: Pair{10, 20}     // swc-expected-error {{parser_err_var_decl_brace_init}}
    @assert(v.x == 10)
}

#test
{
    var v: Pair{10, 20}     // swc-expected-error {{parser_err_var_decl_brace_init}}
    @assert(v.y == 20)
}

#test
{
    const V: Pair{1, 2}     // swc-expected-error {{parser_err_var_decl_brace_init}}
    #assert(V.x == 1)
}

// Named fields are rejected the same way.
#test
{
    let v: Pair{x: 1, y: 2}     // swc-expected-error {{parser_err_var_decl_brace_init}}
    @assert(v.x == 1)
}

// The two supported spellings stay valid.
#test
{
    let a = Pair{10, 20}
    let b: Pair = {10, 20}
    let c: Pair = {x: 10, y: 20}
    @assert(a.x == b.x and b.x == c.x)
    @assert(a.y == b.y and b.y == c.y)
}

// A declaration followed by a scope block is unaffected: the block is separated
// from the type by a blank, so it was never an initializer.
#test
{
    var v: Pair
    {
        v.x = 5
    }

    @assert(v.x == 5)
}
