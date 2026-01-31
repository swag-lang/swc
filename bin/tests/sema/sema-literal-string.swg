#global internal

const A = "hello world"
#assert(A[0] == 'h')
#assert(A[1] == 'e')
#assert(A[100] == '\0') // swc-expected-error {{sema_err_index_out_of_range}}
#assert(A[-1] == '\0') // swc-expected-error {{sema_err_index_negative}}

const B = "hello" ++ "world"
#assert(B[5] == 'w')