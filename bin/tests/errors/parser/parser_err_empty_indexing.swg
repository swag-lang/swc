#global fileprivate

func bad()
{
    var a = [1]
    var b = a[] // swc-expected-error {{parser_err_empty_indexing}}
}
