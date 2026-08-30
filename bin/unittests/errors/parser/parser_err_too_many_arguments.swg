#global private

func test()
{
    Swag.assert(true, false, 42)                     // swc-expected-error {{parser_err_too_many_arguments}}
}
