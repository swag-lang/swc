#global fileprivate

#test
{
    var values: [1] s32 = [1]
    var value = values[18446744073709551616] // swc-expected-error {{sema_err_index_too_large}}
}
