#global private

// A tuple pattern cannot select fields by name.
#test
{
    let (x: first, second) = (1, 2) // swc-expected-error {{parser_err_mixed_destructuring}}
}

#test
{
    let (first, y: second) = (1, 2) // swc-expected-error {{parser_err_mixed_destructuring}}
}

#test
{
    var first, second: s32
    (x: first, second) = (1, 2) // swc-expected-error {{parser_err_mixed_destructuring}}
}

#test
{
    var first, second: s32
    (first, y: second) = (1, 2) // swc-expected-error {{parser_err_mixed_destructuring}}
}
