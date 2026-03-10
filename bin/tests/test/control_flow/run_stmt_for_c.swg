// swc-option suite-test

#global fileprivate

#test
{
    var acc: s32 = 0
    for var i = 0; i < 6; if i == 1 do i += 2 else do i += 1
    {
        if i == 0 do
            continue
        acc = acc * 10 + i
    }

    @assert(acc == 1345)
}

#test
{
    var acc: s32 = 0
    for var i = 0; i < 10; { i += 1; if i == 4 do break }
    {
        acc += i
    }

    @assert(acc == 6)
}
