#global fileprivate // swc-option sema-only

#test
{
    var x: [2, 2] s32 = [[1, 2], [3, 4]]
    @assert(x[0, 0] == 1)
    @assert(x[0, 1] == 2)
    @assert(x[1, 0] == 3)
    @assert(x[1, 1] == 4)
}

#test
{
    var y: [2, 2] s32 = [[1, 2], [3, 4, 5]] // swc-expected-error {{sema_err_array_cast_too_many_values}}
}
