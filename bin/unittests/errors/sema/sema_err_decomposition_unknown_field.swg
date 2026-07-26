#global private

struct Pair
{
    x, y: s32
}

#test
{
    let {z: value} = Pair{1, 2}     // swc-expected-error {{sema_err_decomposition_unknown_field}}
}

#test
{
    var value: s32
    {z: value} = Pair{1, 2}     // swc-expected-error {{sema_err_decomposition_unknown_field}}
}

// Implicit 'itemN' names only address fields that have no explicit name.
#test
{
    let value = {x: 1, 2}
    let {item0: first} = value     // swc-expected-error {{sema_err_decomposition_unknown_field}}
}

#test
{
    let value = {1, y: 2}
    let {item1: second} = value     // swc-expected-error {{sema_err_decomposition_unknown_field}}
}
