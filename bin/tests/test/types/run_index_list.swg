// swc-option suite-test

#global fileprivate

#test
{
    var a: [2, 2] s32
    a[0, 0] = 1
    a[0, 1] = 2
    a[1, 0] = 3
    a[1, 1] = 4
    @assert(a[0, 0] + a[0, 1] + a[1, 0] + a[1, 1] == 10)

    var b: [2, 3, 4] s32
    b[1, 2, 3] = 42
    @assert(b[1, 2, 3] == 42)
}
