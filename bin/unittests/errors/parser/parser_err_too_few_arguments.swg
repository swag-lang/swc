#global fileprivate

// Intrinsics reject too-few-arguments calls.
var v1 = @countof()                              // swc-expected-error {{parser_err_too_few_arguments}}
var v2 = @dataof()                               // swc-expected-error {{parser_err_too_few_arguments}}

func test()
{
    @print()                                     // swc-expected-error {{parser_err_too_few_arguments}}
    @assert()                                    // swc-expected-error {{parser_err_too_few_arguments}}
}
