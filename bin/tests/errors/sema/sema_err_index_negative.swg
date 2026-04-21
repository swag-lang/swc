#global fileprivate

const A = "hello world"
#assert(A[-1] == '\0') // swc-expected-error {{sema_err_index_negative}}

#test
{
    const H = [1, 2]
    var a = H[-1] // swc-expected-error {{sema_err_index_negative}}
}
