#global fileprivate

struct SemaDeferPoint
{
    value: s32
}

func semaDeferMakePoint(value: s32)->SemaDeferPoint
{
    var result: SemaDeferPoint
    result.value = value
    return result
}

#test
{
    var state = 0
    {
        defer state = state * 10 + 1
        defer
        {
            state = state * 10 + 2
        }
    }

    @assert(state == 21)
}

#test
{
    var state = 0
    if true do
        defer state = state * 10 + 1
    if false do
        defer state = state * 10 + 9
    elif true do
        defer state = state * 10 + 2
    else do
        defer state = state * 10 + 8
    if false do
        defer state = state * 10 + 9
    else do
        defer state = state * 10 + 3

    @assert(state == 123)
}

#test
{
    var state = 0
    if var x = 3 do
        defer state = state * 10 + x
    if var y = 0 where y == 0 do
        defer state = state * 10 + y + 4
    if var z = 1 where false do
        defer state = state * 10 + 9
    else do
        defer state = state * 10 + z + 4

    @assert(state == 345)
}

#test
{
    var state = 0
    var point: SemaDeferPoint
    with point = semaDeferMakePoint(1) defer state = state * 10 + .value
    point.value = 2
    with let ptr = &point defer state = state * 10 + .value
    with var local = semaDeferMakePoint(3) defer state = state * 10 + .value

    @assert(state == 123)
}

#test
{
    var state = 0
    var count = 0
    var values: [2] s32 = [8, 9]

    while count < 1 do
        defer
        {
            count += 1
            state = state * 10 + 1
        }

    for i in 6 where (i & 1) == 0 do
        defer state = state * 10 + cast(s32) i + 2

    for var i = 0; i < 1; i += 1 do
        defer state = state * 10 + i + 7

    foreach v in values do
        defer state = state * 10 + v

    @assert(count == 1)
    @assert(state == 1246789)
}

#test
{
    var state = 0

    #scope(Outer)
    {
        defer state = state * 10 + 1
        switch 0
        {
        case 0:
            defer state = state * 10 + 2
            fallthrough
        case 1:
            defer state = state * 10 + 3
            break to Outer
        default:
            defer state = state * 10 + 9
            break
        }
    }

    @assert(state == 231)
}

#test
{
    var state = 0
    defer #move state += 1 // swc-expected-error {{sema_err_modifier_unsupported}}
}

#test
{
    var state = 0
    defer #err state += 1 // swc-expected-error {{sema_err_defer_mode_not_implemented}}
}

#test
{
    var state = 0
    defer #noerr state += 1 // swc-expected-error {{sema_err_defer_mode_not_implemented}}
}
