#global fileprivate

// 'do' introduces a single statement; following it with '{ ... }' is an error in every control header.
func bad1()
{
    if true do {}                         // swc-expected-error {{parser_err_unexpected_do_block}}
}

func bad2()
{
    while true do {}                      // swc-expected-error {{parser_err_unexpected_do_block}}
}
