#global private

func test()
{
    Swag.assert(true, null, #curlocation, 42)     // swc-expected-error {{parser_err_too_many_arguments}}
}
