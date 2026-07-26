#global private

struct Pair
{
    x, y: s32
}

#test
{
    let {x: first, x: second} = Pair{1, 2}     // swc-expected-error {{sema_err_decomposition_duplicate_field}}
}

#test
{
    var first, second: s32
    {y: first, y: second} = Pair{1, 2}     // swc-expected-error {{sema_err_decomposition_duplicate_field}}
}
