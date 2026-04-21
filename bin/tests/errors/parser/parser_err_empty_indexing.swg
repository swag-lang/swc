#global fileprivate

// Every indexing expression must contain at least one bound or expression.
func bad()
{
    var a = [1, 2, 3]
    var b = a[]                // swc-expected-error {{parser_err_empty_indexing}}
    var c = "abc"[]            // swc-expected-error {{parser_err_empty_indexing}}
}
