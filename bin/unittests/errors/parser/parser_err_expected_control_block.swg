#global private

// Control headers require a braced body.
func bad1()->s32
{
    if true return 0                           // swc-expected-error {{parser_err_expected_control_block}}
    return 1
}

func bad2()
{
    while true break                           // swc-expected-error {{parser_err_expected_control_block}}
}

func bad3()
{
    #static if true                          // swc-expected-error {{parser_err_expected_control_block}}
    else
    {
        let value = 1
    }
}
