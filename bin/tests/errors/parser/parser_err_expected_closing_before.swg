#global fileprivate

// A delimiter left unclosed before an unrelated token points at the unexpected token.
func bad1()
{
    let (a, b = titi()                 // swc-expected-error {{parser_err_expected_closing_before}}
}

func bad2()
{
    let (a = 1;                        // swc-expected-error {{parser_err_expected_closing_before}}
}
