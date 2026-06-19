#global fileprivate

// 'if', 'while', 'for', 'switch', '#if' and similar control headers must be followed by 'do' or '{'.
func bad1()->s32
{
    if true return 0                           // swc-expected-error {{parser_err_expected_do_block}}
    return 1
}

func bad2()
{
    while true break                           // swc-expected-error {{parser_err_expected_do_block}}
}

enum Test
{
    #if true do
        A = 0
    #else                                      // swc-expected-error {{parser_err_expected_do_block}}
        A = 1
}
