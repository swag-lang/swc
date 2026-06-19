#global fileprivate

// Intrinsics reject too-many-arguments calls.
var v1 = @countof(1, 2)                          // swc-expected-error {{parser_err_too_many_arguments}}
var v2 = @dataof(1, 2, 3)                        // swc-expected-error {{parser_err_too_many_arguments}}

func test()
{
    @assert(true, false, 42)                     // swc-expected-error {{parser_err_too_many_arguments}}
}
