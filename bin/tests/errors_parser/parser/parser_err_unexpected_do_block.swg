#global fileprivate

func bad()
{
    if true do {} // swc-expected-error {{parser_err_unexpected_do_block}}
}
