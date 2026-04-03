#global fileprivate

func isItemType(ch: u8)->bool
{
    return (ch >= 'a''u8 and ch <= 'z''u8) or (ch >= 'A''u8 and ch <= 'Z''u8)
}

func priorityOf(ch: u8)->u32
{ // swc-expected-error {{parser_err_expected_closing}}
    @assert(isItemType(ch)

    if ch >= 'a''u8 do // swc-expected-error {{parser_err_expected_token}}
        return cast(u32) (ch - 'a''u8) + 1'u32
    return cast(u32) (ch - 'A''u8) + 27'u32
}

// swc-expected-error@* {{parser_err_unexpected_token}}
