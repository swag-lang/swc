#global private

func assignPair()
{
    var first: s32
    var second: s32
    first, second = 1, 2 // swc-expected-error {{parser_err_unexpected_token}}
}

func trailingComma()
{
    var value: s32
    value = 1, // swc-expected-error {{parser_err_unexpected_token}}
}
