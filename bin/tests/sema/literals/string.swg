#global fileprivate

const A = "hello world"
#assert(A[0] == 'h')
#assert(A[1] == 'e')

const B = "hello" ++ "world"
#assert(B[5] == 'w')
