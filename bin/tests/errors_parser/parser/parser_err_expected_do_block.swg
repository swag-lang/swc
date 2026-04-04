#global fileprivate

func bad()->s32
{
    if true return 0 // swc-expected-error {{parser_err_expected_do_block}}
    return 1
}
