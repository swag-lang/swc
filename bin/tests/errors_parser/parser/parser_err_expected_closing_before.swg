#global fileprivate

func bad()
{
    let (a, b = titi() // swc-expected-error {{parser_err_expected_closing_before}}
}
