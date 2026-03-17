// 

#global fileprivate

var state: s32

#init
{
    state += 1
}

#premain
{
    state += 10
}

#test
{
    state += 100
    @assert(state == 111)
}

#test
{
    state += 1000
    @assert(state == 1111)
}

#drop
{
    if state != 11 and state != 1111
    {
        var ptr: [*] u8 = null
        ptr[111] = 111
    }
}
