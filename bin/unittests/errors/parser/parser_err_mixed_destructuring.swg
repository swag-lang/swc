#global private

struct Pair
{
    x, y: s32
}

// A destructuring pattern chooses one mapping mode for all of its entries.
#test
{
    let {x: first, second} = Pair{1, 2}     // swc-expected-error {{parser_err_mixed_destructuring}}
}

#test
{
    let {first, y: second} = Pair{1, 2}     // swc-expected-error {{parser_err_mixed_destructuring}}
}

#test
{
    var first, second: s32
    {x: first, second} = Pair{1, 2}     // swc-expected-error {{parser_err_mixed_destructuring}}
}

#test
{
    var first, second: s32
    {first, y: second} = Pair{1, 2}     // swc-expected-error {{parser_err_mixed_destructuring}}
}
