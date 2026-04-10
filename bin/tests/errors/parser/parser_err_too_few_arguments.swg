#global fileprivate

var value = @countof() // swc-expected-error {{parser_err_too_few_arguments}}

func test()
{
    @print() // swc-expected-error {{parser_err_too_few_arguments}}
}
