#global fileprivate

const A = "hello world"
#assert(A[100] == '\0') // swc-expected-error {{sema_err_index_out_of_range}}

#test
{
    const H = [1, 2]
    var b = H[2] // swc-expected-error {{sema_err_index_out_of_range}}
}
