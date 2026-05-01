#global fileprivate

const A = "hello world"
#assert(A[100] == '\0') // swc-expected-error {{sema_err_index_out_of_range}}
#assert(A[0xFFFF_FFFF_FFFF_FFFF'u64] == '\0') // swc-expected-error {{sema_err_index_out_of_range}}
#assert((cast(const cstring) @dataof("abc"))[3] == '\0') // swc-expected-error {{sema_err_index_out_of_range}}

#test
{
    const H = [1, 2]
    var b = H[2] // swc-expected-error {{sema_err_index_out_of_range}}
}
