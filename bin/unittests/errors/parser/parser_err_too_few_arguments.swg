#global private

func test()
{
    Swag.print()                                     // swc-expected-error {{parser_err_too_few_arguments}}
    Swag.assert()                                    // swc-expected-error {{parser_err_too_few_arguments}}
}
